**Avoiding delinquency fees**

If the borrower closes the market while still in penalized delinquency, they will not have to pay out the remaining time worth of penalized delinquency fees as the timer will be set to zero.

**Malicious or delinquent borrowers can lead to loss of funds**

This one is fairly obvious but worth stating - if a borrower fails to repay their debt for any reason, lenders will inevitably lose funds.

If the borrower is malicious, they can hurt lenders in a variety of ways, including but not limited to: not repaying debt; adding themselves as a lender in order to withdraw beyond the borrow limit on a market they intend to default on; slowly reducing the APR by 25% every two weeks to avoid the penalty of an increased reserve ratio, and several other things.

**Newer withdrawals lose some of their accrued interest to previous withdrawals in the same batch**

This one is intentional but may initially seem erroneous. If Alice creates a withdrawal batch with a request to withdraw 100 tokens while the scale factor is 1, and then bob later requests a withdrawal of 200 tokens when the scale factor is 2 and they are in the same batch, Alice and Bob will both receive 150 underlying tokens because they will each be credited for 100 scaled tokens given to the batch. This is very much the desired behavior, as it prevents earlier lenders from being penalized for creating a batch (which benefits the other lenders). All interest earned on scaled tokens entered into a batch is distributed evenly to the lenders in the batch, as if they had all created their withdrawal requests at the same time.

The example given is also an extreme one, in reality it'd much more likely be a fraction of a percent.

**Bad hooks implementations**

If any of the hooks that are enabled for a market can revert unexpectedly, the corresponding market function may become permanently disabled. This is considered a known/unfixable issue with respect to the market, but if such an issue is actually discovered in a hooks template we have developed, this is a major vulnerability that should be reported.

**Sanctioned account handling on existing markets with withdrawal restrictions**

Markets deployed before the CAF-03 remediation route forced sanctions withdrawals through the same withdrawal hooks as ordinary lender withdrawals. If one of those existing markets uses a hook with a withdrawal restriction, e.g. to prevent withdrawals before a specified date, `nukeFromOrbit` may be blocked until ordinary withdrawals are allowed. This could lead to unavoidable interest payments to a sanctioned entity's escrow address, where the funds will go when withdrawals are eventually unrestricted.

**Open entry with restricted withdrawals on existing markets**

Markets deployed before the CAF-04 remediation could combine open deposits or open transfers with credential-gated withdrawals. An uncredentialed holder who entered through those open paths might not be recorded as a known lender, so queueing a withdrawal can still require credentialed or manually approved access. New hook deployments reject this configuration, but existing markets retain their deployed behavior.

**Future-dated push credentials on existing hooks**

Markets deployed before the CAF-05 remediation allow approved push role providers to call `grantRole` or `grantRoles` with future credential timestamps. Those credentials are usable immediately and expire from the future timestamp, effectively extending the configured provider TTL. New hook deployments reject null or future push credential timestamps, but existing hooks retain their deployed behavior.

**Non-interface push providers on existing hooks**

Markets deployed before the CAF-10 remediation require newly added role providers to implement `isPullProvider()`, even if the address is only meant to push credentials with `grantRole` or `grantRoles`. New hook deployments treat addresses that do not return `true` from `isPullProvider()` as push-only providers, but existing hooks retain their deployed provider-registration behavior.

**Repeated hooksData provider queries on existing hooks**

Markets deployed before the CAF-11 remediation can query a `hooksData`-selected pull provider again in the later automatic pull-provider loop if the selected provider does not yield a valid credential. New hook deployments skip a pull provider already selected by `hooksData`, but existing hooks retain their deployed access-check behavior.

**Malformed pagination ranges on existing ArchController deployments**

Existing ArchController deployments can revert with arithmetic panic for inverted or out-of-bounds paginated registry queries such as `getRegisteredMarkets(start, end)` when `start >= end` after clamping. New ArchController bytecode reverts with an explicit `InvalidPaginationRange()` error for those ranges, but currently deployed ArchController instances retain their original read-surface behavior.

**Hooks lack some specificity**

While one of the stated objectives of hooks is to enable auxiliary behavior based on the state of the market and one example given is a masterchef-style contract, the hooks do not necessarily provide enough information to replicate the market state 1:1 in real time. Specifically, because payment towards a withdrawal batch does not have its own hook, the hooks instance would need to query additional data and perform additional calculations to precisely track the balance of an account including its pending withdrawals in real time, or to know the exact state of a pending/unpaid withdrawal batch.

We anticipate that, for any features added in the future, considering an account to have burned their market tokens at the time a withdrawal is queued will be sufficient precision for the purposes we expect to need this for, and as such we consider the loss of 100% precision on the exact internal market state to be a reasonable sacrifice considering the additional cost such precision would impose.

Any other issues with the ability of a hooks instance to track the state of the market should be reported.
