# External Security Reviews

This index covers completed external reviews of source in this repository. A
review applies only to its stated source scope; it does not cover later releases
or deployments by implication.

Internal reviews, automated scans, pre-audit working papers, and audit
preparation artifacts are not external audits and are not indexed here.

## V2

- **alpeh_v:** [Wildcat V2 Security Review](https://hackmd.io/@geistermeister/BJk4Ekt90),
  conducted 2024-08-12 to 2024-08-23. The review began with protocol source at
  [`f30ea6d`](https://github.com/wildcat-finance/v2-protocol/commit/f30ea6d);
  the final reviewed head is not recorded in the report. The report records 2
  Medium findings, 2 Low findings, and 2 notes.

- **Code4rena:** [The Wildcat Protocol Findings & Analysis Report](https://code4rena.com/reports/2024-08-wildcat),
  covering the 2024-08-31 to 2024-09-18 contest. The
  [contest source](https://github.com/code-423n4/2024-08-wildcat/tree/7c5d8389b2a368ce6c4fc79e50c39eac3516ea5e)
  `src/` tree matches
  [`v2-protocol@5a19f68`](https://github.com/wildcat-finance/v2-protocol/commit/5a19f68).
  The report records 1 High finding, 8 Medium findings, and 22 Low or
  non-critical findings.

## Remediation Provenance

The Code4rena report includes sponsor responses and linked fixes for individual
findings. A complete repository-level finding-to-fix and retest map has not yet
been reconstructed for either engagement. Do not infer retest status from
source ancestry alone.
