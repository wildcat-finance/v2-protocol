// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import { ERC4626 } from 'solady/tokens/ERC4626.sol';
import { IERC20Metadata } from 'openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IWildcatSanctionsSentinel } from '../interfaces/IWildcatSanctionsSentinel.sol';
import { ReentrancyGuard } from '../ReentrancyGuard.sol';
import { MathUtils, RAY } from '../libraries/MathUtils.sol';
import { LibERC20 } from '../libraries/LibERC20.sol';

interface IWildcatMarketToken is IERC20Metadata {
  function scaleFactor() external view returns (uint256);

  function scaledBalanceOf(address account) external view returns (uint256);

  function borrower() external view returns (address);

  function maxTotalSupply() external view returns (uint256);

  function sentinel() external view returns (address);
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
  using MathUtils for uint256;
  using LibERC20 for address;

  error ZeroAddress();
  error ZeroAssets();
  error ZeroShares();
  error CapExceeded();
  error SharesMismatch(uint256 expected, uint256 actual);
  error NotMarketOwner();
  error SanctionedAccount(address account);

  IWildcatMarketToken public immutable wrappedMarket;
  address public immutable marketOwner;
  IWildcatSanctionsSentinel public immutable sanctionsSentinel;

  uint8 private immutable _decimals;
  string private _name;
  string private _symbol;

  /**
   * @param marketAddress the wildcat market (debt token) address to wrap
   */
  constructor(address marketAddress) {
    if (marketAddress == address(0)) revert ZeroAddress();

    wrappedMarket = IWildcatMarketToken(marketAddress);
    address owner = wrappedMarket.borrower();
    if (owner == address(0)) revert ZeroAddress();
    address sentinel = wrappedMarket.sentinel();
    if (sentinel == address(0)) revert ZeroAddress();
    marketOwner = owner;
    sanctionsSentinel = IWildcatSanctionsSentinel(sentinel);
    _decimals = wrappedMarket.decimals();

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

  // -------------------------------------------------------------------------
  // ERC4626 View Interface
  // -------------------------------------------------------------------------

  /// @notice Address of the wrapped Wildcat market token.
  function market() public view returns (address) {
    return address(wrappedMarket);
  }

  /// @notice Alias for the wrapped market so integrators can treat it as the ERC-4626 asset.
  function asset() public view override returns (address) {
    return address(wrappedMarket);
  }

  /// @notice Total normalized market tokens the wrapper currently custodies.
  function totalAssets() public view override returns (uint256) {
    return wrappedMarket.balanceOf(address(this));
  }

  /// @notice Preview how many shares a deposit of `assets` would mint (rounded down per erc4626)
  function convertToShares(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = wrappedMarket.scaleFactor();
    return _convertToSharesDown(assets, scaleFactor);
  }

  /// @notice Preview how many assets burning `shares` yields (rounded down per ERC-4626)
  function convertToAssets(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = wrappedMarket.scaleFactor();
    return _convertToAssetsDown(shares, scaleFactor);
  }

  /// @notice Remaining normalized assets the wrapper can accept before hitting the market's maxTotalSupply
  /// @dev Returns 0 for sanctioned receivers per erc4626 (deposit would revert)
  function maxDeposit(address receiver) public view override returns (uint256) {
    if (_isSanctioned(receiver)) return 0;
    uint256 marketCap = wrappedMarket.maxTotalSupply();
    uint256 held = totalAssets();
    if (held >= marketCap) return 0;
    uint256 capacity = marketCap - held;
    // A capacity worth less than one scaled token would mint zero shares and
    // revert; per spec, maxDeposit must be executable.
    uint256 scaleFactor = wrappedMarket.scaleFactor();
    if (_convertToSharesDown(capacity, scaleFactor) == 0) return 0;
    return capacity;
  }

  /// @notice Shares minted for depositing `assets`, rounded down per spec.
  function previewDeposit(uint256 assets) public view override returns (uint256) {
    return convertToShares(assets);
  }

  /// @notice Remaining shares that could be minted without violating the market's maxTotalSupply
  /// @dev Returns 0 for sanctioned receivers per erc4626 (mint would revert)
  function maxMint(address receiver) public view override returns (uint256) {
    uint256 capAssets = maxDeposit(receiver);
    if (capAssets == 0) return 0;
    uint256 scaleFactor = wrappedMarket.scaleFactor();
    // Max shares obtainable from the remaining capacity under floor scaling;
    // matches the cap check in `mint`.
    return _convertToSharesDown(capAssets, scaleFactor);
  }

  /// @notice Assets required to mint `shares`, rounded up (ceiling) per ERC4626
  function previewMint(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = wrappedMarket.scaleFactor();
    return _convertToAssetsUp(shares, scaleFactor);
  }

  /// @notice Maximum assets `owner_` can pull via `withdraw`, using half-up rounding
  /// @dev Returns 0 for sanctioned owners per erc 4626 (withdraw would revert)
  function maxWithdraw(address owner_) public view override returns (uint256) {
    if (_isSanctioned(owner_)) return 0;
    uint256 shares = balanceOf(owner_);
    if (shares == 0) return 0;
    uint256 scaleFactor = wrappedMarket.scaleFactor();
    // Largest amount whose floor-rounded scaling burns no more than `shares`:
    // one below the smallest amount that would need `shares + 1`. Guaranteed
    // executable: it burns exactly `shares` (>= 1).
    return MathUtils.mulDivUp(shares + 1, scaleFactor, RAY) - 1;
  }

  /// @notice Shares that would be burned to withdraw `assets`, rounded up (ceiling) per ERC-4626
  function previewWithdraw(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = wrappedMarket.scaleFactor();
    return _convertToSharesUp(assets, scaleFactor);
  }

  /// @notice All shares `owner_` currently holds.
  /// @dev Returns 0 for sanctioned owners per ERC-4626 (redeem would revert)
  function maxRedeem(address owner_) public view override returns (uint256) {
    if (_isSanctioned(owner_)) return 0;
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
    return wrappedMarket.scaleFactor();
  }

  /// @notice Returns the current exchange rate of shares per asset, scaled by RAY (1e27).
  /// @dev This is the inverse of the scale factor to see
  ///      how many shares a given asset amount would yield.
  function sharesPerAssetRay() external view returns (uint256) {
    return MathUtils.mulDiv(RAY, RAY, wrappedMarket.scaleFactor());
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
    _checkNotSanctioned(msg.sender);
    if (assets == 0) revert ZeroAssets();

    uint256 limit = _remainingCapacityAssets();
    if (assets > limit) revert CapExceeded();

    uint256 scaleFactor = wrappedMarket.scaleFactor();
    // The market transfer credits floor-scaled tokens; expect exactly that.
    uint256 expectedShares = _convertToSharesDown(assets, scaleFactor);
    if (expectedShares == 0) revert ZeroShares();

    address assetAddress = address(wrappedMarket);
    uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));
    assetAddress.safeTransferFrom(msg.sender, address(this), assets);
    uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

    shares = scaledAfter - scaledBefore;
    if (shares != expectedShares) revert SharesMismatch(expectedShares, shares);

    _mint(receiver, shares);
    emit Deposit(msg.sender, receiver, assets, shares);
    return shares;
  }

  /// @notice Mint exactly `shares` to `receiver`, pulling the minimum required assets from caller
  function mint(
    uint256 shares,
    address receiver
  ) public override nonReentrant returns (uint256 assets) {
    _checkNotSanctioned(msg.sender);
    if (shares == 0) revert ZeroShares();
    uint256 scaleFactor = wrappedMarket.scaleFactor();
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
    uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));
    assetAddress.safeTransferFrom(msg.sender, address(this), assets);
    uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

    uint256 mintedShares = scaledAfter - scaledBefore;
    if (mintedShares != shares) revert SharesMismatch(shares, mintedShares);

    _mint(receiver, shares);
    emit Deposit(msg.sender, receiver, assets, shares);
  }

  /// @notice Withdraw `assets` to `receiver`, burning from `owner_` exactly the
  ///         shares the market's floor-rounded transfer moves
  function withdraw(
    uint256 assets,
    address receiver,
    address owner_
  ) public override nonReentrant returns (uint256 shares) {
    _checkNotSanctioned(msg.sender);
    _checkNotSanctioned(receiver);
    if (assets == 0) revert ZeroAssets();

    uint256 scaleFactor = wrappedMarket.scaleFactor();
    // Exactly the scaled amount the market's floor-rounded transfer will burn.
    shares = _convertToSharesDown(assets, scaleFactor);
    if (shares == 0) revert ZeroShares();

    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));

    _burn(owner_, shares);
    address assetAddress = address(wrappedMarket);
    assetAddress.safeTransfer(receiver, assets);
    uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

    uint256 burnedShares = scaledBefore - scaledAfter;
    if (burnedShares != shares) revert SharesMismatch(shares, burnedShares);
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
    _checkNotSanctioned(msg.sender);
    _checkNotSanctioned(receiver);
    if (shares == 0) revert ZeroShares();

    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    uint256 scaleFactor = wrappedMarket.scaleFactor();
    // Smallest normalized amount whose floor-rounded transfer moves `shares`.
    assets = _convertToAssetsUp(shares, scaleFactor);
    if (assets == 0) revert ZeroAssets();

    uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));

    _burn(owner_, shares);
    address assetAddress = address(wrappedMarket);
    assetAddress.safeTransfer(receiver, assets);
    uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

    uint256 burnedShares = scaledBefore - scaledAfter;
    if (burnedShares != shares) revert SharesMismatch(shares, burnedShares);

    emit Withdraw(msg.sender, receiver, owner_, assets, shares);
  }

  /// @notice Sweep arbitrary ERC20 balances and any stranded wrapped market tokens.
  /// @dev For wrapped market sweeps, only the surplus over total supply is sweepable.
  function sweep(address token, address to) external nonReentrant returns (uint256 amount) {
    if (msg.sender != marketOwner) revert NotMarketOwner();
    if (token == address(0) || to == address(0)) revert ZeroAddress();
    _checkNotSanctioned(to);

    if (token == address(wrappedMarket)) {
      uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));
      uint256 expectedScaled = totalSupply();
      if (scaledBefore <= expectedScaled) revert ZeroAssets();

      uint256 strandedScaled = scaledBefore - expectedScaled;
      uint256 scaleFactor = wrappedMarket.scaleFactor();
      // Smallest normalized amount that sweeps exactly the stranded scaled
      // tokens without touching the backing for outstanding shares.
      amount = _convertToAssetsUp(strandedScaled, scaleFactor);
      if (amount == 0) revert ZeroAssets();

      token.safeTransfer(to, amount);

      uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));
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

  /// @dev Remaining normalized assets before reaching the market's maxTotalSupply,
  ///      without sanctions checks (execution paths already enforce them).
  function _remainingCapacityAssets() internal view returns (uint256) {
    uint256 marketCap = wrappedMarket.maxTotalSupply();
    uint256 held = wrappedMarket.balanceOf(address(this));
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
    return account != address(0) && sanctionsSentinel.isSanctioned(marketOwner, account);
  }

  function _checkNotSanctioned(address account) internal view {
    if (_isSanctioned(account)) {
      revert SanctionedAccount(account);
    }
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    _checkNotSanctioned(from);
    _checkNotSanctioned(to);
    if (amount == 0) {
      return;
    }
  }
}
