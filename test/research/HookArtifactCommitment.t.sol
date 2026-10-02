// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // HookArtifactCommitment.t
//  \ ^ /   Hook artifact commitments at registration and deployment.
//    V
//
//  MUTABLE CODE TARGET
//  setCode(...)
//  fallback()
//
//  FIXTURE
//  setUp()
//  _register(...)
//
//  ARTIFACT REGISTRATION
//  test_registrationCommitsArtifactForRawAndCompressedStores()
//  testFuzz_registrationRejectsWrongHashWithoutWritingState(...)
//  test_registrationRequiresTheNewHashArgument()
//
//  STANDALONE DEPLOYMENT INTEGRITY
//  test_changedDecodedBytesRejectedBeforeStandaloneConstructor()
//  test_readerChangingAfterRegistrationCannotDeployDifferentCode()
//  _expectStandaloneMismatch(...)
//
//  COMBINED DEPLOYMENT INTEGRITY
//  test_combinedDeploymentRejectsBeforeHookOrMarketAndCanRetry()
//  _combined(...)
// ═════

import './SingleStorageDeployment.t.sol';
import { IHooksFactory, IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';
import { IHooksFactoryRevolving } from 'src/IHooksFactoryRevolving.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';

// ┌─ MutableHookCodeReader ────────────────────────────────────────────────────
/// @dev registration can see correct bytes while later deployments get something else.
///      the supplied tooling rejects this reader; exercise the on-chain check without it.
contract MutableHookCodeReader {
  bytes internal _code;

  // ░░▒▒▓▓██ [ MUTABLE CODE TARGET ] ──────────────────────────────────────────

  // ┌─ setCode ─────
  function setCode(bytes memory code) external {
    _code = code;
  }

  // ┌─ fallback ─────
  fallback() external {
    bytes memory code = _code;
    assembly ('memory-safe') {
      return(add(code, 32), mload(code))
    }
  }
}

// ┌─ HookArtifactCommitmentTest ───────────────────────────────────────────────
contract HookArtifactCommitmentTest is SingleStorageDeploymentFixture {
  ProductionStack internal _stack;
  bytes internal _original;
  bytes32 internal _artifactHash;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    _stack = _deployProductionStack();
    _original = vm.getCode('src/access/OpenTermHooks.sol:OpenTermHooks');
    _artifactHash = keccak256(_original);
  }

  // ┌─ _register ─────
  function _register(IHooksFactory factory, address store, bytes32 expectedHash) internal {
    factory.addHooksTemplate(store, 'committed hook', address(0), address(0), 0, 0, expectedHash);
  }

  // ░░▒▒▓▓██ [ ARTIFACT REGISTRATION ] ────────────────────────────────────────

  // ┌─ test_registrationCommitsArtifactForRawAndCompressedStores ─────
  function test_registrationCommitsArtifactForRawAndCompressedStores() external {
    address[2] memory stores =
      [LibStoredInitCode.deployInitCode(_original), LibCompressedInitCode.deployInitCode(_original)];
    for (uint256 model; model < 2; ++model) {
      IHooksFactory factory = _factoryFor(_stack, MatrixMarketKind(model));
      for (uint256 format; format < stores.length; ++format) {
        address store = stores[format];
        assertEq(factory.getHooksTemplateInitCodeHash(store), bytes32(0));
        vm.expectEmit(address(factory));
        emit IHooksFactoryEventsAndErrors.HooksTemplateInitCodeHashRecorded(store, _artifactHash);
        _register(factory, store, _artifactHash);
        assertTrue(factory.isHooksTemplate(store));
        assertEq(factory.getHooksTemplateInitCodeHash(store), _artifactHash);
        vm.prank(MatrixBorrower);
        address instance = factory.deployHooksInstance(store, '');
        assertEq(factory.getHooksTemplateForInstance(instance), store);
        assertEq(factory.getHooksAdministrator(instance), MatrixBorrower);

        factory.updateHooksTemplateFees(store, MatrixAlice, address(0), 0, 100);
        factory.disableHooksTemplate(store);
        assertEq(factory.getHooksTemplateInitCodeHash(store), _artifactHash, 'fees and disable preserve the commitment');
        vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateAlreadyExists.selector);
        _register(factory, store, bytes32(uint256(_artifactHash) ^ 1));
      }
    }
  }

  // ┌─ testFuzz_registrationRejectsWrongHashWithoutWritingState ─────
  function testFuzz_registrationRejectsWrongHashWithoutWritingState(
    bytes32 wrongHash,
    bool compressed,
    bool revolving
  )
    external
  {
    if (wrongHash == _artifactHash) wrongHash = bytes32(uint256(wrongHash) ^ 1);
    IHooksFactory factory = _factoryFor(_stack, revolving ? MatrixMarketKind.Revolving : MatrixMarketKind.Standard);
    address store =
      compressed ? LibCompressedInitCode.deployInitCode(_original) : LibStoredInitCode.deployInitCode(_original);
    uint256 count = factory.getHooksTemplatesCount();
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateInitCodeHashMismatch.selector);
    _register(factory, store, wrongHash);
    assertFalse(factory.isHooksTemplate(store));
    assertEq(factory.getHooksTemplateInitCodeHash(store), bytes32(0));
    assertEq(factory.getHooksTemplatesCount(), count);
    // a rejected registration must not consume this template address.
    _register(factory, store, _artifactHash);
    assertEq(factory.getHooksTemplatesCount(), count + 1);
  }

  // ┌─ test_registrationRequiresTheNewHashArgument ─────
  function test_registrationRequiresTheNewHashArgument() external {
    address store = LibCompressedInitCode.deployInitCode(_original);
    for (uint256 model; model < 2; ++model) {
      IHooksFactory factory = _factoryFor(_stack, MatrixMarketKind(model));
      (bool success,) = address(factory)
        .call(
          abi.encodeWithSignature(
            'addHooksTemplate(address,string,address,address,uint80,uint16)',
            store,
            'unchecked',
            address(0),
            address(0),
            uint80(0),
            uint16(0)
          )
        );
      assertFalse(success, 'no unchecked registration overload');
      assertFalse(factory.isHooksTemplate(store));
      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateInitCodeHashMismatch.selector);
      _register(factory, store, bytes32(0));
    }
  }

  // ░░▒▒▓▓██ [ STANDALONE DEPLOYMENT INTEGRITY ] ──────────────────────────────

  // ┌─ test_changedDecodedBytesRejectedBeforeStandaloneConstructor ─────
  function test_changedDecodedBytesRejectedBeforeStandaloneConstructor() external {
    for (uint256 model; model < 2; ++model) {
      IHooksFactory factory = _factoryFor(_stack, MatrixMarketKind(model));
      address store = _stack.hooksTemplates[0];
      bytes memory saved = store.code;
      address wrong = LibCompressedInitCode.deployInitCode(hex'fe');
      vm.etch(store, wrong.code);
      _expectStandaloneMismatch(factory, store);
      vm.etch(store, saved);
      vm.prank(MatrixBorrower);
      address instance = factory.deployHooksInstance(store, '');
      assertEq(factory.getHooksTemplateForInstance(instance), store);
    }
  }

  // ┌─ test_readerChangingAfterRegistrationCannotDeployDifferentCode ─────
  function test_readerChangingAfterRegistrationCannotDeployDifferentCode() external {
    MutableHookCodeReader reader =
      MutableHookCodeReader(_deployCode('test/research/HookArtifactCommitment.t.sol:MutableHookCodeReader'));
    for (uint256 model; model < 2; ++model) {
      IHooksFactory factory = _factoryFor(_stack, MatrixMarketKind(model));
      reader.setCode(_original);
      _register(factory, address(reader), _artifactHash);
      reader.setCode(hex'fe');
      _expectStandaloneMismatch(factory, address(reader));
      reader.setCode(_original);
      vm.prank(MatrixBorrower);
      address instance = factory.deployHooksInstance(address(reader), '');
      assertEq(factory.getHooksTemplateForInstance(instance), address(reader));
    }
  }

  // ┌─ _expectStandaloneMismatch ─────
  function _expectStandaloneMismatch(IHooksFactory factory, address store) internal {
    uint64 creationNonce = vm.getNonce(address(factory));
    uint256 hookNonce = factory.getHooksInstanceDeploymentNonce(MatrixBorrower);
    uint256 count = factory.getHooksInstancesCountForAdministrator(MatrixBorrower);
    vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateInitCodeHashMismatch.selector);
    vm.prank(MatrixBorrower);
    factory.deployHooksInstance(store, '');
    assertEq(vm.getNonce(address(factory)), creationNonce);
    assertEq(factory.getHooksInstanceDeploymentNonce(MatrixBorrower), hookNonce);
    assertEq(factory.getHooksInstancesCountForAdministrator(MatrixBorrower), count);
    assertEq(factory.getHooksTemplateInitCodeHash(store), _artifactHash);
  }

  // ░░▒▒▓▓██ [ COMBINED DEPLOYMENT INTEGRITY ] ────────────────────────────────

  // ┌─ test_combinedDeploymentRejectsBeforeHookOrMarketAndCanRetry ─────
  function test_combinedDeploymentRejectsBeforeHookOrMarketAndCanRetry() external {
    for (uint256 kind; kind < 2; ++kind) {
      MatrixMarketKind model = MatrixMarketKind(kind);
      IHooksFactory factory = _factoryFor(_stack, model);
      address store = _stack.hooksTemplates[0];
      bytes memory saved = store.code;
      address wrong = LibCompressedInitCode.deployInitCode(hex'fe');
      vm.etch(store, wrong.code);
      bytes32 salt = _marketSalt(MatrixBorrower, uint96(700 + kind));
      address expectedMarket = factory.computeMarketAddress(salt);
      uint64 creationNonce = vm.getNonce(address(factory));
      uint256 hookNonce = factory.getHooksInstanceDeploymentNonce(MatrixBorrower);
      uint256 marketCount = factory.getMarketsForHooksTemplateCount(store);
      vm.expectRevert(IHooksFactoryEventsAndErrors.HooksTemplateInitCodeHashMismatch.selector);
      _combined(factory, model, store, salt);
      assertEq(expectedMarket.code.length, 0);
      assertEq(vm.getNonce(address(factory)), creationNonce);
      assertEq(factory.getHooksInstanceDeploymentNonce(MatrixBorrower), hookNonce);
      assertEq(factory.getHooksInstancesCountForAdministrator(MatrixBorrower), 0);
      assertEq(factory.getMarketsForHooksTemplateCount(store), marketCount);
      vm.etch(store, saved);
      (address market, address instance) = _combined(factory, model, store, salt);
      assertEq(market, expectedMarket);
      assertEq(factory.getHooksTemplateForInstance(instance), store);
      assertEq(factory.getMarketsForHooksTemplateCount(store), marketCount + 1);
    }
  }

  // ┌─ _combined ─────
  function _combined(
    IHooksFactory factory,
    MatrixMarketKind model,
    address store,
    bytes32 salt
  )
    internal
    returns (address market, address instance)
  {
    MatrixOptions memory options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, model);
    DeployMarketInputs memory inputs = _marketInputs(_stack, options, EmptyHooksConfig);
    bytes memory data = _hooksData(options, vm.getBlockTimestamp());
    vm.prank(MatrixBorrower);
    if (model == MatrixMarketKind.Standard) {
      return factory.deployMarketAndHooks(store, '', inputs, data, salt, address(0), 0);
    }
    return IHooksFactoryRevolving(address(factory))
      .deployMarketAndHooks(store, '', inputs, data, abi.encode(uint8(1), uint16(200)), salt, address(0), 0);
  }
}
