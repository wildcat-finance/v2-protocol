# Sepolia Authority Helper Rotation

Status: implemented and rehearsed on a pinned Sepolia fork. No live transaction
is authorized or recorded by this document.

Last reviewed: 2026-08-21

## Objective

Replace the deployed Sepolia `MockArchControllerOwner` with a durable testnet
authority helper, add `0xca7007a75296b532ce1606d9e130eaa849800ca7`
as an executor, and run future ceremonies from that wallet without redeploying
the `WildcatArchController` or losing any existing protocol state.

The existing executor
`0xca732651410E915090d7A7D889A1E44eF4575fcE` remains authorized through the
deployment and validation period. Removing it is a later, separately reviewed
operation.

## Live Sepolia Authority Baseline

The relevant live contracts are:

- `WildcatArchController`:
  `0xC003f20F2642c76B81e5e1620c6D8cdEE826408f`
- Existing `MockArchControllerOwner`:
  `0xa476920af80B587f696734430227869795E2Ea78`
- SphereX engine:
  `0xCc65C2Ad8ab5b5c63489cfC77F782175E0c6A36e`
- Legacy `WildcatMarketControllerFactory`:
  `0xEb97C8E52d7Fdf978a64a538F28271Fd8499b864`

Read against Sepolia on 2026-08-21:

- the existing helper owns the ArchController;
- the old executor is the only usable authorized account in that helper;
- the old executor is the ArchController's SphereX admin and operator;
- the old executor is the SphereX engine's default admin and has its operator
  role;
- the ArchController has the SphereX engine's sender-adder role; and
- the new executor is not yet authorized, is not a registered borrower, has
  nonce zero, and has no ETH.

The deployed helper cannot authorize a fresh executor. Its
`authorizeAccount(address)` implementation checks the authorization state of
the target account instead of the caller.

The deployed helper also exposes the legacy
`setProtocolFeeConfiguration(...)` forwarding method. That method was used on
2023-12-15 to configure the legacy Sepolia controller factory. It is part of
the compatibility surface and must not be removed.

## Replacement Helper Requirements

Keep the contract and deployment key named `MockArchControllerOwner` so the SDK
and ceremony configuration retain a stable concept while the deployed address
changes.

### Executor administration

- Accept an explicit initial executor list in the constructor. Do not infer
  authority from `msg.sender`.
- Reject the zero address and duplicate initial executors.
- Preserve `authorizedAccounts(address)` for SDK and ceremony compatibility.
- Expose the executor count and an enumerable executor list for operational
  verification.
- Permit authorized executors to add and remove executors.
- Emit explicit authorization and deauthorization events.
- Prevent removal of the final executor.
- Keep the old and new wallets authorized during the initial migration.

### Compatibility methods

- Keep permissionless `registerBorrower(address)` and
  `registerBorrowers(address[])` for testnet onboarding.
- Keep `returnOwnership()` for recovery and compatibility.
- Keep the legacy `setProtocolFeeConfiguration(...)` signature, restricted to
  authorized executors.
- Expose the immutable ArchController address and a helper version identifier
  for ceremony preflight checks.

### Authorized protocol execution

Add a single-action, authorized-only forwarding method. It must:

- execute one call per transaction;
- bubble the target's original revert data;
- return the target's return data;
- emit the executor, target, and four-byte selector;
- reject EOAs and invalid targets; and
- permit only:
  - the immutable ArchController;
  - the ArchController's current SphereX engine; or
  - a protocol contract whose `archController()` resolves to the immutable
    ArchController.

Do not add batching to the first version. One action per card keeps review,
simulation, receipts, predicates, and recovery precise.

This forwarding path replaces the checked-in helper's hardcoded dependency on
one `HooksFactory`. It supports both V2.5 hooks factories, the legacy controller
factory, the borrower identity registry, future compatible factories, and the
current SphereX authority surfaces.

## Authority Boundary

The helper may perform protocol-owner actions, including:

- ArchController registry administration and asset blacklist changes;
- hooks-template addition, fee updates, and disablement on any compatible
  standard or revolving hooks factory;
- legacy controller-factory fee configuration;
- borrower identity registry account-factory approval and removal;
- ArchController SphereX administration and engine propagation; and
- SphereX engine administration after the engine roles are migrated.

The helper must not bypass borrower or administrator authority. These remain
with their existing principals:

- market borrower transfer;
- hooks administrator transfer;
- managed role-provider administrator transfer;
- borrower-account principal transfer;
- role-provider membership and root administration; and
- ordinary deployment of standalone role providers and their factories.

## Implemented Source And Test Work

The replacement helper is implemented in
`script/mock/MockArchControllerOwner.sol`. Focused tests cover:

- constructor validation and enumeration;
- executor add/remove behavior and final-executor protection;
- permissionless borrower registration;
- authorized-only legacy fee forwarding;
- valid and invalid protocol forwarding targets;
- return-data and revert-data propagation;
- ArchController ownership reclaim and return;
- ArchController SphereX admin/operator migration;
- SphereX engine default-admin/operator migration; and
- old and new executors operating concurrently.

The migration generator is `scripts/authority-migration.js`. It produces three
separate, validated plans matching the live sequence below. The final authority
check and atomic deployment-alias update are implemented by
`scripts/authority-helper.js`.

The SDK ABI and address update remains intentionally deferred until the helper
is deployed and its live address is accepted.

## Ceremony Changes

Change Sepolia from the current `temporary-mock-owner` ceremony model to an
authorized-helper model.

- Contract deployments remain direct transactions from the reviewed executor.
- Protocol-owner calls target the helper's forwarding method.
- The helper remains ArchController owner throughout the ceremony.
- Remove the initial `returnOwnership()` card and compensating final
  `transferOwnership(helper)` card.
- Preserve one reviewed action per card.
- Display and validate the nested target, function selector, and arguments in
  the deployment UI rather than presenting only opaque forwarding calldata.
- Continue evaluating postcondition predicates against the actual
  ArchController, factory, registry, or SphereX target.
- Preflight the helper version, immutable ArchController, current owner,
  authorized executor, SphereX engine, and expected authority roles.
- Extend inventory and plan validation so a package cannot silently mix the
  old temporary-owner and new authorized-helper models.

The Anvil rehearsal must reproduce the same helper ownership and SphereX role
shape used on Sepolia.

## Live Migration Sequence

### Preparation

1. Freeze the reviewed helper bytecode and record its runtime code hash.
2. Fund the new executor without using it to deploy the replacement helper, so
   its contract-deployment nonce remains zero.
3. Deploy the replacement helper from the old wallet with both wallets in the
   initial executor list.
4. Verify source, constructor arguments, helper version, immutable
   ArchController, executor enumeration, and runtime code hash.

### ArchController ownership

5. The old wallet calls `returnOwnership()` on the existing helper.
6. Verify the ArchController owner is the old wallet.
7. The old wallet calls `ArchController.transferOwnership(newHelper)`.
8. Verify the new helper owns the ArchController and both wallets remain
   authorized by the new helper.

### ArchController SphereX roles

9. The old wallet calls
   `ArchController.transferSphereXAdminRole(newHelper)`.
10. Verify the new helper is the pending SphereX admin.
11. An authorized wallet directs the helper to call
    `ArchController.acceptSphereXAdminRole()`.
12. Verify the new helper is the SphereX admin and the pending admin is zero.
13. An authorized wallet directs the helper to call
    `ArchController.changeSphereXOperator(newHelper)`.
14. Verify the new helper is both ArchController SphereX admin and operator and
    the configured engine is unchanged.

### SphereX engine roles

15. The old wallet calls
    `SphereXEngine.beginDefaultAdminTransfer(newHelper)`.
16. Verify the pending default admin and its acceptance timestamp. The current
    engine delay is one hour.
17. After the delay, an authorized wallet directs the helper to call
    `SphereXEngine.acceptDefaultAdminTransfer()`.
18. Verify the helper is the engine default admin.
19. An authorized wallet directs the helper to grant itself the engine
    operator role.
20. Verify the helper has the operator role, then direct it to revoke that role
    from the old wallet.
21. Verify the ArchController still has the sender-adder role and the engine's
    rules and allowed-sender state are unchanged.

### Functional verification

22. Register the new wallet as a borrower through the permissionless helper
    path.
23. Simulate every authorized call class through the helper.
24. Update the protocol deployment inventory and ceremony configuration to the
    replacement helper address.
25. Update the prepared SDK's helper address and ABI. The frontend inherits the
    new address through the SDK.
26. Generate, independently review, and rehearse a completely fresh Sepolia
    package from the new executor's actual nonce and current chain state.

## Recovery Rules

- Do not remove the old executor during the initial migration or V2.5
  deployment.
- Stop after any failed predicate; do not continue merely because the preceding
  transaction succeeded.
- Before the ArchController transfer, the existing helper remains the recovery
  path.
- After the ArchController transfer, either authorized wallet can operate the
  replacement helper.
- During a pending SphereX admin transfer, the old wallet remains admin until
  the helper accepts.
- During the SphereX engine's one-hour delay, the old wallet remains default
  admin and operator.
- Do not revoke the old engine operator role until the helper's default-admin
  and operator roles are both verified.
- Do not reuse any plan whose expected helper, executor, nonce, authority
  predicates, or chain state no longer matches.

## Delayed Old-Wallet Removal

Removing `0xca732651410E915090d7A7D889A1E44eF4575fcE` is a later operation after the
replacement helper, fresh V2.5 contracts, subgraph, SDK, and app have been
validated for several days.

Before removal, verify:

- the replacement helper still owns the ArchController;
- the replacement helper is the ArchController SphereX admin and operator;
- the replacement helper is the SphereX engine default admin and operator;
- the new wallet is authorized and funded;
- the old wallet has no remaining direct SphereX roles; and
- the SDK and testnet application use the replacement helper address.

Then remove the old wallet from the helper in one separately reviewed
transaction and verify the complete authority state again.

Existing market, hooks, role-provider, borrower-account, and fee-recipient
history is not rewritten by this operation.
