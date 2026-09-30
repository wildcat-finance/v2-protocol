# Withdrawal-counter capacity: review handoff

Observed 2026-09-29; handoff prepared 2026-09-30. This is an unresolved
accounting-capacity concern for pre-deployment source, not an established
deployed exposure. The user assigned further assessment to another session;
do not interpret this note as approval to modify or adopt either experiment.

| Comparison | Explicit source |
| --- | --- |
| Development base, cumulative scaled counters still uint104 | `7d792812a771484f2481543d4a0b9d66a0e5e2af` |
| Counter-only widening | `23c47cde20c60d42c8e7a6aa1d4639968e45f9fb` |
| Complete carry with size reductions | `7b7db0e7517401da002239470a8aff3802e3c646` |
| Latest compatibility stack under verification | `ade86605a79eac916d6595ba7b4813398dd28a9e` |

The relevant market source is unchanged between the carry source and the latest
compatibility stack. The metadata and origination-fee changes do not address
this concern. Source revisions do not establish deployment identity.

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

## Questions for the next reviewer

1. Verify the old implicit normalized bound and the widened admission domain
   directly against each revision. Compare rejection before admission with
   failure after admission; counter widths alone do not decide safety.
2. Determine whether production constraints bound lifetime volume tightly
   enough: factor growth, batch duration, asset units, transaction feasibility,
   liquidity, borrowing and all queue/claim paths. State which conditions are
   injected and which can be established through normal history.
3. Check existing requests when prices accrue after admission, along with
   partial funding, expiration, sanctions paths and manual/automatic closure.
   A check only at queue time may not cover later growth.
4. If remediation is warranted, compare admission bounds, wider/changed payment
   representation and batch rollover/separation. Define the accepted-request
   invariant first; preserve debt, reserved assets, pro-rata ownership and exits.
5. Record an explicit disposition: fix, reject the widening, or accept a
   quantified operating boundary with rationale. Practical exposure remains
   unestablished until that review supplies evidence.

Original local traces, layout measurements and characterization results were
retained under `artifacts/withdrawal-counter-review/` in the protocol's local
evidence collection. The source attached here makes the key test travel with
Git; those external local logs do not automatically travel with a pushed branch.
