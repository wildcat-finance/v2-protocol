# Token metadata compatibility review

Baseline source: `7b7db0e7517401da002239470a8aff3802e3c646`, reviewed on
2026-09-29 and preserved in `review/token-metadata@c5f7a08`. The user selected
canonical empty-string support and best-effort cosmetic lens reads. The local
candidate is on `experiment/token-metadata`; it changes factory decoding and
lens behavior without changing market accounting or the lens ABI. This is
source and local-test evidence, not deployment evidence. The original CAF-15,
CertiK finding 13 and WKI-013 dispositions assumed asset-listing review would
exclude unusual metadata. Arbitrary ERC-20 assets have always been permitted;
there is no Foundation metadata allowlist protecting these paths.

ERC-20 makes `name`, `symbol` and `decimals` optional. A token's conformity to
the [standard](https://eips.ethereum.org/EIPS/eip-20) therefore does not prove
compatibility with the factory's mandatory metadata reads. Rebasing,
fee-on-transfer and dishonest balance/transfer accounting remain unsupported;
this review does not propose accommodating those behaviors.

## Baseline behavior before this candidate

The following table describes the unmodified baseline, not the candidate's
new empty-string and cosmetic-fallback behavior.

| Case | Factory and market | Lens / consumer consequence |
| --- | --- | --- |
| Canonical empty dynamic `name` or `symbol` | Deployment fails in `StringQuery`: the valid 64-byte `[offset][zero length]` response is rejected. | Strict token and full market reads also fail. Empty legacy `bytes32` metadata is accepted in this candidate, so acceptance depends on encoding. |
| Long name or symbol | Prefix plus underlying string must fit 63 **bytes**, because the market caches each string in two immutable words. An asset name exceeding 63 bytes cannot fit even with an empty prefix. | The shared decoder and direct token lens do not impose this factory packing limit. Shortening an optional prefix helps only when the asset text itself fits. |
| Ordinary Unicode | Accepted as opaque bytes when the combined UTF-8 encoding fits. There is no ASCII restriction. | Consumers must distinguish display labels from token identity, which is chain plus address. Confusables and control characters need display handling; byte slicing can split UTF-8. |
| Missing, failed or malformed decimals | Deployment requires an exactly 32-byte result in the uint8 range; it does not assume 18. | Strict token reads fail. Guessing a denomination could cause incorrect amount conversion. |
| Name or symbol later changes | The market retains its creation-time name and symbol. Transfers and accounting do not query underlying names or symbols. | The lens reads the underlying token's current metadata, so market and underlying labels can differ. |
| Metadata later reverts | Already-created markets do not need those reads to deposit, queue or execute a withdrawal. | Full market/token batch reads are strict. One failed token can abort a response that also includes healthy markets. |
| Decimals later changes | The market retains its creation-time decimals and continues operating on raw atomic units. | The lens can return different decimals for market and underlying tokens. Consumers must identify the discrepancy rather than silently reinterpret normalized claims. |

These are different compatibility boundaries. Cosmetic read failures do not
demonstrate a custody or accounting failure. A successful transfer interface
also does not guarantee that discovery reads will remain available.

## Baseline verification

At `c5f7a08`, `test/lens/TokenMetadataReview.t.sol` characterizes the unchanged source using
real standard and revolving factories, real open-term hooks and the real core
lens. Metadata responses are explicitly mocked on an otherwise ordinary ERC-20;
this models interface availability/changes without modifying transfer behavior.

The cases cover canonical empty versus legacy empty encoding, factory UTF-8
byte limits, preservation and caching of Unicode labels, missing decimals,
live-versus-cached decimals, and a failed metadata read in a mixed market batch.
The last case also executes a deposit and complete paid withdrawal while the
underlying name read reverts, then restores metadata and checks batch recovery.

Run those historical assertions at that revision. The candidate updates them
to verify the remediated behavior and adds parser and gas-bound tests.
All seven baseline characterizations passed; they asserted the original
limitations and were not evidence of remediation.

## Implemented candidate

The strict shared decoder accepts canonical 64-byte empty strings while still
rejecting wrong offsets, missing declared data and overflowing lengths. Both
real factories can now create a market whose underlying name or symbol is
empty; the caller's normal prefix remains in the market's cached label.

The lens queries names and symbols independently with bounded gas and response
sizes, returning empty text for failed or malformed cosmetic reads. The
optional mock-marker probe is bounded as well. Decimals and required market
accounting remain strict. See the
[lens integration contract](../integrations/lenses.md#token-labels-and-denominations)
for limits, fallback meanings and client obligations. There is no new
availability flag: valid empty and unavailable labels share the existing empty
string representation. Labels are not silently truncated or used as identity.

Run focused regressions with:

```sh
forge test --match-path 'test/{libraries/StringQuery,lens/TokenMetadataReview}.t.sol' -vv
```

The candidate passed the 928-test full protocol suite with Solidity 0.8.25 and
the unchanged Foundry profile. Final focused runs passed all 25 metadata/parser
tests, including 1,000 dynamic-string cases and an additional 1,000 arbitrary
response cases checking bounded results and preservation of later reads.
Production Solidity was unchanged between the full and final focused runs.
The tests cover both factories, core/aggregation/facade propagation, mixed
market availability, malformed data, independent fields, call-gas exhaustion,
complete mock markers, strict decimals, label limits and Unicode preservation.
They do not establish support for arbitrary transfer callbacks or unsupported
transfer accounting, and do not verify deployed contracts.

Deployment-profile bytecode agrees with the default profile:

| Contract | Baseline bytes | Candidate bytes | Change |
| --- | --- | --- | --- |
| Standard market | 23,998 | 23,998 | 0; runtime bytes identical |
| Revolving market | 24,554 | 24,554 | 0; runtime bytes identical |
| Core lens | 21,376 | 21,431 | +55 |
| Aggregation lens | 22,251 | 22,306 | +55 |
| Standard factory | 16,576 | 16,576 | 0; decoder behavior changed |
| Revolving factory | 17,126 | 17,126 | 0; decoder behavior changed |

The live lens and facade runtimes are also identical to baseline. All eight
contracts retain their baseline ABIs. These are measurements of this source
and its existing compiler settings, not a claim about other optimizer profiles
or deployed code. Adoption requires new factories for empty-string deployment
support and new core/aggregation lens helpers for cosmetic read fallback;
already-deployed contracts do not gain the behavior from a source update.

The dedicated `MarketLensDeploymentTest` passed with
`--code-size-limit 24576`, deploying all four lens contracts and both real
market families. The larger metadata integration test harness itself exceeds
EIP-170; it runs under the normal test profile and is not a deployable protocol
contract. A combined strict-limit run rejected that harness's constructor;
the parser tests and dedicated deployment test passed under the same limit.
The final runs separated that harness from the real-limit deployment check.
Formatting and `git diff --check` passed.

## Selection and deferred alternatives

1. **Canonical empty strings: implemented.** The dynamic minimum is 64 bytes;
   the remaining offset, length, padding and overflow checks are retained.
2. **Cosmetic lens metadata: implemented.** The selected empty fallback
   preserves the existing tuple. A future availability flag or partial-result
   API remains an alternative; merely catching a whole market response would
   still discard that market's readable accounting data.
3. **Keep denominations explicit.** Missing decimals should remain a clear
   unsupported case unless a deliberate deployment API accepts an explicit
   denomination. For existing markets, expose cached denomination separately
   from current token metadata and flag conflicts. An underlying decimals
   change can represent a real token unit change, so silently substituting
   cached decimals is not a general solution.
4. **Retain packing or provide deliberate short labels.** The 63-byte limit
   is a market representation choice. Optional full name/symbol overrides at
   creation could accommodate long or unavailable underlying labels without
   enlarging the market's immutable representation. That would require a
   reviewed factory ABI and consumer update. Do not silently truncate UTF-8.

The latter two policy choices are deferred. This candidate does not adopt the
withdrawal-counter or rounding experiments merely because they are its source
base. Its metadata patch must be integrated into the selected release source.

## Existing fixes and history

F-05's factory/lens disagreement about legacy `bytes32` metadata is already
fixed in the baseline V2.5 candidate. The factory's strict decoder and the new
bounded cosmetic lens decoder both understand that legacy representation.
The associated malformed-response and high-bit final-byte corrections are
also present. They should not be reported as still-unfixed metadata cases.

Explicit source comparisons show the same rejection of 64-byte empty dynamic
strings at tags `v2.0.0` and `v2.1.0`. Those tags' lenses use typed dynamic-string
reads instead of the candidate's shared decoder. This is a source comparison;
it is not a new verification of deployed bytecode.

The SDK at `e64e7668691c0e92ff90bb4d748c71a4556c5ee0` constructs separate
market and underlying token objects from lens metadata and uses underlying
decimals for many amount conversions. Its normalized-market token-identity
guard rejects mismatched denominations on paths using that guard; it is not a
blanket rejection at market construction. Empty labels already fit the SDK's
token-construction types; the lens ABI is unchanged by this metadata patch.
SDK/app display handling must treat an empty label as unavailable or empty,
with an address fallback. No consumer implementation has changed here. The
candidate adds no events or storage fields requiring a subgraph schema change;
indexed metadata policy and client decoding/rendering remain follow-up work.
