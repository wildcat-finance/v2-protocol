# E09: compressed initcode in one storage contract

Source parent: `714f4c2` (E08). E10 only records compiler experiments.

Hypothesis: preserve the complete creation code and its deployment context, but
compress its stored representation. Put the decoder and payload in the same
storage contract. This can remove the creation-storage bottleneck without
splitting storage or extracting any live market logic.

## Format and deployment

`LibCompressedInitCode` uses the already vendored Solady FastLZ codec. Each
storage contract contains the reader runtime, one compressed payload and a
two-byte compressed-length footer. The reader decompresses its own code and
returns the original creation bytes on STATICCALL. `CompressedInitCodeReader`
is a runtime blueprint; it is not separately deployed. There is no mutable
storage, external decoder or delegatecall.

`LibStoredInitCode.getInitCode` recognizes the existing leading-STOP format and
still copies it directly. An executable store instead returns creation bytes
through STATICCALL. CREATE and CREATE2 execute those bytes from the factory,
with the existing constructor arguments, sender, value and original initcode
hash. Both factories use the same reader for hook instance deployment.

The encoder rejects creation payloads above 49,152 bytes and stored runtimes
above 24,576 bytes. The reader caps returned creation bytes at 49,152; CREATE
also applies its own limit after constructor arguments are appended. An empty
address, failed reader call or oversized response returns DeploymentFailed.
These invalid-store checks are deliberate new behavior, not an ABI change.

The assembly helpers use owned buffers or temporary memory above the free
memory pointer. CREATE2 hashing now uses that temporary area rather than
borrowing the free-memory-pointer slot. The helpers can therefore carry valid
memory-safe annotations, including when inlined into test callers.

## Measurements

This changes the deployment format, not the market's creation or runtime bytes.
It adds **100 bytes** to each factory at runs 44, or **101 bytes** with E05.
Factory ABIs and storage layouts are unchanged. All other measured production
and composition targets are byte-for-byte unaffected by E09.
[Factory measurements](./results/e09.json).

The combination with E11 and E05 was deployed with the actual 24,576-byte limit:

| Payload | Stored contract runtime | Storage headroom |
| --- | ---: | ---: |
| Standard market | 17,769 | 6,807 |
| Revolving market | 18,248 | 6,328 |
| Open hook | 13,156 | 11,420 |
| Fixed hook | 14,079 | 10,497 |
| Periodic hook | 16,532 | 8,044 |

These sizes include the entire reader and footer. The six market/hook
combinations reuse exactly five stores. Tests check the creation nonce changes
by exactly one per payload and compare every decoded payload byte for byte.

## Validation and adoption boundary

The initial codec qualification passed 34 tests at the real code-size limit:
the existing raw-storage and bounded-call tests, plus nine compressed-storage
tests. Coverage includes round trips, boundary lengths, incompressible data,
the storage and creation limits, STATICCALL restrictions, constructor arguments
from memory/calldata, ETH value, factory context and duplicate CREATE2 salts.

The final combination also passes a real-limit factory deployment test covering
all six production market/hook combinations, followed by deposit, borrow,
repay and on-time automatic closure. Its seven production artifacts exactly
match the independent compiler measurements. External receipts are
`e09-codec-tests/`, `e09-e11-deployment-noF/` and `e09-e11-final-{default,noF}/`.

The final draft with E11 passes **375 focused tests at canonical runs 44**,
including the complete codec suite (`e09-e11-all-default/`). The compiler
candidate's broad qualification is recorded with E12. Earlier broad
no-F attempts failed to compile test code; those are failed qualification
attempts, not passing results. No raw-storage gate has been weakened.

Decision: retain as an optional deployment-format candidate. It solves storage
capacity but cannot fix an oversized live market runtime. E05 plus E11 is the
currently demonstrated runtime-fitting combination. Canonical runs 44 still
leaves the revolving runtime oversized.

The original E09 checkpoint left deployment tooling on raw storage.
[E15](./E15-compression-integrity.md) adds preparation and verification of
compressed artifacts to `LibDeployment`, `DeployScriptBase`, and the V2.5 plan
scripts, with CLI/UI hash predicates. It also checks decoded market code before
its constructor runs. A release review must still include the codec and
executable-store trust boundary; registered storage contracts remain controlled
deployment inputs. The raw format remains available, so hooks which already
fit need not be compressed.
