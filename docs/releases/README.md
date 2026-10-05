# Releases

These pages describe contract changes and integration compatibility between
versions. Addresses, factory lifecycle, and transaction receipts are recorded
in [`deployments/`](https://github.com/wildcat-finance/v2-protocol/tree/bfe1412141f263ba6b056c60c3f4654a461598dd/deployments).

The [audit scope](./v2.5-audit-scope.md) and its file manifest define this
branch. Historical inventories remain in the release repository.

## V2.5

[V2.5](./v2.5.md) adds revolving markets, repayment scheduling and default
tracking, periodic-term hooks, borrower transfers, and expanded wrapper and
lens interfaces. The release notes describe changes from V2.1 and the ABI
updates required by integrators.

## V2.1

[V2.1](./v2.1.md) adds the first canonical ERC-4626 wrapper and wrapper factory.
It does not change the V2.0 core market or hook source.

- Tag: [`v2.1.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.1.0)
- Commit: `c7be4039f8f383a9dda4e45f63331c17d63f9ed9`

## V2.0

[V2.0](./v2.0.md) is the baseline for this repository's release history.

- Tag: [`v2.0.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.0.0)
- Commit: `a70f297fbd1b1ab597e0e9a3458a2d13a34b4657`

Completed external reviews are indexed in [`audits/`](../../audits/README.md).
A later tag does not extend an earlier review's source scope.

## V2.5 review material

- [Audit scope](./v2.5-audit-scope.md): current source identity, review boundary,
  security properties, exclusions, and test accounting.
- [Scope manifest](./v2.5-audit-manifest.json): retained source hashes, artifact
  identities, and supporting-file inventory.
- [Verification receipt](./v2.5-audit-verification.json): results for this
  pruned package, including source and artifact comparisons.
- [2026-10-05 release test review](./test-review-2026-10-05.json): historical
  full-provider-suite results and partial coverage. Its 958-test total predates
  this package's provider exclusions.

The earlier audit packet and deployment evidence are available at the
[release base](https://github.com/wildcat-finance/v2-protocol/tree/bfe1412141f263ba6b056c60c3f4654a461598dd).
Their source boundaries and measurements do not override this package's scope.
