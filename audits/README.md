# External security reviews

This index covers completed external reviews of this repository. Each review
only applies to its stated source scope. It does not cover later releases or
deployments by implication.

This index does not include internal reviews, automated scans, working papers,
or audit preparation material.

## V2

- **alpeh_v:** [Wildcat V2 Security Review](https://hackmd.io/@geistermeister/BJk4Ekt90),
  conducted from 2024-08-12 to 2024-08-23.

  - Starting source: [`f30ea6d`](https://github.com/wildcat-finance/v2-protocol/commit/f30ea6d)
  - Final reviewed head: not recorded in the report
  - Findings: 2 Medium, 2 Low, and 2 notes

- **Code4rena:** [The Wildcat Protocol Findings & Analysis Report](https://code4rena.com/reports/2024-08-wildcat),
  covering the contest held from 2024-08-31 to 2024-09-18.
  - Reviewed source: the contest
    [`src/` tree](https://github.com/code-423n4/2024-08-wildcat/tree/7c5d8389b2a368ce6c4fc79e50c39eac3516ea5e)
    matches [`v2-protocol@5a19f68`](https://github.com/wildcat-finance/v2-protocol/commit/5a19f68)
  - Findings: 1 High, 8 Medium, and 22 Low or non-critical

## Remediation provenance

The Code4rena report includes sponsor responses and linked fixes for individual
findings. We have not yet reconstructed a complete finding-to-fix and retest
map for either engagement. Source ancestry alone is not evidence that a finding
was retested.
