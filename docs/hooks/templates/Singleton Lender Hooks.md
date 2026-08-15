# Singleton lender hooks

The singleton templates make one address the market's sole direct credentialed lender. That address
may be an EOA or a contract. The hook creates one immutable pull provider during construction,
checks the provider's deterministic address and lender binding, then seals its provider set. It
cannot later add, remove, or replace a credential source.

The three variants differ only in the market promise around that sole lender:

- `SingletonOpenTermHooks` keeps an open market. A tranching controller is the obvious shape: the
  controller owns the direct market position and handles its own junior/senior claims elsewhere.
- `SingletonFixedTermHooks` keeps a fixed maturity and prevents pre-maturity closure, term
  reduction, APR changes, and reserve-ratio changes. A BRC-shaped note contract is one possible
  lender: it owns the market position while its own contract handles the observation and waterfall.
- `SingletonPeriodicTermHooks` keeps recurring withdrawal windows and the periodic APR-reduction
  process. It exists as a one-lender option for a future periodic product; this repository does not
  prescribe that product.

The templates are not product implementations. They put the one-lender market boundary into the
market's hook configuration while the nominated lender contract owns any further logic.

## Construction and admission

Each template accepts a `NameAndProviderInputs` payload and a non-zero lender address. The input
must create exactly one zero-TTL provider through `SingletonRoleProviderFactory`, with no existing
provider and no push provider. The hook recomputes the CREATE2 provider address using itself as the
factory caller, verifies the created provider's immutable lender, and seals provider configuration.

All three require deposit and transfer dispatch in the supplied `HooksConfig`. This means the
singleton provider is consulted when a lender enters or receives a direct market position. An
unrelated address cannot deposit or receive market tokens.

## Canonical wrapper

When market transfers are enabled, the market's registered canonical 4626 wrapper is the sole
transfer-recipient exception. Its address is read from the market, and that address can only be set
once by the immutable wrapper factory. The wrapper has not received a lender credential; other
market-token recipients still follow the singleton check.

When `transfersDisabled` is true, the exception is unavailable and every market-token transfer
reverts. If a market's raw `useOnQueueWithdrawal` choice requires withdrawal credentials, the
wrapper cannot queue a withdrawal itself because it remains uncredentialed. The direct singleton
lender can receive its market tokens back and queue, or the market can use a non-credentialed queue
path.

## Reuse and limits

One hooks instance can create more than one market. Those markets share the same nominated lender;
the singleton property is per market, not one hooks instance per market.

The templates leave the base lineage's non-admission behaviour alone. In particular, sanctions,
delinquency, and the nominated lender contract's own governance are not changed here.
