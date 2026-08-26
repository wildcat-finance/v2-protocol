# Security

Report suspected vulnerabilities privately to
[`operations@wildcat.finance`](mailto:operations@wildcat.finance). Do not open
a public GitHub issue.

Include, where available:

- the affected contract, deployment, network, and source revision;
- the expected and observed behavior;
- the security impact and required attacker capabilities; and
- a minimal reproduction or transaction trace.

## Credit Risk Boundary

Wildcat markets extend undercollateralized credit. Borrower default, or a
borrower acting adversely within authority explicitly granted by the protocol,
is credit risk and is not by itself a protocol vulnerability.

A path that exceeds documented authority, violates protocol accounting, or
changes another participant's rights outside the documented state model may be
a security issue and should be reported.

Completed external review records are indexed in [`audits/`](./audits/README.md).
