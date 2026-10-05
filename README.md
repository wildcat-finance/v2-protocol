# Wildcat Protocol V2.5 audit package

Wildcat Protocol V2.5 provides undercollateralized credit markets with rebasing
lender balances, batched withdrawals, and configurable access and term hooks.
This branch contains the contracts, tests, and technical documentation for a
focused V2.5 security review.

Start with the [audit scope](./docs/releases/v2.5-audit-scope.md). This package
derives from release commit `bfe1412141f263ba6b056c60c3f4654a461598dd`.
Role-provider scope is limited to AccessList, its factory, and the shared
managed-provider base. Retained protocol source is unchanged from that commit.

Deployment ceremonies, UI code, historical deployment artifacts, and excluded
provider implementations remain in the
[release repository](https://github.com/wildcat-finance/v2-protocol/tree/bfe1412141f263ba6b056c60c3f4654a461598dd).
This branch is an audit snapshot; its pruning changes should not be merged
back into the release branch.

[Whitepaper v2.0](https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v2.0.pdf)
· [The Wildcat Manifesto](https://medium.com/@wildcatprotocol/the-wildcat-manifesto-db23d4b9484d)

Product and user documentation lives at
[docs.wildcat.finance](https://docs.wildcat.finance/).

## Build and test

Install [Foundry](https://book.getfoundry.sh/getting-started/installation) using
the version pinned in [`.foundry-version`](./.foundry-version). The full test
suite also needs Python 3 and a C compiler (`cc`).

```sh
foundryup --install "$(cat .foundry-version)"
git submodule update --init
forge test --block-timestamp 1724284800 --fuzz-seed 0x5eed --summary
```

[`foundry.toml`](./foundry.toml) pins the compiler configuration.
[`TESTS.md`](./TESTS.md) covers reproducible runs, adding tests, and coverage
limits. The canonical suite needs no RPC endpoint, wallet, or JavaScript
dependency installation.

For optional linting and inventory generation, follow the
[JavaScript setup](./CONTRIBUTING.md#javascript-toolchain).

## Documentation

- [Technical documentation](./docs/README.md)
- [Audit scope and verification](./docs/releases/v2.5-audit-scope.md)
- [Release notes and compatibility](./docs/releases/README.md)
- [External security reviews](./audits/README.md)
- [Security reporting](./SECURITY.md)
- [Contributing and source style](./CONTRIBUTING.md)
- [License](./LICENSE.md)
