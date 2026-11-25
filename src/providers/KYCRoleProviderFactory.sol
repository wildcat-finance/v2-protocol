// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderFactory
//  \ ^ /   Canonical KYC policies, borrower allowances, and hooks authorization.
//    V
//
//  EXTERNAL INTERFACES
//  IKYCHooksFactory.isHooksInstance(...)
//  IKYCHooksFactory.getMarketsForHooksInstanceCount(...)
//  IKYCHooksFactory.getMarketsForHooksInstance(...)
//  IKYCHooksInstance.borrower()
//  IKYCMarket.updateState()
//  IKYCMarket.isClosed()
//
//  SETUP
//  constructor(...)
//
//  CONFIGURATION
//  setHooksFactory(...)
//  _setHooksFactory(...)
//  setSlotReclamationEnabled(...)
//  setBorrowerAllowance(...)
//
//  POLICY CATALOG
//  deployRoleProvider(...)
//  _validatePolicy(...)
//  setProviderAttachmentEnabled(...)
//  isRoleProvider(...)
//  getRoleProvidersCount()
//  getRoleProviders()
//  getRoleProviders(...)
//
//  ENTITLEMENTS
//  createRoleProvider(...)
//  authorizeHooks(...)
//  authorizeHooks(...)
//  _authorizeHooks(...)
//  _authorizeNewHooks(...)
//  _reclaimPreClosedMarkets(...)
//  _expandHooksAuthorization(...)
//  reduceUnusedSlots(...)
//  migrateHooksBorrower(...)
//  reclaimClosedMarket(...)
//  reclaimClosedMarkets(...)
//  _reclaimClosedMarket(...)
//  isHooksAuthorized(...)
//
//  QUERIES
//  isApprovedHooksFactory(...)
//  getApprovedHooksFactories()
//  getHooksAuthorization(...)
//  getBorrowerAuthorizedHooksCount(...)
//  getBorrowerAuthorizedHooks(...)
//  _paginate(...)
// ═════

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { SafeCastLib } from '../libraries/SafeCastLib.sol';
import { IKYCRegistry } from './IKYCRegistry.sol';
import {
  ClosedMarketClaim,
  HooksAuthorization,
  IKYCRoleProviderFactory,
  KYCRoleProviderAttachInputs
} from './IKYCRoleProviderFactory.sol';
import { KYCRoleProvider } from './KYCRoleProvider.sol';
import { ManagedRoleProvider } from './ManagedRoleProvider.sol';

// ┌─ IKYCHooksFactory ─────────────────────────────────────────────────────────
/// @dev minimal `HooksFactory` read surface shared by v2.0/v2.1 and v2.5 factories.
interface IKYCHooksFactory {
  // ┌─ isHooksInstance ─────
  function isHooksInstance(address hooksInstance) external view returns (bool);

  // ┌─ getMarketsForHooksInstanceCount ─────
  function getMarketsForHooksInstanceCount(address hooksInstance) external view returns (uint256);

  // ┌─ getMarketsForHooksInstance ─────
  function getMarketsForHooksInstance(
    address hooksInstance,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory);
}

// ┌─ IKYCHooksInstance ────────────────────────────────────────────────────────
/// @dev minimal hooks authority getter; v2.5 keeps `borrower()` as an alias for `administrator`.
interface IKYCHooksInstance {
  // ┌─ borrower ─────
  function borrower() external view returns (address);
}

// ┌─ IKYCMarket ───────────────────────────────────────────────────────────────
/// @dev minimal state-sync and closure surface shared by v2.0/v2.1 and v2.5 markets.
interface IKYCMarket {
  // ┌─ updateState ─────
  function updateState() external;

  // ┌─ isClosed ─────
  function isClosed() external view returns (bool);
}

// ┌─ KYCRoleProviderFactory ───────────────────────────────────────────────────
/// @notice singleton managing canonical `KYCRoleProvider` policies and borrower market entitlements.
///
/// @dev entitlements count markets across all policies deployed here. attaching multiple policies to
///      one hooks instance consumes no extra slots. lowering `borrowerAllowance` only gates future
///      allocations and never disables live authorized hooks.
contract KYCRoleProviderFactory is IKYCRoleProviderFactory, ManagedRoleProvider {
  using EnumerableSet for EnumerableSet.AddressSet;
  using SafeCastLib for uint256;

  IKYCRegistry public immutable override registry;

  bool public override slotReclamationEnabled;

  EnumerableSet.AddressSet internal _approvedHooksFactories;
  EnumerableSet.AddressSet internal _roleProviders;

  mapping(bytes32 policyHash => address provider) public override policyProvider;
  mapping(address provider => bool enabled) public override isProviderAttachmentEnabled;

  mapping(address borrower => uint32 allowance) public override borrowerAllowance;
  mapping(address borrower => uint32 used) public override usedSlots;

  mapping(address hooksInstance => HooksAuthorization) internal _hooksAuthorizations;
  mapping(address borrower => EnumerableSet.AddressSet) internal _borrowerAuthorizedHooks;
  mapping(address market => bool reclaimed) public override closedMarketReclaimed;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  /// @param administrator_        initial nonzero authority over policies, factories, and allowances.
  /// @param registry_             immutable `KYCRegistry` backing all policies deployed here.
  /// @param initialHooksFactories initial allowlisted `HooksFactory` addresses (v2.0/v2.1, v2.5, etc.).
  constructor(
    address administrator_,
    IKYCRegistry registry_,
    address[] memory initialHooksFactories
  )
    ManagedRoleProvider(administrator_)
  {
    if (address(registry_) == address(0)) revert InvalidRegistry();

    registry = registry_;
    slotReclamationEnabled = true;

    for (uint256 i; i < initialHooksFactories.length; ++i) {
      _setHooksFactory(initialHooksFactories[i], true);
    }
  }

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ setHooksFactory ─────
  /// @notice add or remove a `HooksFactory` from the allowlist for future allocations.
  ///
  /// @dev removing a factory never disables hooks that were already authorized on it.
  function setHooksFactory(address hooksFactory, bool allowed) external override onlyAdministrator {
    _setHooksFactory(hooksFactory, allowed);
  }

  // ┌─ _setHooksFactory ─────
  function _setHooksFactory(address hooksFactory, bool allowed) internal {
    if (hooksFactory == address(0)) revert InvalidHooksFactory();
    if (allowed) {
      _approvedHooksFactories.add(hooksFactory);
    } else {
      _approvedHooksFactories.remove(hooksFactory);
    }
    emit HooksFactoryUpdated(administrator, hooksFactory, allowed);
  }

  // ┌─ setSlotReclamationEnabled ─────
  /// @notice toggle whether closed markets can return slots to their borrower's allowance.
  function setSlotReclamationEnabled(bool enabled) external override onlyAdministrator {
    slotReclamationEnabled = enabled;
    emit SlotReclamationEnabledUpdated(administrator, enabled);
  }

  // ┌─ setBorrowerAllowance ─────
  /// @notice set `borrower`'s forward-looking market allowance across all KYC policies.
  ///
  /// @dev lowering below `usedSlots[borrower]` blocks new slots without touching live hooks.
  function setBorrowerAllowance(address borrower, uint32 allowance) external override onlyAdministrator {
    if (borrower == address(0)) revert InvalidBorrower();

    uint32 previousAllowance = borrowerAllowance[borrower];
    borrowerAllowance[borrower] = allowance;
    emit BorrowerAllowanceUpdated(administrator, borrower, previousAllowance, allowance);
  }

  // ░░▒▒▓▓██ [ POLICY CATALOG ] ───────────────────────────────────────────────

  // ┌─ deployRoleProvider ─────
  /// @notice deploy one canonical `KYCRoleProvider` for sorted, disjoint required and forbidden keys.
  ///
  /// @dev reverts if an identical `(requiredAttributes, forbiddenAttributes)` policy already exists.
  function deployRoleProvider(
    string calldata name,
    bytes32[] calldata requiredAttributes,
    bytes32[] calldata forbiddenAttributes
  )
    external
    override
    onlyAdministrator
    returns (address provider)
  {
    _validatePolicy(requiredAttributes, forbiddenAttributes);

    bytes32 policyHash = keccak256(abi.encode(requiredAttributes, forbiddenAttributes));
    if (policyProvider[policyHash] != address(0)) revert PolicyAlreadyDeployed();

    provider = address(
      new KYCRoleProvider{ salt: policyHash }(registry, this, name, requiredAttributes, forbiddenAttributes)
    );
    policyProvider[policyHash] = provider;
    _roleProviders.add(provider);
    isProviderAttachmentEnabled[provider] = true;

    emit RoleProviderDeployed(provider, policyHash, name, requiredAttributes, forbiddenAttributes);
  }

  // ┌─ _validatePolicy ─────
  function _validatePolicy(bytes32[] calldata required, bytes32[] calldata forbidden) internal pure {
    uint256 reqLen = required.length;
    if (reqLen == 0) revert InvalidPolicy();

    // require nonzero, strictly ascending keys in both arrays so `policyHash` is canonical.
    for (uint256 i; i < reqLen; ++i) {
      bytes32 key = required[i];
      if (key == bytes32(0) || (i != 0 && key <= required[i - 1])) revert InvalidPolicy();
    }

    uint256 forbLen = forbidden.length;
    for (uint256 i; i < forbLen; ++i) {
      bytes32 key = forbidden[i];
      if (key == bytes32(0) || (i != 0 && key <= forbidden[i - 1])) revert InvalidPolicy();
    }

    // both lists are strictly ascending, so a single merge pass catches any overlap.
    uint256 r;
    uint256 f;
    while (r < reqLen && f < forbLen) {
      bytes32 rk = required[r];
      bytes32 fk = forbidden[f];
      if (rk == fk) revert InvalidPolicy();
      if (rk < fk) ++r;
      else ++f;
    }
  }

  // ┌─ setProviderAttachmentEnabled ─────
  /// @notice enable or disable a deployed policy for new attachments via `createRoleProvider`.
  ///
  /// @dev soft deprecation gate on `createRoleProvider`; hooks authorization remains hook-level,
  ///      so already-attached hooks and direct `hooks.addRoleProvider` calls are unaffected.
  function setProviderAttachmentEnabled(address provider, bool enabled) external override onlyAdministrator {
    if (!_roleProviders.contains(provider)) revert UnknownRoleProvider();
    isProviderAttachmentEnabled[provider] = enabled;
    emit ProviderAttachmentEnabledUpdated(administrator, provider, enabled);
  }

  // ┌─ isRoleProvider ─────
  function isRoleProvider(address provider) external view override returns (bool) {
    return _roleProviders.contains(provider);
  }

  // ┌─ getRoleProvidersCount ─────
  function getRoleProvidersCount() external view override returns (uint256) {
    return _roleProviders.length();
  }

  // ┌─ getRoleProviders ─────
  function getRoleProviders() external view override returns (address[] memory) {
    return _roleProviders.values();
  }

  // ┌─ getRoleProviders ─────
  function getRoleProviders(uint256 start, uint256 end) external view override returns (address[] memory providers) {
    return _paginate(_roleProviders, start, end);
  }

  // ░░▒▒▓▓██ [ ENTITLEMENTS ] ─────────────────────────────────────────────────

  // ┌─ createRoleProvider ─────
  /// @notice authorize `msg.sender` and return an existing canonical policy for `BaseAccessControls`
  ///         to attach in one transaction.
  ///
  /// @dev deploys nothing; the calling hooks instance already authenticated its borrower/administrator.
  function createRoleProvider(bytes calldata data) external override returns (address provider) {
    KYCRoleProviderAttachInputs memory inputs = abi.decode(data, (KYCRoleProviderAttachInputs));
    if (!_roleProviders.contains(inputs.provider)) revert UnknownRoleProvider();
    if (!isProviderAttachmentEnabled[inputs.provider]) revert ProviderAttachmentDisabled();

    _authorizeHooks(
      inputs.hooksFactory, msg.sender, inputs.targetApprovedMarketCount, inputs.closedMarketsToReclaim, true
    );
    return inputs.provider;
  }

  // ┌─ authorizeHooks ─────
  /// @notice authorize `hooksInstance` or raise its approved market count without reclaiming slots.
  function authorizeHooks(
    address hooksFactory,
    address hooksInstance,
    uint32 targetApprovedMarketCount
  )
    external
    override
  {
    _authorizeHooks(hooksFactory, hooksInstance, targetApprovedMarketCount, new ClosedMarketClaim[](0), false);
  }

  // ┌─ authorizeHooks ─────
  /// @notice reclaim optional closed markets, then authorize `hooksInstance` or raise its ceiling.
  ///
  /// @dev on first authorization, claims targeting `hooksInstance` itself offset pre-existing closed
  ///      markets so the borrower pays only for net active/pre-allocated slots.
  function authorizeHooks(
    address hooksFactory,
    address hooksInstance,
    uint32 targetApprovedMarketCount,
    ClosedMarketClaim[] calldata closedMarketsToReclaim
  )
    external
    override
  {
    _authorizeHooks(hooksFactory, hooksInstance, targetApprovedMarketCount, closedMarketsToReclaim, false);
  }

  // ┌─ _authorizeHooks ─────
  function _authorizeHooks(
    address hooksFactory,
    address hooksInstance,
    uint32 targetApprovedMarketCount,
    ClosedMarketClaim[] memory closedMarketsToReclaim,
    bool viaHooksCallback
  )
    internal
  {
    if (targetApprovedMarketCount == 0) revert TargetCannotBeZero();

    HooksAuthorization memory auth = _hooksAuthorizations[hooksInstance];
    if (auth.approvedMarketCount == 0) {
      _authorizeNewHooks(
        hooksFactory, hooksInstance, targetApprovedMarketCount, closedMarketsToReclaim, viaHooksCallback
      );
      return;
    }

    for (uint256 i; i < closedMarketsToReclaim.length; ++i) {
      _reclaimClosedMarket(closedMarketsToReclaim[i].hooksInstance, closedMarketsToReclaim[i].marketIndex);
    }

    // reload after inline reclaims in case one targeted `hooksInstance`.
    auth = _hooksAuthorizations[hooksInstance];
    _expandHooksAuthorization(auth, hooksFactory, hooksInstance, targetApprovedMarketCount, viaHooksCallback);
  }

  // ┌─ _authorizeNewHooks ─────
  function _authorizeNewHooks(
    address hooksFactory,
    address hooksInstance,
    uint32 targetApprovedMarketCount,
    ClosedMarketClaim[] memory closedMarketsToReclaim,
    bool viaHooksCallback
  )
    internal
  {
    if (!_approvedHooksFactories.contains(hooksFactory)) revert InvalidHooksFactory();
    if (!IKYCHooksFactory(hooksFactory).isHooksInstance(hooksInstance)) revert InvalidHooksInstance();

    address borrower = IKYCHooksInstance(hooksInstance).borrower();
    if (borrower == address(0)) revert InvalidBorrower();
    if (!viaHooksCallback && msg.sender != borrower && msg.sender != administrator) {
      revert CallerNotHooksBorrowerOrAdmin();
    }

    uint256 currentMarkets = IKYCHooksFactory(hooksFactory).getMarketsForHooksInstanceCount(hooksInstance);
    if (targetApprovedMarketCount < currentMarkets) revert TargetBelowCurrentMarkets();

    // reclaim closed markets on other authorized hooks first, then offset pre-closed markets on `hooksInstance`.
    uint32 preClosedCount =
      _reclaimPreClosedMarkets(hooksFactory, hooksInstance, borrower, currentMarkets, closedMarketsToReclaim);

    uint32 netSlots = targetApprovedMarketCount - preClosedCount;
    uint256 newUsed = uint256(usedSlots[borrower]) + netSlots;
    if (newUsed > borrowerAllowance[borrower]) revert InsufficientAllowance();

    usedSlots[borrower] = newUsed.toUint32();
    _hooksAuthorizations[hooksInstance] = HooksAuthorization({
      hooksFactory: hooksFactory,
      borrower: borrower,
      approvedMarketCount: targetApprovedMarketCount,
      reclaimedMarketCount: preClosedCount
    });
    _borrowerAuthorizedHooks[borrower].add(hooksInstance);
    emit HooksAuthorized(hooksFactory, hooksInstance, borrower, 0, targetApprovedMarketCount);
  }

  // ┌─ _reclaimPreClosedMarkets ─────
  function _reclaimPreClosedMarkets(
    address hooksFactory,
    address hooksInstance,
    address borrower,
    uint256 currentMarkets,
    ClosedMarketClaim[] memory claims
  )
    internal
    returns (uint32 preClosedCount)
  {
    for (uint256 i; i < claims.length; ++i) {
      ClosedMarketClaim memory claim = claims[i];
      if (claim.hooksInstance != hooksInstance) {
        _reclaimClosedMarket(claim.hooksInstance, claim.marketIndex);
        continue;
      }

      if (!slotReclamationEnabled) revert SlotReclamationDisabled();
      if (claim.marketIndex >= currentMarkets) revert MarketIndexOutOfBounds();

      address[] memory markets = IKYCHooksFactory(hooksFactory).getMarketsForHooksInstance(
        hooksInstance, claim.marketIndex, claim.marketIndex + 1
      );
      if (markets.length == 0) revert MarketIndexOutOfBounds();

      address market = markets[0];
      if (closedMarketReclaimed[market]) revert MarketAlreadyReclaimed();

      // commit any v2.5 projected scheduled closure before checking `isClosed()`.
      IKYCMarket(market).updateState();
      if (!IKYCMarket(market).isClosed()) revert MarketNotClosed();

      closedMarketReclaimed[market] = true;
      ++preClosedCount;
      emit ClosedMarketSlotReclaimed(hooksInstance, market, borrower, claim.marketIndex);
    }
  }

  // ┌─ _expandHooksAuthorization ─────
  function _expandHooksAuthorization(
    HooksAuthorization memory auth,
    address hooksFactory,
    address hooksInstance,
    uint32 targetApprovedMarketCount,
    bool viaHooksCallback
  )
    internal
  {
    if (auth.hooksFactory != hooksFactory) revert HooksFactoryMismatch();
    if (targetApprovedMarketCount < auth.approvedMarketCount) revert TargetBelowApprovedMarkets();

    uint256 deployedMarkets = IKYCHooksFactory(hooksFactory).getMarketsForHooksInstanceCount(hooksInstance);
    if (targetApprovedMarketCount < deployedMarkets) revert TargetBelowCurrentMarkets();

    address currentHooksBorrower = IKYCHooksInstance(hooksInstance).borrower();
    uint32 delta = targetApprovedMarketCount - auth.approvedMarketCount;
    if (delta == 0) {
      // already covered: attaching another KYC policy consumes zero extra slots.
      if (
        !viaHooksCallback && msg.sender != currentHooksBorrower && msg.sender != auth.borrower
          && msg.sender != administrator
      ) {
        revert CallerNotHooksBorrowerOrAdmin();
      }
      return;
    }

    if (!_approvedHooksFactories.contains(hooksFactory)) revert InvalidHooksFactory();

    // don't let a post-transfer hooks admin spend the original borrower's remaining allowance.
    if (currentHooksBorrower != auth.borrower) revert HooksBorrowerMismatch();
    if (!viaHooksCallback && msg.sender != auth.borrower && msg.sender != administrator) {
      revert CallerNotHooksBorrowerOrAdmin();
    }

    uint256 expandedUsed = uint256(usedSlots[auth.borrower]) + delta;
    if (expandedUsed > borrowerAllowance[auth.borrower]) revert InsufficientAllowance();

    usedSlots[auth.borrower] = expandedUsed.toUint32();
    _hooksAuthorizations[hooksInstance].approvedMarketCount = targetApprovedMarketCount;
    emit HooksAuthorized(
      hooksFactory, hooksInstance, auth.borrower, auth.approvedMarketCount, targetApprovedMarketCount
    );
  }

  // ┌─ reduceUnusedSlots ─────
  /// @notice refund pre-allocated slots above the hooks instance's currently deployed market count.
  ///
  /// @dev never drops below `getMarketsForHooksInstanceCount`, so deployed and reclaimed markets stay
  ///      strictly inside `approvedMarketCount`. reducing to zero clears an empty hook's record.
  function reduceUnusedSlots(address hooksInstance, uint32 newApprovedMarketCount) external override {
    HooksAuthorization memory auth = _hooksAuthorizations[hooksInstance];
    if (auth.approvedMarketCount == 0) revert HooksNotAuthorized();
    if (msg.sender != auth.borrower && msg.sender != administrator) revert CallerNotHooksBorrowerOrAdmin();

    uint256 currentMarkets = IKYCHooksFactory(auth.hooksFactory).getMarketsForHooksInstanceCount(hooksInstance);
    if (newApprovedMarketCount >= auth.approvedMarketCount || newApprovedMarketCount < currentMarkets) {
      revert InvalidSlotReduction();
    }

    uint32 refund = auth.approvedMarketCount - newApprovedMarketCount;
    usedSlots[auth.borrower] -= refund;
    if (newApprovedMarketCount == 0) {
      delete _hooksAuthorizations[hooksInstance];
      _borrowerAuthorizedHooks[auth.borrower].remove(hooksInstance);
    } else {
      _hooksAuthorizations[hooksInstance].approvedMarketCount = newApprovedMarketCount;
    }

    emit UnusedSlotsReduced(hooksInstance, auth.borrower, auth.approvedMarketCount, newApprovedMarketCount);
  }

  // ┌─ migrateHooksBorrower ─────
  /// @notice rebind a hooks instance's pinned allowance owner to its current `borrower()` after rotation.
  ///
  /// @dev callable by the new `hooks.borrower()` or factory administrator. moves only unreclaimed
  ///      slots (`approvedMarketCount - reclaimedMarketCount`) so conservation stays exact.
  function migrateHooksBorrower(address hooksInstance) external override {
    HooksAuthorization memory auth = _hooksAuthorizations[hooksInstance];
    if (auth.approvedMarketCount == 0) revert HooksNotAuthorized();

    address newBorrower = IKYCHooksInstance(hooksInstance).borrower();
    if (newBorrower == address(0)) revert InvalidBorrower();
    if (newBorrower == auth.borrower) revert BorrowerUnchanged();
    if (msg.sender != newBorrower && msg.sender != administrator) revert CallerNotHooksBorrowerOrAdmin();

    uint32 activeSlots = auth.approvedMarketCount - auth.reclaimedMarketCount;
    uint256 newBorrowerUsed = uint256(usedSlots[newBorrower]) + activeSlots;
    if (newBorrowerUsed > borrowerAllowance[newBorrower]) revert InsufficientAllowance();

    usedSlots[auth.borrower] -= activeSlots;
    usedSlots[newBorrower] = newBorrowerUsed.toUint32();
    _borrowerAuthorizedHooks[auth.borrower].remove(hooksInstance);
    _borrowerAuthorizedHooks[newBorrower].add(hooksInstance);
    _hooksAuthorizations[hooksInstance].borrower = newBorrower;

    emit HooksBorrowerMigrated(msg.sender, hooksInstance, auth.borrower, newBorrower, activeSlots);
  }

  // ┌─ reclaimClosedMarket ─────
  /// @notice return one slot to the borrower once the market at `marketIndex` permanently closes.
  function reclaimClosedMarket(address hooksInstance, uint256 marketIndex) external override {
    _reclaimClosedMarket(hooksInstance, marketIndex);
  }

  // ┌─ reclaimClosedMarkets ─────
  /// @notice reclaim a batch of closed markets atomically.
  function reclaimClosedMarkets(ClosedMarketClaim[] calldata claims) external override {
    for (uint256 i; i < claims.length; ++i) {
      _reclaimClosedMarket(claims[i].hooksInstance, claims[i].marketIndex);
    }
  }

  // ┌─ _reclaimClosedMarket ─────
  function _reclaimClosedMarket(address hooksInstance, uint256 marketIndex) internal {
    if (!slotReclamationEnabled) revert SlotReclamationDisabled();

    HooksAuthorization memory auth = _hooksAuthorizations[hooksInstance];
    if (auth.approvedMarketCount == 0) revert HooksNotAuthorized();

    // only markets inside the paid ceiling can return a slot; unapproved extras can't mint credit.
    if (marketIndex >= auth.approvedMarketCount) revert MarketIndexOutOfBounds();

    uint256 currentMarkets = IKYCHooksFactory(auth.hooksFactory).getMarketsForHooksInstanceCount(hooksInstance);
    if (marketIndex >= currentMarkets) revert MarketIndexOutOfBounds();

    address[] memory markets =
      IKYCHooksFactory(auth.hooksFactory).getMarketsForHooksInstance(hooksInstance, marketIndex, marketIndex + 1);
    if (markets.length == 0) revert MarketIndexOutOfBounds();

    address market = markets[0];
    if (closedMarketReclaimed[market]) revert MarketAlreadyReclaimed();

    // commit any v2.5 projected scheduled closure before checking `isClosed()`.
    IKYCMarket(market).updateState();
    if (!IKYCMarket(market).isClosed()) revert MarketNotClosed();

    closedMarketReclaimed[market] = true;
    _hooksAuthorizations[hooksInstance].reclaimedMarketCount = auth.reclaimedMarketCount + 1;
    usedSlots[auth.borrower] -= 1;
    emit ClosedMarketSlotReclaimed(hooksInstance, market, auth.borrower, marketIndex);
  }

  // ┌─ isHooksAuthorized ─────
  /// @notice report whether `hooksInstance` is authorized and within its approved market count.
  function isHooksAuthorized(address hooksInstance) external view override returns (bool) {
    HooksAuthorization memory auth = _hooksAuthorizations[hooksInstance];
    if (auth.approvedMarketCount == 0) return false;
    return IKYCHooksFactory(auth.hooksFactory).getMarketsForHooksInstanceCount(hooksInstance)
      <= auth.approvedMarketCount;
  }

  // ░░▒▒▓▓██ [ QUERIES ] ──────────────────────────────────────────────────────

  // ┌─ isApprovedHooksFactory ─────
  function isApprovedHooksFactory(address hooksFactory) external view override returns (bool) {
    return _approvedHooksFactories.contains(hooksFactory);
  }

  // ┌─ getApprovedHooksFactories ─────
  function getApprovedHooksFactories() external view override returns (address[] memory) {
    return _approvedHooksFactories.values();
  }

  // ┌─ getHooksAuthorization ─────
  function getHooksAuthorization(address hooksInstance) external view override returns (HooksAuthorization memory) {
    return _hooksAuthorizations[hooksInstance];
  }

  // ┌─ getBorrowerAuthorizedHooksCount ─────
  function getBorrowerAuthorizedHooksCount(address borrower) external view override returns (uint256) {
    return _borrowerAuthorizedHooks[borrower].length();
  }

  // ┌─ getBorrowerAuthorizedHooks ─────
  function getBorrowerAuthorizedHooks(
    address borrower,
    uint256 start,
    uint256 end
  )
    external
    view
    override
    returns (address[] memory hooksInstances)
  {
    return _paginate(_borrowerAuthorizedHooks[borrower], start, end);
  }

  // ┌─ _paginate ─────
  function _paginate(
    EnumerableSet.AddressSet storage set,
    uint256 start,
    uint256 end
  )
    internal
    view
    returns (address[] memory items)
  {
    if (start > end) revert InvalidPaginationRange();
    uint256 total = set.length();
    if (end > total) end = total;
    if (start >= end) return new address[](0);

    items = new address[](end - start);
    for (uint256 i; i < items.length; ++i) {
      items[i] = set.at(start + i);
    }
  }
}
