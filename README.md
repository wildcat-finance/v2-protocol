# Wildcat Protocol

Smart contracts, tests, and deployment tooling for Wildcat Protocol.

[Whitepaper v2.0](https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v2.0.pdf)
· [The Wildcat Manifesto](https://medium.com/@wildcatprotocol/the-wildcat-manifesto-db23d4b9484d)

Product and user documentation lives at
[docs.wildcat.finance](https://docs.wildcat.finance/).

## Build and test

[Foundry](https://book.getfoundry.sh/getting-started/installation) is required.

```sh
git submodule update --init
forge build
forge test
```

[`foundry.toml`](./foundry.toml) pins Solidity `0.8.25` and the Cancun EVM
target. [`TESTS.md`](./TESTS.md) covers the full test setup.

## Start here

- [Technical documentation](./docs/README.md)
- [External security reviews](./audits/README.md)
- [Security reporting](./SECURITY.md)
- [Contribution policy](./CONTRIBUTING.md)
- [License](./LICENSE.md)

Previous releases live in Git tags. Documentation on a release branch describes
the source on that branch.
