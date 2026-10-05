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

## JavaScript toolchain

Use Node `24.21.0`, Yarn Classic `1.22.22` for the protocol root, and npm
`11.19.0` for `deploy-ui`. [`.node-version`](./.node-version) selects Node for
compatible version managers. Each package manifest declares its Node and package
manager versions; the UI also rejects incompatible engines during installation.

Use Corepack to select the root Yarn pin without a global Yarn installation.
Verify the installed tools, then install from the existing lockfiles:

```sh
node --version
corepack yarn --version
(cd deploy-ui && npm --version)
corepack yarn install --frozen-lockfile --ignore-scripts
(cd deploy-ui && npm ci --ignore-scripts)
```

Keep `yarn.lock` at the root and `package-lock.json` in `deploy-ui`. Do not swap
package managers or regenerate a lockfile as part of routine setup.
The `yarn` commands elsewhere in these docs can also be run as `corepack yarn`.

The root `.yarnrc` and UI `.npmrc` disable automatic lifecycle scripts by default.
Explicit test and build commands still run. Do not enable dependency scripts to
work around an install failure without reviewing the package and its scripts.

## Source style

Follow [`STYLE_GUIDE.md`](./STYLE_GUIDE.md) for Solidity formatting, function
ordering, file headers, and comment layout. Follow
[`STYLE_VOICE.md`](./STYLE_VOICE.md) when writing or revising comment prose.
The guides include the reference file and the checks needed to preserve
behavior and documentation coverage.

Use Forge for Solidity formatting. `yarn lint:check` checks formatting with Forge,
then runs Solhint. `yarn lint:fix` formats with Forge, then runs Solhint. Prettier
shares the basic settings but cannot reproduce Forge's function-header layout;
if your editor uses it, finish with Forge before committing Solidity changes.

Solhint is pinned separately from the formatters. The lint commands disable its
network update check and promotional output; they do not apply Solhint autofixes.

## Things to check before changing contracts

- Some type definitions are accessed directly from assembly. If you change a
  type, check every assembly use of its memory layout.

- Many events and errors use custom emitter functions. Those functions depend
  on the parameter order in the definition, so reordering parameters is a
  behavioral change.

Product and user documentation is maintained at
[docs.wildcat.finance](https://docs.wildcat.finance/).
