# Releases

These pages describe contract changes and integration compatibility between
versions. Addresses, factory lifecycle, and transaction receipts are recorded
in [`deployments/`](../../deployments/).

Generated [contract inventories](./inventory/README.md) pin each first-party
source unit and ABI-bearing declaration to a release commit.

## v2.5.8

The initial v2.5.8 release port extends [nuke protection](../integrations/nuke-protection.md)
to approved integration contracts and derives [delinquency default](../protocol/repayment-and-default.md#grace-tracker-default)
from the decaying Grace Tracker. Wrapper deployment remains optional, and the
repayment deadline remains an independent default trigger.

The [audit snapshot at `b695926c`](https://github.com/wildcat-finance/v2-protocol/blob/b695926cd1fe2141f0b9c737a27fafccc64a4b6c/docs/releases/v2.5-audit-scope.md)
also exempts protected accounts from lender sanctions checks in the market and
canonical wrapper. The release branch adds four fixes to that snapshot. They
cover canonical wrapper share recovery (GA-1), closed-market deposit capacity
(GA-2), native market coverage for legacy quotes (GA-3), and withdrawal timing
after closure (GA-5).

## v2.5

[v2.5](./v2.5.md) adds revolving markets, repayment scheduling and default
tracking, periodic-term hooks, borrower transfers, and expanded wrapper and
lens interfaces. The release notes describe changes from v2.1 and the ABI
updates required by integrators.

## v2.1

[v2.1](./v2.1.md) adds the first canonical ERC-4626 wrapper and wrapper factory.
It does not change the v2.0 core market or hook source.

- Tag: [`v2.1.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.1.0)
- Commit: `c7be4039f8f383a9dda4e45f63331c17d63f9ed9`

## v2.0

[v2.0](./v2.0.md) is the baseline for this repository's release history.

- Tag: [`v2.0.0`](https://github.com/wildcat-finance/v2-protocol/tree/v2.0.0)
- Commit: `a70f297fbd1b1ab597e0e9a3458a2d13a34b4657`

Completed external reviews are indexed in [`audits/`](../../audits/README.md).
A later tag does not extend an earlier review's source scope.

## v2.5 review material

The [final audit manifest](https://github.com/wildcat-finance/v2-protocol/blob/b695926cd1fe2141f0b9c737a27fafccc64a4b6c/docs/releases/v2.5-audit-manifest.json)
lists the 102 source files reviewed at `b695926c`. The records below cover
earlier revisions.

- [Quote-package guide](./v2.5-audit-quote-package.md): the starting document in
  [Wildcat v2.5 Audit Quote Package.zip](<../Wildcat v2.5 Audit Quote Package.zip>),
  which bundles the quote, scope, comparison, and supporting records.
- The [October 5 audit quote](./v2.5-audit-quote.md) records the scope and terms
  for 100 files at `529f2db55d656b89db4b17ecf6685b7589d5d7dd`.
- [V2.1-to-V2.5 source comparison](./v2.1-to-v2.5-change-summary.md): retained
  code, mechanical changes, and substantive changes against the V2.1 `main`
  snapshot, with a [per-file comparison record](./v2.1-to-v2.5-comparison.json).
- [Earlier audit scope](./v2.5-audit-scope.md): the prior source freeze, subsequent
  review delta, and requirements for a new audit packet.
- [Contract inventory](./inventory/v2.5.json): the prior `7fad3de` audit source.
- [Pre-freeze verification](./v2.5-verification.md): results for an earlier
  candidate, using that candidate's compiler settings.
- [2026-10-05 test review](./test-review-2026-10-05.json): canonical test results,
  compilation timing, partial coverage, Slither compatibility, and the
  subsequent test-maintenance checks.

The release retains the provider contracts and deployment tooling excluded
from the audit package.
