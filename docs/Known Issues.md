**Avoiding delinquency fees**

If the borrower closes the market while still in penalized delinquency, they will not have to pay out the remaining time worth of penalized delinquency fees as the timer will be set to zero.

**Delinquency transitions are recorded on state writes**

Market accounting is updated lazily. Interest and fees for an elapsed interval
use the previously stored `isDelinquent` flag, and the market stores its new
delinquency status when a state-changing transaction writes the updated state.
Normal market activity provides these checkpoints for busy markets.

Wildcat operates the Hydra keeper to monitor pending delinquency across all
markets and refresh state before and after the relevant timeout when a threshold
crosses. Polling and block-inclusion latency mean this is not exact to the
instant, so a small cadence-dependent difference is accepted. Reports that only
restate this lazy-update behavior are duplicates of this known issue. A path that
defeats timely checkpointing or leaves a material accounting discrepancy after
the checkpoint should still be reported.

**Finite `uint104` withdrawal-batch lifetime counters**

Withdrawal-batch totals, paid-share totals, and each account's queued amount are
cumulative for an expiry. Paid positions can be replaced before that expiry, so
the counters can grow beyond the market's live token supply. These counters use
`uint104` and revert on checked-arithmetic overflow at `2^104 - 1` rather than
rolling over or opening another batch.

At the minimum scale factor, reaching the limit requires approximately
`2.03e13` nominal tokens for an 18-decimal asset or `2.03e25` for a 6-decimal
asset; scale-factor growth only raises that requirement. Saturation must also
repeatedly replace paid shares before the same batch expires. The low-capital
demonstration used an unsupported 30-decimal token. The Foundation-controlled
asset list currently contains only 6- and 18-decimal assets, so the finite
counter and existing storage layout are accepted.

Reports that only restate the finite `uint104` ceiling are duplicates of this
known issue. A practical path that reaches it for a supported asset, overflows a
counter earlier, or avoids the same-batch timing and capital constraints should
still be reported. Revisit this decision before listing a higher-decimal asset.

**Finite `uint112` scale-factor lifetime**

`MarketState.scaleFactor` is stored as a `uint112` and grows monotonically while
interest or delinquency fees accrue. The checked casts in `FeeMath` and
`WildcatMarketRevolving` intentionally revert rather than truncate if the next
scale factor exceeds `uint112.max`. Because market operations accrue interest
before applying their own state transitions, a market that reaches this limit
cannot use the ordinary close, rate-change, transfer, or withdrawal paths.
The failed transaction leaves the previous state unchanged, so accounting does
not wrap or truncate, but this is fail-closed liveness rather than a recovery
path.

This finite lifetime is a known and accepted limitation. For standard
(non-revolving) markets, the theoretical code maximum of 100% APR plus a 100%
delinquency fee reaches the limit after approximately 7.7 years under maximally
frequent updates.

For a fully drawn revolving (RCF) market, the theoretical code maximum of a
100% commitment fee, 100% APR, and 100% delinquency fee reaches the limit after
approximately 5.15 years under maximally frequent updates.

A 100% setting for any of these rate components is already economically
impractical. At a 28% cumulative rate the horizon exceeds 55 years, and at
typical 10-15% cumulative rates it exceeds 100 years. Markets are expected to
close, reduce their rates, or provide a replacement market for lenders to
migrate to long before reaching the representation limit.

Reports that only restate this finite `uint112` horizon are duplicates of this
known issue. A path that reaches the limit materially earlier, bypasses the
checked cast, or causes a distinct loss should still be reported.

**Malicious or delinquent borrowers can lead to loss of funds**

This one is fairly obvious but worth stating - if a borrower fails to repay their debt for any reason, lenders will inevitably lose funds.

If the borrower is malicious, they can hurt lenders in a variety of ways, including but not limited to: not repaying debt; adding themselves as a lender in order to withdraw beyond the borrow limit on a market they intend to default on; slowly reducing the APR by 25% every two weeks to avoid the penalty of an increased reserve ratio, and several other things.

**Newer withdrawals lose some of their accrued interest to previous withdrawals in the same batch**

This one is intentional but may initially seem erroneous. If Alice creates a withdrawal batch with a request to withdraw 100 tokens while the scale factor is 1, and then bob later requests a withdrawal of 200 tokens when the scale factor is 2 and they are in the same batch, Alice and Bob will both receive 150 underlying tokens because they will each be credited for 100 scaled tokens given to the batch. This is very much the desired behavior, as it prevents earlier lenders from being penalized for creating a batch (which benefits the other lenders). All interest earned on scaled tokens entered into a batch is distributed evenly to the lenders in the batch, as if they had all created their withdrawal requests at the same time.

The example given is also an extreme one, in reality it'd much more likely be a fraction of a percent.

**Partial withdrawal-batch payments round down independently**

Each partial payment to a withdrawal batch is rounded down independently, which can result in a rounding loss of less than one atomic unit of the underlying asset per payment. This is accepted because the Foundation controls which assets are listed and can exclude assets for which one atomic unit has material value.

**Protocol fees round independently on each accrual**

Each state update rounds protocol fees independently to the nearest atomic unit without carrying fractional remainders. Frequent updates can therefore reduce aggregate protocol fees, including rounding an interval below half an atomic unit to zero; lender interest is unaffected. This is accepted because the Foundation controls which assets are listed and can exclude assets for which one atomic unit has material value.

**Fee-recipient updates apply only to new markets**

A market's fee recipient is immutable. Updating template fees changes the recipient for subsequently deployed markets, while pushing protocol fee bips to existing markets changes only their rate; this is expected behavior. Markets may intentionally be deployed with a zero rate and zero recipient, but operators must not later push a positive rate to such a market because accrued fees would be reserved but could not be collected.

**Bad hooks implementations**

If any of the hooks that are enabled for a market can revert unexpectedly, the corresponding market function may become permanently disabled. This is considered a known/unfixable issue with respect to the market, but if such an issue is actually discovered in a hooks template we have developed, this is a major vulnerability that should be reported.

**External dependency: Chainalysis sanctions oracle liveness**

Markets consult the Chainalysis sanctions list (through the sanctions
sentinel) inside `borrow`, `executeWithdrawal`, and `nukeFromOrbit`. The
oracle is an external contract outside protocol control: if it ever reverts
or returns malformed data, those market functions revert until it recovers
(the assembly call sites deliberately bubble the failure rather than
defaulting open or closed). Deposits, transfers, and withdrawal queueing do
not consult the oracle and remain live. This is an accepted external
dependency; the revert-bubbling branches are intentionally untestable
without a hostile sentinel mock and are documented rather than covered.

**Canonical ERC-4626 wrappers on legacy V2 markets require a sanctions override**

Markets deployed before v2.5 do not record their canonical ERC-4626 wrapper.
The wrapper contract is therefore treated as an ordinary lender account by the
market. If the wrapper contract address itself becomes flagged by the external
sanctions oracle and the borrower has not overridden that flag, market-level
sanctions handling can move the wrapper's pooled market-token backing while its
ERC-4626 share supply remains outstanding. The wrapper shares would then be
under-backed.

Borrowers whose legacy market has a canonical wrapper should proactively call
`overrideSanction(canonicalWrapper)` on the sanctions sentinel and retain that
override while the wrapper is in use. This borrower-specific override exempts
only the pooled wrapper contract at the market boundary; it does not exempt
wrapper shareholders from the wrapper's own sanctions checks. V2.5 markets
instead register the canonical wrapper atomically during permissionless wrapper
deployment and reject market-level sanctions handling for that registered
address.

**CAF-03: Sanctioned account handling with withdrawal restrictions**

`nukeFromOrbit` queues a sanctioned lender's balance through the same withdrawal hooks as ordinary lender withdrawals. If a market uses a hook with a withdrawal restriction, e.g. to prevent withdrawals before a specified date, `nukeFromOrbit` may be blocked until ordinary withdrawals are allowed. The CAF-03 remediation bypassed `onQueueWithdrawal`, but that also bypassed fixed-term and other withdrawal restrictions, so RCF V2 keeps the ordinary withdrawal path and treats the sanctions liveness limitation as accepted behavior.

On the periodic-term template this deferral recurs every period rather than ending at a fixed date: a lender sanctioned just after a withdrawal window closes cannot be quarantined until the next window opens (up to `periodDuration`, bounded by 365 days), and their balance continues to accrue interest and remains transferable in the interim. This was reviewed and accepted as the same trade-off, consistent with a long fixed term.

**Open entry with restricted withdrawals on existing markets**

Markets deployed before the CAF-04 remediation could combine open deposits or open transfers with credential-gated withdrawals. An uncredentialed holder who entered through those open paths might not be recorded as a known lender, so queueing a withdrawal can still require credentialed or manually approved access. New hook deployments reject this configuration, but existing markets retain their deployed behavior.

**Future-dated push credentials on existing hooks**

Markets deployed before the CAF-05 remediation allow approved push role providers to call `grantRole` or `grantRoles` with future credential timestamps. Those credentials are usable immediately and expire from the future timestamp, effectively extending the configured provider TTL. New hook deployments reject null or future push credential timestamps, but existing hooks retain their deployed behavior.

**Non-interface push providers on existing hooks**

Markets deployed before the CAF-10 remediation require newly added role providers to implement `isPullProvider()`, even if the address is only meant to push credentials with `grantRole` or `grantRoles`. New hook deployments treat addresses that do not return `true` from `isPullProvider()` as push-only providers, but existing hooks retain their deployed provider-registration behavior.

**Repeated hooksData provider queries on existing hooks**

Markets deployed before the CAF-11 remediation can query a `hooksData`-selected pull provider again in the later automatic pull-provider loop if the selected provider does not yield a valid credential. New hook deployments skip a pull provider already selected by `hooksData`, but existing hooks retain their deployed access-check behavior.

**CAF-13: Malformed pagination ranges on the ArchController singleton**

The deployed ArchController singleton can revert with arithmetic panic for inverted or out-of-bounds paginated registry queries such as `getRegisteredMarkets(start, end)` when `start >= end` after clamping. The CAF-13 remediation is to explicitly reject malformed ranges before subtraction. RCF V2 is not redeploying the ArchController, so the repository keeps the singleton behavior and documents the remediation in comments instead of changing the active ArchController code.

**CAF-16: Raw registry addresses on the ArchController singleton**

The deployed ArchController singleton allows privileged callers to register arbitrary addresses as controller factories, controllers, or markets. A misconfigured owner, controller factory, or controller can therefore add EOAs or nonconforming contracts to the registry, polluting registry, lens, subgraph, or SphereX allowed-sender surfaces. The CAF-16 remediation is to reject non-contract and wrong-arch factory/controller/market registrations and require registered markets to report the registering controller as their factory. RCF V2 is not redeploying the ArchController, so operator validation remains the control for singleton registrations.

**SphereX engine rotations require an atomic controller cutover**

SphereX-protected contracts cache their engine address. If the ArchController switches engines before the market-deploying controllers (`HooksFactory` and `HooksFactoryRevolving`) are updated, a borrower can deploy a market that uses the controller's old engine even though the ArchController registers and allowlists it on the new engine. V2.5 does not rotate the SphereX engine, so this does not affect the release deployment. For any future rotation, keep the old engine operational and atomically update the ArchController and all market-deploying controllers before new markets can be created; existing markets can then be migrated in gas-bounded batches and checked against the ArchController's engine.

**Deployment targets must support EIP-1153**

Wildcat V2 bytecode uses transient storage for reentrancy protection and factory deployment scratch space. Deployment targets that do not support `TSTORE` / `TLOAD` can deploy bytecode that later fails when those paths execute. Active deployment scripts probe the target RPC before deployment, but manual or third-party deployments must still restrict targets to Cancun-compatible chains.

**Closing markets with many unpaid withdrawal batches**

`closeMarket()` processes all unpaid withdrawal batches before the market is closed. If a market has accumulated many unpaid batches, a close transaction can run out of gas. This is accepted operational behavior: callers should process unpaid batches incrementally with `repayAndProcessUnpaidWithdrawalBatches(0, maxBatches)` before calling `closeMarket()` on heavily aged markets.

**Nonstandard token metadata on listed assets**

Wildcat intentionally supports both ABI strings and legacy fixed-width `bytes32` values for token `name()` and `symbol()`. Market deployment and the lens use the same `LibERC20` decoder for those values and for `decimals()`.

Outside that compatibility form, Wildcat assumes listed assets expose stable metadata and standard transfer semantics. Empty, malformed, mutable, excessively long, or confusing display metadata, including names that rely on invisible unicode characters, can block deployment, later break lens reads, or produce misleading offchain display text. Zero-amount transfer reverts can also break fee paths that otherwise amount to no economic transfer. This is accepted as an asset-listing boundary: asset review must reject or explicitly approve such tokens before listing.

**Hooks lack some specificity**

While one of the stated objectives of hooks is to enable auxiliary behavior based on the state of the market and one example given is a masterchef-style contract, the hooks do not necessarily provide enough information to replicate the market state 1:1 in real time. Specifically, because payment towards a withdrawal batch does not have its own hook, the hooks instance would need to query additional data and perform additional calculations to precisely track the balance of an account including its pending withdrawals in real time, or to know the exact state of a pending/unpaid withdrawal batch.

We anticipate that, for any features added in the future, considering an account to have burned their market tokens at the time a withdrawal is queued will be sufficient precision for the purposes we expect to need this for, and as such we consider the loss of 100% precision on the exact internal market state to be a reasonable sacrifice considering the additional cost such precision would impose.

Any other issues with the ability of a hooks instance to track the state of the market should be reported.
