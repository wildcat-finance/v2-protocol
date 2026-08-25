# Production-shaped economics

Status: replaced.

## Boundary

`ProductionEconomicsTest` is a native replacement-suite owner built on the artifact-backed
production factory fixture. It does not import the frozen suite or reuse its fixture graph.

The scenarios use a 130 million asset capacity, 70 million initial draw, 8.5% APR, 5% delinquency
fee, 48-hour grace period, 24-hour withdrawal cycle, 20% reserve ratio, and a 4% revolving
commitment fee. The large values are here to retain the production-shaped arithmetic boundary,
not to create another general market test family.

## Preserved intent

One runtime property applies the same lifecycle to standard and revolving markets deployed by the
production factories. It checks a healthy month, full utilization, entry into delinquency, the
grace interval, penalized accrual, repayment, and complete delinquency-clock decay. Each accrual
segment is checked against a closed-form oracle that independently includes the appropriate
standard or revolving base rate and delinquency penalty time.

One runtime property checks lender-yield ordering at 10% utilization, the production-shaped 53.8%
utilization point, and 95% utilization. Both market types must match the independent 30-day oracle
exactly before their scale factors are compared.

The two frozen wrapper variants do not own a large-balance-specific guarantee. Wrapper execution at
an accrued fractional scale factor, standard/revolving parity, access readiness, and production
factory routing already have focused owners in `Wildcat4626WrapperIntegrationTest` and
`Wildcat4626WrapperFactoryTest`. Repeating those paths with more token digits would add another
composition without testing a new boundary.

## Focused result

Both properties pass under the canonical via-IR profile. The focused artifact compiled in 24.99
seconds and the two scenarios executed in 5.32 milliseconds.
