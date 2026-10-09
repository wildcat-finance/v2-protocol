// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // Wildcat4626Wrapper
//  \ ^ /   Scaled ERC-4626 shares over rebasing Wildcat market tokens.
//    V
//
//  MARKET CONFIGURATION
//  hooks()
//  borrower()
//  borrowerPrincipal()
//  sentinel()
//  wrapperFactory()
//
//  SCALED ACCOUNTING
//  scaleFactor()
//  scaledBalanceOf(...)
//  maxTotalSupply()
//
//  SETUP
//  constructor(...)
//  _useVirtualShares()
//  _underlyingDecimals()
//
//  METADATA AND ASSETS
//  name()
//  symbol()
//  decimals()
//  market()
//  marketOwner()
//  asset()
//  totalAssets()
//
//  DEPOSITS
//  deposit(...)
//  maxDeposit(...)
//  previewDeposit(...)
//  mint(...)
//  _receiveAssets(...)
//  maxMint(...)
//  previewMint(...)
//  _maxDepositAndScaleFactor(...)
//  _remainingCapacityAssets()
//  _requireMarketTokenRecipientAllowed()
//  _canReceiveMarketTokens()
//
//  WITHDRAWALS
//  withdraw(...)
//  maxWithdraw(...)
//  previewWithdraw(...)
//  redeem(...)
//  _releaseAssets(...)
//  maxRedeem(...)
//  previewRedeem(...)
//
//  CONVERSIONS
//  convertToShares(...)
//  convertToAssets(...)
//  assetsPerShareRay()
//  sharesPerAssetRay()
//  _convertToSharesDown(...)
//  _convertToSharesUp(...)
//  _convertToAssetsDown(...)
//  _convertToAssetsUp(...)
//
//  SURPLUS RECOVERY
//  sweep(...)
//
//  SANCTIONS AND SHARE TRANSFERS
//  transferFrom(...)
//  nukeFromOrbit(...)
//  _beforeTokenTransfer(...)
//  _isEscrowRelease(...)
//  _getEscrowAddress(...)
//  _checkNotSanctioned(...)
//  _checkNotSanctioned(...)
//  _isSanctioned(...)
//  _isSanctioned(...)
//  _tryIsSanctioned(...)
//
//  OPERATIONAL CHECKS
//  _requireOperational(...)
//  _requireOperational(...)
//  _requireSolvent(...)
//  _isLimitOperational(...)
//
//  MARKET READERS
//  _scaleFactor()
//  _scaledBalance()
//  _borrowerPrincipal()
//  _borrower()
//  _marketBalance()
//  _tryReadMarketAddress(...)
//  _tryReadMarketWord(...)
//  _tryReadMarketWord(...)
//  _tryReadScaleFactor()
//  _tryStaticcallWord(...)
// ═════

import { ERC4626 } from 'solady/tokens/ERC4626.sol';
import { IERC20 } from 'openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC20Metadata } from 'openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { IMarketTransferPolicy } from '../access/IMarketTransferPolicy.sol';
import { IWildcatSanctionsSentinel } from '../interfaces/IWildcatSanctionsSentinel.sol';
import { ReentrancyGuard } from '../ReentrancyGuard.sol';
import { MathUtils, RAY } from '../libraries/MathUtils.sol';
import { LibERC20 } from '../libraries/LibERC20.sol';
import { HooksConfig, LibHooksConfig } from '../types/HooksConfig.sol';

// ┌─ IWildcatMarketToken ──────────────────────────────────────────────────────
/// @notice market-token surface the wrapper needs for scaled accounting and live borrower identity.
interface IWildcatMarketToken is IERC20Metadata {
  // ░░▒▒▓▓██ [ MARKET CONFIGURATION ] ─────────────────────────────────────────

  // ┌─ hooks ─────
  /// @notice packed hook address and enabled callbacks installed on the market.
  function hooks() external view returns (HooksConfig);

  // ┌─ borrower ─────
  /// @notice current operational borrower.
  function borrower() external view returns (address);

  // ┌─ borrowerPrincipal ─────
  /// @notice current registered borrower principal.
  function borrowerPrincipal() external view returns (address);

  // ┌─ sentinel ─────
  /// @notice sanctions sentinel used by the market.
  function sentinel() external view returns (address);

  // ┌─ wrapperFactory ─────
  /// @notice canonical factory allowed to register this market's wrapper.
  function wrapperFactory() external view returns (address);

  // ░░▒▒▓▓██ [ SCALED ACCOUNTING ] ────────────────────────────────────────────

  // ┌─ scaleFactor ─────
  /// @notice current ray-scaled conversion ratio from scaled shares to normalized tokens.
  function scaleFactor() external view returns (uint256);

  // ┌─ scaledBalanceOf ─────
  /// @notice direct scaled market-token balance for `account`.
  function scaledBalanceOf(address account) external view returns (uint256);

  // ┌─ maxTotalSupply ─────
  /// @notice normalized market deposit cap.
  function maxTotalSupply() external view returns (uint256);
}

// ┌─ Wildcat4626Wrapper ───────────────────────────────────────────────────────
/// @title Wildcat ERC-4626 wrapper
///
/// @notice turn a rebasing Wildcat market token into non-rebasing shares equal to scaled
///         ownership.
///
/// @dev conversions use the market scale factor, not `totalAssets() / totalSupply()`. execution is
///      only compatible with markets whose transfers round scaled amounts down. pre-V2.5 markets
///      round half-up and trip `SharesMismatch`, so wrappers must come through the generation-aware
///      `Wildcat4626WrapperFactory`.
contract Wildcat4626Wrapper is ERC4626, ReentrancyGuard {
  using LibHooksConfig for HooksConfig;
  using MathUtils for uint256;
  using LibERC20 for address;

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

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

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  /// @notice rebasing market token held as the ERC-4626 asset.
  IWildcatMarketToken public immutable wrappedMarket;

  /// @notice sanctions sentinel captured from the market at deployment.
  IWildcatSanctionsSentinel public immutable sanctionsSentinel;
  IMarketTransferPolicy internal immutable _transferPolicy;

  uint8 private immutable _decimals;
  string private _name;
  string private _symbol;

  /// @dev remembers which escrows currently have one release authorized by this wrapper.
  mapping(address escrow => bool authorized) private _authorizedEscrows;

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when the operational borrower recovers an ERC-20 balance or backing surplus.
  event TokensSwept(address indexed token, address indexed to, uint256 amount);

  /// @notice emitted when sanctioned wrapper shares move into their deterministic escrow.
  event SanctionedAccountSharesSentToEscrow(address indexed account, address indexed escrow, uint256 shares);

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param marketAddress Wildcat market token to wrap.
  ///
  /// @dev only the wrapper factory reported by the market can deploy this contract.
  constructor(address marketAddress) {
    if (marketAddress == address(0)) revert ZeroAddress();

    wrappedMarket = IWildcatMarketToken(marketAddress);
    if (msg.sender != wrappedMarket.wrapperFactory()) {
      revert NotWrapperFactory();
    }
    address currentBorrower = _borrower();
    if (currentBorrower == address(0)) revert ZeroAddress();
    if (_borrowerPrincipal() == address(0)) {
      revert ZeroAddress();
    }
    address sentinel = wrappedMarket.sentinel();
    if (sentinel == address(0)) revert ZeroAddress();
    sanctionsSentinel = IWildcatSanctionsSentinel(sentinel);
    HooksConfig hooksConfig = wrappedMarket.hooks();
    _transferPolicy = IMarketTransferPolicy(hooksConfig.hooksAddress());
    _decimals = wrappedMarket.decimals();

    string memory marketSymbol = IERC20Metadata(marketAddress).symbol();
    _name = string.concat(marketSymbol, ' [4626 Vault Shares]');
    _symbol = string.concat('v-', marketSymbol);
  }

  // ┌─ _useVirtualShares ─────
  /// @dev no virtual shares: conversions use the market's scale factor.
  function _useVirtualShares() internal pure override returns (bool) {
    return false;
  }

  // ┌─ _underlyingDecimals ─────
  function _underlyingDecimals() internal view override returns (uint8) {
    return _decimals;
  }

  // ░░▒▒▓▓██ [ METADATA AND ASSETS ] ──────────────────────────────────────────

  // ┌─ name ─────
  function name() public view override returns (string memory) {
    return _name;
  }

  // ┌─ symbol ─────
  function symbol() public view override returns (string memory) {
    return _symbol;
  }

  // ┌─ decimals ─────
  function decimals() public view override returns (uint8) {
    return _decimals;
  }

  // ┌─ market ─────
  /// @notice return the wrapped Wildcat market token.
  function market() public view returns (address) {
    return address(wrappedMarket);
  }

  // ┌─ marketOwner ─────
  /// @notice return the market's current operational borrower.
  ///
  /// @dev retained as a compatibility getter; sweep authorization reads the same live value.
  function marketOwner() public view returns (address) {
    return _borrower();
  }

  // ┌─ asset ─────
  /// @notice return the wrapped market as the ERC-4626 asset.
  function asset() public view override returns (address) {
    return address(wrappedMarket);
  }

  // ┌─ totalAssets ─────
  /// @notice return the normalized market-token balance currently held by the wrapper.
  ///
  /// @dev direct market-token transfers increase this without minting shares.
  function totalAssets() public view override returns (uint256) {
    return _marketBalance();
  }

  // ░░▒▒▓▓██ [ DEPOSITS ] ─────────────────────────────────────────────────────

  // market transfers move floor(amount * RAY / scaleFactor) scaled tokens
  // (`scaleAmountDown` since v2.5; earlier markets rounded half-up). every execution
  // path must satisfy SharesMismatch against that floor. asset-to-share amounts
  // round down; share-to-asset amounts round up to the smallest normalized amount
  // that moves exactly `shares`. the round-trip identity
  // floor(ceil(s * sf / RAY) * RAY / sf) == s requires scaleFactor >= RAY.
  // the market guarantees this: its scale factor starts at RAY and only grows.
  // previews keep their ERC-4626 rounding directions and bound execution as required.
  //
  // normalized amounts label exact scaled ownership. the `assets` returned by redeem
  // (and passed to withdraw) can exceed the receiver's `balanceOf` delta by up to one
  // scaled token's value: the rebasing balance view rounds separately from transfers.
  // reconcile `scaledBalanceOf` deltas, not `balanceOf`.
  // ┌─ deposit ─────
  /// @notice pull `assets` from the caller and mint the exact observed scaled increase to
  ///         `receiver`.
  ///
  /// @dev reverts on zero input, sanctions, insolvency, cap failure, recipient-policy denial, or a
  ///      scaled-balance mismatch.
  ///
  /// @return shares nonzero scaled market tokens credited by the transfer.
  function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
    _requireOperational(msg.sender, address(0));
    if (assets == 0) revert ZeroAssets();

    uint256 limit = _remainingCapacityAssets();
    if (assets > limit) revert CapExceeded();

    uint256 scaleFactor = _scaleFactor();
    // match the market transfer's floor-scaled credit exactly.
    shares = _convertToSharesDown(assets, scaleFactor);
    if (shares == 0) revert ZeroShares();

    _receiveAssets(assets, receiver, shares);
    return shares;
  }

  // ┌─ maxDeposit ─────
  /// @notice return the normalized assets the wrapper can accept for `receiver` right now.
  ///
  /// @dev returns zero if sanctions, wrapper health, wrapper capacity, rounding, or the market's
  ///      recipient policy would make the deposit fail.
  function maxDeposit(address receiver) public view override returns (uint256) {
    (uint256 capacity,) = _maxDepositAndScaleFactor(receiver);
    return capacity;
  }

  // ┌─ previewDeposit ─────
  /// @notice return shares quoted for depositing `assets`, rounded down.
  function previewDeposit(uint256 assets) public view override returns (uint256) {
    return convertToShares(assets);
  }

  // ┌─ mint ─────
  /// @notice mint exactly `shares` to `receiver` and pull the minimum matching asset amount.
  ///
  /// @return assets normalized market tokens pulled from the caller.
  function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
    _requireOperational(msg.sender, address(0));
    if (shares == 0) revert ZeroShares();
    uint256 scaleFactor = _scaleFactor();
    assets = _remainingCapacityAssets();
    if (assets == 0 || shares > _convertToSharesDown(assets, scaleFactor)) {
      revert CapExceeded();
    }

    // ceiling conversion is the minimum asset amount that floor-scales to exactly `shares`.
    assets = _convertToAssetsUp(shares, scaleFactor);

    uint256 expectedShares = _convertToSharesDown(assets, scaleFactor);
    if (expectedShares != shares) revert SharesMismatch(shares, expectedShares);

    _receiveAssets(assets, receiver, shares);
  }

  // ┌─ _receiveAssets ─────
  /// @dev mint only the scaled backing actually received; market transfers can round or reject.
  function _receiveAssets(uint256 assets, address receiver, uint256 shares) private {
    _requireMarketTokenRecipientAllowed();

    address assetAddress = address(wrappedMarket);
    uint256 scaledBefore = _scaledBalance();
    assetAddress.safeTransferFrom(msg.sender, address(this), assets);
    uint256 scaledAfter = _scaledBalance();

    uint256 mintedShares = scaledAfter - scaledBefore;
    if (mintedShares != shares) revert SharesMismatch(shares, mintedShares);

    _mint(receiver, shares);
    _requireSolvent(scaledAfter);
    emit Deposit(msg.sender, receiver, assets, shares);
  }

  // ┌─ maxMint ─────
  /// @notice return shares the wrapper can mint for `receiver` right now.
  ///
  /// @dev reads capacity and scale together. dependency failures close the limit to zero.
  function maxMint(address receiver) public view override returns (uint256) {
    (uint256 capAssets, uint256 scaleFactor) = _maxDepositAndScaleFactor(receiver);
    if (capAssets == 0) return 0;
    // use the same floor scaling as mint's capacity check.
    return _convertToSharesDown(capAssets, scaleFactor);
  }

  // ┌─ previewMint ─────
  /// @notice return assets required to mint `shares`, rounded up.
  function previewMint(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = _scaleFactor();
    return _convertToAssetsUp(shares, scaleFactor);
  }

  // ┌─ _maxDepositAndScaleFactor ─────
  /// @dev read capacity and scale together. a strict scale read after a safe maxDeposit would
  ///      let a broken dependency revert maxMint instead of returning zero.
  function _maxDepositAndScaleFactor(address receiver) internal view returns (uint256 capacity, uint256 scaleFactor) {
    if (!_isLimitOperational(receiver)) return (0, 0);
    if (!_canReceiveMarketTokens()) return (0, 0);

    (bool success, uint256 marketCap) = _tryReadMarketWord(IWildcatMarketToken.maxTotalSupply.selector);
    // market storage gives maxTotalSupply uint128. keep the same bound here so malformed data
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

  // ┌─ _remainingCapacityAssets ─────
  /// @dev remaining normalized assets before reaching the market's maxTotalSupply,
  ///      without sanctions checks (execution paths already enforce them).
  function _remainingCapacityAssets() internal view returns (uint256) {
    uint256 marketCap = wrappedMarket.maxTotalSupply();
    uint256 held = _marketBalance();
    if (held >= marketCap) return 0;
    return marketCap - held;
  }

  // ┌─ _requireMarketTokenRecipientAllowed ─────
  /// @dev enforce the same live recipient policy used by maxDeposit and maxMint.
  function _requireMarketTokenRecipientAllowed() internal view {
    if (!_canReceiveMarketTokens()) revert MarketTokenRecipientNotAllowed();
  }

  // ┌─ _canReceiveMarketTokens ─────
  /// @dev wrapper deposits are plain market-token transfers, so they don't have hook data to
  ///      carry permission. keep this fail closed: if the policy probe breaks, report zero
  ///      capacity instead of breaking the ERC-4626 limit view too.
  function _canReceiveMarketTokens() internal view returns (bool allowed) {
    (bool success, uint256 word) = _tryStaticcallWord(
      address(_transferPolicy),
      abi.encodeCall(IMarketTransferPolicy.isMarketTransferRecipientAllowed, (address(wrappedMarket), address(this)))
    );
    // only a canonical true opens capacity; false and malformed answers stay closed.
    return success && word == 1;
  }

  // ░░▒▒▓▓██ [ WITHDRAWALS ] ──────────────────────────────────────────────────

  // ┌─ withdraw ─────
  /// @notice send `assets` to `receiver` and burn the exact scaled amount the market transfer
  ///         moves.
  ///
  /// @dev delegated callers spend `owner_` allowance against the execution amount, which rounds
  ///      down.
  ///
  /// @return shares scaled wrapper shares burned from `owner_`.
  function withdraw(
    uint256 assets,
    address receiver,
    address owner_
  )
    public
    override
    nonReentrant
    returns (uint256 shares)
  {
    _requireOperational(msg.sender, receiver);
    if (assets == 0) revert ZeroAssets();

    uint256 scaleFactor = _scaleFactor();
    // match the market transfer's floor-scaled debit exactly.
    shares = _convertToSharesDown(assets, scaleFactor);
    if (shares == 0) revert ZeroShares();

    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    _releaseAssets(assets, receiver, owner_, shares);
  }

  // ┌─ maxWithdraw ─────
  /// @notice return the largest normalized amount `owner_` can pull through `withdraw`.
  ///
  /// @dev returns zero if sanctions, insolvency, or a dependency read closes the limit. a nonzero
  ///      result consumes the owner's complete share balance under market floor rounding.
  function maxWithdraw(address owner_) public view override returns (uint256) {
    if (!_isLimitOperational(owner_)) return 0;
    uint256 shares = balanceOf(owner_);
    if (shares == 0) return 0;
    (bool success, uint256 scaleFactor) = _tryReadScaleFactor();
    if (!success) return 0;
    // stay one asset unit below the first amount that would burn `shares + 1`.
    // with scaleFactor >= RAY, this burns exactly the nonzero `shares` balance.
    return MathUtils.mulDivUp(shares + 1, scaleFactor, RAY) - 1;
  }

  // ┌─ previewWithdraw ─────
  /// @notice return the ERC-4626 preview of shares for `assets`, rounded up.
  function previewWithdraw(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = _scaleFactor();
    return _convertToSharesUp(assets, scaleFactor);
  }

  // ┌─ redeem ─────
  /// @notice burn exactly `shares` from `owner_` and send the matching assets to `receiver`.
  ///
  /// @dev execution rounds assets up to the smallest normalized amount whose floor-rounded market
  ///      transfer moves exactly `shares`. delegated callers spend the owner's allowance.
  ///
  /// @return assets normalized market tokens sent to `receiver`.
  function redeem(
    uint256 shares,
    address receiver,
    address owner_
  )
    public
    override
    nonReentrant
    returns (uint256 assets)
  {
    _requireOperational(msg.sender, receiver);
    if (shares == 0) revert ZeroShares();

    if (msg.sender != owner_) {
      _spendAllowance(owner_, msg.sender, shares);
    }

    uint256 scaleFactor = _scaleFactor();
    // ceiling conversion makes the floor-rounded market transfer move exactly `shares`.
    assets = _convertToAssetsUp(shares, scaleFactor);
    if (assets == 0) revert ZeroAssets();

    _releaseAssets(assets, receiver, owner_, shares);
  }

  // ┌─ _releaseAssets ─────
  /// @dev burn before transferring, then verify the exact scaled debit and remaining backing.
  function _releaseAssets(uint256 assets, address receiver, address owner_, uint256 shares) private {
    uint256 scaledBefore = _scaledBalance();

    _burn(owner_, shares);
    address assetAddress = address(wrappedMarket);
    assetAddress.safeTransfer(receiver, assets);
    uint256 scaledAfter = _scaledBalance();

    uint256 burnedShares = scaledBefore - scaledAfter;
    if (burnedShares != shares) revert SharesMismatch(shares, burnedShares);
    _requireSolvent(scaledAfter);

    emit Withdraw(msg.sender, receiver, owner_, assets, shares);
  }

  // ┌─ maxRedeem ─────
  /// @notice return all shares `owner_` can currently redeem.
  ///
  /// @dev returns zero if sanctions, insolvency, or a dependency read closes the limit.
  function maxRedeem(address owner_) public view override returns (uint256) {
    if (!_isLimitOperational(owner_)) return 0;
    return balanceOf(owner_);
  }

  // ┌─ previewRedeem ─────
  /// @notice return the ERC-4626 preview of assets for `shares`, rounded down.
  function previewRedeem(uint256 shares) public view override returns (uint256) {
    return convertToAssets(shares);
  }

  // ░░▒▒▓▓██ [ CONVERSIONS ] ──────────────────────────────────────────────────

  // ┌─ convertToShares ─────
  /// @notice convert normalized `assets` to scaled shares, rounding down.
  ///
  /// @dev this is a pure exchange-rate quote; it ignores sanctions, capacity, and transfer policy.
  function convertToShares(uint256 assets) public view override returns (uint256) {
    if (assets == 0) return 0;
    uint256 scaleFactor = _scaleFactor();
    return _convertToSharesDown(assets, scaleFactor);
  }

  // ┌─ convertToAssets ─────
  /// @notice convert scaled `shares` to normalized assets, rounding down.
  ///
  /// @dev this is a pure exchange-rate quote; it ignores sanctions and wrapper solvency.
  function convertToAssets(uint256 shares) public view override returns (uint256) {
    if (shares == 0) return 0;
    uint256 scaleFactor = _scaleFactor();
    return _convertToAssetsDown(shares, scaleFactor);
  }

  // ┌─ assetsPerShareRay ─────
  /// @notice return assets per share as a ray (`1e27`).
  ///
  /// @dev exactly the market scale factor.
  function assetsPerShareRay() external view returns (uint256) {
    return _scaleFactor();
  }

  // ┌─ sharesPerAssetRay ─────
  /// @notice return shares per asset as a ray (`1e27`), rounded down.
  ///
  /// @dev the floored ray inverse of the market scale factor.
  function sharesPerAssetRay() external view returns (uint256) {
    return MathUtils.mulDiv(RAY, RAY, _scaleFactor());
  }

  // ┌─ _convertToSharesDown ─────
  /// @dev floor rounding for spec-compliant previews.
  function _convertToSharesDown(uint256 assets, uint256 scaleFactor) internal pure returns (uint256) {
    return MathUtils.mulDiv(assets, RAY, scaleFactor);
  }

  // ┌─ _convertToSharesUp ─────
  /// @dev ceiling rounding for ERC-4626 compliant previews (previewWithdraw).
  function _convertToSharesUp(uint256 assets, uint256 scaleFactor) internal pure returns (uint256) {
    return MathUtils.mulDivUp(assets, RAY, scaleFactor);
  }

  // ┌─ _convertToAssetsDown ─────
  /// @dev floor rounding for spec-compliant previews.
  function _convertToAssetsDown(uint256 shares, uint256 scaleFactor) internal pure returns (uint256) {
    return MathUtils.mulDiv(shares, scaleFactor, RAY);
  }

  // ┌─ _convertToAssetsUp ─────
  /// @dev ceiling rounding for ERC-4626 compliant previews (previewMint).
  function _convertToAssetsUp(uint256 shares, uint256 scaleFactor) internal pure returns (uint256) {
    return MathUtils.mulDivUp(shares, scaleFactor, RAY);
  }

  // ░░▒▒▓▓██ [ SURPLUS RECOVERY ] ─────────────────────────────────────────────

  // ┌─ sweep ─────
  /// @notice sweep an ERC-20 balance to `to` for the market's current operational borrower.
  ///
  /// @dev other tokens sweep in full. the market token only sweeps scaled backing above share
  ///      supply and verifies that exact surplus moved. `to` must not be sanctioned.
  ///
  /// @param token ERC-20 to recover. use the market token to recover only scaled backing surplus.
  /// @param to    recipient of the recovered tokens.
  ///
  /// @return amount token units sent to `to`.
  function sweep(address token, address to) external nonReentrant returns (uint256 amount) {
    if (msg.sender != _borrower()) {
      revert NotMarketOwner();
    }
    if (token == address(0) || to == address(0)) revert ZeroAddress();
    _checkNotSanctioned(to);

    if (token == address(wrappedMarket)) {
      uint256 scaledBefore = _scaledBalance();
      uint256 expectedScaled = totalSupply();
      if (scaledBefore <= expectedScaled) revert ZeroAssets();

      uint256 strandedScaled = scaledBefore - expectedScaled;
      uint256 scaleFactor = _scaleFactor();
      // ceiling conversion sweeps exactly the scaled surplus, not backing for live shares.
      amount = _convertToAssetsUp(strandedScaled, scaleFactor);
      if (amount == 0) revert ZeroAssets();

      token.safeTransfer(to, amount);

      uint256 scaledAfter = _scaledBalance();
      uint256 sweptScaled = scaledBefore - scaledAfter;
      if (sweptScaled != strandedScaled) revert SharesMismatch(strandedScaled, sweptScaled);
    } else {
      amount = LibERC20.balanceOf(token, address(this));
      if (amount == 0) revert ZeroAssets();

      token.safeTransfer(to, amount);
    }

    emit TokensSwept(token, to, amount);
  }

  // ░░▒▒▓▓██ [ SANCTIONS AND SHARE TRANSFERS ] ────────────────────────────────

  // ┌─ transferFrom ─────
  /// @notice transfer shares using an unsanctioned caller's allowance.
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    _checkNotSanctioned(msg.sender);
    return super.transferFrom(from, to, amount);
  }

  // ┌─ nukeFromOrbit ─────
  /// @notice quarantine a sanctioned holder's direct market position and wrapper shares.
  ///
  /// @dev anyone can call this. the wrapper forwards the complete calldata, including trailing hook
  ///      data, to the market before moving all wrapper shares to their deterministic escrow.
  ///
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

    address escrow = sanctionsSentinel.createEscrow(_borrowerPrincipal(), account, address(this));
    _authorizedEscrows[escrow] = true;
    _transfer(account, escrow, shares);
    emit SanctionedAccountSharesSentToEscrow(account, escrow, shares);
  }

  // ┌─ _beforeTokenTransfer ─────
  /// @dev enforces solvency and sanctions on share moves. a sanctioned holder may only move to its
  ///      deterministic escrow; an authorized escrow gets one release under its original principal.
  function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
    address principal = _borrowerPrincipal();
    bool fromIsSanctioned = _isSanctioned(from, principal);
    bool toIsSanctioned = _isSanctioned(to, principal);
    bool isEscrowRelease = _isEscrowRelease(from, to);
    if ((fromIsSanctioned || toIsSanctioned) && isEscrowRelease) {
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
    if (isEscrowRelease) {
      delete _authorizedEscrows[from];
    }
  }

  // ┌─ _isEscrowRelease ─────
  /// @dev `from` only gets the release exception if this wrapper currently authorizes it and it
  ///      still matches `account` under its original principal.
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

  // ┌─ _getEscrowAddress ─────
  function _getEscrowAddress(address principal, address account) internal view returns (address escrow) {
    return sanctionsSentinel.getEscrowAddress(principal, account, address(this));
  }

  // ┌─ _checkNotSanctioned ─────
  function _checkNotSanctioned(address account) internal view {
    if (_isSanctioned(account)) {
      revert SanctionedAccount(account);
    }
  }

  // ┌─ _checkNotSanctioned ─────
  function _checkNotSanctioned(address account, address principal) internal view {
    if (_isSanctioned(account, principal)) {
      revert SanctionedAccount(account);
    }
  }

  // ┌─ _isSanctioned ─────
  function _isSanctioned(address account) internal view returns (bool) {
    if (account == address(0)) return false;
    return _isSanctioned(account, _borrowerPrincipal());
  }

  // ┌─ _isSanctioned ─────
  function _isSanctioned(address account, address principal) internal view returns (bool isSanctioned_) {
    return account != address(0) && sanctionsSentinel.isSanctioned(principal, account);
  }

  // ┌─ _tryIsSanctioned ─────
  /// @dev max* version of the sanctions check: a broken read closes the limit instead of reverting.
  function _tryIsSanctioned(
    address account,
    address principal
  )
    internal
    view
    returns (bool success, bool isSanctioned_)
  {
    if (account == address(0)) return (true, false);
    uint256 word;
    (success, word) = _tryStaticcallWord(
      address(sanctionsSentinel), abi.encodeCall(IWildcatSanctionsSentinel.isSanctioned, (principal, account))
    );
    if (!success || word > 1) return (false, false);
    return (true, word == 1);
  }

  // ░░▒▒▓▓██ [ OPERATIONAL CHECKS ] ───────────────────────────────────────────

  // ┌─ _requireOperational ─────
  function _requireOperational(address principal) internal view {
    _checkNotSanctioned(address(this), principal);
    _requireSolvent(_scaledBalance());
  }

  // ┌─ _requireOperational ─────
  function _requireOperational(address account, address secondAccount) internal view {
    address principal = _borrowerPrincipal();
    _checkNotSanctioned(account, principal);
    _checkNotSanctioned(secondAccount, principal);
    _checkNotSanctioned(address(this), principal);
    _requireSolvent(_scaledBalance());
  }

  // ┌─ _requireSolvent ─────
  function _requireSolvent(uint256 scaledBacking) internal view {
    uint256 shareSupply = totalSupply();
    // don't let new deposits recapitalize existing shareholders' claims.
    if (scaledBacking < shareSupply) revert InsolventWrapper(scaledBacking, shareSupply);
  }

  // ┌─ _isLimitOperational ─────
  /// @dev max* version of the operational check. every external answer has to be present and
  ///      shaped like a canonical market value, or the limit stays closed.
  function _isLimitOperational(address account) internal view returns (bool) {
    (bool success, address principal) = _tryReadMarketAddress(IWildcatMarketToken.borrowerPrincipal.selector);
    if (!success || principal == address(0)) return false;

    bool sanctioned;
    (success, sanctioned) = _tryIsSanctioned(account, principal);
    if (!success || sanctioned) return false;
    if (account != address(this)) {
      (success, sanctioned) = _tryIsSanctioned(address(this), principal);
      if (!success || sanctioned) return false;
    }

    uint256 scaledBacking;
    (success, scaledBacking) = _tryReadMarketWord(IWildcatMarketToken.scaledBalanceOf.selector, address(this));
    // market account balances are uint104. once backing fits and covers totalSupply,
    // maxWithdraw can safely do shares + 1 and shares * scaleFactor.
    return success && scaledBacking <= type(uint104).max && scaledBacking >= totalSupply();
  }

  // ░░▒▒▓▓██ [ MARKET READERS ] ───────────────────────────────────────────────

  // ┌─ _scaleFactor ─────
  function _scaleFactor() private view returns (uint256) {
    return wrappedMarket.scaleFactor();
  }

  // ┌─ _scaledBalance ─────
  function _scaledBalance() private view returns (uint256) {
    return wrappedMarket.scaledBalanceOf(address(this));
  }

  // ┌─ _borrowerPrincipal ─────
  function _borrowerPrincipal() private view returns (address) {
    return wrappedMarket.borrowerPrincipal();
  }

  // ┌─ _borrower ─────
  function _borrower() private view returns (address) {
    return wrappedMarket.borrower();
  }

  // ┌─ _marketBalance ─────
  function _marketBalance() private view returns (uint256) {
    return wrappedMarket.balanceOf(address(this));
  }

  // ┌─ _tryReadMarketAddress ─────
  function _tryReadMarketAddress(bytes4 selector) internal view returns (bool success, address value) {
    uint256 word;
    (success, word) = _tryReadMarketWord(selector);
    // an ABI address gets 160 low bits and 96 zero bits. don't quietly truncate dirty padding.
    if (!success || word > type(uint160).max) return (false, address(0));
    value = address(uint160(word));
  }

  // ┌─ _tryReadMarketWord ─────
  /// @dev max* needs a reader that reports failure instead of bubbling it.
  function _tryReadMarketWord(bytes4 selector) internal view returns (bool success, uint256 value) {
    return _tryStaticcallWord(address(wrappedMarket), abi.encodeWithSelector(selector));
  }

  // ┌─ _tryReadMarketWord ─────
  /// @dev max* version of the one-argument market reader.
  function _tryReadMarketWord(bytes4 selector, address account) internal view returns (bool success, uint256 value) {
    return _tryStaticcallWord(address(wrappedMarket), abi.encodeWithSelector(selector, account));
  }

  // ┌─ _tryReadScaleFactor ─────
  function _tryReadScaleFactor() internal view returns (bool success, uint256 scaleFactor) {
    (success, scaleFactor) = _tryReadMarketWord(IWildcatMarketToken.scaleFactor.selector);
    // market storage gives this uint112, starts it at RAY, and only moves it up. keeping those
    // bounds here also keeps the later max* multiplication inside uint256.
    if (!success || scaleFactor < RAY || scaleFactor > type(uint112).max) {
      return (false, 0);
    }
  }

  // ┌─ _tryStaticcallWord ─────
  /// @dev failed or short responses are unavailable. copy only the first word, so oversized
  ///      returndata cannot force a memory-expansion revert in a non-reverting limit view.
  function _tryStaticcallWord(address target, bytes memory callData)
    private
    view
    returns (bool success, uint256 value)
  {
    assembly ('memory-safe') {
      success := staticcall(gas(), target, add(callData, 0x20), mload(callData), 0, 0x20)
      success := and(success, iszero(lt(returndatasize(), 0x20)))
      if success { value := mload(0) }
    }
  }
}
