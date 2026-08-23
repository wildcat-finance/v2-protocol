# Production matrix scenarios

Status: production topology, deterministic lifecycle, and withdrawal-boundary intents replaced.

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

The stateful matrix remains separate. It owns randomized action ordering and conservation; these
scenarios own required business sequences and real-factory composition.

## Focused result

All three properties pass under the canonical via-IR profile. After the first fixture compile, the
expanded scenario artifact compiled in 25.46 seconds and the complete runtime matrix executed in
under 10 milliseconds.
