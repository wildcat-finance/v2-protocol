# Nuke protection

v2.5 markets use `isNukeProtected(account)` to protect pooled lender contracts,
such as ERC-4626 wrappers, from sanctions quarantine and account freezes. Nuking
a pool as one lender would quarantine the backing of all its users. A protected
address causes `nukeFromOrbit` to revert with `CannotNukeProtectedAccount` before
sanctions queries, hooks, or withdrawal accounting.

## Authority and permanence

| Operation                            | Authority                                                           |
| ------------------------------------ | ------------------------------------------------------------------- |
| Approve or disable a feature factory | Current `ArchController.owner()`, separately on each market factory |
| Request protection for an instance   | An approved feature factory                                         |
| Write the market's protection entry  | The market's immutable `factory()`                                  |

Both market factories expose
`setNukeProtectionFactoryApproval(featureFactory, approved)` and
`isApprovedNukeProtectionFactory(featureFactory)`. Initial and later approvals
use the same owner authority; configuring a wrapper factory does not approve it.

Protection cannot be removed. Disabling a feature factory prevents future
registrations but leaves existing entries intact. Borrower and ownership
changes do not revoke them. Registration remains open after funding and
closure; it does not move balances or change accounting.

## Instance registration

An approved feature factory calls
`registerNukeProtectedAccount(market, account)` on the market factory. The
market factory checks the caller's approval, that it deployed the market, and
that the account has code. It then calls the market's registration function.

The approved factory must authenticate the instance's immutable implementation,
configuration, and market binding. Code presence alone does not establish
provenance. Approval also relies on each feature enforcing sanctions on its
individual participants. An unrestricted relay for arbitrary addresses would
defeat this boundary.

New feature factories must register each instance in its deployment
transaction and revert creation if registration fails. Registration follows
the instance's constructor, since the code check cannot pass during
construction. Approval alone does not add this behavior to a factory.
Approved factories may also authenticate and register existing instances.

## Canonical wrapper

Wrapper creation is optional and permissionless, including after market
funding. The configured wrapper factory must be approved before
`createWrapper(market)` can succeed. That transaction deploys the wrapper,
registers its protection, and records its canonical identity; failure reverts
the whole transaction. Market creation does not deploy a wrapper.

Protection does not make another integration canonical or grant the
canonical wrapper's transfer privileges. Wrapper eligibility and recipient
policy are described in the [wrapper guide](./erc-4626-wrapper.md).

## Scope

The market and its canonical wrapper exempt protected accounts from their
lender sanctions checks. A listed integration can deposit, transfer, queue and
collect withdrawals without a borrower override. Its withdrawals pay the
integration directly rather than sanctions escrow. Ordinary lenders and wrapper
holders remain subject to sanctions enforcement.

Protection applies only on the registering market and its wrapper. Hook policy,
solvency, accounting, and raw borrower/principal sanctions checks still apply.
The sentinel's reported status is unchanged.

Consumers need the updated market and factory ABIs; `MarketState` and hook
callback tuples are unchanged by this feature. See
[wrapper and sanctions events](./events.md#wrappers-withdrawals-and-sanctions)
for registration events and their order.
