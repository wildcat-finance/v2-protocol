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
  error CannotSweepMarketAsset();
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
    return marketCap - held;
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
    return _convertToSharesHalfUp(capAssets, scaleFactor);
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
    return _convertToAssetsHalfUp(shares, scaleFactor);
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
    uint256 expectedShares = _convertToSharesHalfUp(assets, scaleFactor);
    if (expectedShares == 0) revert ZeroShares();

    address assetAddress = address(wrappedMarket);
    uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));
    assetAddress.safeTransferFrom(msg.sender, address(this), assets);
    uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

    shares = scaledAfter - scaledBefore;
    if (shares < expectedShares) revert SharesMismatch(expectedShares, shares);

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
    if (assets == 0 || shares > _convertToSharesHalfUp(assets, scaleFactor)) {
      revert CapExceeded();
    }
  
    //  minimum assets for half-up rounding to yield `shares`
    uint256 numerator = shares * scaleFactor;
    uint256 halfSf = scaleFactor / 2;
    if (numerator <= halfSf) revert ZeroAssets();
    assets = (numerator - halfSf + RAY - 1) / RAY; // ceiling
  
    // Verify the formula produced the correct result
    uint256 expectedShares = _convertToSharesHalfUp(assets, scaleFactor);
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

  /// @notice Withdraw `assets` to `receiver`, burning shares from `owner_` using half-up rounding
  function withdraw(
    uint256 assets,
    address receiver,
    address owner_
  ) public override nonReentrant returns (uint256 shares) {
    _checkNotSanctioned(msg.sender);
    _checkNotSanctioned(receiver);
    if (assets == 0) revert ZeroAssets();

    uint256 scaleFactor = wrappedMarket.scaleFactor();
    shares = _convertToSharesHalfUp(assets, scaleFactor);
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

  /// @notice Redeem exactly `shares` from `owner_` and send the corresponding assets to `receiver` half-up rounding
  /// @dev Uses half-up rounding for assets to match the market behavior
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
    assets = _convertToAssetsHalfUp(shares, scaleFactor);
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

  /// @notice sweep arbitrary erc20 balances (excluding the wrapped market's debt token)
  /// @dev only the underlying market's borrower may call this. util for any case where
  ///      non-market tokens somehow accrue to the wrapper
  function sweep(address token, address to) external nonReentrant returns (uint256 amount) {
    if (msg.sender != marketOwner) revert NotMarketOwner();
    if (token == address(0) || to == address(0)) revert ZeroAddress();
    if (token == address(wrappedMarket)) revert CannotSweepMarketAsset();
    _checkNotSanctioned(to);

    amount = LibERC20.balanceOf(token, address(this));
    if (amount == 0) revert ZeroAssets();

    token.safeTransfer(to, amount);
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

  /// @dev half-up rounding to match the market's rayDiv behavior in transfers
  function _convertToSharesHalfUp(
    uint256 assets,
    uint256 scaleFactor
  ) internal pure returns (uint256) {
    return (assets * RAY + scaleFactor / 2) / scaleFactor;
  }

  /// @dev floor rounding for spec-compliant previews.
  function _convertToAssetsDown(
    uint256 shares,
    uint256 scaleFactor
  ) internal pure returns (uint256) {
    return MathUtils.mulDiv(shares, scaleFactor, RAY);
  }

  /// @dev half-up rounding to match the market's rayMul behavior in transfers
  function _convertToAssetsHalfUp(
    uint256 shares,
    uint256 scaleFactor
  ) internal pure returns (uint256) {
    return (shares * scaleFactor + RAY / 2) / RAY;
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
