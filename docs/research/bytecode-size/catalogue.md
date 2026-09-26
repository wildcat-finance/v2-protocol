# Bytecode experiment catalogue

See the [research protocol](./README.md) for constraints and baseline sizes.
All listed commits belong to the experimental branch. Split initcode storage
is excluded. No experiment has been adopted into the release branch.

| Experiment | Hypothesis                                                     | Source parent | Result                                           | Decision / dependencies                                             |
| ---------- | -------------------------------------------------------------- | ------------- | ------------------------------------------------ | ------------------------------------------------------------------- |
| E00        | Reproduce the exact compiler baseline with the research runner | `7b47eec`     | Exact match on all 10 targets                    | Runner qualified                                                    |
| E01        | [Compiler size bias](./E01-compiler.md)                        | `9cc8b18`     | Best variant saves 374/394 market creation bytes | Keep no-specializer and low runs as unqualified compiler candidates |
