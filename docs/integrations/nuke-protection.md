# Protection for pooled lender contracts

The V2.5 design decision as of 2026-10-15 is permissionless, optional canonical-wrapper
creation with permanent protection and no first-deposit deadline. Protocol `2.5.8` is prepared on
`fix/nuke_and_grace`; this describes source behavior, not a deployed upgrade.

V2.5 markets keep permanent `isNukeProtected(account)` entries for approved
integration contracts. A protected account cannot be passed to the market's
`nukeFromOrbit`: it reverts with `CannotNukeProtectedAccount` before sanctions
lookups, hooks, or withdrawal accounting.

This protects a pooled position, such as an ERC-4626 wrapper's backing, from
being quarantined as though the contract were one individual lender. It also
supports future dedicated lender contracts without adding another special
address to the market implementation.

The protection applies only to `nukeFromOrbit`. It does not authorize deposits,
transfers, withdrawal queueing, or withdrawals; it does not override the
sanctions sentinel. A sanctioned wrapper still fails its operational checks.
Integration-specific exit and sanctions handling remain the integration's
responsibility.

## Authority and permanence

| Operation | Authority | Effect |
| --- | --- | --- |
| Approve or disable a feature factory | Current `ArchController.owner()` | Changes eligibility for future registrations on that market factory |
| Request protection for an instance | An approved feature factory | Vouches for an instance it deployed or authenticated, bound to this market |
| Write the market's protection entry | The market's immutable `factory()` | Adds a permanent local entry at any point in the market's lifetime |
| Remove protection | Nobody | No removal path exists |

Both standard and revolving market factories expose
`setNukeProtectionFactoryApproval(featureFactory, approved)` and
`isApprovedNukeProtectionFactory(featureFactory)`. Each factory maintains its
own approvals. The ArchController itself is unchanged; hooks do not decide
whether an account is protected.

Deployment scripts configure initial approvals through the same current
ArchController owner authority used for later additions. Deploying a market
factory does not create a separate deployer role or automatically approve its
configured wrapper factory.

An approved feature factory calls
`registerNukeProtectedAccount(market, account)` on the market's factory. The
relay checks the caller's approval, its own record that it deployed the market,
and that the account has deployed code. It then calls
`market.registerNukeProtectedAccount(account)`.

Approval makes a feature factory eligible to request protection; it does not
protect the factory address or its instances by itself. The feature factory's
deployment flow must register each qualifying instance in the same transaction
that creates it, and revert creation if registration fails. The canonical
wrapper factory does this whenever anyone calls `createWrapper(market)`; a
future TranchingManager factory or other approved feature factory must do the
same. There is no separate per-instance Foundation approval or operator step.

The feature factory calls the relay after the instance's constructor returns,
before returning the instance to its caller. The relay requires deployed code,
so the instance cannot register from inside its own constructor. Approval of a
factory does not insert this call into its code; atomic registration is part
of the implementation that must be reviewed before approval.

Contract code alone does not establish provenance. Approval trusts the reviewed
feature factory to enforce the instance's implementation, constructor
configuration, market binding, and lack of upgrade or arbitrary forwarding
paths. An instance's self-reported interface, a runtime hash containing mutable
delegation, or a Safe's code is not sufficient. An approved factory must never
provide an unrestricted relay for user-supplied addresses.

Factory approval can be removed to prevent new registrations. Existing market
entries do not consult that approval again. Ownership transfer, approval
removal, and borrower changes cannot undo them. The owner retains authority to
approve additional feature factories for existing markets, but cannot remove
protection from any registered account.

## Registration remains open after funding

Protection is permanent per account; the set of accounts is not frozen. A new
approved feature factory can register authentic instances in an already funded
market, including months after its first deposit. An eligible existing instance
may also receive protection after acquiring its market position. Registration
does not move balances or grant deposit, transfer, or withdrawal permissions.

The initially prepared first-deposit cutoff was removed after design review.
There is no seal flag or registration deadline. Deposits, withdrawals, zero
supply, and market closure do not change registration eligibility. Approved
registration may occur during a deposit callback; the setter has no external
calls, changes only the protection mapping, and rolls back with a reverted
transaction. All factory authorization and provenance rules still apply.

This deliberately retains trust in future factory approvals: an incorrectly
approved factory could introduce inappropriate exemptions into existing markets.
Reviewing immutable factory code and instance configuration is the boundary for
new additions. Irrevocable market entries address the separate risk of later
administrative removal. New integrations must register during instance creation
so that their initial backing is protected. The relay also permits authenticated
existing instances to be registered; market funding is not a protocol-level
deadline.

## Canonical wrapper setup

Market creation does not deploy a wrapper or call the wrapper factory. Anyone
may call `createWrapper(market)` separately, including after the market has
been funded for months. The wrapper factory deploys the wrapper, requests
protection through the market factory, and calls `registerWrapper` to record
its canonical identity. These steps are atomic within the wrapper transaction.
If approval is missing, wrapper creation rolls back; the existing market and
its lender positions are unaffected.

Wrapper creation checks the market's installed hook for the complete
`IMarketTransferPolicy` interface and enabled transfers. Markets with disabled
transfers or unsupported wrapper policy remain deployable and usable without
a wrapper. These compatibility checks belong to the wrapper factory, not
market creation.

The wrapper factory must be approved on a market factory before it can create
protected wrappers for that factory's markets. This approval is not a
prerequisite for deploying or funding markets. `registeredWrapper()` remains
the canonical identity used by transfer policy and discovery; nuke protection
comes from the local mapping. The wrapper's own self-nuke guard still uses
`CannotNukeWrapper`.

Canonical identity remains limited to the implementation deployed by the
market's configured wrapper factory. An approved feature factory can register
nuke protection for a different wrapper or lender contract, but that does not
make it canonical or grant the canonical wrapper's transfer-policy privileges.
Deploying a custom wrapper and admitting it through ordinary lender policy
remain separate from these privileges.

## Rollout and consumer changes

This change targets new V2.5 deployments. It does not migrate existing contracts.
Deploy the updated wrapper factory, market artifacts, and market factories;
approve the wrapper factory on each intended market factory before wrapper creation.
For later feature versions, review and deploy the immutable feature factory,
then approve its exact address on each intended market factory.

The preparation script below reads the current owners and deployed code and
produces transaction calldata for review. The owner submits those transactions:

```sh
RPC_URL=... node scripts/prepare-nuke-protection-approvals.js \
  FEATURE_FACTORY STANDARD_MARKET_FACTORY REVOLVING_MARKET_FACTORY
```

Use `--disable` to prepare removal of eligibility for future registrations.
This cannot remove existing protection.

The output describes the owner-level call. When the owner is a contract, submit
it through that contract's execution mechanism. Sepolia's version-2
`MockArchControllerOwner` supports `executeProtocolAction(factory, data)` from
an authorized executor; it accepts factories bound to the same ArchController
without a selector allowlist. No owner-helper replacement is needed for this
approval.

Consumers must regenerate the market and factory ABIs. The market emits
`NukeProtectionRegistered(account)`; the factory emits
`NukeProtectionRequested(market, account, featureFactory)` and
`NukeProtectionFactoryApproval(featureFactory, approved)`. Deposits do not close
registration. Clients retain the optional, separate wrapper-deployment flow
and discover existing wrappers through the canonical market/factory getters.
Removing the temporary automatic-deployment implementation changes no public
market or factory ABI.

`MarketState` and hook callback tuples are unchanged. The new mapping is separate
storage. The independent grace/default correction is outside this
change.

The [initial verification receipt](../releases/v2.5.8-nuke-verification.json)
records the superseded candidate that included the first-deposit cutoff.
The [open-registration receipt](../releases/v2.5.8-open-registration-verification.json)
records removal of that cutoff while automatic wrapper creation was still
enabled. The [optional-wrapper receipt](../releases/v2.5.8-optional-wrapper-verification.json)
records removal of automatic deployment. These checks do not qualify the
pending grace/default correction or a future deployment package.
