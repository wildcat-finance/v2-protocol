# M1 baseline: existing hook templates

- Source: `4ab8dbf9821d1ce9f9157cb1659d0b36f59fd62c` on `feat/tranching_support`.
- Captured: 2026-09-22 UTC.
- Execution status: identity established; verification and measurements follow
  in M1-02/M1-03. See the [tracker](hook-refactor-m1-tracker.md).
- Raw evidence root, relative to the checkout:
  `audits/hook-refactor/m1/2026-09-22/` (ignored).

## Identity and reproduction settings

The initial checkout has no tracked modifications. The untracked composition
documents and two user-supplied reference documents do not affect compilation.
Subsequent documentation commits retain this production/test source baseline.
The reference PDF and lifecycle sketch are excluded from milestone commits.

| Input | Recorded value |
| --- | --- |
| Git tree | `834fced977e552562beec8325670096389a5de58` |
| Foundry pin / actual Forge | `v1.8.3` / `1.8.3`, commit `cae51ad458f6abb64852b7709eb784352429825d` |
| Solidity | `0.8.25+commit.b61c2a91.Linux.g++` |
| EVM / optimizer | Cancun; via IR; optimizer enabled, 44 runs |
| Metadata | Bytecode hash `none`; CBOR metadata disabled |
| Default / deploy initial timestamp | `1`; suites may explicitly warp |
| Default fuzz / invariant settings | 1,000 fuzz runs; 2,000 invariant runs, depth 30; no configured seed |
| Fixed command | Timestamp `1724284800`, fuzz seed `0x5eed` |
| Deploy profile differences | `deploy-out`, `deploy-cache`, additional `ir` / `irOptimized` output files; same compiler/EVM/optimization settings |
| Node / Yarn | `v24.21.0` / `1.22.22` |

All four top-level submodules match their recorded revisions and have clean
working trees:

| Submodule | Revision |
| --- | --- |
| `lib/forge-std` | `b6a506db2262cad5ff982a87789ee6d1558ec861` |
| `lib/openzeppelin-contracts` | `fd81a96f01cc42ef1c9a5399364968d0e07e9e90` |
| `lib/solady` | `2ba1cc1eaa3bffd5c093d94f76ef1b87b167ff3c` |
| `lib/solmate` | `1b3adf677e7e383cc684b5d5bd441da86bf4bf1c` |

`inputs.sha256.json` records 1,166 materialized tracked files under `src`,
`test`, `script`, `scripts`, and `lib`, plus the build/package pins and lockfile.
Four nested dependency gitlinks are not materialized as files and are listed
separately in `identity.json`; they are not compiler inputs for this suite.
Compiler artifact metadata will identify the sources actually used by each
template. Configuration captures come from `forge config --json` with the
corresponding `FOUNDRY_PROFILE`.

| Evidence / executable | SHA-256 |
| --- | --- |
| `identity.json` | `0f3a6aa6164f840aa33d979652eacfc013e855f08f0f51553c16d935761eae31` |
| `inputs.sha256.json` | `52b23073b83e3f1b81d3065fd0aa465ec17ad20648562d3036bf7c44d53aa35c` |
| `config-default.json` | `43acd28461317a1f75c1f064dab1c0d6890b3805e3146056b1fe30245cdfcbff` |
| `config-deploy.json` | `a771cfc793c764faec63cf0f7aa70b6f18d070b7b0ce58a1130e678e105596eb` |
| Forge executable | `deb412a722e873e11e60051deb9d403b584a2d7e49d8b9ee68441edfea215e9c` |
| solc executable | `c42aada7a52057ddbed93ec011235e256c564c440b68dbaac5ae482babbb3d6d` |

Yarn was absent from the shell. Corepack supplied Yarn 1.22.22 through an
ignored local shim; no package or toolchain configuration was changed:

```sh
corepack enable --install-directory audits/hook-refactor/m1/2026-09-22/bin yarn
export PATH="$PWD/audits/hook-refactor/m1/2026-09-22/bin:$PATH"
export COREPACK_ENABLE_AUTO_PIN=0
```

## Prior evidence disposition

| Existing evidence | Disposition | Reason |
| --- | --- | --- |
| `/tmp/v2-protocol-foundry-1.8.3-{canonical,fixed,deploy}.log` | Historical | Passing output is inspectable, but the logs do not bind the run to an input manifest, tool binary, and effective settings. |
| `/tmp/v2-protocol-foundry-1.8.3-{default,deploy}-sizes.log` | Historical | Size tables lack the same run identity and do not measure the template storage deployment boundary. |
| Existing `out/` and `deploy-out/` artifacts | Build cache, subject to fresh Forge verification | Metadata identifies compiler/source hashes; cache presence alone is not test evidence. |
| Earlier build-only scratch artifacts | Not adopted | Not canonical test receipts; no reason to revive the canceled tooling task. |
| Prior per-operation hook gas receipts | Unavailable | No qualifying receipt found. M1-03 will establish the measurements. |

The historical logs' exact hashes are recorded in `identity.json`. Their
existence avoids ambiguity about what was inspected; no historical passing
count is claimed as a new M1 result. M1-02 will run the three commands in
[`TESTS.md`](../../TESTS.md), export compiler ABIs, and inventory compatibility.
M1-03 will capture creation/runtime sizes and representative operation gas.
