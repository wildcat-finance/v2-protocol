# Singleton fixed-term hooks

`SingletonFixedTermHooks` is the fixed-term member of the singleton lender family. A borrower
deploys a market with one nominated lender address. The address may be an EOA or a contract. The
hooks instance creates the only role provider during construction, verifies the provider and lender
binding, then permanently seals the provider set. See
[Singleton Lender Hooks](./Singleton%20Lender%20Hooks.md) for the shared open, fixed, and periodic
model.

The template does not define the lender's business logic. A lender contract may run a fund, a note,
or any other policy outside the market. At the Wildcat layer, the direct market position has one
credential route for its entire lifetime.

## Construction

The constructor takes `SingletonFixedTermHooksInputs`:

- `accessControlInputs` must create exactly one new provider through
  `SingletonRoleProviderFactory`, with no existing provider, no push provider, and a TTL of zero.
- `lender` must be non-zero and must equal the lender encoded into the factory input.

The template checks the singleton-factory runtime code, predicts the provider address using the
hooks instance as the factory caller, checks the provider created at that address, and seals the
role-provider configuration. Later `createRoleProvider`, `addRoleProvider`, and
`removeRoleProvider` calls revert.

## Market policy

The template uses the `FixedTermHooks` fixed-term data encoding:

```solidity
abi.encode(
  uint32 fixedTermEndTime,
  uint128 minimumDeposit,
  bool transfersDisabled,
  bool allowClosureBeforeTerm,
  bool allowTermReduction
)
```

All five words are required. `FixedTermHooks` validates the end time against its one-year maximum.
The singleton template adds these restrictions:

- Deposit and transfer dispatch must be enabled in the supplied `HooksConfig`.
- `allowClosureBeforeTerm` must be false.
- `allowTermReduction` must be false.
- Before `fixedTermEndTime`, `annualInterestBips` and `reserveRatioBips` must equal their current
  values. The combined Wildcat setter cannot change either value.

The parent template already requires the queue-withdrawal, close-market, and combined
APR/reserve-ratio hooks. Those required bits are merged into the market configuration and cannot be
silenced by the borrower at deployment or later.

`transfersDisabled` remains a deployment choice. When true, all market-token transfers revert.
When false, transfer dispatch still runs: the nominated lender can receive market tokens through
its live singleton credential, and the market's registered canonical 4626 wrapper may receive them
through its market-authenticated exemption. No other recipient can receive market tokens.

The wrapper is a transfer recipient, not a credentialed lender. If the supplied raw
`useOnQueueWithdrawal` flag requires withdrawal access, it cannot queue a withdrawal itself. The
direct singleton lender can receive the market tokens back and queue, or deployment can leave that
raw flag false.

## Fixed-term lifecycle

Before the term ends, the borrower cannot close the market because both early-closure flags are
false. The fixed-term end cannot be shortened through `setFixedTermEndTime`. The borrower also
cannot reprice the coupon or change the reserve ratio while the term is live. At or after the end
time, the inherited fixed-term lifecycle permits normal withdrawal and closure behaviour.

The template does not alter delinquency, sanctions, borrower transfer, or the lender contract's
own governance. It also leaves the inherited minimum-deposit setter available to the hook
administrator; that setting does not create another lender credential route or change the fixed
term, coupon, or reserve-ratio policy.

## Required evidence

The implementation must prove all of the following with unit or integration tests:

- direct `deployMarketAndHooks` deployment creates a sealed instance with the expected provider and
  lender;
- the nominated lender can deposit, an unrelated address cannot deposit, and an unrelated address
  cannot receive market tokens;
- the canonical wrapper can receive and return market tokens when transfers are enabled;
- malformed data, missing deposit or transfer dispatch, early closure, and term reduction are
  rejected at deployment;
- provider changes, pre-maturity closure, term reduction, and APR/reserve-ratio changes revert.
