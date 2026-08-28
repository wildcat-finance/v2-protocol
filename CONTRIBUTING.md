# Contributions

This repository is public so people can inspect the protocol, build
integrations, review the code, and reuse it under its license.

Contributions are welcome. Most development will still be maintainer-led, and
the review bar for core contracts is high. They are deployed immutably and
handle lender funds.

Talk through a substantial change with a maintainer before investing heavily
in it. Keep changes narrow, test them properly, and follow the repository's
existing design and security constraints.

Report suspected vulnerabilities privately as described in
[`SECURITY.md`](./SECURITY.md), not through a public issue or pull request.

## Things to check before changing contracts

- Some type definitions are accessed directly from assembly. If you change a
  type, check every assembly use of its memory layout.

- Many events and errors use custom emitter functions. Those functions depend
  on the parameter order in the definition, so reordering parameters is a
  behavioral change.

Product and user documentation is maintained at
[docs.wildcat.finance](https://docs.wildcat.finance/).
