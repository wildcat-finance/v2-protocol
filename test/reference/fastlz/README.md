# FastLZ test reference

Unmodified upstream `fastlz.c` and `fastlz.h` from
[ariya/FastLZ at 344eb4025f9ae866ebf7a2ec48850f7113a97a42](https://github.com/ariya/FastLZ/tree/344eb4025f9ae866ebf7a2ec48850f7113a97a42).
That is the level-1 reference named by the vendored Solady `LibZip.sol` at
Solady commit `2ba1cc1eaa3bffd5c093d94f76ef1b87b167ff3c`.

The MIT license and copyright notices are retained in both files. These files
are test dependencies and do not enter Solidity builds or deployed contracts.

`scripts/research/fastlz-reference.py` verifies the source SHA-256 hashes,
compiles with the local C compiler and caches the shared library in `deploy-out`.
Tests run offline and require Python 3, `cc`, and Foundry FFI. The C oracle is
given valid streams; malformed-input testing stays inside the EVM. For inputs
shorter than upstream's documented 16-byte minimum, the adapter emits one
literal run directly. Empty input maps to an empty stream.

The suite checks both directions: C decodes Solady's output and our deployed
reader decodes C's output. A shared encoder/decoder bug cannot satisfy both
comparisons merely by making the two Solidity functions agree.
