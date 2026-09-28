# Wildcat Protocol

Smart contracts, tests, and deployment tooling for Wildcat Protocol.

[Whitepaper v2.0](https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v2.0.pdf)
· [The Wildcat Manifesto](https://medium.com/@wildcatprotocol/the-wildcat-manifesto-db23d4b9484d)

Product and user documentation lives at
[docs.wildcat.finance](https://docs.wildcat.finance/).

## Build and test

[Foundry](https://book.getfoundry.sh/getting-started/installation) `1.8.3` is
required. [`.foundry-version`](./.foundry-version) supplies the version for CI
and the Sepolia wrapper-factory installer.

```sh
foundryup --install "$(cat .foundry-version)"
git submodule update --init
forge build
forge test
```

[`foundry.toml`](./foundry.toml) pins Solidity `0.8.25`, the Cancun EVM target,
via-IR, optimizer runs `1`, and the exact Yul optimizer sequence. These settings
keep both market runtimes within the deployment size limit and apply to normal
builds, tests, and the `deploy` profile. [`TESTS.md`](./TESTS.md) covers the full
test setup.

See [deployment](./docs/operations/deployment.md) for creation-code storage,
artifact verification, and release ceremonies.

## Start here

- [Technical documentation](./docs/README.md)
- [External security reviews](./audits/README.md)
- [Security reporting](./SECURITY.md)
- [Contribution policy](./CONTRIBUTING.md)
- [License](./LICENSE.md)

Previous releases live in Git tags. Documentation on a release branch describes
the source on that branch.
