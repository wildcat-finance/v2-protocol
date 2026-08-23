# Production matrix scenarios

Status: production topology and the deterministic matrix integration intents are replaced.

## Boundary

`ProductionMatrixScenariosTest` uses one artifact-backed stack with the production ArchController,
borrower identity registry, sanctions Sentinel, wrapper factory, standard hooks factory, revolving
hooks factory, and stored production market and hook initcode. It does not import any legacy fixture
or inherited test entrypoint.

The runtime matrix covers:

- OpenTerm × standard
- FixedTerm × standard
- PeriodicTerm × standard
- OpenTerm × revolving
- FixedTerm × revolving
- PeriodicTerm × revolving

## Preserved intent

The topology property proves both production factories deploy each built-in hook type, bind the
correct template and administrator, register the resulting market, retain the effective hook flags,
and expose the configured revolving commitment fee. Every cell also executes a credentialed deposit.

The deterministic lifecycle property runs every cell through deposits, a draw, three independently
calculated accrual segments, partial and final repayment, a hook-gated withdrawal, closure, and full
lender drain. It checks lender yield, withdrawal accounting, zero final scaled supply, zero pending
and unpaid withdrawals, and at most bounded dust in the market.

The boundary property checks both market implementations at one second before and exactly at a
FixedTerm end, and immediately before, at the start of, at the end of, and at the next PeriodicTerm
withdrawal window.

The periodic APR properties run the proposal lifecycle through real periodic hooks and both market
implementations. They check the response bounds, premature execution, lender exit, permissionless
execution, expiry, APR-increase cancellation, market-close cancellation, and proposal cleanup.

The minimum-deposit properties check capacity clamping before hook validation, live borrower
updates, clearing the minimum, administrator authority, and the exact accepted/rejected boundary
after the scale factor has accrued. The accrued-scale boundary runs against all three production
hook templates.

The rounding property restores the audited numeric stranding windows with explicit non-vacuity
checks, then proves both a fully queued close and a withdrawal queued after close can drain without
leaving an unpaid batch or lender balance.

The sanctions property composes the real sanctions list, Sentinel, escrow, hooks, and markets. It
checks direct nuke -> expiry -> escrow -> borrower override -> release, the accepted periodic-window
limitation, and that nuking a lender in a revolving market does not change drawn principal.

The stateful matrix remains separate. It owns randomized action ordering and conservation; these
scenarios own required business sequences and real-factory composition.

## Focused result

All nine properties pass under the canonical via-IR profile. Compile and runtime measurements are
recorded again at the suite cutover gate rather than treated as stable while this file is growing.
