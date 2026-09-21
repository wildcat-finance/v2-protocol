# Security

If you find a suspected vulnerability, report it privately to
[`operations@wildcat.finance`](mailto:operations@wildcat.finance). Please don't
open a public GitHub issue.

Send whatever you have. Useful details include:

- the affected contract, deployment, network, and source revision;
- the expected and observed behavior;
- the security impact and required attacker capabilities; and
- a minimal reproduction or transaction trace.

## Credit risk boundary

Wildcat markets extend undercollateralized credit. A borrower defaulting, or
acting adversely within authority the protocol explicitly grants them, is
credit risk. It is not a protocol vulnerability by itself.

Please report any path that exceeds documented authority, breaks protocol
accounting, or changes another participant's rights outside the documented
state model.

Completed external reviews are listed in [`audits/`](./audits/README.md).
