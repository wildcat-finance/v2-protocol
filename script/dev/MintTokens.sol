// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // MintTokens
//  \ ^ /   Development token approval and market deposit runner.
//    V
//
//  TOKEN DEPLOYMENT
//  deployMockERC20(...)
//
//  EXECUTION
//  run()
// ═════

// import 'src/WildcatMarketControllerFactory.sol';
import 'src/WildcatSanctionsSentinel.sol';
import 'src/WildcatArchController.sol';
import '../mock/MockERC20Factory.sol';
import '../mock/MockArchControllerOwner.sol';
// import './mock/MockChainalysis.sol';
import 'forge-std/Script.sol';
import 'src/market/WildcatMarket.sol';
import 'src/libraries/LibStoredInitCode.sol';
import 'src/access/OpenTermHooks.sol';
import 'src/HooksFactory.sol';
import '../common/LibDeployment.sol';

// ┌─ IMockERC20Factory ────────────────────────────────────────────────────────
interface IMockERC20Factory {
  // ░░▒▒▓▓██ [ TOKEN DEPLOYMENT ] ─────────────────────────────────────────────

  // ┌─ deployMockERC20 ─────
  function deployMockERC20(string memory name, string memory symbol) external returns (address);
}

// ┌─ MintTokens ───────────────────────────────────────────────────────────────
contract MintTokens is Script {
  // ░░▒▒▓▓██ [ EXECUTION ] ────────────────────────────────────────────────────

  // ┌─ run ─────
  function run() external {
    WildcatMarket market = WildcatMarket(0x89998f1cA5BA398948F0f8A15467EE6a5533b51A);
    MockERC20 token = MockERC20(0xc02b598A43EEc2117BD5d1A914286D860471868a);
    vm.broadcast(vm.envUint('PVT_KEY'));
    token.approve(address(market), 10e18);
    vm.broadcast(vm.envUint('PVT_KEY'));
    market.deposit(10e18);
  }
}
