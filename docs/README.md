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

- [Markets](./protocol/markets.md) covers market configuration, implementations,
  and borrower authority.
- [Accounting](./protocol/accounting.md) and
  [scaling](./protocol/scaling-and-rounding.md) cover collateral obligations,
  interest, fees, balances, and rounding.
- [Withdrawals](./protocol/withdrawals.md) covers batch ownership, payment
  priority, and execution.
- [Borrower identity and transfers](./protocol/borrower-identity.md)
  covers principals, operational accounts, registry state, and authority moves.
- [Glossary](./protocol/glossary.md) defines protocol-specific terms.

## Integrations

- [Hooks](./integrations/hooks.md) covers callback dispatch and `extraData`;
  see [access control](./integrations/access-control.md) and
  [periodic term hooks](./integrations/periodic-term-hooks.md) for template
  behavior.
- [Role providers](./integrations/role-providers.md) covers credential-provider
  capabilities and construction paths.
- [ERC-4626 wrapper](./integrations/erc-4626-wrapper.md) covers wrapping, redemption, rounding,
  sanctions, and integration constraints.
- [Event model](./integrations/events.md) covers ABI families, event ordering,
  deployment discovery, and indexer replay.

## Releases and Operations

- [Changelog](./CHANGELOG.md) describes protocol release boundaries.
- [Deployment](./operations/deployment.md) describes the deployment inventory,
  plan, ceremony, verification, and handoff model. Machine-readable state in
  [`deployments/`](../deployments/) remains the authority for deployment facts.

Historical checklists, completed ceremony records, generated tool output, and
internal audit-preparation papers are not protocol specifications.
