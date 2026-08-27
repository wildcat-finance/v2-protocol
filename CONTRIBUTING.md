# Contributions

This repository is public for transparency, integration work, independent
review, and reuse under its license. Contributions are welcome, although most
development is expected to remain maintainer-led.

Core contracts are deployed immutably and handle lender funds, so substantive
changes carry a high review burden. Discuss the approach with a maintainer
before investing heavily. Changes should be narrowly scoped, well tested, and
consistent with the repository's design and security requirements.

Report suspected vulnerabilities privately as described in
[`SECURITY.md`](./SECURITY.md), not through a public issue or pull request.

## Repository-specific Cautions

Type definitions may be accessed directly from assembly. When changing a type,
check every assembly use of its memory layout.

Many events and errors use custom emitter functions whose behavior depends on
the order of parameters in their definitions. Treat parameter reordering as a
behavioral change.

Product and user documentation is maintained separately at
[docs.wildcat.finance](https://docs.wildcat.finance/).
