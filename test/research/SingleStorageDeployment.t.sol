// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';
import { LibCompressedInitCode } from 'src/libraries/LibCompressedInitCode.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { PeriodicTransferHooks } from '../mocks/TransferFeatureHooks.sol';
import { PeriodicBorrowHooks } from '../mocks/BorrowFeatureHooks.sol';
import { PeriodicAprReplacementHooks } from '../mocks/AprReplacementHooks.sol';

abstract contract SingleStorageDeploymentFixture is ProductionMatrixFixture {
  event log_named_uint(string key, uint256 value);

  uint256 internal _storageContracts;

  function _storeInitCode(
    string memory artifact
  ) internal override returns (address store, uint256 codeHash) {
    bytes memory initCode = vm.getCode(artifact);
    uint64 nonce = vm.getNonce(address(this));
    store = LibCompressedInitCode.deployInitCode(initCode);
    assertEq(vm.getNonce(address(this)), nonce + 1, 'one storage contract per payload');
    assertTrue(store.code.length <= 24_576, 'stored runtime fits');
    assertEq(LibStoredInitCode.getInitCode(store), initCode, 'exact creation-code round trip');
    codeHash = uint256(keccak256(initCode));
    _storageContracts++;
    emit log_named_uint(artifact, store.code.length);
  }
}

/// @dev run this suite with --code-size-limit 24576. no etching, oversized-code allowance,
///      substituted market runtime, or second storage contract is needed for these deployments.
contract SingleStorageDeploymentTest is SingleStorageDeploymentFixture {
  function test_realLimits_AllSixFactoryMarketCombinations() external {
    ProductionStack memory stack = _deployProductionStack();
    assertEq(_storageContracts, 5, 'two markets and three templates');
    for (uint256 model; model < 2; ++model) {
      for (uint256 policy; policy < 3; ++policy) {
        _exerciseCell(
          stack,
          MatrixMarketKind(model),
          MatrixHooksKind(policy),
          uint96(1 + model * 3 + policy)
        );
      }
    }
    assertEq(_storageContracts, 5, 'all deployments reuse the five single stores');
  }

  function test_realLimits_PeriodicFeatureCompositions() external {
    ProductionStack memory stack = _deployProductionStack();
    string[3] memory artifacts = [
      'test/mocks/TransferFeatureHooks.sol:PeriodicTransferHooks',
      'test/mocks/BorrowFeatureHooks.sol:PeriodicBorrowHooks',
      'test/mocks/AprReplacementHooks.sol:PeriodicAprReplacementHooks'
    ];
    for (uint256 feature; feature < artifacts.length; ++feature) {
      (address store, uint256 initCodeHash) = _storeInitCode(artifacts[feature]);
      stack.hooksTemplates[uint256(MatrixHooksKind.PeriodicTerm)] = store;
      stack.standardFactory.addHooksTemplate(
        store,
        'Periodic feature',
        address(0),
        address(0),
        0,
        0,
        bytes32(initCodeHash)
      );
      stack.revolvingFactory.addHooksTemplate(
        store,
        'Periodic feature',
        address(0),
        address(0),
        0,
        0,
        bytes32(initCodeHash)
      );
      for (uint256 model; model < 2; ++model) {
        _exerciseCell(
          stack,
          MatrixMarketKind(model),
          MatrixHooksKind.PeriodicTerm,
          uint96(10 + feature * 2 + model)
        );
      }
    }
    assertEq(_storageContracts, 8, 'five production stores plus one per composition');
  }

  function _exerciseCell(
    ProductionStack memory stack,
    MatrixMarketKind model,
    MatrixHooksKind policy,
    uint96 nonce
  ) internal {
    MatrixOptions memory options = _defaultMatrixOptions(policy, model);
    options.repaymentDate = uint32(vm.getBlockTimestamp() + 90 days);
    options.repaymentPeriod = 7 days;
    address expected = _factoryFor(stack, model).computeMarketAddress(
      _marketSalt(MatrixBorrower, nonce)
    );
    MatrixCell memory cell = _deployMatrixCell(
      stack,
      options,
      MatrixBorrower,
      MatrixBorrower,
      nonce
    );
    assertEq(address(cell.market), expected, 'CREATE2 uses the original initcode hash');
    assertTrue(address(cell.market).code.length <= 24_576, 'market runtime fits');
    assertTrue(address(cell.hooks).code.length <= 24_576, 'hook runtime fits');
    assertEq(cell.market.repaymentDate(), options.repaymentDate);
    assertEq(cell.market.factory(), address(_factoryFor(stack, model)), 'constructor context');

    _authorize(stack, cell, MatrixAlice);
    _deposit(stack, cell, MatrixAlice, 10_000e18);
    _borrow(cell, 1_000e18);
    _approveBorrower(stack, cell, 1_000e18);
    _repay(cell, 1_000e18);
    assertEq(cell.market.totalAssets(), 10_000e18);

    vm.warp(options.repaymentDate);
    uint256 remaining = cell.market.totalDebts() - cell.market.totalAssets();
    _approveBorrower(stack, cell, remaining);
    _repay(cell, remaining);
    assertTrue(cell.market.isClosed(), 'fully funded scheduled repayment closes');
    assertEq(cell.market.defaultedAt(), 0, 'on-time repayment does not default');
    assertEq(cell.market.borrowableAssets(), 0);
  }
}
