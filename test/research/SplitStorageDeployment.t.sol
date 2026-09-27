// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';
import { LibSplitInitCode } from 'src/libraries/LibSplitInitCode.sol';
import { SplitInitCodeReader } from 'src/libraries/LibSplitInitCode.sol';
import { IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { HooksConfig, HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { LibCompressedInitCode } from 'src/libraries/LibCompressedInitCode.sol';
import { PeriodicTransferHooks } from '../mocks/TransferFeatureHooks.sol';
import { PeriodicBorrowHooks } from '../mocks/BorrowFeatureHooks.sol';
import { PeriodicAprReplacementHooks } from '../mocks/AprReplacementHooks.sol';

contract StoredInitCodeReadProbe {
  function readHash(address store) external view returns (bytes32) {
    return keccak256(LibStoredInitCode.getInitCode(store));
  }
}

abstract contract SplitStorageFixture is ProductionMatrixFixture {
  uint256 internal storageContracts;
  mapping(address => address) internal secondaries;

  function _storeInitCode(
    string memory artifact
  ) internal override returns (address store, uint256 codeHash) {
    bytes memory initCode = vm.getCode(artifact);
    uint64 nonce = vm.getNonce(address(this));
    address secondary;
    (store, secondary) = LibSplitInitCode.deployInitCode(initCode);
    secondaries[store] = secondary;
    assertEq(vm.getNonce(address(this)), nonce + 2, 'exactly two stores');
    assertTrue(store.code.length <= 24_576, 'primary fits');
    assertTrue(secondary.code.length <= 24_576, 'secondary fits');
    assertEq(LibStoredInitCode.getInitCode(store), initCode, 'original creation bytes');
    codeHash = uint256(keccak256(initCode));
    storageContracts += 2;
  }
}

contract SplitStorageIntegrityTest is SplitStorageFixture {
  function test_factoryRejectsCorruptedMarketTailBeforeCreate2() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 model; model < 2; ++model) {
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind.OpenTerm,
        MatrixMarketKind(model)
      );
      address store = _factoryFor(stack, options.marketKind).marketInitCodeStorage();
      address secondary = secondaries[store];
      bytes memory original = secondary.code;
      assertTrue(original.length > 1, 'market spans two payloads');
      bytes memory corrupted = bytes.concat(original);
      corrupted[1] ^= 0x01;
      vm.prank(MatrixBorrower);
      address hook = _factoryFor(stack, options.marketKind).deployHooksInstance(
        stack.hooksTemplates[0],
        ''
      );
      HooksDeploymentConfig config = IHooks(hook).config();
      HooksConfig flags = config.optionalFlags().setHooksAddress(hook).mergeAllFlags(
        config.requiredFlags()
      );
      vm.etch(secondary, corrupted);
      uint64 nonce = vm.getNonce(address(_factoryFor(stack, options.marketKind)));
      vm.expectRevert(IHooksFactoryEventsAndErrors.MarketDeploymentAddressMismatch.selector);
      _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(model), flags);
      assertEq(
        vm.getNonce(address(_factoryFor(stack, options.marketKind))),
        nonce,
        'CREATE2 not reached'
      );
      vm.etch(secondary, original);
      MatrixCell memory cell = _deployMatrixCell(
        stack,
        options,
        MatrixBorrower,
        MatrixBorrower,
        uint96(model),
        flags
      );
      assertEq(
        cell.market.factory(),
        address(_factoryFor(stack, options.marketKind)),
        'reverted callback rolled back'
      );
    }
  }

  function test_factoryRejectsChangedApprovedHookArtifact() external {
    ProductionStack memory stack = _deployProductionStack();
    address template = stack.hooksTemplates[0];
    bytes memory original = template.code;
    bytes memory corrupted = bytes.concat(original);
    corrupted[type(SplitInitCodeReader).runtimeCode.length] ^= 0x01;
    vm.etch(template, corrupted);
    for (uint256 model; model < 2; ++model) {
      vm.prank(MatrixBorrower);
      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateInitCodeHashMismatch.selector);
      _factoryFor(stack, MatrixMarketKind(model)).deployHooksInstance(template, '');
    }
    vm.etch(template, original);
  }
}

/// @dev real-limit deployments only. no etched or substituted market/store runtime.
contract SplitStorageDeploymentTest is SplitStorageFixture {
  function test_realLimits_SixProductionAndSixComposedMarkets() external {
    ProductionStack memory stack = _deployProductionStack();
    assertEq(storageContracts, 10, 'two markets and three templates, two stores each');
    for (uint256 model; model < 2; ++model) {
      for (uint256 policy; policy < 3; ++policy) {
        _exercise(
          stack,
          MatrixMarketKind(model),
          MatrixHooksKind(policy),
          uint96(1 + model * 3 + policy)
        );
      }
    }
    string[3] memory artifacts = [
      'test/mocks/TransferFeatureHooks.sol:PeriodicTransferHooks',
      'test/mocks/BorrowFeatureHooks.sol:PeriodicBorrowHooks',
      'test/mocks/AprReplacementHooks.sol:PeriodicAprReplacementHooks'
    ];
    for (uint256 feature; feature < 3; ++feature) {
      (address store, uint256 hash) = _storeInitCode(artifacts[feature]);
      stack.hooksTemplates[2] = store;
      stack.standardFactory.addHooksTemplate(
        store,
        'composed',
        address(0),
        address(0),
        0,
        0,
        bytes32(hash)
      );
      stack.revolvingFactory.addHooksTemplate(
        store,
        'composed',
        address(0),
        address(0),
        0,
        0,
        bytes32(hash)
      );
      for (uint256 model; model < 2; ++model) {
        _exercise(
          stack,
          MatrixMarketKind(model),
          MatrixHooksKind.PeriodicTerm,
          uint96(10 + feature * 2 + model)
        );
      }
    }
    assertEq(storageContracts, 16, 'exactly eight pairs');
  }

  function _exercise(
    ProductionStack memory stack,
    MatrixMarketKind model,
    MatrixHooksKind policy,
    uint96 nonce
  ) private {
    MatrixOptions memory options = _defaultMatrixOptions(policy, model);
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 90 days);
    options.repaymentPeriod = 7 days;
    MatrixCell memory cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    assertEq(
      address(cell.market),
      _factoryFor(stack, model).computeMarketAddress(_marketSalt(MatrixBorrower, nonce)),
      'original CREATE2 hash'
    );
    assertEq(cell.market.factory(), address(_factoryFor(stack, model)), 'factory context');
    assertEq(cell.market.repaymentDate(), options.repaymentDate, 'repayment terms');
    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 10_000e18);
    _borrow(cell, 1_000e18);
    _approveBorrower(stack, cell, 1_000e18);
    _repay(cell, 1_000e18);
    vm.warp(options.repaymentDate);
    uint256 owed = cell.market.totalDebts() - cell.market.totalAssets();
    _approveBorrower(stack, cell, owed);
    _repay(cell, owed);
    assertTrue(cell.market.isClosed(), 'scheduled closure');
    assertEq(cell.market.defaultedAt(), 0, 'on-time repayment');
  }
}

contract SplitStorageParityTest is ProductionMatrixFixture {
  // keep the E23 compression control explicit now that the shared fixture uses split storage.
  function _storeInitCode(
    string memory artifact
  ) internal override returns (address store, uint256 hash) {
    bytes memory original = vm.getCode(artifact);
    store = original.length <= 24_575
      ? LibStoredInitCode.deployInitCode(original)
      : LibCompressedInitCode.deployInitCode(original);
    return (store, uint256(keccak256(original)));
  }

  struct Observation {
    address market;
    address hooks;
    bytes32 marketRuntime;
    bytes32 hooksRuntime;
    bytes32 state;
    bytes32 logs;
  }

  function _observe(
    ProductionStack memory stack,
    MatrixOptions memory options,
    uint96 nonce
  ) private returns (Observation memory result) {
    vm.recordLogs();
    MatrixCell memory cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    result = Observation(
      address(cell.market),
      address(cell.hooks),
      address(cell.market).codehash,
      address(cell.hooks).codehash,
      keccak256(abi.encode(cell.market.previousState())),
      keccak256(abi.encode(vm.getRecordedLogs()))
    );
  }

  function test_sameInitializedRuntimeStateEventsAndAddresses() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 model; model < 2; ++model) {
      for (uint256 policy; policy < 3; ++policy) {
        MatrixOptions memory options = _defaultMatrixOptions(
          MatrixHooksKind(policy),
          MatrixMarketKind(model)
        );
        options.repaymentDate = uint32(vm.getBlockTimestamp() + 90 days);
        options.repaymentPeriod = 7 days;
        uint256 snapshot = vm.snapshot();
        Observation memory compressed = _observe(stack, options, uint96(100 + model * 3 + policy));
        assertTrue(vm.revertToAndDelete(snapshot));
        address marketStore = _factoryFor(stack, options.marketKind).marketInitCodeStorage();
        address template = stack.hooksTemplates[policy];
        bytes memory savedMarket = marketStore.code;
        bytes memory savedTemplate = template.code;
        (address splitMarket, ) = LibSplitInitCode.deployInitCode(
          LibStoredInitCode.getInitCode(marketStore)
        );
        (address splitTemplate, ) = LibSplitInitCode.deployInitCode(
          LibStoredInitCode.getInitCode(template)
        );
        // hold every address fixed to compare all immutable bytes and events too.
        // strict deployment coverage is separate and never etches code.
        vm.etch(marketStore, splitMarket.code);
        vm.etch(template, splitTemplate.code);
        Observation memory split = _observe(stack, options, uint96(100 + model * 3 + policy));
        assertEq(abi.encode(split), abi.encode(compressed), 'complete deployment parity');
        vm.etch(marketStore, savedMarket);
        vm.etch(template, savedTemplate);
      }
    }
  }

  function test_exportPreparedComparisonArtifacts() external {
    string[5] memory names = [
      'WildcatMarket',
      'WildcatMarketRevolving',
      'PeriodicTransferHooks',
      'PeriodicBorrowHooks',
      'PeriodicAprReplacementHooks'
    ];
    string[5] memory paths = [
      'src/market/WildcatMarket.sol:WildcatMarket',
      'src/market/WildcatMarketRevolving.sol:WildcatMarketRevolving',
      'test/mocks/TransferFeatureHooks.sol:PeriodicTransferHooks',
      'test/mocks/BorrowFeatureHooks.sol:PeriodicBorrowHooks',
      'test/mocks/AprReplacementHooks.sol:PeriodicAprReplacementHooks'
    ];
    string memory output;
    for (uint256 i; i < names.length; ++i) {
      bytes memory original = vm.getCode(paths[i]);
      vm.serializeBytes('split-comparison', string.concat(names[i], '_creation'), original);
      vm.serializeBytes(
        'split-comparison',
        string.concat(names[i], '_compressed'),
        LibCompressedInitCode.getStorageRuntime(original)
      );
      vm.serializeBytes(
        'split-comparison',
        string.concat(names[i], '_secondary'),
        LibSplitInitCode.getSecondaryRuntime(original)
      );
      output = vm.serializeBytes(
        'split-comparison',
        string.concat(names[i], '_primaryZeroAddress'),
        LibSplitInitCode.getPrimaryRuntime(original, address(0))
      );
    }
    vm.writeJson(output, 'deploy-out/split-comparison.json');
  }
}
