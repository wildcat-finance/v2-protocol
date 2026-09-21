# Fixed-term hooks

[`FixedTermHooks`](../../src/access/FixedTermHooks.sol) blocks withdrawal
queueing before one maturity timestamp. It uses the credential and lender
policy described in [Access control](./access-control.md).

## Configuration

Market creation supplies one required ABI word and up to four optional words:

```text
uint32 fixedTermEndTime
uint128 minimumDeposit          // optional; defaults to zero
bool transfersDisabled          // optional; defaults to false
bool allowClosureBeforeTerm     // optional; defaults to false
bool allowTermReduction         // optional; defaults to false
```

The maturity can equal the creation timestamp. It cannot be in the past or more
than 365 days after creation. Missing optional words decode as zero.

## Maturity and withdrawals

`queueWithdrawal`, `queueWithdrawalScaled`, and `queueFullWithdrawal` revert
while `block.timestamp < fixedTermEndTime`. Queueing opens at the exact maturity
timestamp. Maturity does not gate execution of an existing withdrawal.

`nukeFromOrbit` uses the same queueing path. Quarantine of a sanctioned account
can therefore wait until maturity or an allowed early closure. Once a request is
queued, the market's immutable withdrawal-batch duration still applies.

## Term changes and closure

If `allowTermReduction` is enabled, the hooks administrator can move maturity
earlier, including into the past. They cannot extend it.

Before maturity, the borrower can close the market if either
`allowClosureBeforeTerm` or `allowTermReduction` is enabled. The hook moves
maturity to the closure timestamp. If both flags are false, early closure
reverts. Closure at or after maturity needs no term-policy permission.

## APR changes

Before maturity, APR reductions revert. Equal or higher APRs use the shared
constraints in [Hooks](./hooks.md#built-in-parameter-constraints).

At and after maturity, reductions use the shared two-week temporary
reserve-ratio policy. This template ignores the borrower-supplied reserve ratio.

## Other market policy

A positive initial `minimumDeposit` enables the deposit callback. A market
created with a zero minimum and no deposit callback cannot add a positive
minimum later. The hook compares the minimum and tendered amount after flooring
both to scaled units.

Withdrawal access requires deposit access and either transfer access or
disabled transfers. See [Access control](./access-control.md) for credentials,
known-lender state, deposit blocks, and transfer policy.

## Tests

- [`FixedTermHooks.t.sol`](../../test/access/FixedTermHooks.t.sol): configuration,
  maturity boundaries, term changes, closure, APR policy, and access behavior
- [`ProductionMatrixScenarios.t.sol`](../../test/integration/ProductionMatrixScenarios.t.sol):
  standard and revolving market deployments using this template
