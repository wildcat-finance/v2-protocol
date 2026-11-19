// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // Deploy4626Factory
//  \ ^ /   Validate a market and deploy or discover its wrapper.
//    V
//
//  MARKET QUERIES
//  borrower()
//  hooks()
//
//  DEPLOYMENT
//  run()
// ═════

import 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';

// ┌─ IWildcatMarketFor4626Deploy ──────────────────────────────────────────────
interface IWildcatMarketFor4626Deploy {
  // ░░▒▒▓▓██ [ MARKET QUERIES ] ───────────────────────────────────────────────

  // ┌─ borrower ─────
  function borrower() external view returns (address);

  // ┌─ hooks ─────
  function hooks() external view returns (HooksConfig);
}

// ┌─ Deploy4626Factory ────────────────────────────────────────────────────────
contract Deploy4626Factory is Script {
  // ░░▒▒▓▓██ [ DEPLOYMENT ] ───────────────────────────────────────────────────

  // ┌─ run ─────
  function run() external {
    address archController = vm.envAddress('ARCH_CONTROLLER');
    address market = vm.envAddress('MARKET');

    address expectedHooks = vm.envOr('EXPECTED_HOOKS', address(0));
    address existingFactory = vm.envOr('WRAPPER_FACTORY', address(0));
    uint256 privateKey = vm.envOr('PVT_KEY', uint256(0));

    if (privateKey != 0) {
      address expectedDeployer = vm.envOr('DEPLOYER_ADDRESS', address(0));
      address deployer = vm.addr(privateKey);
      console.log('Deployer:', deployer);
      if (expectedDeployer != address(0)) {
        require(deployer == expectedDeployer, 'PVT_KEY does not match DEPLOYER_ADDRESS');
      }
    }

    if (expectedHooks != address(0)) {
      address actualHooks = IWildcatMarketFor4626Deploy(market).hooks().hooksAddress();
      require(actualHooks == expectedHooks, 'Unexpected market hooks');
    }

    bool isRegistered = IWildcatArchController(archController).isRegisteredMarket(market);
    require(isRegistered, 'Market is not registered in arch controller');

    if (privateKey != 0) {
      vm.startBroadcast(privateKey);
    } else {
      vm.startBroadcast();
    }

    Wildcat4626WrapperFactory factory;
    if (existingFactory == address(0)) {
      // legacy half-up markets route to V1. its address is immutable: a silent zero
      // default would strand legacy markets on chains that have a V1 deployment.
      // require an explicit zero on chains without one.
      address v1Factory = vm.envAddress('WRAPPER_FACTORY_V1');
      factory = new Wildcat4626WrapperFactory(archController, v1Factory);
    } else {
      factory = Wildcat4626WrapperFactory(existingFactory);
    }

    console.log('Wrapper factory:', address(factory));

    address wrapper = factory.wrapperForMarket(market);
    if (wrapper == address(0)) {
      wrapper = factory.createWrapper(market);
      console.log('Wrapper deployed:', wrapper);
    } else {
      console.log('Wrapper already exists:', wrapper);
    }

    vm.stopBroadcast();

    require(Wildcat4626Wrapper(wrapper).asset() == market, 'Wrapper asset mismatch');
    console.log('Wrapper asset ok:', market);
    console.log('Market borrower:', IWildcatMarketFor4626Deploy(market).borrower());
  }
}
