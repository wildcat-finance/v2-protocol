# Token metadata compatibility review

Source scope: `7b7db0e7517401da002239470a8aff3802e3c646`, reviewed on
2026-09-29. This is local source characterization, not deployment evidence.
The review branch changes tests and documentation only. The original CAF-15,
CertiK finding 13 and WKI-013 dispositions assumed asset-listing review would
exclude unusual metadata. Arbitrary ERC-20 assets have always been permitted;
there is no Foundation metadata allowlist protecting these paths.

ERC-20 makes `name`, `symbol` and `decimals` optional. A token's conformity to
the [standard](https://eips.ethereum.org/EIPS/eip-20) therefore does not prove
compatibility with the factory's mandatory metadata reads. Rebasing,
fee-on-transfer and dishonest balance/transfer accounting remain unsupported;
this review does not propose accommodating those behaviors.

## Current behavior

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

## Local verification

`test/lens/TokenMetadataReview.t.sol` characterizes the unchanged source using
real standard and revolving factories, real open-term hooks and the real core
lens. Metadata responses are explicitly mocked on an otherwise ordinary ERC-20;
this models interface availability/changes without modifying transfer behavior.

The cases cover canonical empty versus legacy empty encoding, factory UTF-8
byte limits, preservation and caching of Unicode labels, missing decimals,
live-versus-cached decimals, and a failed metadata read in a mixed market batch.
The last case also executes a deposit and complete paid withdrawal while the
underlying name read reverts, then restores metadata and checks batch recovery.

Run the focused characterization with:

```sh
forge test --match-path test/lens/TokenMetadataReview.t.sol -vv
```

All seven focused tests passed with Solidity 0.8.25 and the unchanged Foundry
profile. Formatting and `git diff --check` also passed. These tests assert
current limitations; passing does not mean they are fixed.
They do not establish behavior for arbitrary transfer callbacks, unsupported
assets, every hook configuration or deployed contracts.

## Candidate improvements

1. **Accept canonical empty strings in the shared decoder.** The dynamic
   minimum should be 64 bytes; retain offset, length, padding and overflow
   checks. Empty text does not require additional market storage. Malformed
   64-byte responses declaring nonzero length must still fail. This is a
   narrow compatibility correction worth considering independently.
2. **Make cosmetic lens metadata best effort.** Missing/reverting names and
   symbols should not need to invalidate otherwise-readable market data.
   Use bounded calls/return sizes and explicit availability information or a
   documented fallback. Keep genuine market-state failures visible. This is
   a lens/consumer contract change; it does not need code added to the market.
   A partial-result API is another option, but merely catching a whole market
   response still discards that market's readable accounting data.
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

No remediation or ABI change has been selected or implemented here. Market
runtime-size impact has not been measured for any proposed change.

## Existing fixes and history

F-05's factory/lens disagreement about legacy `bytes32` metadata is already
fixed in the reviewed V2.5 candidate: both use `LibERC20` and the shared decoder.
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
blanket rejection at market construction. A lens fallback or availability
change therefore requires deliberate SDK handling. App/subgraph adaptations
have not been implemented or fully assessed in this focused review.
