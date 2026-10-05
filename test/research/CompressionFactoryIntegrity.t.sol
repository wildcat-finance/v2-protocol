// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // CompressionFactoryIntegrity.t
//  \ ^ /   Raw and compressed factory deployment integrity comparisons.
//    V
//
//  DEPLOYMENT PARITY
//  test_rawAndCompressedFactoryDeploymentsAreByteExact()
//  _observe(...)
//
//  WRONG CODE REJECTION
//  test_wrongCodeRejectedBeforeConstructorForBothFactories()
//  _rejectWrongCode(...)
//
//  CONSTRUCTOR PROBE
//  constructor(...)
//
//  FIXTURE
//  setUp()
//
//  CONSTRUCTOR ARGUMENTS
//  testFuzz_factoryConstructorArgumentsAndAddress(...)
//  _checkArguments(...)
// ═════

import { SingleStorageDeploymentFixture } from './SingleStorageDeployment.t.sol';
import { IHooksFactory, IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';
import { LibCompressedInitCode } from 'src/libraries/LibCompressedInitCode.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { HooksConfig, HooksDeploymentConfig } from 'src/types/HooksConfig.sol';

// ┌─ CompressionFactoryIntegrityTest ──────────────────────────────────────────
contract CompressionFactoryIntegrityTest is SingleStorageDeploymentFixture {
  struct DeploymentObservation {
    address market;
    address hooks;
    bytes32 marketRuntime;
    bytes32 hookRuntime;
    bytes32 marketState;
    bytes32 logs;
  }

  struct RejectedDeployment {
    IHooksFactory factory;
    address store;
    bytes original;
    address hooks;
    HooksConfig flags;
    bytes32 salt;
    address expected;
    uint64 nonce;
  }

  // ░░▒▒▓▓██ [ DEPLOYMENT PARITY ] ────────────────────────────────────────────

  // ┌─ test_rawAndCompressedFactoryDeploymentsAreByteExact ─────
  function test_rawAndCompressedFactoryDeploymentsAreByteExact() external {
    ProductionStack memory stack = _deployProductionStack();
    for (uint256 model; model < 2; ++model) {
      for (uint256 policy; policy < 3; ++policy) {
        MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind(policy), MatrixMarketKind(model));
        options.repaymentDate = uint32(vm.getBlockTimestamp() + 90 days);
        options.repaymentPeriod = 7 days;
        uint256 snapshot = vm.snapshot();
        DeploymentObservation memory compressed = _observe(stack, options, uint96(100 + model * 3 + policy));
        assertTrue(vm.revertToAndDelete(snapshot));
        // keep addresses and immutables identical. the raw oracle is deliberately etched:
        // market initcode exceeds the raw storage cap. the separate real-limit tests never etch.
        address marketStore = _factoryFor(stack, options.marketKind).marketInitCodeStorage();
        bytes memory savedMarketStore = marketStore.code;
        address template = stack.hooksTemplates[policy];
        bytes memory savedTemplate = template.code;
        vm.etch(marketStore, bytes.concat(hex'00', LibStoredInitCode.getInitCode(marketStore)));
        vm.etch(template, bytes.concat(hex'00', LibStoredInitCode.getInitCode(template)));
        DeploymentObservation memory raw = _observe(stack, options, uint96(100 + model * 3 + policy));
        assertEq(abi.encode(raw), abi.encode(compressed), 'same addresses, runtimes, initial state and events');
        vm.etch(marketStore, savedMarketStore);
        vm.etch(template, savedTemplate);
      }
    }
  }

  // ┌─ _observe ─────
  function _observe(
    ProductionStack memory stack,
    MatrixOptions memory options,
    uint96 nonce
  )
    internal
    returns (DeploymentObservation memory result)
  {
    vm.recordLogs();
    MatrixCell memory cell = _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, nonce);
    result.market = address(cell.market);
    result.hooks = address(cell.hooks);
    result.marketRuntime = result.market.codehash;
    result.hookRuntime = result.hooks.codehash;
    result.marketState = keccak256(abi.encode(cell.market.previousState()));
    result.logs = keccak256(abi.encode(vm.getRecordedLogs()));
  }

  // ░░▒▒▓▓██ [ WRONG CODE REJECTION ] ─────────────────────────────────────────

  // ┌─ test_wrongCodeRejectedBeforeConstructorForBothFactories ─────
  function test_wrongCodeRejectedBeforeConstructorForBothFactories() external {
    ProductionStack memory stack = _deployProductionStack();
    _rejectWrongCode(stack, MatrixMarketKind.Standard);
    _rejectWrongCode(stack, MatrixMarketKind.Revolving);
  }

  // ┌─ _rejectWrongCode ─────
  function _rejectWrongCode(ProductionStack memory stack, MatrixMarketKind model) internal {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, model);
    RejectedDeployment memory attempt;
    attempt.factory = _factoryFor(stack, model);
    attempt.store = attempt.factory.marketInitCodeStorage();
    attempt.original = attempt.store.code;
    // INVALID would fail inside CREATE2 with DeploymentFailed if the hash were checked later.
    address wrongStore = LibCompressedInitCode.deployInitCode(hex'fe');
    vm.etch(attempt.store, wrongStore.code);
    vm.prank(MatrixBorrower);
    attempt.hooks = attempt.factory.deployHooksInstance(stack.hooksTemplates[0], '');
    HooksDeploymentConfig config = IHooks(attempt.hooks).config();
    attempt.flags = config.optionalFlags().setHooksAddress(attempt.hooks).mergeAllFlags(config.requiredFlags());
    attempt.salt = _marketSalt(MatrixBorrower, uint96(500 + uint256(model)));
    attempt.expected = attempt.factory.computeMarketAddress(attempt.salt);
    attempt.nonce = vm.getNonce(address(attempt.factory));
    vm.expectRevert(IHooksFactoryEventsAndErrors.MarketDeploymentAddressMismatch.selector);
    _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(500 + uint256(model)), attempt.flags);
    assertEq(attempt.expected.code.length, 0);
    assertEq(vm.getNonce(address(attempt.factory)), attempt.nonce, 'failed deployment rolls back nonce');
    assertEq(attempt.factory.getMarketsForHooksInstance(attempt.hooks).length, 0, 'registration rolls back');
    vm.etch(attempt.store, attempt.original);
    // the reverted onCreateMarket callback must not poison the next valid deployment.
    MatrixCell memory recovered =
      _deployMatrixCell(stack, options, MatrixBorrower, MatrixBorrower, uint96(500 + uint256(model)), attempt.flags);
    assertEq(address(recovered.market), attempt.expected);
  }
}

// ┌─ CompressionHookConstructorProbe ──────────────────────────────────────────
contract CompressionHookConstructorProbe {
  address public immutable factory;
  address public immutable administrator;
  bytes32 public immutable dataHash;
  uint256 public immutable dataLength;

  // ░░▒▒▓▓██ [ CONSTRUCTOR PROBE ] ────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address administrator_, bytes memory data) {
    factory = msg.sender;
    administrator = administrator_;
    dataHash = keccak256(data);
    dataLength = data.length;
  }
}

// ┌─ CompressionHookArgsTest ──────────────────────────────────────────────────
contract CompressionHookArgsTest is SingleStorageDeploymentFixture {
  ProductionStack internal _stack;
  address internal _probeStore;
  bytes internal _probeCode;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    _stack = _deployProductionStack();
    _probeCode = vm.getCode('test/research/CompressionFactoryIntegrity.t.sol:CompressionHookConstructorProbe');
    _probeStore = LibCompressedInitCode.deployInitCode(_probeCode);
    _stack.standardFactory
      .addHooksTemplate(_probeStore, 'constructor probe', address(0), address(0), 0, 0, keccak256(_probeCode));
    _stack.revolvingFactory
      .addHooksTemplate(_probeStore, 'constructor probe', address(0), address(0), 0, 0, keccak256(_probeCode));
  }

  // ░░▒▒▓▓██ [ CONSTRUCTOR ARGUMENTS ] ────────────────────────────────────────

  // ┌─ testFuzz_factoryConstructorArgumentsAndAddress ─────
  function testFuzz_factoryConstructorArgumentsAndAddress(bytes memory data) external {
    ProductionStack memory stack = _stack;
    _checkArguments(_factoryFor(stack, MatrixMarketKind.Standard), data);
    _checkArguments(_factoryFor(stack, MatrixMarketKind.Revolving), data);
  }

  // ┌─ _checkArguments ─────
  function _checkArguments(IHooksFactory factory, bytes memory data) internal {
    uint256 nonce = factory.getHooksInstanceDeploymentNonce(MatrixBorrower);
    bytes32 salt = bytes32((uint256(uint160(MatrixBorrower)) << 96) | nonce);
    // the factory appends the administrator, offset, byte length and exact bytes without
    // padding the final word. keep that existing CREATE2 identity at every data length.
    bytes32 initHash = keccak256(bytes.concat(_probeCode, abi.encode(MatrixBorrower, uint256(64), data.length), data));
    address expected = address(uint160(uint256(keccak256(abi.encodePacked(hex'ff', address(factory), salt, initHash)))));
    uint256 snapshot = vm.snapshot();
    vm.prank(MatrixBorrower);
    address compressed = factory.deployHooksInstance(_probeStore, data);
    assertEq(compressed, expected);
    bytes32 runtimeHash = compressed.codehash;
    CompressionHookConstructorProbe probe = CompressionHookConstructorProbe(compressed);
    assertEq(probe.factory(), address(factory));
    assertEq(probe.administrator(), MatrixBorrower);
    assertEq(probe.dataHash(), keccak256(data));
    assertEq(probe.dataLength(), data.length);
    assertTrue(vm.revertToAndDelete(snapshot));
    bytes memory saved = _probeStore.code;
    vm.etch(_probeStore, bytes.concat(hex'00', _probeCode));
    vm.prank(MatrixBorrower);
    address raw = factory.deployHooksInstance(_probeStore, data);
    assertEq(raw, expected);
    assertEq(raw.codehash, runtimeHash);
    vm.etch(_probeStore, saved);
  }
}
