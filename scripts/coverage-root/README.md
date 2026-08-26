# Focused Coverage Root

This directory intentionally contains no Solidity source. The `coverage`
Foundry profile uses it as `src` and `script` so a focused `FOUNDRY_TEST` path
compiles only the production graph imported by that test family. Pointing
coverage at the complete `src/` tree pulls in production graphs that the
non-via-IR coverage compiler cannot currently build.
