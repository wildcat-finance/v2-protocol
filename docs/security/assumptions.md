# Security Assumptions

This page states the trust and compatibility assumptions of the active release
source. Deployment-specific addresses and role holders are recorded under
[`deployments/`](../../deployments/).

## Credit and borrower authority

Wildcat markets provide undercollateralized credit. Borrower default and adverse
use of authority explicitly granted by the market are credit risk. They are not,
by themselves, protocol vulnerabilities. See [`SECURITY.md`](../../SECURITY.md)
for the reporting boundary.

Borrower authority is constrained by market liquidity requirements, hooks, and
the market lifecycle. It still includes control over draws and supported
configuration changes. Lenders and integrators must evaluate the borrower,
market terms, and hook policy rather than treating registration as a repayment
guarantee.

## Onchain authority

Authority is expressed through contract roles. The repository does not infer a
legal entity from an address. Relevant roles include ArchController ownership,
SphereX administration and operation, hooks administration, role-provider
administration, and market borrower authority.

Registry membership records an authorized protocol relationship. It is not a
general endorsement of arbitrary code at that address. Deployment and
integration tooling must validate bytecode, expected interfaces, and factory
relationships against the intended release.

## Hooks

A market's hook address and enabled callbacks are immutable. The hook's own
state and administration may remain mutable. An enabled callback can reject its
corresponding market action, so market liveness depends on the selected hook
implementation and configuration.

Sanctions quarantine uses the ordinary withdrawal path. A withdrawal hook may
therefore defer `nukeFromOrbit` until the market's normal term or withdrawal
window permits queueing.

## Sanctions dependency

Sanctions-gated market and wrapper paths depend on the configured sentinel and
its external sanctions list. Calls fail closed when the dependency reverts or
returns malformed data. Affected paths include deposits, market-token transfers,
withdrawal queueing and execution, borrower sanction checks, wrapper operations,
and sanctions escrow release.

Borrower-specific overrides apply only where the sentinel's
`isSanctioned(principal, account)` policy is used. Borrowing and borrower
transfers check the raw sanctions status of the relevant borrower identities.

## Underlying assets

Wildcat assumes a supported underlying asset has stable ERC-20 transfer and
metadata behavior. Metadata may use ABI strings or legacy fixed-width `bytes32`
values. Malformed or mutable metadata, fee-on-transfer behavior, rebasing,
callbacks, nonstandard zero-value transfers, or other unusual token semantics
require explicit compatibility review before use.

The protocol does not make an arbitrary ERC-20 safe merely because a market can
be deployed against it.
