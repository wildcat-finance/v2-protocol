# Withdrawal-counter capacity: review handoff

Observed 2026-09-29; handoff prepared and disposition reviewed 2026-09-30.
This records a pre-deployment accounting-capacity concern and the selected
remediation. It does not establish exposure in any deployed market.

| Comparison | Explicit source |
| --- | --- |
| Development base, cumulative scaled counters still uint104 | `7d792812a771484f2481543d4a0b9d66a0e5e2af` |
| Counter-only widening | `23c47cde20c60d42c8e7a6aa1d4639968e45f9fb` |
| Complete carry with size reductions | `7b7db0e7517401da002239470a8aff3802e3c646` |
| Latest compatibility stack under verification | `ade86605a79eac916d6595ba7b4813398dd28a9e` |

The relevant market source is unchanged between the carry source and the latest
compatibility stack. The metadata and origination-fee changes do not address
this concern. Source revisions do not establish deployment identity.

## Disposition

Keep the packed `uint128` field declarations, but reject any queue operation
that would take one batch's cumulative scaled ownership above
`type(uint104).max`. The check occurs at the original cumulative-addition
boundary and preserves its `Panic(0x11)` behavior. Normalized, scaled and full
withdrawals, together with `nukeFromOrbit`, all use that boundary.

This restores the old mathematical guarantee without reverting the carry
accounting or changing the current getter ABI and storage packing. A rejected
balance remains live and can enter the next batch. The focused regression in
[`WithdrawalCounters.t.sol`](../../test/market/WithdrawalCounters.t.sol) covers
all admission routes, all four market/hook combinations, narrow-reader
compatibility, rollover, and the maximum-factor bound.

The separate global `normalizedUnclaimedWithdrawals` counter can temporarily
fill across several extreme-factor batches. That state is recoverable: older
batches are executable before a new batch opens, anyone can execute their
claims, and execution releases global capacity before payment is retried. The
regression suite records that recovery path. Underlying-token transfer failure
can still delay it under the documented unsupported-token boundary.

The evidence below remains unchanged as characterization of the rejected
widening behavior and to preserve its provenance.

## Why widening might move the failure boundary

Widening adds headroom and is not intrinsically incorrect. The concern is that
the scaled counters were widened while the cumulative **normalized payment**
counter stayed uint128. The old scaled cap implicitly bounded the normalized
counter across a batch's entire lifetime.

Let `R = 10^27`, `Q` be the cumulative scaled shares paid in one batch, and `F`
the scale factor. The source represents `F` as uint112. Before widening:

```text
Q <= 2^104 - 1
F <= 2^112 - 1
sum of floor-paid units <= floor((2^104 - 1) * (2^112 - 1) / R)
                       = 105312291668557186697918027683665219739
uint128 maximum        = 340282366920938463463374607431768211455
```

The bound holds across different payment factors: each factor is at most the
same representable maximum. In that source, the scaled admission cap is reached
before cumulative normalized payments can exhaust uint128. A failed new queue
operation leaves its tokens unqueued; a later batch remains an alternative.

After widening, `Q` can approach `2^128 - 1`; live balances and live supply are
still uint104. Paid shares can be replaced through later deposits, so live
supply does not bound lifetime batch volume. At sufficiently high factors,
normalized payment capacity can run out before the new scaled admission cap.

This matters if a queue operation accepts a request while liquidity is absent,
then the later payment overflows. The request is already in the batch. Claiming
previous payments decreases global `normalizedUnclaimedWithdrawals`, but does
not decrease the batch's cumulative `normalizedAmountPaid`. Releasing global
capacity therefore does not necessarily make that batch settleable.

At factor RAY, widening provides substantially more aligned scaled/normalized
headroom. This handoff does not claim ordinary small deposits become less safe,
or that the high-factor fixture is economically representative. The question
is whether all newly admitted requests retain a representable settlement path.

## Evidence and its limits

The original test source is preserved byte-for-byte at
[`evidence/withdrawal-counter-capacity/WithdrawalCounterBoundary.t.sol`](./evidence/withdrawal-counter-capacity/WithdrawalCounterBoundary.t.sol).
SHA-256:
`23158ec7e74ba2c4e186267646f6846579703d16cabdfeee5c52e8f200b3f3b2`.

`test_highFactorLifetimeVolume_AcceptsAnUnsettleableRequest` covers standard and
revolving markets with open-term and fixed-term hooks. It injects only a scale
factor of `4e33`, within uint112, standing in for historical accrual. It builds
the subsequent deposit, queue, funding, claim and batch history through public
market actions. Four paid cycles fit the normalized counter; a fifth request
is accepted without liquidity. Earlier paid claims can exit, but the test
observes later payment and closure reverting at the cumulative payment cap.

The fixture **does not reproduce the historical accrual needed to reach that
factor**, identify a realistically valued asset, or prove deployed exposure.
Its no-interest configuration preserves the injected factor during the test.
Passing means the expected failure was reproduced, not that settlement is safe.
The same high-factor case was observed at both counter-only and carry revisions.

Other tests in the preserved file inject batch/account history directly. Those
are packing and representation checks, with storage roots pinned to `23c47cd`;
they are not reachability demonstrations and must not all be run against the
carry layout. The high-factor case does not use those mapping roots.

To reproduce the high-factor case in a separate worktree at either named
revision, copy the evidence to `test/review/WithdrawalCounterBoundary.t.sol`
(keeping its relative fixture import valid), initialize the recorded library
gitlinks, and run:

```sh
forge test --match-path test/review/WithdrawalCounterBoundary.t.sol \
  --match-test test_highFactorLifetimeVolume_AcceptsAnUnsettleableRequest -vv
```

Do not add this characterization to a release suite as an assertion that
unsettleable requests are acceptable. Keep the original bytes and provenance;
derive remediation tests separately if a fix is selected.

## Review resolution

1. The old implicit normalized bound and the unsafe widened admission domain
   were reproduced against explicit revisions.
2. Practical exploitation was not established: the natural-factor example
   requires about 12.3 years at 100% APR and no realistic affected asset was
   identified. Arbitrary ERC20 admission still makes the broken invariant
   unsuitable for immutable source.
3. The restored cap holds across rising factors and partial payments because
   every paid share uses a factor no larger than `uint112.max`; carry preserves
   the same cumulative numerator.
4. Widening normalized payments to 160 bits would add an account-status slot,
   require full-precision claim arithmetic, and expand downstream review. The
   admission cap is the narrower complete fix.
5. The widening behavior is rejected. The physical `uint128` layout remains
   for compatibility, while valid cumulative ownership retains the earlier
   `uint104` limit.

Original local traces, layout measurements and characterization results were
retained under `artifacts/withdrawal-counter-review/` in the protocol's local
evidence collection. The source attached here makes the key test travel with
Git; those external local logs do not automatically travel with a pushed branch.
