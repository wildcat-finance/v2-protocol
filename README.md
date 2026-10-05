# Wildcat Protocol

Wildcat Protocol V2.5 provides undercollateralized credit markets with rebasing
lender balances, batched withdrawals, and configurable access and term hooks.
This repository contains its Solidity contracts, tests, and deployment tooling.

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
forge build
forge test
```

[`foundry.toml`](./foundry.toml) pins the compiler configuration.
[`TESTS.md`](./TESTS.md) covers reproducible runs, coverage, and deployment-tooling
tests.

For deployment tooling and linting, follow the
[JavaScript setup](./CONTRIBUTING.md#javascript-toolchain).

## Documentation

- [Technical documentation](./docs/README.md)
- [Release notes and compatibility](./docs/releases/README.md)
- [Deployment tooling](./docs/operations/deployment.md) and
  [deployment records](./deployments/)
- [External security reviews](./audits/README.md)
- [Security reporting](./SECURITY.md)
- [Contributing and source style](./CONTRIBUTING.md)
- [License](./LICENSE.md)
