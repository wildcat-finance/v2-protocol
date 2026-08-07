// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

/**
 * @dev Deterministic addresses and salts for the covenant libraries.
 *
 *      Covenant bodies live in external libraries reached by `DELEGATECALL`,
 *      so they do not count against a template's EIP-170 limit. Templates are
 *      compiled against fixed addresses, which keeps deployment single-phase.
 *
 *      Every consumer reads these constants: the deploy script for its
 *      bootstrap and drift assertion, and the test suites for the code they
 *      place before exercising a template. `foundry.toml` cannot import
 *      Solidity, so its `libraries` entry is the one unavoidable duplicate.
 *      **Change an address here and change it there in the same commit.**
 *
 *      The addresses are a function of each library's compiled creation code,
 *      so they move if the compiler version or optimizer settings change.
 *      These values are for the `deploy` profile (via_ir, optimizer, 200 runs),
 *      which is what ships. The deploy script recomputes and asserts a match,
 *      so drift fails a run rather than registering templates linked to an
 *      empty address. Regenerate with:
 *
 *      ```
 *      FOUNDRY_PROFILE=deploy forge build --force --skip test --skip script
 *      cast create2 --deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C \
 *        --salt <salt> --init-code-hash $(cast keccak $(jq -r '.bytecode.object' \
 *        deploy-out/<Lib>.sol/<Lib>.json))
 *      ```
 *
 *      A new covenant library takes the next salt and a constant here.
 */

/// @dev Canonical deterministic-deployment proxy. Same address on mainnet and
///      Sepolia, which is what keeps the library addresses chain-independent.
address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

bytes32 constant CROSS_MARKET_GATE_LIB_SALT =
  0x0000000000000000000000000000000000000000000000000000000000000001;
bytes32 constant CLEAN_DOWN_LIB_SALT =
  0x0000000000000000000000000000000000000000000000000000000000000002;

bytes32 constant COMMITMENT_SCHEDULE_LIB_SALT =
  0x0000000000000000000000000000000000000000000000000000000000000003;
bytes32 constant DRAW_TIMELOCK_LIB_SALT =
  0x0000000000000000000000000000000000000000000000000000000000000004;

address constant COMMITMENT_SCHEDULE_LIB = 0x06AE339781C3bb2edd0039a8A66Ea75e74dFB9Eb;
address constant DRAW_TIMELOCK_LIB = 0xb290005F652E8989c8341709c24387bc2B0b60a7;

bytes32 constant BORROWING_BASE_LIB_SALT =
  0x0000000000000000000000000000000000000000000000000000000000000005;
bytes32 constant CROSS_MARKET_CAP_LIB_SALT =
  0x0000000000000000000000000000000000000000000000000000000000000006;

address constant BORROWING_BASE_LIB = 0x0534D8c7B743e7bF9C9D319A567D77FA0880aE21;
address constant CROSS_MARKET_CAP_LIB = 0xA8ccf7e3241a86920A0Dea46274c95E7369c998c;

address constant CROSS_MARKET_GATE_LIB = 0x1c6f2EbF304E87AA8AB9e3f8E916360d00C6F404;
address constant CLEAN_DOWN_LIB = 0xEfE248377801886F5EB1eD8Fa3511f2Be4f975eD;
