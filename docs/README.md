# Technical Documentation

This directory describes the intended supported behavior of the contracts on
the active release branch. It is written for auditors, integrators, and
contributors.

Documents on a release branch apply to the source on that branch. Previous
release source and documentation are preserved in Git tags.

## Authority

- [`src/`](../src/) and [`test/`](../test/) provide implementation evidence.
- [`TESTS.md`](../TESTS.md) defines the canonical test commands and suite policy.
- [`deployments/`](../deployments/) owns machine-readable deployment facts.
- [`audits/`](../audits/README.md) indexes completed external security reviews.

If documentation and source disagree, report the discrepancy. Do not infer
deployment status, review coverage, or remediation status from source ancestry
alone.

## Protocol

- [Core behavior](./protocol/markets.md) covers market configuration, lifecycle,
  borrowing, repayment, and withdrawals.
- [Scaling](./protocol/scaling-and-rounding.md) explains normalized accounting, scaled balances,
  and rounding.
- [Borrower identity and transfers](./protocol/borrower-identity.md)
  covers principals, operational accounts, registry state, and authority moves.
- [Terminology](./Terminology.md) defines protocol-specific terms.

## Integrations

- [Hooks](./hooks/How%20Hooks%20Work.md) covers callback dispatch and `extraData`;
  see [access control](./hooks/templates/Access%20Control%20Hooks.md) and
  [periodic term hooks](./hooks/templates/Periodic%20Term%20Hooks.md) for template
  behavior.
- [Role providers](./Role%20Provider%20Inventory.md) covers credential-provider
  capabilities and construction paths.
- [ERC-4626 wrapper](./EIP-4626.md) covers wrapping, redemption, rounding,
  sanctions, and integration constraints.
- [Event model](./v2.5%20Event%20Model.md) covers ABI families, event ordering,
  deployment discovery, and indexer replay.

## Releases and Operations

- [Changelog](./CHANGELOG.md) describes protocol release boundaries.
- [Deployment](./deployment.md) describes the deployment inventory and ceremony
  model. Machine-readable state in [`deployments/`](../deployments/) remains the
  authority for deployment facts.

Historical checklists, completed ceremony records, generated tool output, and
internal audit-preparation papers are not protocol specifications.
