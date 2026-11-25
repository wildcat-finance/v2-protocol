// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // IKYCRoleProviderFactory
//  \ ^ /   Policy catalog, borrower allowances, and hooks authorization.
//    V
//
//  CONFIGURATION
//  registry()
//  slotReclamationEnabled()
//  setHooksFactory(...)
//  setSlotReclamationEnabled(...)
//  setBorrowerAllowance(...)
//
//  POLICY CATALOG
//  deployRoleProvider(...)
//  setProviderAttachmentEnabled(...)
//  policyProvider(...)
//  isRoleProvider(...)
//  isProviderAttachmentEnabled(...)
//  getRoleProvidersCount()
//  getRoleProviders()
//  getRoleProviders(...)
//
//  ENTITLEMENTS
//  authorizeHooks(...)
//  authorizeHooks(...)
//  reduceUnusedSlots(...)
//  migrateHooksBorrower(...)
//  reclaimClosedMarket(...)
//  reclaimClosedMarkets(...)
//  isHooksAuthorized(...)
//
//  QUERIES
//  isApprovedHooksFactory(...)
//  getApprovedHooksFactories()
//  borrowerAllowance(...)
//  usedSlots(...)
//  getHooksAuthorization(...)
//  getBorrowerAuthorizedHooksCount(...)
//  getBorrowerAuthorizedHooks(...)
//  closedMarketReclaimed(...)
// ═════

import '../access/IManagedRoleProvider.sol';
import '../access/IRoleProviderFactory.sol';
import './IKYCRegistry.sol';

/// @notice authorization record and market-slot ceiling for one hooks instance.
///
/// @param hooksFactory         allowlisted `HooksFactory` that deployed this hooks instance.
/// @param borrower             pinned allowance account charged for slots and credited on refunds or reclaims.
/// @param approvedMarketCount  ceiling checked against `HooksFactory.getMarketsForHooksInstanceCount`.
/// @param reclaimedMarketCount closed markets already reclaimed on this hooks instance.
struct HooksAuthorization {
  address hooksFactory;
  address borrower;
  uint32 approvedMarketCount;
  uint32 reclaimedMarketCount;
}

/// @notice closed-market target for slot reclamation.
struct ClosedMarketClaim {
  address hooksInstance;
  uint256 marketIndex;
}

/// @notice calldata payload decoded by `IRoleProviderFactory.createRoleProvider`.
///
/// @dev does not deploy a new contract; authorizes `msg.sender` (the calling hooks instance) and
///      returns an existing admin-deployed `provider` so `BaseAccessControls` attaches it in one tx.
struct KYCRoleProviderAttachInputs {
  address hooksFactory;
  address provider;
  uint32 targetApprovedMarketCount;
  ClosedMarketClaim[] closedMarketsToReclaim;
}

// ┌─ IKYCRoleProviderFactory ──────────────────────────────────────────────────
/// @notice singleton factory for canonical KYC policies and onchain borrower market entitlements.
///
/// @dev entitlements count markets across all deployed `KYCRoleProvider` instances. lowering a
///      borrower's allowance only caps future allocations; live authorized hooks stay active.
interface IKYCRoleProviderFactory is IManagedRoleProvider, IRoleProviderFactory {
  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when a `HooksFactory` address is added to or removed from the allowlist.
  event HooksFactoryUpdated(address indexed administrator, address indexed hooksFactory, bool allowed);

  /// @notice emitted when the administrator deploys a canonical `KYCRoleProvider` policy.
  event RoleProviderDeployed(
    address indexed provider,
    bytes32 indexed policyHash,
    string name,
    bytes32[] requiredAttributes,
    bytes32[] forbiddenAttributes
  );

  /// @notice emitted when a policy is enabled or disabled for new `createRoleProvider` attachments.
  event ProviderAttachmentEnabledUpdated(address indexed administrator, address indexed provider, bool enabled);

  /// @notice emitted when closed-market slot reclamation is toggled.
  event SlotReclamationEnabledUpdated(address indexed administrator, bool enabled);

  /// @notice emitted when a borrower's forward-looking market allowance changes.
  event BorrowerAllowanceUpdated(
    address indexed administrator, address indexed borrower, uint32 previousAllowance, uint32 newAllowance
  );

  /// @notice emitted when a hooks instance is authorized or its approved market count increases.
  event HooksAuthorized(
    address indexed hooksFactory,
    address indexed hooksInstance,
    address indexed borrower,
    uint32 previousApprovedMarketCount,
    uint32 newApprovedMarketCount
  );

  /// @notice emitted when unused pre-allocated slots above deployed market count are refunded.
  event UnusedSlotsReduced(
    address indexed hooksInstance,
    address indexed borrower,
    uint32 previousApprovedMarketCount,
    uint32 newApprovedMarketCount
  );

  /// @notice emitted when a hooks instance's pinned allowance owner migrates after hooks-admin transfer.
  event HooksBorrowerMigrated(
    address indexed caller,
    address indexed hooksInstance,
    address indexed previousBorrower,
    address newBorrower,
    uint32 activeSlotsMoved
  );

  /// @notice emitted when a permanently closed market returns one slot to its borrower's allowance.
  event ClosedMarketSlotReclaimed(
    address indexed hooksInstance, address indexed market, address indexed borrower, uint256 marketIndex
  );

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev registry address cannot be zero.
  error InvalidRegistry();

  /// @dev hooks factory is zero or not allowlisted.
  error InvalidHooksFactory();

  /// @dev hooks instance is not registered on the supplied hooks factory.
  error InvalidHooksInstance();

  /// @dev borrower address cannot be zero.
  error InvalidBorrower();

  /// @dev policy requires nonzero sorted unique keys with no overlap between required and forbidden.
  error InvalidPolicy();

  /// @dev a provider with identical required and forbidden attributes already exists.
  error PolicyAlreadyDeployed();

  /// @dev provider was not deployed by this factory.
  error UnknownRoleProvider();

  /// @dev provider is disabled for new attachments via `createRoleProvider`.
  error ProviderAttachmentDisabled();

  /// @dev supplied hooks factory does not match the factory recorded for this hooks instance.
  error HooksFactoryMismatch();

  /// @dev caller is neither the hooks borrower/allowance owner nor the factory administrator.
  error CallerNotHooksBorrowerOrAdmin();

  /// @dev live `hooks.borrower()` diverged from the pinned allowance owner; migrate before expanding.
  error HooksBorrowerMismatch();

  /// @dev live `hooks.borrower()` already matches the pinned allowance owner.
  error BorrowerUnchanged();

  /// @dev target approved market count cannot be zero.
  error TargetCannotBeZero();

  /// @dev target approved market count is below the markets already deployed on the hooks instance.
  error TargetBelowCurrentMarkets();

  /// @dev target approved market count cannot shrink through `authorizeHooks`; use `reduceUnusedSlots`.
  error TargetBelowApprovedMarkets();

  /// @dev borrower does not have enough remaining allowance for the requested market slots.
  error InsufficientAllowance();

  /// @dev hooks instance has no active authorization record.
  error HooksNotAuthorized();

  /// @dev reduced slot count must be strictly below approved count and at least current deployed count.
  error InvalidSlotReduction();

  /// @dev closed-market slot reclamation is currently disabled.
  error SlotReclamationDisabled();

  /// @dev market index is outside the authorized and deployed markets on the hooks instance.
  error MarketIndexOutOfBounds();

  /// @dev closed market slot was already reclaimed.
  error MarketAlreadyReclaimed();

  /// @dev market must be permanently closed before reclaiming its slot.
  error MarketNotClosed();

  /// @dev pagination start index exceeds end index.
  error InvalidPaginationRange();

  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  // ┌─ registry ─────
  /// @notice return the immutable `KYCRegistry` shared by all providers deployed here.
  function registry() external view returns (IKYCRegistry);

  // ┌─ slotReclamationEnabled ─────
  /// @notice report whether closed markets can currently return slots to borrower allowances.
  function slotReclamationEnabled() external view returns (bool);

  // ┌─ setHooksFactory ─────
  /// @notice allowlist or disallow a `HooksFactory` for future hooks authorizations.
  function setHooksFactory(address hooksFactory, bool allowed) external;

  // ┌─ setSlotReclamationEnabled ─────
  /// @notice toggle whether closed markets can return slots to borrower allowances.
  function setSlotReclamationEnabled(bool enabled) external;

  // ┌─ setBorrowerAllowance ─────
  /// @notice set a borrower's forward-looking KYC market allowance.
  ///
  /// @dev never disables already-authorized hooks even if `allowance` drops below `usedSlots`.
  function setBorrowerAllowance(address borrower, uint32 allowance) external;

  // ░░▒▒▓▓██ [ POLICY CATALOG ] ───────────────────────────────────────────────

  // ┌─ deployRoleProvider ─────
  /// @notice deploy a canonical `KYCRoleProvider` for sorted, disjoint required and forbidden attributes.
  function deployRoleProvider(
    string calldata name,
    bytes32[] calldata requiredAttributes,
    bytes32[] calldata forbiddenAttributes
  )
    external
    returns (address provider);

  // ┌─ setProviderAttachmentEnabled ─────
  /// @notice enable or disable an existing policy for new attachments via `createRoleProvider`.
  ///
  /// @dev soft deprecation gate on the factory callback and UI; hooks authorization itself stays
  ///      hook-level, so direct `hooks.addRoleProvider` on an authorized hook is unaffected.
  function setProviderAttachmentEnabled(address provider, bool enabled) external;

  // ┌─ policyProvider ─────
  /// @notice return the canonical provider deployed for `policyHash`, or zero if none exists.
  function policyProvider(bytes32 policyHash) external view returns (address);

  // ┌─ isRoleProvider ─────
  /// @notice report whether `provider` was deployed by this factory.
  function isRoleProvider(address provider) external view returns (bool);

  // ┌─ isProviderAttachmentEnabled ─────
  /// @notice report whether `provider` accepts new attachments through `createRoleProvider`.
  function isProviderAttachmentEnabled(address provider) external view returns (bool);

  // ┌─ getRoleProvidersCount ─────
  /// @notice count canonical providers deployed by this factory.
  function getRoleProvidersCount() external view returns (uint256);

  // ┌─ getRoleProviders ─────
  /// @notice return all canonical providers deployed by this factory.
  function getRoleProviders() external view returns (address[] memory);

  // ┌─ getRoleProviders ─────
  /// @notice return a half-open `[start, end)` page of deployed canonical providers.
  function getRoleProviders(uint256 start, uint256 end) external view returns (address[] memory providers);

  // ░░▒▒▓▓██ [ ENTITLEMENTS ] ─────────────────────────────────────────────────

  // ┌─ authorizeHooks ─────
  /// @notice authorize `hooksInstance` or raise its approved market count without reclaiming closed markets.
  function authorizeHooks(address hooksFactory, address hooksInstance, uint32 targetApprovedMarketCount) external;

  // ┌─ authorizeHooks ─────
  /// @notice reclaim optional closed markets, then authorize `hooksInstance` or raise its approved market count.
  function authorizeHooks(
    address hooksFactory,
    address hooksInstance,
    uint32 targetApprovedMarketCount,
    ClosedMarketClaim[] calldata closedMarketsToReclaim
  )
    external;

  // ┌─ reduceUnusedSlots ─────
  /// @notice refund pre-allocated slots above the hooks instance's currently deployed market count.
  function reduceUnusedSlots(address hooksInstance, uint32 newApprovedMarketCount) external;

  // ┌─ migrateHooksBorrower ─────
  /// @notice rebind a hooks instance's pinned allowance owner to its current `borrower()` after rotation.
  ///
  /// @dev callable by the new `hooks.borrower()` or factory administrator. moves only unreclaimed
  ///      slots (`approvedMarketCount - reclaimedMarketCount`) to the new borrower's allowance.
  function migrateHooksBorrower(address hooksInstance) external;

  // ┌─ reclaimClosedMarket ─────
  /// @notice return one slot to the borrower after the market at `marketIndex` permanently closes.
  function reclaimClosedMarket(address hooksInstance, uint256 marketIndex) external;

  // ┌─ reclaimClosedMarkets ─────
  /// @notice reclaim a batch of closed markets atomically.
  function reclaimClosedMarkets(ClosedMarketClaim[] calldata claims) external;

  // ┌─ isHooksAuthorized ─────
  /// @notice report whether `hooksInstance` is authorized and within its approved market count.
  function isHooksAuthorized(address hooksInstance) external view returns (bool);

  // ░░▒▒▓▓██ [ QUERIES ] ──────────────────────────────────────────────────────

  // ┌─ isApprovedHooksFactory ─────
  /// @notice report whether `hooksFactory` is allowlisted for new authorizations.
  function isApprovedHooksFactory(address hooksFactory) external view returns (bool);

  // ┌─ getApprovedHooksFactories ─────
  /// @notice return all currently allowlisted `HooksFactory` addresses.
  function getApprovedHooksFactories() external view returns (address[] memory);

  // ┌─ borrowerAllowance ─────
  /// @notice return the current forward-looking market allowance configured for `borrower`.
  function borrowerAllowance(address borrower) external view returns (uint32);

  // ┌─ usedSlots ─────
  /// @notice return unreclaimed market slots currently reserved across all hooks for `borrower`.
  function usedSlots(address borrower) external view returns (uint32);

  // ┌─ getHooksAuthorization ─────
  /// @notice return the stored authorization record for `hooksInstance`.
  function getHooksAuthorization(address hooksInstance) external view returns (HooksAuthorization memory);

  // ┌─ getBorrowerAuthorizedHooksCount ─────
  /// @notice count hooks instances currently authorized for `borrower`.
  function getBorrowerAuthorizedHooksCount(address borrower) external view returns (uint256);

  // ┌─ getBorrowerAuthorizedHooks ─────
  /// @notice return a half-open `[start, end)` page of hooks instances authorized for `borrower`.
  function getBorrowerAuthorizedHooks(
    address borrower,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory hooksInstances);

  // ┌─ closedMarketReclaimed ─────
  /// @notice report whether `market` has already returned its slot.
  function closedMarketReclaimed(address market) external view returns (bool);
}
