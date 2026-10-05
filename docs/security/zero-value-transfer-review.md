# Zero-value transfer compatibility review

Reviewed on 2026-09-29 against
`e7ff6c7bd83045616932084f8d7bd87933864c58`, which inherits the paused withdrawal
experiments and the selected metadata candidate. Baseline characterizations are
preserved at `review/zero-value-transfers@4a2a329`. The user selected the narrow
factory fix; the candidate is on `experiment/zero-origination-fee`. This does
not select the withdrawal experiments for release. Local source/tests are not
deployment evidence.

CAF-15 accepted metadata and zero-transfer compatibility under an asset-listing
assumption. Arbitrary underlying ERC-20 assets have always been allowed. The
historical disposition remains intact; this note reassesses the zero-transfer
part. Rebasing, fee-on-transfer and dishonest balance accounting remain outside
supported behavior.

## Finding and scope

Before this candidate, both `HooksFactory._deployMarket` and
`HooksFactoryRevolving._deployMarket` call `safeTransferFrom` whenever the
supplied origination-fee asset is nonzero, including when the configured fee
amount is zero. The arguments must first match the template's fee asset and
amount exactly.

This unnecessarily couples a free deployment to the fee token's transfer
behavior. A token rejecting zero amounts causes deployment to fail. There is
also a permitted configuration with a nonzero fee token, zero amount, zero
protocol fee and zero recipient: a token rejecting a zero recipient then blocks
deployment even if it accepts zero amounts. Both failures surface as
`TransferFromFailed()`.

The fee token is configured by the template owner and need not be the deposit
asset. This is not evidence that an arbitrary deposit asset rejecting zero
amounts breaks ordinary lending. Clearing the configured fee asset when no
origination fee is due is an existing administrative workaround.

The same amount-insensitive transfer guard is present in source tags `v2.0.0`
and `v2.1.0`. That comparison does not establish deployed code or historical
exposure.

## Implemented narrow change

Both factories now transfer only when `runtimeParams.originationFeeAmount != 0`.
The existing exact fee-match check remains before the guard. Template validation
already requires a nonzero token and recipient for a positive origination fee.
Positive fee collection therefore retains its current validation and transfer.

The candidate preserves hooks creation and `onCreateMarket`, deployment events
and recorded fee asset/amount, including a configured token with amount zero. The intentional
observable difference is that no external token call or token `Transfer(0)` log
occurs for a zero origination fee. Do not replace the token address with zero in
deployment arguments or events: exact configuration matching still matters.

This changes factories only: no market runtime budget, market storage,
ABI tuple or event-schema change. Existing deployed factories retain the old
behavior; source integration and deployment of new factories are separate work.

At `subgraph@584e5de`, V2.5 fee configuration is indexed from
`MarketDeploymentConfig` in `src/hooks-factory-v2-5.ts`, rather than inferred
from a fee-token transfer. At `wildcat.ts@e64e766`,
`src/access/access-control.ts` requires fee balance/allowance only for a positive
amount and sends the configured token and amount to either factory route.
Those paths need no interface change for this guard. This is a scoped
source inspection, not a full SDK/app integration test; no consumers changed.

## Other transfer callers

| Caller | Current zero behavior | Recommendation |
| --- | --- | --- |
| Deposit, standalone repay, fee collection, executed withdrawal payout | Reject zero before the transfer; deposits also reject a rounded-to-zero mint. | Retain. |
| `repayAndProcessUnpaidWithdrawalBatches(0, ...)` | Already skips both the repayment transfer and repayment hook while processing batches. | Retain the process-only mode. |
| Market closure | Repays only a shortfall and returns only an excess. | No zero-transfer change needed. |
| `borrow(0)` | Subject to normal access/lifecycle checks, then runs its hook/state/event path and transfers zero. | Leave unchanged in this narrow proposal. Skipping the token call would require deliberate preservation of the rest of that behavior. A token rejecting zero does not thereby reject positive draws. |
| `rescueTokens` with no recoverable balance | Can attempt a zero transfer, including closed-market underlying rescue. | Optional convenience improvement; failure of an empty rescue alone is not evidence that positive payouts fail. Avoid spending scarce market bytecode here without a separate reason. |
| `WildcatSanctionsEscrow.releaseEscrow()` when empty | Can attempt a zero transfer and emit a zero release. | Optional convenience improvement, separate from the factories; a funded escrow uses a positive transfer. |
| ERC-4626 wrapper actions/sweep | Zero actions/surplus are rejected before transfer; regular actions transfer market tokens, not the underlying arbitrary asset. | Retain. Do not change public token-transfer semantics. |

Do not make `LibERC20` globally suppress zero calls. Different callers have
different hook, event and validation contracts; this factory issue has a local
solution.

## Baseline verification

```sh
forge test --match-path test/factories/ZeroValueTransferReview.t.sol -vv
```

Run the command above at `4a2a329` for the original assertions. All five baseline
characterizations passed with Solidity 0.8.25 and the existing Foundry
profile. Each covers both standard/revolving factories and both existing-hooks
and atomic hooks-plus-market deployment routes:

- Zero-rejecting fee token blocks a zero-fee deployment.
- A token accepting zero amounts but rejecting a zero recipient blocks the
  permitted zero-fee/null-recipient configuration.
- Positive fees transfer the exact amount on each deployment, consuming the
  expected allowance and leaving the expected recipient/borrower balances.
- A zero fee with no fee token deploys successfully without an ERC-20 transfer.
- Fee mismatch is rejected before attempting the transfer.

The fixture uses real factories, markets and open-term hooks and a conventional
balance-accounting token with explicit transfer rejection rules. Those original
tests characterize the old behavior; the candidate updates the first two to
assert successful creation and preservation of `MarketDeploymentConfig`.

## Candidate verification

```sh
forge test --match-path 'test/factories/*.t.sol' -vv
```

The candidate's eight focused tests cover both factory kinds and both deployment
routes. They check successful zero-fee deployment with zero-rejecting tokens or
null recipients; preservation of the configured token, zero amount and recipient
in the deployment event; real market registration and hooks attachment; no token
call even when a token would accept zero; exact positive-fee transfers; rejection
of token/amount mismatches and attempts to bypass a positive fee with zero; and
failure when a positive fee lacks approval. The existing factory suite supplies
the wider template, fee-validation, hooks, authorization and deployment checks.

All 37 factory tests passed with Solidity 0.8.25 and the unchanged Foundry
profile, including the eight focused regressions. A targeted deployment-profile
build passed; its runtimes match the default profile. No full market/invariant
suite or consumer build was run for this factory-only change. Formatting and
diff checks passed.

| Contract | Baseline bytes | Candidate bytes | Change |
| --- | --- | --- | --- |
| Standard factory | 16,576 | 16,568 | -8 |
| Revolving factory | 17,126 | 17,118 | -8 |
| Standard market | 23,998 | 23,998 | Runtime bytes identical |
| Revolving market | 24,554 | 24,554 | Runtime bytes identical |

All four ABIs are identical to baseline. These are measurements with the
repository's compiler settings, not claims about other profiles or deployed code.

These regressions do not establish support for arbitrary callbacks or unsupported
token accounting. They do not verify historical deployments or complete the
later SDK/app pass.
