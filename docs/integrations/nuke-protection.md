# Protection for pooled lender contracts

The V2.5 design decision as of 2026-10-15 is automatic canonical-wrapper
creation for compatible markets. Protocol `2.5.8` is prepared on
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
| Write the market's protection entry | The market's immutable `factory()` | Adds a permanent local entry before the first successful deposit |
| Remove protection | Nobody | No removal path exists |

Both standard and revolving market factories expose
`setNukeProtectionFactoryApproval(featureFactory, approved)` and
`isApprovedNukeProtectionFactory(featureFactory)`. Each factory maintains its
own approvals. The ArchController itself is unchanged; hooks do not decide
whether an account is protected.

An approved feature factory calls
`registerNukeProtectedAccount(market, account)` on the market's factory. The
relay checks the caller's approval, its own record that it deployed the market,
and that the account has deployed code. It then calls
`market.registerNukeProtectedAccount(account)`.

Contract code alone does not establish provenance. Approval trusts the reviewed
feature factory to enforce the instance's implementation, constructor
configuration, market binding, and lack of upgrade or arbitrary forwarding
paths. An instance's self-reported interface, a runtime hash containing mutable
delegation, or a Safe's code is not sufficient. An approved factory must never
provide an unrestricted relay for user-supplied addresses.

Factory approval can be removed to prevent new registrations. Existing market
entries do not consult that approval again. Ownership transfer, approval
removal, and borrower changes cannot undo them. This limits administrative
authority over an already funded market.

## Registration closes at first funding

This is a new restriction introduced by freezing the protection list. The
previous canonical-wrapper guard allowed wrapper registration after funding.
The local mapping itself does not require a deadline; the deadline enforces
the chosen rule that lenders' protection set cannot change after first funding.

The first successful `deposit` or `depositUpTo` permanently sets
`nukeProtectionSealed()`. The write precedes the deposit hook and asset transfer,
so callbacks cannot add protection while the deposit is in progress. A reverted
deposit, including an exact-deposit capacity failure, rolls the write back.

Emptying the supply, settling withdrawal claims, or closing the market does not
reopen registration. New approved feature types can serve new or still unfunded
markets; they cannot add protected accounts to a market that has already had a
successful deposit. Integrations that require protection must complete creation
and registration before allowing a first deposit, preferably atomically.

## Canonical wrapper setup

Both market factories create the canonical wrapper in the market-deployment
transaction, after the discovery event bundle. The wrapper factory deploys it,
requests protection through the market factory, and calls `registerWrapper`
to record its canonical identity. Failure of any step reverts the entire
market deployment. This closes the window in which a first deposit could
otherwise seal the protection list before wrapper setup.

The compatibility check uses the final hook address returned by the creation
callback and installed on the market. Markets whose hooks disable transfers or
do not expose both valid boolean queries of `IMarketTransferPolicy` remain
deployable without a wrapper. The
factory bounds each probe's returned data to one word. A false recipient
eligibility result still proves that query is supported; the probe account
does not itself need lender credentials. For compatible markets, actual
wrapper-creation failures are not swallowed.

The wrapper factory must be approved on each market factory before compatible
markets can be deployed. `registeredWrapper()` remains the canonical identity
used by transfer policy and discovery; nuke protection
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
approve the wrapper factory on every market factory before enabling creation.
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
`NukeProtectionFactoryApproval(featureFactory, approved)`. A successful first
`Deposit` seals registration; there is no separate seal event. Clients must
discover the wrapper after compatible market creation instead of submitting
a second deployment transaction or presenting wrapper deployment as optional.

`MarketState` and hook callback tuples are unchanged. The new mapping and seal
are separate storage. The independent grace/default correction is outside this
change.

The [verification receipt](../releases/v2.5.8-nuke-verification.json) records
the source hashes, complete test runs, and runtime sizes for this candidate.
It does not qualify a future deployment package or the pending grace/default
correction.
