# Security assumptions

These are the trust and compatibility assumptions of the active release source.
Deployment-specific addresses and role holders live in
[`deployments/`](../../deployments/).

## Credit and borrower authority

Wildcat markets provide undercollateralized credit.

Borrower default is credit risk. So is adverse use of authority explicitly
granted by a market. Neither is, by itself, a protocol vulnerability. See
[`SECURITY.md`](../../SECURITY.md) for the reporting boundary.

Liquidity requirements, hooks, and the market lifecycle constrain borrower
authority. Borrowers still control draws and supported configuration changes.

Registration is not a repayment guarantee. Lenders and integrators must evaluate:

- The borrower.
- Market terms.
- Hook policy.

## Onchain authority

Authority is expressed through contract roles. This repository does not infer a
legal entity from an address.

Relevant roles include:

- ArchController ownership.
- SphereX administration and operation.
- Hook administration.
- Role-provider administration.
- Market borrower authority.

Registry membership records an authorized protocol relationship. It does not
endorse arbitrary code at that address.

Deployment and integration tooling must validate against the intended release:

- Bytecode.
- Expected interfaces.
- Factory relationships.

## Hooks

A market's hook address and enabled callbacks are immutable. The hook's state
and administration may remain mutable.

An enabled callback can reject its corresponding market action. Market
liveness therefore depends on the selected hook implementation and
configuration.

Sanctions quarantine uses the ordinary withdrawal path. A withdrawal hook may
therefore defer `nukeFromOrbit` until the market's normal term or withdrawal
window permits queueing.

## Sanctions dependency

Sanctions-gated market and wrapper paths depend on the configured sentinel and
its external sanctions list. Calls fail closed if that dependency reverts or
returns malformed data.

Affected paths include:

- Deposits and market-token transfers.
- Withdrawal queueing and execution.
- Borrower sanctions checks.
- Wrapper operations.
- Sanctions escrow release.

Borrower-specific overrides apply only where the sentinel uses
`isSanctioned(principal, account)`. Borrowing and borrower transfers check the
raw sanctions status of the relevant borrower identities.

## Underlying assets

Wildcat assumes supported underlying assets have stable ERC-20 transfer and
metadata behavior. Metadata may use ABI strings or legacy fixed-width `bytes32`
values.

Review these behaviors explicitly before supporting an asset:

- Malformed or mutable metadata.
- Fee-on-transfer or rebasing behavior.
- Transfer callbacks.
- Nonstandard zero-value transfers.
- Other unusual token semantics.

Deployability does not make an arbitrary ERC-20 safe.
