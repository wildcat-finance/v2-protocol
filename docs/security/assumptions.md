# Security assumptions

These are the trust and compatibility assumptions of the active release source.
Deployment-specific addresses and role holders live in
[`deployments/`](https://github.com/wildcat-finance/v2-protocol/tree/bfe1412141f263ba6b056c60c3f4654a461598dd/deployments).

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

New V2.5 markets do not permit execution hooks to veto collection. Markets with
repayment terms also bypass queue hooks from their date and closure hooks for
automatic completion. Token transfers, sanctions dependencies and other enabled
callbacks retain their own failure boundaries. See
[repayment and default](../protocol/repayment-and-default.md).

Sanctions quarantine uses the ordinary withdrawal path. A withdrawal hook may
therefore defer `nukeFromOrbit` until the market's normal term or withdrawal
window permits queueing, or until an enabled repayment date bypasses that queue
hook. The nuke callback itself can still reject the action.

## Creation-code storage

Deployment tooling prepares one raw store or two split stores from the reviewed
creation artifact. A split primary contains a reader and an immutable link to
its secondary; neither contract exposes a mutation path. Verification checks
both complete runtime images, their link, and the returned original bytes.

The factory separately hashes recovered creation code before CREATE2. Market
hashes are fixed at factory deployment; hook hashes are fixed at template
registration. The hash must come from the reviewed artifact. A store's own
claim about its output does not establish that identity. Review the reader,
installation constructors, plan commitments and execution tooling together;
see [deployment](https://github.com/wildcat-finance/v2-protocol/blob/bfe1412141f263ba6b056c60c3f4654a461598dd/docs/operations/deployment.md#stored-creation-code).

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
