# Singleton periodic-term hooks

`SingletonPeriodicTermHooks` is the periodic member of the singleton lender family. It uses the
same one-address provider construction as `SingletonOpenTermHooks` and
`SingletonFixedTermHooks`; see [Singleton Lender Hooks](./Singleton%20Lender%20Hooks.md) for the
shared admission and wrapper rules.

This template is available for a product that needs one direct lender and recurring withdrawal
windows. It does not impose a product model beyond that. Its role is narrow: a borrower cannot add
another lender credential route after the market exists.

## Construction

The constructor takes `SingletonPeriodicTermHooksInputs`:

- `accessControlInputs` must create exactly one provider through
  `SingletonRoleProviderFactory`, with no existing provider, no push provider, and a TTL of zero.
- `lender` must be non-zero and must match the lender encoded into the factory input.

The hook checks the singleton-factory runtime code, predicts the provider address using the hooks
instance as factory caller, checks the provider created there, and seals role-provider
configuration. Calls to `createRoleProvider`, `addRoleProvider`, and `removeRoleProvider` then
revert.

## Market policy

The template requires every field of the periodic data encoding:

```solidity
abi.encode(
  uint32 firstWithdrawalWindowStart,
  uint32 periodDuration,
  uint32 withdrawalWindowDuration,
  uint128 minimumDeposit,
  bool transfersDisabled
)
```

Deposit and transfer dispatch must be enabled in the supplied `HooksConfig`. The parent
`PeriodicTermHooks` validates the withdrawal schedule and forces its queue-withdrawal, close-market,
APR/reserve-ratio, and pending-APR-execution paths on. It continues to govern the schedule, market
closure, and APR-reduction proposal flow; this singleton template does not change them.

`transfersDisabled` remains a deployment choice. If it is false, the nominated lender and the
market's registered canonical 4626 wrapper can receive market tokens. No other recipient can. If
it is true, all market-token transfers revert.

## Required evidence

The implementation must prove that deployment produces a sealed provider set, invalid singleton
configuration fails, the nominated lender alone can deposit and receive a direct position, the
canonical wrapper round-trips a position when enabled, and the inherited withdrawal-window rules
remain live.
