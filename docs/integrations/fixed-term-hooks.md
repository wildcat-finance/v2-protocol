# Fixed Term Hooks

[`FixedTermHooks`](../../src/access/FixedTermHooks.sol) prevents withdrawal
queueing before a single maturity timestamp. It shares the credential and
lender-policy system described in [access control](./access-control.md).

## Configuration

Market creation supplies one required ABI word followed by four optional words:

```text
uint32 fixedTermEndTime
uint128 minimumDeposit          // optional; defaults to zero
bool transfersDisabled          // optional; defaults to false
bool allowClosureBeforeTerm     // optional; defaults to false
bool allowTermReduction         // optional; defaults to false
```

The maturity may equal the creation timestamp. It cannot be in the past or more
than 365 days after creation. Missing optional words read as zero.

## Maturity and withdrawals

`queueWithdrawal`, `queueWithdrawalScaled`, and `queueFullWithdrawal` revert
while `block.timestamp < fixedTermEndTime`. Queueing opens at the exact maturity
timestamp. The term does not gate execution of an existing withdrawal.

`nukeFromOrbit` uses the ordinary queue-withdrawal path, so a sanctioned
account's quarantine can also be deferred until maturity or an allowed early
closure. The market's immutable withdrawal-batch duration still applies after
a request is queued.

## Term changes and closure

When `allowTermReduction` is enabled, the hooks administrator may move the
maturity earlier, including into the past. The administrator cannot extend it.

Before maturity, the market borrower may close the market when either
`allowClosureBeforeTerm` or `allowTermReduction` is enabled. The hook moves the
maturity to the closure timestamp. With neither flag, early closure reverts.
Closure at or after maturity needs no term-policy permission.

## APR changes

Before maturity, the hook rejects APR reductions. Equal or higher APRs use the
shared constraints in [hooks](./hooks.md#built-in-parameter-constraints). At or
after maturity, reductions use the same two-week temporary reserve-ratio policy.
The borrower-supplied reserve-ratio value is not applied by this template.

## Other market policy

A positive initial `minimumDeposit` enables the deposit callback. A market
created with a zero minimum and no deposit callback cannot later adopt a
positive minimum. The configured minimum and tendered amount are compared after
both are floored to scaled units.

Withdrawal access requires deposit access and either transfer access or
disabled transfers. See [access control](./access-control.md) for credentials,
known-lender state, deposit blocks, and transfers.

## Tests

- [`FixedTermHooks.t.sol`](../../test/access/FixedTermHooks.t.sol) covers
  configuration, maturity boundaries, term changes, closure, APR policy, and
  access behavior.
- [`ProductionMatrixScenarios.t.sol`](../../test/integration/ProductionMatrixScenarios.t.sol)
  covers the template through deployed standard and revolving markets.
