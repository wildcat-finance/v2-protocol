# Bytecode experiment catalogue

See the [research protocol](./README.md) for constraints and baseline sizes.
All listed commits belong to the experimental branch. Split initcode storage
is excluded. No experiment has been adopted into the release branch.

| Experiment | Hypothesis                                                     | Source parent | Result                        | Decision / dependencies                                |
| ---------- | -------------------------------------------------------------- | ------------- | ----------------------------- | ------------------------------------------------------ |
| E00        | Reproduce the exact compiler baseline with the research runner | `7b47eec`     | Exact match on all 10 targets | Runner qualified                                       |
| E01        | Bias compiler optimization toward size                         | `7b47eec`     | Pending                       | Keep settings experiments separate from source savings |
