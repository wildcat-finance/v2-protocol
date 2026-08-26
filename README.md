# Wildcat Protocol

Smart contracts, tests, and deployment tooling for the Wildcat Protocol.

[Whitepaper v2.0](https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v2.0.pdf)
· [The Wildcat Manifesto](https://medium.com/@wildcatprotocol/the-wildcat-manifesto-db23d4b9484d)

Product and user documentation is published at
[docs.wildcat.finance](https://docs.wildcat.finance/).

## Build and Test

[Foundry](https://book.getfoundry.sh/getting-started/installation) is required.

```sh
git submodule update --init
forge build
forge test
```

The repository pins Solidity `0.8.25` and the Cancun EVM target in
[`foundry.toml`](./foundry.toml). See [`TESTS.md`](./TESTS.md) for the complete
testing contract.

## Start Here

- [Technical documentation](./docs/README.md)
- [External security reviews](./audits/README.md)
- [Security reporting](./SECURITY.md)
- [Contribution policy](./CONTRIBUTING.md)
- [License](./LICENSE.md)

Previous releases are preserved in Git tags. Documentation on the active
release branch describes that release's supported source.
