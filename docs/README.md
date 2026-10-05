# Technical documentation

Contract behavior, integration guides, and deployment tooling for developers
and security reviewers.

Use the documentation from the same tag or commit as the contracts you are
working with. [Release notes](./releases/README.md) describe compatibility
between versions; [deployment records](../deployments/) identify contracts by
network, address, and release.

## Build and contribute

- [Build setup](../README.md#build-and-test)
- [Testing](../TESTS.md): canonical commands, reproducible runs, and tooling tests
- [Test suite guide](../test/README.md): fixtures, invariants, and coverage limits
- [Contributing](../CONTRIBUTING.md): toolchain setup and source conventions

## Protocol

- [Markets](./protocol/markets.md): configuration, implementations, and borrower
  authority
- [Repayment and default](./protocol/repayment-and-default.md): immutable terms,
  inclusive deadlines, penalty runs, automatic closure, and collection
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
- [Hook development](./integrations/hook-development.md): shared defaults,
  reusable term policies, feature composition, and explicit override decisions
- [Role providers](./integrations/role-providers.md): credential-provider
  capabilities and construction paths
- [ERC-4626 wrapper](./integrations/erc-4626-wrapper.md): wrapping, redemption,
  rounding, sanctions, and integration constraints
- [Market lenses](./integrations/lenses.md): lifecycle, liquidity, hook policies,
  factory commitments, withdrawal claims, and return-ABI compatibility
- [Event model](./integrations/events.md): ABI families, event ordering,
  deployment discovery, and indexer replay

## Security model

- [Security assumptions](./security/assumptions.md): credit, authority, hook,
  sanctions, and asset boundaries
- [Known limitations](./security/known-issues.md): accepted accounting,
  liveness, dependency, and legacy behavior
- [`SECURITY.md`](../SECURITY.md): private vulnerability reporting
- [`audits/`](../audits/README.md): published external review evidence

## Releases and operations

- [Release notes](./releases/README.md): V2.0, V2.1, and V2.5 source boundaries
  and compatibility changes
- [V2.5 review material](./releases/README.md#v25-review-material): source
  inventories, review scope, and dated verification results
- [Deployment](./operations/deployment.md): inventory, plans, ceremonies,
  verification, and release-specific runbooks
