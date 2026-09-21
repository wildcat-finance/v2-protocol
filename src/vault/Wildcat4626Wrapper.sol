// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import { ERC4626 } from 'solady/tokens/ERC4626.sol';
import { IERC20 } from 'openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC20Metadata } from 'openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IMarketTransferPolicy } from '../access/IMarketTransferPolicy.sol';
import { IWildcatSanctionsSentinel } from '../interfaces/IWildcatSanctionsSentinel.sol';
import { ReentrancyGuard } from '../ReentrancyGuard.sol';
import { MathUtils, RAY } from '../libraries/MathUtils.sol';
import { LibERC20 } from '../libraries/LibERC20.sol';
import { HooksConfig, LibHooksConfig } from '../types/HooksConfig.sol';

/// @notice market-token surface the wrapper needs for scaled accounting and live borrower identity.
interface IWildcatMarketToken is IERC20Metadata {
  /// @notice packed hook address and enabled callbacks installed on the market.
  function hooks() external view returns (HooksConfig);

  /// @notice current ray-scaled conversion ratio from scaled shares to normalized tokens.
  function scaleFactor() external view returns (uint256);

  /// @notice direct scaled market-token balance for `account`.
  function scaledBalanceOf(address account) external view returns (uint256);

  /// @notice current operational borrower.
  function borrower() external view returns (address);

  /// @notice current registered borrower principal.
  function borrowerPrincipal() external view returns (address);

  /// @notice normalized market deposit cap.
  function maxTotalSupply() external view returns (uint256);

  /// @notice sanctions sentinel used by the market.
  function sentinel() external view returns (address);

  /// @notice canonical factory allowed to register this market's wrapper.
  function wrapperFactory() external view returns (address);
}

/// @title Wildcat ERC-4626 wrapper
/// @notice turns a rebasing Wildcat market token into non-rebasing shares equal to scaled
///         ownership.
/// @dev conversions use the market scale factor, not `totalAssets() / totalSupply()`. execution is
///      only compatible with markets whose transfers round scaled amounts down. pre-V2.5 markets
///      round half-up and trip `SharesMismatch`, so wrappers must come through the generation-aware
///      `Wildcat4626WrapperFactory`.
contract Wildcat4626Wrapper is ERC4626, ReentrancyGuard {
  using LibHooksConfig for HooksConfig;
  using MathUtils for uint256;
  using LibERC20 for address;

  /// @dev a required market, borrower, principal, or sentinel address is zero.
  error ZeroAddress();
  /// @dev an asset-denominated action resolves to zero assets.
  error ZeroAssets();
  /// @dev an asset-denominated action resolves to zero wrapper shares.
  error ZeroShares();
  /// @dev the deposit would exceed the wrapped market's normalized supply cap.
  error CapExceeded();
  /// @dev the market's transfer policy does not currently allow the wrapper to receive tokens.
  error MarketTokenRecipientNotAllowed();
  /// @dev the market moved a different scaled amount than the wrapper expected.
  error SharesMismatch(uint256 expected, uint256 actual);
  /// @dev the caller is not the market's current operational borrower.
  error NotMarketOwner();
  /// @dev the requested account is currently sanctioned in the live borrower namespace.
  error SanctionedAccount(address account);
  /// @dev the requested account is not currently sanctioned in the live borrower namespace.
  error AccountNotSanctioned(address account);
  /// @dev the wrapper cannot quarantine its own wrapper-share balance.
  error CannotNukeWrapper();
  /// @dev the deployer is not the wrapper factory reported by the market.
  error NotWrapperFactory();
  /// @dev scaled market-token backing is below outstanding wrapper shares.
  error InsolventWrapper(uint256 scaledBacking, uint256 shareSupply);

  /// @notice rebasing market token held as the ERC-4626 asset.
  IWildcatMarketToken public immutable wrappedMarket;

  /// @notice sanctions sentinel captured from the market at deployment.
  IWildcatSanctionsSentinel public immutable sanctionsSentinel;
  IMarketTransferPolicy internal immutable _transferPolicy;

  uint8 private immutable _decimals;
  string private _name;
  string private _symbol;

  /// @dev remembers which escrows this wrapper actually used to quarantine sanctioned shares.
  mapping(address escrow => bool authorized) private _authorizedEscrows;

  /// @param marketAddress Wildcat market token to wrap.
  /// @dev only the wrapper factory reported by the market can deploy this contract.
  constructor(address marketAddress) {
    if (marketAddress == address(0)) revert ZeroAddress();

    wrappedMarket = IWildcatMarketToken(marketAddress);
    if (msg.sender != _readMarketAddress(IWildcatMarketToken.wrapperFactory.selector)) {
      revert NotWrapperFactory();
    }
    address currentBorrower = _readMarketAddress(IWildcatMarketToken.borrower.selector);
    if (currentBorrower == address(0)) revert ZeroAddress();
    if (_readMarketAddress(IWildcatMarketToken.borrowerPrincipal.selector) == address(0)) {
      revert ZeroAddress();
    }
    address sentinel = _readMarketAddress(IWildcatMarketToken.sentinel.selector);
    if (sentinel == address(0)) revert ZeroAddress();
    sanctionsSentinel = IWildcatSanctionsSentinel(sentinel);
    HooksConfig hooksConfig = HooksConfig.wrap(
      _readMarketWord(IWildcatMarketToken.hooks.selector)
    );
    _transferPolicy = IMarketTransferPolicy(hooksConfig.hooksAddress());
    uint256 marketDecimals = _readMarketWord(IERC20Metadata.decimals.selector);
    if (marketDecimals > type(uint8).max) {
      // decimals() promises a uint8, but the shared reader gives us the whole return word. keep
      // the range check Solidity's decoder would perform, then fail without adding an error
      // selector just for malformed market data.
      assembly ('memory-safe') {
        revert(0, 0)
      }
    }
    _decimals = uint8(marketDecimals);

    string memory marketSymbol = IERC20Metadata(marketAddress).symbol();
    _name = string.concat(marketSymbol, ' [4626 Vault Shares]');
    _symbol = string.concat('v-', marketSymbol);
  }

  // -------------------------------------------------------------------------
  // ERC20 Metadata
  // -------------------------------------------------------------------------

  function name() public view override returns (string memory) {
    return _name;
  }

  function symbol() public view override returns (string memory) {
    return _symbol;
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  // -------------------------------------------------------------------------
  // ERC4626 Configuration Overrides
  // -------------------------------------------------------------------------

  /// @dev disabled virtual shares since we use the market's scale factor for conversions
  function _useVirtualShares() internal pure override returns (bool) {
    return false;
  }

  function _underlyingDecimals() internal view override returns (uint8) {
    return _decimals;
  }

  // -------------------------------------------------------------------------
  // Events
  // -------------------------------------------------------------------------

  /// @notice emitted when the operational borrower recovers an ERC-20 balance or backing surplus.
  event TokensSwept(address indexed token, address indexed to, uint256 amount);

  /// @notice emitted when sanctioned wrapper shares move into their deterministic escrow.
  event SanctionedAccountSharesSentToEscrow(
    address indexed account,
    address indexed escrow,
    uint256 shares
  );

  // -------------------------------------------------------------------------
  // ERC4626 View Interface
  // -------------------------------------------------------------------------

  /// @notice returns the wrapped Wildcat market token.
  function market() public view returns (address) {
    return address(wrappedMarket);
  }

  /// @notice returns the market's current operational borrower.
  /// @dev retained as a compatibility getter; sweep authorization reads the same live value.
  function marketOwner() public view returns (address) {
    return _readMarketAddress(IWildcatMarketToken.borrower.selector);
  }

  /// @notice returns the wrapped market as the ERC-4626 asset.
  function asset() public view override returns (address) {
    return address(wrappedMarket);
  }

  /// @notice returns the normalized market-token balance currently held by the wrapper.
  /// @dev direct market-token transfers increase this without minting shares.
  function totalAssets() public view override returns (uint256) {
    return _readMarketWord(IERC20.balanceOf.selector, address(this));
  }

  /// @notice converts normalized `assets` to scaled shares, rounding down.
  /// @dev this is a pure exchange-rate quote; it ignores sanctions, capacity, and transfer policy.
  function convertToShares(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToSharesDown(assets, scaleFactor);
  }

  /// @notice converts scaled `shares` to normalized assets, rounding down.
  /// @dev this is a pure exchange-rate quote; it ignores sanctions and wrapper solvency.
  function convertToAssets(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToAssetsDown(shares, scaleFactor);
  }

  /// @notice returns the normalized assets the wrapper can accept for `receiver` right now.
  /// @dev returns zero if sanctions, wrapper health, wrapper capacity, rounding, or the market's
  ///      recipient policy would make the deposit fail.
  function maxDeposit(address receiver) public view override returns (uint256) {
    (uint256 capacity, ) = _maxDepositAndScaleFactor(receiver);
    return capacity;
  }

  /// @notice returns shares quoted for depositing `assets`, rounded down.
  function previewDeposit(uint256 assets) public view override returns (uint256) {
    return convertToShares(assets);
  }

  /// @notice returns shares the wrapper can mint for `receiver` right now.
  /// @dev reads capacity and scale together. dependency failures close the limit to zero.
  function maxMint(address receiver) public view override returns (uint256) {
    (uint256 capAssets, uint256 scaleFactor) = _maxDepositAndScaleFactor(receiver);
    if (capAssets == 0) return 0;
    // Max shares obtainable from the remaining capacity under floor scaling;
    // matches the cap check in `mint`.
    return _convertToSharesDown(capAssets, scaleFactor);
  }

  /// @notice returns assets required to mint `shares`, rounded up.
  function previewMint(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToAssetsUp(shares, scaleFactor);
  }

  /// @notice returns the largest normalized amount `owner_` can pull through `withdraw`.
  /// @dev returns zero if sanctions, insolvency, or a dependency read closes the limit. a nonzero
  ///      result consumes the owner's complete share balance under market floor rounding.
  function maxWithdraw(address owner_) public view override returns (uint256) {
    if (!_isLimitOperational(owner_)) return 0;
    uint256 shares = balanceOf(owner_);
    if (shares == 0) return 0;
    (bool success, uint256 scaleFactor) = _tryReadScaleFactor();
    if (!success) return 0;
    // Largest amount whose floor-rounded scaling burns no more than `shares`:
    // one below the smallest amount that would need `shares + 1`. Guaranteed
    // executable: it burns exactly `shares` (>= 1).
    return MathUtils.mulDivUp(shares + 1, scaleFactor, RAY) - 1;
  }

  /// @notice returns the ERC-4626 preview of shares for `assets`, rounded up.
  function previewWithdraw(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToSharesUp(assets, scaleFactor);
  }

  /// @notice returns all shares `owner_` can currently redeem.
  /// @dev returns zero if sanctions, insolvency, or a dependency read closes the limit.
  function maxRedeem(address owner_) public view override returns (uint256) {
    if (!_isLimitOperational(owner_)) return 0;
    return balanceOf(owner_);
  }

  /// @notice returns the ERC-4626 preview of assets for `shares`, rounded down.
  function previewRedeem(uint256 shares) public view override returns (uint256) {
    return convertToAssets(shares);
  }

  /// @notice returns assets per share as a ray (`1e27`).
  /// @dev exactly the market scale factor.
  function assetsPerShareRay() external view returns (uint256) {
    return _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
  }

  /// @notice returns shares per asset as a ray (`1e27`), rounded down.
  /// @dev the floored ray inverse of the market scale factor.
  function sharesPerAssetRay() external view returns (uint256) {
    return MathUtils.mulDiv(RAY, RAY, _readMarketWord(IWildcatMarketToken.scaleFactor.selector));
  }

  // -------------------------------------------------------------------------
  // Mutating Interface
  // -------------------------------------------------------------------------

  // Rounding contract for all execution paths: the market's transfer moves
  // floor(amount * RAY / scaleFactor) scaled tokens (`scaleAmountDown`, since
  // the v2.5 rounding hardening; earlier markets rounded half-up). Each path
  // converts to hold its SharesMismatch identity exactly against that floor:
  // inbound amounts convert down, outbound amounts convert up -- the smallest
  // normalized amount that moves exactly `shares` scaled tokens. The ceil
  // round-trip, floor(ceil(s * sf / RAY) * RAY / sf) == s, requires
  // scaleFactor >= RAY, which the market guarantees (the scale factor starts
  // at RAY and only grows). Previews keep their ERC-4626 rounding directions
  // and are bounded by these executions in the directions the spec requires.
  //
  // Note for integrators: normalized amounts are labels over exact scaled
  // accounting. The `assets` returned by redeem (and passed to withdraw) can
  // exceed the receiver's `balanceOf` delta by up to one scaled token's value,
  // because the market's rebasing balance view rounds independently of its
  // transfer. Reconcile against `scaledBalanceOf` deltas, not `balanceOf`.

  /// @notice pulls `assets` from the caller and mints the exact observed scaled increase to
  ///         `receiver`.
  /// @dev reverts on zero input, sanctions, insolvency, cap failure, recipient-policy denial, or a
  ///      scaled-balance mismatch.
  /// @return shares nonzero scaled market tokens credited by the transfer.
  function deposit(
    uint256 assets,
    address receiver
  ) public override nonReentrant returns (uint256 shares) {
    _requireOperational(msg.sender, address(0));
    if (assets == 0) revert ZeroAssets();

    uint256 limit = _remainingCapacityAssets();
    if (assets > limit) revert CapExceeded();

    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // The market transfer credits floor-scaled tokens; expect exactly that.
    uint256 expectedShares = _convertToSharesDown(assets, scaleFactor);
    if (expectedShares == 0) revert ZeroShares();

    _requireMarketTokenRecipientAllowed();

    address assetAddress = address(wrappedMarket);
    uint256 scaledBefore = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );
    assetAddress.safeTransferFrom(msg.sender, address(this), assets);
    uint256 scaledAfter = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );

    shares = scaledAfter - scaledBefore;
    if (shares != expectedShares) revert SharesMismatch(expectedShares, shares);

    _mint(receiver, shares);
    _requireSolvent(scaledAfter);
    emit Deposit(msg.sender, receiver, assets, shares);
    return shares;
  }

  /// @notice mints exactly `shares` to `receiver` and pulls the minimum matching asset amount.
  /// @return assets normalized market tokens pulled from the caller.
  function mint(
    uint256 shares,
    address receiver
  ) public override nonReentrant returns (uint256 assets) {
    _requireOperational(msg.sender, address(0));
    if (shares == 0) revert ZeroShares();
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // Reuse the `assets` return variable to hold remaining capacity for the cap check.
    assets = _remainingCapacityAssets();
    if (assets == 0 || shares > _convertToSharesDown(assets, scaleFactor)) {
      revert CapExceeded();
    }

    // Minimum assets whose floor-rounded scaling in the market's transfer
    // moves exactly `shares` scaled tokens.
    assets = _convertToAssetsUp(shares, scaleFactor);

    // Verify the formula produced the correct result
    uint256 expectedShares = _convertToSharesDown(assets, scaleFactor);
    if (expectedShares != shares) revert SharesMismatch(shares, expectedShares);

    _requireMarketTokenRecipientAllowed();

    address assetAddress = address(wrappedMarket);
    uint256 scaledBefore = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );
    assetAddress.safeTransferFrom(msg.sender, address(this), assets);
    uint256 scaledAfter = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );

    uint256 mintedShares = scaledAfter - scaledBefore;
    if (mintedShares != shares) revert SharesMismatch(shares, mintedShares);

    _mint(receiver, shares);
    _requireSolvent(scaledAfter);
    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /// @notice sends `assets` to `receiver` and burns the exact scaled amount the market transfer
  ///         moves.
  /// @dev delegated callers spend `owner_` allowance against the execution amount, which rounds
  ///      down.
  /// @return shares scaled wrapper shares burned from `owner_`.
  function withdraw(
    uint256 assets,
    address receiver,
    address owner_
  ) public override nonReentrant returns (uint256 shares) {
    _requireOperational(msg.sender, receiver);
    if (assets == 0) revert ZeroAssets();

    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // Exactly the scaled amount the market's floor-rounded transfer will burn.
    shares = _convertToSharesDown(assets, scaleFactor);
    if (shares == 0) revert ZeroShares();

    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    uint256 scaledBefore = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );

    _burn(owner_, shares);
    address assetAddress = address(wrappedMarket);
    assetAddress.safeTransfer(receiver, assets);
    uint256 scaledAfter = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );

    uint256 burnedShares = scaledBefore - scaledAfter;
    if (burnedShares != shares) revert SharesMismatch(shares, burnedShares);
    _requireSolvent(scaledAfter);
    emit Withdraw(msg.sender, receiver, owner_, assets, shares);
  }

  /// @notice burns exactly `shares` from `owner_` and sends the matching assets to `receiver`.
  /// @dev execution rounds assets up to the smallest normalized amount whose floor-rounded market
  ///      transfer moves exactly `shares`. delegated callers spend the owner's allowance.
  /// @return assets normalized market tokens sent to `receiver`.
  function redeem(
    uint256 shares,
    address receiver,
    address owner_
  ) public override nonReentrant returns (uint256 assets) {
    _requireOperational(msg.sender, receiver);
    if (shares == 0) revert ZeroShares();

    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // Smallest normalized amount whose floor-rounded transfer moves `shares`.
    assets = _convertToAssetsUp(shares, scaleFactor);
    if (assets == 0) revert ZeroAssets();

    uint256 scaledBefore = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );

    _burn(owner_, shares);
    address assetAddress = address(wrappedMarket);
    assetAddress.safeTransfer(receiver, assets);
    uint256 scaledAfter = _readMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );

    uint256 burnedShares = scaledBefore - scaledAfter;
    if (burnedShares != shares) revert SharesMismatch(shares, burnedShares);
    _requireSolvent(scaledAfter);

    emit Withdraw(msg.sender, receiver, owner_, assets, shares);
  }

  /// @notice quarantines a sanctioned holder's direct market position and wrapper shares.
  /// @dev anyone can call this. the wrapper forwards the complete calldata, including trailing hook
  ///      data, to the market before moving all wrapper shares to their deterministic escrow.
  /// @param account sanctioned holder to quarantine.
  function nukeFromOrbit(address account) external nonReentrant {
    if (account == address(this)) revert CannotNukeWrapper();
    if (!_isSanctioned(account)) revert AccountNotSanctioned(account);

    address marketAddress = address(wrappedMarket);
    assembly {
      let freeMemoryPointer := mload(0x40)
      calldatacopy(freeMemoryPointer, 0, calldatasize())
      if iszero(call(gas(), marketAddress, 0, freeMemoryPointer, calldatasize(), 0, 0)) {
        returndatacopy(freeMemoryPointer, 0, returndatasize())
        revert(freeMemoryPointer, returndatasize())
      }
    }

    uint256 shares = balanceOf(account);
    if (shares == 0) return;

    address escrow = sanctionsSentinel.createEscrow(
      _readMarketAddress(IWildcatMarketToken.borrowerPrincipal.selector),
      account,
      address(this)
    );
    _authorizedEscrows[escrow] = true;
    _transfer(account, escrow, shares);
    emit SanctionedAccountSharesSentToEscrow(account, escrow, shares);
  }

  /// @notice sweeps an ERC-20 balance to `to` for the market's current operational borrower.
  /// @dev other tokens sweep in full. the market token only sweeps scaled backing above share
  ///      supply and verifies that exact surplus moved. `to` must not be sanctioned.
  /// @param token ERC-20 to recover. use the market token to recover only scaled backing surplus.
  /// @param to recipient of the recovered tokens.
  /// @return amount token units sent to `to`.
  function sweep(address token, address to) external nonReentrant returns (uint256 amount) {
    if (msg.sender != _readMarketAddress(IWildcatMarketToken.borrower.selector)) {
      revert NotMarketOwner();
    }
    if (token == address(0) || to == address(0)) revert ZeroAddress();
    _checkNotSanctioned(to);

    if (token == address(wrappedMarket)) {
      uint256 scaledBefore = _readMarketWord(
        IWildcatMarketToken.scaledBalanceOf.selector,
        address(this)
      );
      uint256 expectedScaled = totalSupply();
      if (scaledBefore <= expectedScaled) revert ZeroAssets();

      uint256 strandedScaled = scaledBefore - expectedScaled;
      uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
      // Smallest normalized amount that sweeps exactly the stranded scaled
      // tokens without touching the backing for outstanding shares.
      amount = _convertToAssetsUp(strandedScaled, scaleFactor);
      if (amount == 0) revert ZeroAssets();

      token.safeTransfer(to, amount);

      uint256 scaledAfter = _readMarketWord(
        IWildcatMarketToken.scaledBalanceOf.selector,
        address(this)
      );
      uint256 sweptScaled = scaledBefore - scaledAfter;
      if (sweptScaled != strandedScaled) revert SharesMismatch(strandedScaled, sweptScaled);
    } else {
      amount = LibERC20.balanceOf(token, address(this));
      if (amount == 0) revert ZeroAssets();

      token.safeTransfer(to, amount);
    }

    emit TokensSwept(token, to, amount);
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  function _readMarketWord(bytes4 selector) internal view returns (uint256 value) {
    address marketAddress = address(wrappedMarket);
    // turn bytes4 into an ordinary low-end integer before Yul sees it. mstore will put those
    // four bytes at the right edge of its word, which is what the +0x1c call offset expects.
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      // borrow the free-memory pointer for four bytes of input and one word of output. nothing
      // needs this buffer after the assembly block, so leave 0x40 alone.
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)

      // +0x1c skips the 28 leading zero bytes and sends only the selector. ask for one return
      // word back at the start of the same buffer.
      if iszero(staticcall(gas(), marketAddress, add(pointer, 0x1c), 0x04, pointer, 0x20)) {
        // the getter reverted. replace our scratch data with the full revert payload and pass
        // it through unchanged.
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }

      // success with less than one word is still malformed. extra data is fine; this helper
      // only promises the first word.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      value := mload(pointer)
    }
  }

  function _readMarketWord(
    bytes4 selector,
    address account
  ) internal view returns (uint256 value) {
    address marketAddress = address(wrappedMarket);
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      // same scratch-buffer layout as the no-argument reader, with account in the next full
      // ABI slot. four selector bytes plus one 32-byte argument gives us the 0x24 call length.
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), account)
      if iszero(staticcall(gas(), marketAddress, add(pointer, 0x1c), 0x24, pointer, 0x20)) {
        // don't hide a useful market error behind the reader. copy and bubble the whole thing.
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }
      // just like the no-argument reader, we need one complete word and ignore anything after it.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      value := mload(pointer)
    }
  }

  /// @dev max* needs a reader that reports failure instead of bubbling it.
  function _tryReadMarketWord(
    bytes4 selector
  ) internal view returns (bool success, uint256 value) {
    address marketAddress = address(wrappedMarket);
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      // borrow one word at the free-memory pointer. everything leaves on the stack, so there's
      // no reason to move 0x40 or keep this buffer around.
      let pointer := mload(0x40)

      // mstore right-aligns selectorWord. start 28 bytes in so calldata begins with the four-byte
      // selector instead of its leading zeroes.
      mstore(pointer, selectorWord)

      // copy at most one return word. an ordinary Solidity low-level call copies all returndata,
      // which lets a broken dependency turn this supposedly safe view into a memory-expansion
      // revert.
      success := staticcall(gas(), marketAddress, add(pointer, 0x1c), 0x04, pointer, 0x20)

      // a revert or short response means unavailable. trailing bytes don't matter; the first
      // complete word is all this reader promises.
      success := and(success, iszero(lt(returndatasize(), 0x20)))
      if success {
        value := mload(pointer)
      }
    }
  }

  /// @dev max* version of the one-argument market reader.
  function _tryReadMarketWord(
    bytes4 selector,
    address account
  ) internal view returns (bool success, uint256 value) {
    address marketAddress = address(wrappedMarket);
    uint256 selectorWord = uint32(selector);
    assembly ('memory-safe') {
      // same temporary buffer, with one ABI address after the selector. 4 + 32 gives us the
      // 0x24-byte call below.
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), account)

      // still copy only one return word. this is the non-reverting twin of
      // _readMarketWord(selector, account), not a general ABI decoder.
      success := staticcall(gas(), marketAddress, add(pointer, 0x1c), 0x24, pointer, 0x20)

      // don't load the buffer unless a full word landed. value stays zero on failure, and the
      // caller uses success to collapse the limit to 0.
      success := and(success, iszero(lt(returndatasize(), 0x20)))
      if success {
        value := mload(pointer)
      }
    }
  }

  function _readMarketAddress(bytes4 selector) internal view returns (address value) {
    uint256 word = _readMarketWord(selector);
    assembly ('memory-safe') {
      // shr(160, word) drops the address-sized low bits. anything left is dirty ABI padding,
      // which Solidity's normal address decoder would reject too.
      if shr(160, word) {
        revert(0, 0)
      }
      // the upper bits are clean now, so narrowing the first return word to address is safe.
      value := word
    }
  }

  function _tryReadMarketAddress(
    bytes4 selector
  ) internal view returns (bool success, address value) {
    uint256 word;
    (success, word) = _tryReadMarketWord(selector);
    // an ABI address gets 160 low bits and 96 zero bits. don't quietly truncate dirty padding.
    if (!success || word > type(uint160).max) return (false, address(0));
    value = address(uint160(word));
  }

  function _tryReadScaleFactor() internal view returns (bool success, uint256 scaleFactor) {
    (success, scaleFactor) = _tryReadMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // market storage gives this uint112, starts it at RAY, and only moves it up. keeping those
    // bounds here also keeps the later max* multiplication inside uint256.
    if (!success || scaleFactor < RAY || scaleFactor > type(uint112).max) {
      return (false, 0);
    }
  }

  /// @dev read capacity and scale together. following a safe maxDeposit with one strict scale
  ///      read would just recreate the bug in maxMint.
  function _maxDepositAndScaleFactor(
    address receiver
  ) internal view returns (uint256 capacity, uint256 scaleFactor) {
    if (!_isLimitOperational(receiver)) return (0, 0);
    if (!_canReceiveMarketTokens()) return (0, 0);

    (bool success, uint256 marketCap) = _tryReadMarketWord(
      IWildcatMarketToken.maxTotalSupply.selector
    );
    // market storage gives maxTotalSupply uint128. keep the same bound here so nonsense data
    // can't overflow the capacity-to-shares multiplication.
    if (!success || marketCap > type(uint128).max) return (0, 0);

    uint256 held;
    (success, held) = _tryReadMarketWord(IERC20.balanceOf.selector, address(this));
    if (!success || held >= marketCap) return (0, 0);

    (success, scaleFactor) = _tryReadScaleFactor();
    if (!success) return (0, 0);

    capacity = marketCap - held;
    // if the remaining capacity can't mint one scaled token, deposit would revert with ZeroShares.
    if (_convertToSharesDown(capacity, scaleFactor) == 0) return (0, 0);
  }

  /// @dev Remaining normalized assets before reaching the market's maxTotalSupply,
  ///      without sanctions checks (execution paths already enforce them).
  function _remainingCapacityAssets() internal view returns (uint256) {
    uint256 marketCap = _readMarketWord(IWildcatMarketToken.maxTotalSupply.selector);
    uint256 held = _readMarketWord(IERC20.balanceOf.selector, address(this));
    if (held >= marketCap) return 0;
    return marketCap - held;
  }

  /// @dev floor rounding for spec-compliant previews.
  function _convertToSharesDown(
    uint256 assets,
    uint256 scaleFactor
  ) internal pure returns (uint256) {
    return MathUtils.mulDiv(assets, RAY, scaleFactor);
  }

  /// @dev floor rounding for spec-compliant previews.
  function _convertToAssetsDown(
    uint256 shares,
    uint256 scaleFactor
  ) internal pure returns (uint256) {
    return MathUtils.mulDiv(shares, scaleFactor, RAY);
  }

  /// @dev ceiling rounding for ERC-4626 compliant previews (previewMint).
  function _convertToAssetsUp(uint256 shares, uint256 scaleFactor) internal pure returns (uint256) {
    return MathUtils.mulDivUp(shares, scaleFactor, RAY);
  }

  /// @dev ceiling rounding for ERC-4626 compliant previews (previewWithdraw).
  function _convertToSharesUp(uint256 assets, uint256 scaleFactor) internal pure returns (uint256) {
    return MathUtils.mulDivUp(assets, RAY, scaleFactor);
  }

  function _isSanctioned(address account) internal view returns (bool) {
    if (account == address(0)) return false;
    return _isSanctioned(
      account,
      _readMarketAddress(IWildcatMarketToken.borrowerPrincipal.selector)
    );
  }

  function _isSanctioned(
    address account,
    address principal
  ) internal view returns (bool isSanctioned_) {
    if (account == address(0)) return false;
    address sentinel = address(sanctionsSentinel);
    uint256 selectorWord = uint32(IWildcatSanctionsSentinel.isSanctioned.selector);
    assembly ('memory-safe') {
      // borrow the free-memory pointer for calldata and the first return word. nothing needs
      // this buffer after the assembly block, so leave 0x40 alone.
      let pointer := mload(0x40)

      // mstore puts the four-byte selector at the right edge of a 32-byte word. starting the
      // call at +0x1c skips the leading zeroes, so calldata is selector | principal | account.
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), principal)
      mstore(add(pointer, 0x40), account)

      // ask staticcall to write up to the first return word over the start of our buffer. if it
      // reverts, replace that with the full revert payload and bubble it up.
      if iszero(staticcall(gas(), sentinel, add(pointer, 0x1c), 0x44, pointer, 0x20)) {
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }

      // Solidity would reject a short bool or anything other than zero or one. do the same
      // here. extra return data is fine; the bool still lives in the first word.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      isSanctioned_ := mload(pointer)
      if gt(isSanctioned_, 1) {
        revert(0, 0)
      }
    }
  }

  /// @dev max* version of the sanctions check: a broken read closes the limit instead of reverting.
  function _tryIsSanctioned(
    address account,
    address principal
  ) internal view returns (bool success, bool isSanctioned_) {
    if (account == address(0)) return (true, false);
    address sentinel = address(sanctionsSentinel);
    uint256 selectorWord = uint32(IWildcatSanctionsSentinel.isSanctioned.selector);
    assembly ('memory-safe') {
      // borrow three words at the free-memory pointer. calldata is the right-aligned
      // isSanctioned selector followed by the principal and account words.
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), principal)
      mstore(add(pointer, 0x40), account)

      // +0x1c skips the selector's leading zeroes. 0x44 is four selector bytes plus two address
      // words. copy at most one return word so an oversized response stays cheap to ignore.
      success := staticcall(gas(), sentinel, add(pointer, 0x1c), 0x44, pointer, 0x20)

      // a failed call or short word closes the limit without bubbling. trailing data is fine;
      // the strict reader already follows the same first-word rule.
      success := and(success, iszero(lt(returndatasize(), 0x20)))
      if success {
        isSanctioned_ := mload(pointer)

        // Solidity booleans are exactly 0 or 1. anything else is malformed and closes the limit.
        success := iszero(gt(isSanctioned_, 1))
        if iszero(success) {
          isSanctioned_ := 0
        }
      }
    }
  }

  function _getEscrowAddress(
    address principal,
    address account
  ) internal view returns (address escrow) {
    address sentinel = address(sanctionsSentinel);
    assembly ('memory-safe') {
      // same calldata trick as _isSanctioned, just with one more address. address() is this
      // wrapper when we're inside Yul.
      let pointer := mload(0x40)
      mstore(pointer, 0x1cdf58b0)
      mstore(add(pointer, 0x20), principal)
      mstore(add(pointer, 0x40), account)
      mstore(add(pointer, 0x60), address())

      // reuse the start of the buffer for the return word. on failure, overwrite it with the
      // complete revert payload and bubble that up instead.
      if iszero(staticcall(gas(), sentinel, add(pointer, 0x1c), 0x64, pointer, 0x20)) {
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }
      // short data can't hold an address. trailing data is fine; we only use the first word.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }

      // an ABI address is 160 bits with zeroes on the left. reject anything in those upper bits
      // so this behaves like Solidity's normal decoder.
      escrow := mload(pointer)
      if shr(160, escrow) {
        revert(0, 0)
      }
    }
  }

  /// @dev `from` only gets the release exception if this wrapper authorized it and it still matches
  ///      `account` under its original principal.
  function _isEscrowRelease(address from, address account) internal view returns (bool) {
    if (!_authorizedEscrows[from]) return false;
    address escrowPrincipal;
    assembly {
      mstore(0, 0x7df1f1b9) // borrower()
      if and(eq(returndatasize(), 0x20), staticcall(gas(), from, 0x1c, 0x04, 0, 0x20)) {
        escrowPrincipal := and(mload(0), 0xffffffffffffffffffffffffffffffffffffffff)
      }
    }
    return escrowPrincipal != address(0) && _getEscrowAddress(escrowPrincipal, account) == from;
  }

  /// @dev max* version of the operational check. every external answer has to be present and
  ///      shaped like a canonical market value, or the limit stays closed.
  function _isLimitOperational(address account) internal view returns (bool) {
    (bool success, address principal) = _tryReadMarketAddress(
      IWildcatMarketToken.borrowerPrincipal.selector
    );
    if (!success || principal == address(0)) return false;

    bool sanctioned;
    (success, sanctioned) = _tryIsSanctioned(account, principal);
    if (!success || sanctioned) return false;
    if (account != address(this)) {
      (success, sanctioned) = _tryIsSanctioned(address(this), principal);
      if (!success || sanctioned) return false;
    }

    uint256 scaledBacking;
    (success, scaledBacking) = _tryReadMarketWord(
      IWildcatMarketToken.scaledBalanceOf.selector,
      address(this)
    );
    // market account balances are uint104. once backing fits and covers totalSupply,
    // maxWithdraw can safely do shares + 1 and shares * scaleFactor.
    return
      success &&
      scaledBacking <= type(uint104).max &&
      scaledBacking >= totalSupply();
  }

  /// @dev Applies the same live recipient-policy gate used by maxDeposit and maxMint.
  function _requireMarketTokenRecipientAllowed() internal view {
    if (!_canReceiveMarketTokens()) revert MarketTokenRecipientNotAllowed();
  }

  /// @dev wrapper deposits are plain market-token transfers, so they don't have hook data to
  ///      carry permission. keep this fail closed: if the policy probe breaks, report zero
  ///      capacity instead of breaking the ERC-4626 limit view too.
  function _canReceiveMarketTokens() internal view returns (bool allowed) {
    address policy = address(_transferPolicy);
    address marketAddress = address(wrappedMarket);
    uint256 selectorWord = uint32(
      IMarketTransferPolicy.isMarketTransferRecipientAllowed.selector
    );
    assembly ('memory-safe') {
      // same layout again: the selector starts at +0x1c, then market and wrapper each get a
      // normal 32-byte ABI slot.
      let pointer := mload(0x40)
      mstore(pointer, selectorWord)
      mstore(add(pointer, 0x20), marketAddress)
      mstore(add(pointer, 0x40), address())
      let success := staticcall(gas(), policy, add(pointer, 0x1c), 0x44, pointer, 0x20)

      // only open capacity when all three checks pass: the call succeeded, returned a full
      // word, and that word is exactly one. a revert, short return, dirty bool, or ordinary
      // false all stay closed without breaking the view.
      allowed := and(
        success,
        and(iszero(lt(returndatasize(), 0x20)), eq(mload(pointer), 1))
      )
    }
  }

  function _requireSolvent(uint256 scaledBacking) internal view {
    uint256 shareSupply = totalSupply();
    // New deposits must not recapitalize claims held by the existing shareholders.
    if (scaledBacking < shareSupply) revert InsolventWrapper(scaledBacking, shareSupply);
  }

  function _requireOperational(address principal) internal view {
    _checkNotSanctioned(address(this), principal);
    _requireSolvent(
      _readMarketWord(IWildcatMarketToken.scaledBalanceOf.selector, address(this))
    );
  }

  function _requireOperational(address account, address secondAccount) internal view {
    address principal = _readMarketAddress(IWildcatMarketToken.borrowerPrincipal.selector);
    _checkNotSanctioned(account, principal);
    _checkNotSanctioned(secondAccount, principal);
    _checkNotSanctioned(address(this), principal);
    _requireSolvent(
      _readMarketWord(IWildcatMarketToken.scaledBalanceOf.selector, address(this))
    );
  }

  function _checkNotSanctioned(address account) internal view {
    if (_isSanctioned(account)) {
      revert SanctionedAccount(account);
    }
  }

  function _checkNotSanctioned(address account, address principal) internal view {
    if (_isSanctioned(account, principal)) {
      revert SanctionedAccount(account);
    }
  }

  /// @dev enforces solvency and sanctions on share moves. a sanctioned holder may only move to its
  ///      deterministic escrow; an authorized escrow may release back under its original principal.
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    address principal = _readMarketAddress(IWildcatMarketToken.borrowerPrincipal.selector);
    bool fromIsSanctioned = _isSanctioned(from, principal);
    bool toIsSanctioned = _isSanctioned(to, principal);
    if ((fromIsSanctioned || toIsSanctioned) && _isEscrowRelease(from, to)) {
      _requireOperational(principal);
    } else {
      if (fromIsSanctioned) {
        address escrow = _getEscrowAddress(principal, from);
        if (to != escrow) revert SanctionedAccount(from);
      } else {
        _requireOperational(principal);
      }
      if (toIsSanctioned) revert SanctionedAccount(to);
    }
    if (amount == 0) {
      return;
    }
  }
}
