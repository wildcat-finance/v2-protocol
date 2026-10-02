# Wildcat Protocol

Smart contracts, tests, and deployment tooling for Wildcat Protocol V2.5.
Markets provide undercollateralized credit with rebasing lender balances,
batched withdrawals, and configurable access and term hooks.

[Whitepaper v2.0](https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v2.0.pdf)
· [The Wildcat Manifesto](https://medium.com/@wildcatprotocol/the-wildcat-manifesto-db23d4b9484d)

Product and user documentation lives at
[docs.wildcat.finance](https://docs.wildcat.finance/).

## Build and test

[Foundry](https://book.getfoundry.sh/getting-started/installation) `1.8.3` is
required. [`.foundry-version`](./.foundry-version) supplies the version for CI
and the Sepolia wrapper-factory installer.

The full test suite also needs Python 3 and a C compiler (`cc`) for its offline
storage-codec reference.

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
- [Solidity source layout](./STYLE_GUIDE.md) and [comment voice](./STYLE_VOICE.md)
- [License](./LICENSE.md)

These docs describe the source in this checkout, not the state of live
deployments. See [V2.5](./docs/releases/v2.5.md) for source and compatibility
boundaries, and [`deployments/`](./deployments/) for recorded deployment facts.
Previous releases and their docs live in Git tags.
