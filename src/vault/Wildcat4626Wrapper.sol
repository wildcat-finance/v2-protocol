// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import { ERC4626 } from 'solady/tokens/ERC4626.sol';
import { IERC20Metadata } from 'openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IMarketTransferPolicy } from '../access/IMarketTransferPolicy.sol';
import { IWildcatSanctionsSentinel } from '../interfaces/IWildcatSanctionsSentinel.sol';
import { ReentrancyGuard } from '../ReentrancyGuard.sol';
import { MathUtils, RAY } from '../libraries/MathUtils.sol';
import { LibERC20 } from '../libraries/LibERC20.sol';
import { HooksConfig, LibHooksConfig } from '../types/HooksConfig.sol';

interface IWildcatMarketToken is IERC20Metadata {
  function hooks() external view returns (HooksConfig);

  function scaleFactor() external view returns (uint256);

  function scaledBalanceOf(address account) external view returns (uint256);

  function borrower() external view returns (address);

  function borrowerPrincipal() external view returns (address);

  function maxTotalSupply() external view returns (uint256);

  function sentinel() external view returns (address);

  function wrapperFactory() external view returns (address);
}

/**
 * @title Wildcat4626Wrapper
 * @notice Wraps a debt token with an erc-4626 non-rebasing share token.
 *  Shares mirror the market's scaled balance.
 * @dev Only compatible with markets whose transfers round scaled amounts
 *      down (v2.5+). Earlier markets round half-up, which trips the
 *      SharesMismatch guards; pair wrappers with markets through
 *      Wildcat4626WrapperFactory, which enforces the market generation.
 */
contract Wildcat4626Wrapper is ERC4626, ReentrancyGuard {
  using LibHooksConfig for HooksConfig;
  using MathUtils for uint256;
  using LibERC20 for address;

  error ZeroAddress();
  error ZeroAssets();
  error ZeroShares();
  error CapExceeded();
  error SharesMismatch(uint256 expected, uint256 actual);
  error NotMarketOwner();
  error SanctionedAccount(address account);
  error AccountNotSanctioned(address account);
  error CannotNukeWrapper();
  error NotWrapperFactory();
  error InsolventWrapper(uint256 scaledBacking, uint256 shareSupply);

  IWildcatMarketToken public immutable wrappedMarket;
  IWildcatSanctionsSentinel public immutable sanctionsSentinel;
  IMarketTransferPolicy internal immutable _transferPolicy;

  uint8 private immutable _decimals;
  string private _name;
  string private _symbol;

  /// @dev remembers which escrows this wrapper actually used to quarantine sanctioned shares.
  mapping(address escrow => bool authorized) private _authorizedEscrows;

  /**
   * @param marketAddress the wildcat market (debt token) address to wrap
   */
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

  event TokensSwept(address indexed token, address indexed to, uint256 amount);

  event SanctionedAccountSharesSentToEscrow(
    address indexed account,
    address indexed escrow,
    uint256 shares
  );

  // -------------------------------------------------------------------------
  // ERC4626 View Interface
  // -------------------------------------------------------------------------

  /// @notice Address of the wrapped Wildcat market token.
  function market() public view returns (address) {
    return address(wrappedMarket);
  }

  /// @notice Current operational borrower of the wrapped market.
  function marketOwner() public view returns (address) {
    return _readMarketAddress(IWildcatMarketToken.borrower.selector);
  }

  /// @notice Alias for the wrapped market so integrators can treat it as the ERC-4626 asset.
  function asset() public view override returns (address) {
    return address(wrappedMarket);
  }

  /// @notice Total normalized market tokens the wrapper currently custodies.
  function totalAssets() public view override returns (uint256) {
    return _readMarketWord(0x70a08231, address(this));
  }

  /// @notice Preview how many shares a deposit of `assets` would mint (rounded down per erc4626)
  function convertToShares(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToSharesDown(assets, scaleFactor);
  }

  /// @notice Preview how many assets burning `shares` yields (rounded down per ERC-4626)
  function convertToAssets(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToAssetsDown(shares, scaleFactor);
  }

  /// @notice normalized assets the wrapper can accept right now.
  /// @dev returns 0 if sanctions, wrapper health, market capacity, rounding, or the market's
  ///      recipient policy would make the deposit fail.
  function maxDeposit(address receiver) public view override returns (uint256) {
    if (_isSanctioned(receiver) || !_isOperational() || !_canReceiveMarketTokens()) return 0;
    uint256 marketCap = _readMarketWord(IWildcatMarketToken.maxTotalSupply.selector);
    uint256 held = totalAssets();
    if (held >= marketCap) return 0;
    uint256 capacity = marketCap - held;
    // A capacity worth less than one scaled token would mint zero shares and
    // revert; per spec, maxDeposit must be executable.
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    if (_convertToSharesDown(capacity, scaleFactor) == 0) return 0;
    return capacity;
  }

  /// @notice Shares minted for depositing `assets`, rounded down per spec.
  function previewDeposit(uint256 assets) public view override returns (uint256) {
    return convertToShares(assets);
  }

  /// @notice shares the wrapper can mint right now.
  /// @dev goes through maxDeposit so it tells the same truth about whether the wrapper is ready.
  function maxMint(address receiver) public view override returns (uint256) {
    uint256 capAssets = maxDeposit(receiver);
    if (capAssets == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // Max shares obtainable from the remaining capacity under floor scaling;
    // matches the cap check in `mint`.
    return _convertToSharesDown(capAssets, scaleFactor);
  }

  /// @notice Assets required to mint `shares`, rounded up (ceiling) per ERC4626
  function previewMint(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToAssetsUp(shares, scaleFactor);
  }

  /// @notice Maximum assets `owner_` can pull via `withdraw`, using half-up rounding
  /// @dev Returns 0 for sanctioned owners per erc 4626 (withdraw would revert)
  function maxWithdraw(address owner_) public view override returns (uint256) {
    if (_isSanctioned(owner_) || !_isOperational()) return 0;
    uint256 shares = balanceOf(owner_);
    if (shares == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // Largest amount whose floor-rounded scaling burns no more than `shares`:
    // one below the smallest amount that would need `shares + 1`. Guaranteed
    // executable: it burns exactly `shares` (>= 1).
    return MathUtils.mulDivUp(shares + 1, scaleFactor, RAY) - 1;
  }

  /// @notice Shares that would be burned to withdraw `assets`, rounded up (ceiling) per ERC-4626
  function previewWithdraw(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
    return _convertToSharesUp(assets, scaleFactor);
  }

  /// @notice All shares `owner_` currently holds.
  /// @dev Returns 0 for sanctioned owners per ERC-4626 (redeem would revert)
  function maxRedeem(address owner_) public view override returns (uint256) {
    if (_isSanctioned(owner_) || !_isOperational()) return 0;
    return balanceOf(owner_);
  }

  /// @notice Assets returned when redeeming `shares`, rounded down per spec
  function previewRedeem(uint256 shares) public view override returns (uint256) {
    return convertToAssets(shares);
  }

  /// @notice Returns the current exchange rate of assets per share, scaled by RAY (1e27)
  /// @dev This is equivalent to the market's scale factor. Useful for integrators to see
  ///      the exchange rate without needing to pick a sample share size.
  function assetsPerShareRay() external view returns (uint256) {
    return _readMarketWord(IWildcatMarketToken.scaleFactor.selector);
  }

  /// @notice Returns the current exchange rate of shares per asset, scaled by RAY (1e27).
  /// @dev This is the inverse of the scale factor to see
  ///      how many shares a given asset amount would yield.
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

  /// @notice Pull `assets` from the caller and mint the resulting shares to `receiver`.
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

  /// @notice Mint exactly `shares` to `receiver`, pulling the minimum required assets from caller
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

  /// @notice Withdraw `assets` to `receiver`, burning from `owner_` exactly the
  ///         shares the market's floor-rounded transfer moves
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

  /// @notice Redeem exactly `shares` from `owner_` and send the corresponding assets to `receiver`
  /// @dev Rounds assets up: the smallest normalized amount whose floor-rounded
  ///      scaling in the market's transfer moves exactly `shares`
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

  /// @notice Quarantine a sanctioned holder's direct market position and wrapper shares.
  /// @dev The optional wrapper coordinates into the already-deployed market and forwards any
  ///      trailing hook data, so the market never depends on wrapper deployment.
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

  /// @notice Sweep arbitrary ERC20 balances and any stranded wrapped market tokens.
  /// @dev For wrapped market sweeps, only the surplus over total supply is sweepable.
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

  /// @dev Remaining normalized assets before reaching the market's maxTotalSupply,
  ///      without sanctions checks (execution paths already enforce them).
  function _remainingCapacityAssets() internal view returns (uint256) {
    uint256 marketCap = _readMarketWord(IWildcatMarketToken.maxTotalSupply.selector);
    uint256 held = _readMarketWord(0x70a08231, address(this));
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
    assembly ('memory-safe') {
      // borrow the free-memory pointer for calldata and the first return word. nothing needs
      // this buffer after the assembly block, so leave 0x40 alone.
      let pointer := mload(0x40)

      // mstore puts the four-byte selector at the right edge of a 32-byte word. starting the
      // call at +0x1c skips the leading zeroes, so calldata is selector | principal | account.
      mstore(pointer, 0x06e74444)
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

  function _isSolvent() internal view returns (bool) {
    return
      _readMarketWord(IWildcatMarketToken.scaledBalanceOf.selector, address(this)) >= totalSupply();
  }

  function _isOperational() internal view returns (bool) {
    return !_isSanctioned(address(this)) && _isSolvent();
  }

  /// @dev wrapper deposits are plain market-token transfers, so they don't have hook data to
  ///      carry permission. keep this fail closed: if the policy probe breaks, report zero
  ///      capacity instead of breaking the ERC-4626 limit view too.
  function _canReceiveMarketTokens() internal view returns (bool allowed) {
    address policy = address(_transferPolicy);
    address marketAddress = address(wrappedMarket);
    assembly ('memory-safe') {
      // same layout again: the selector starts at +0x1c, then market and wrapper each get a
      // normal 32-byte ABI slot.
      let pointer := mload(0x40)
      mstore(pointer, 0x02439e44)
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
