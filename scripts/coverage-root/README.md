# Focused coverage root

This directory intentionally contains no Solidity source.

The `coverage` Foundry profile uses it as `src` and `script`. A focused
`FOUNDRY_TEST` path then compiles only the production graph imported by that
test family.

Do not point coverage at the complete `src/` tree. It pulls in production graphs
that the non-via-IR coverage compiler cannot currently build.
