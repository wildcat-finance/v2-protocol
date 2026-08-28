# Technical documentation

These docs describe the intended behavior of the contracts on the active
release branch. They are written for auditors, integrators, and contributors.

The docs on a release branch apply to the source on that branch. Previous
releases and their documentation live in Git tags.

## What is authoritative

- [`src/`](../src/) and [`test/`](../test/) provide implementation evidence.
- [`TESTS.md`](../TESTS.md) defines the canonical test commands and suite policy.
- [`deployments/`](../deployments/) owns machine-readable deployment facts.
- [`audits/`](../audits/README.md) indexes completed external security reviews.

If the docs and source disagree, report it. Don't infer deployment status,
review coverage, or remediation status from source ancestry alone.

## Protocol

- [Markets](./protocol/markets.md): configuration, implementations, and borrower
  authority
- [Accounting](./protocol/accounting.md) and
  [scaling](./protocol/scaling-and-rounding.md): collateral obligations,
  interest, fees, balances, and rounding
- [Withdrawals](./protocol/withdrawals.md): batch ownership, payment priority,
  and execution
- [Borrower identity and transfers](./protocol/borrower-identity.md): principals,
  operational accounts, registry state, and authority transfers
- [Glossary](./protocol/glossary.md): protocol-specific terms

## Integrations

- [Hooks](./integrations/hooks.md): callback dispatch and `extraData`; see
  [access control](./integrations/access-control.md),
  [fixed term hooks](./integrations/fixed-term-hooks.md), and
  [periodic term hooks](./integrations/periodic-term-hooks.md)
- [Role providers](./integrations/role-providers.md): credential-provider
  capabilities and construction paths
- [ERC-4626 wrapper](./integrations/erc-4626-wrapper.md): wrapping, redemption,
  rounding, sanctions, and integration constraints
- [Event model](./integrations/events.md): ABI families, event ordering,
  deployment discovery, and indexer replay

## Security model

- [Security assumptions](./security/assumptions.md): credit, authority, hook,
  sanctions, and asset boundaries
- [`SECURITY.md`](../SECURITY.md): private vulnerability reporting
- [`audits/`](../audits/README.md): published external review evidence

## Releases and operations

- [Release notes](./releases/README.md): V2.0, V2.1, and V2.5 source boundaries
  and compatibility changes
- [Deployment](./operations/deployment.md): inventory, plans, ceremonies,
  verification, and handoffs

Machine-readable state in [`deployments/`](../deployments/) is authoritative for
deployment facts.

Historical checklists, completed ceremony records, generated tool output, and
internal audit-preparation papers are not protocol specifications.
