// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // LibStoredInitCode.t
// ║  ██▀▀     ▀▀██   Stored-initcode construction, address, and deployment tests.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  FAILED CONSTRUCTION
// ║  constructor()
// ║
// ║  FIXTURE
// ║  setUp()
// ║
// ║  INITCODE STORAGE
// ║  test_deployInitCode(...)
// ║  test_deployInitCode()
// ║  test_deployInitCode_InitCodeDeploymentFailed()
// ║
// ║  CREATE DEPLOYMENT
// ║  test_createWithStoredInitCode()
// ║  test_createWithStoredInitCode_WithValue()
// ║  test_createWithStoredInitCode_DeploymentFailed()
// ║
// ║  CREATE2 ADDRESSES
// ║  test_getCreate2Prefix(...)
// ║  test_getCreate2Prefix()
// ║  test_calculateCreate2Address(...)
// ║  test_calculateCreate2Address()
// ║
// ║  CREATE2 DEPLOYMENT
// ║  test_create2WithStoredInitCode(...)
// ║  test_create2WithStoredInitCode_DeploymentFailed(...)
// ║  test_create2WithStoredInitCode_WithValue(...)
// ║  test_create2WithStoredInitCodeCD_DeploymentFailed(...)
// ║  test_create2WithStoredInitCode_MemoryConstructorArgs(...)
// ╚═════

import './wrappers/LibStoredInitCodeExternal.sol';
import { TestKernel } from '../shared/TestKernel.sol';

// ┌─ Undeployable ─────────────────────────────────────────────────────────────
contract Undeployable {
  // ░░▒▒▓▓██ [ FAILED CONSTRUCTION ] ──────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() {
    assembly {
      revert(0, 0)
    }
  }
}

// ┌─ LibStoredInitCodeTest ────────────────────────────────────────────────────
contract LibStoredInitCodeTest is TestKernel {
  LibStoredInitCodeExternal internal lib;

  uint256 public immutable getContractParameters = 123;

  // ░░▒▒▓▓██ [ FIXTURE ] ──────────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    lib = LibStoredInitCodeExternal(
      _deployCode('test/libraries/wrappers/LibStoredInitCodeExternal.sol:LibStoredInitCodeExternal')
    );
  }

  // ░░▒▒▓▓██ [ INITCODE STORAGE ] ─────────────────────────────────────────────

  // ┌─ test_deployInitCode ─────
  function test_deployInitCode(bytes memory data) external {
    vm.assume(data.length < 30_000);
    address deployed = lib.deployInitCode(data);
    assertEq(deployed.codehash, keccak256(abi.encodePacked(uint8(0x00), data)));
  }

  // ┌─ test_deployInitCode ─────
  function test_deployInitCode() external {
    bytes memory data = hex'aabbccddeeff';
    address deployed = lib.deployInitCode(data);
    assertEq(deployed.codehash, keccak256(abi.encodePacked(uint8(0x00), data)));
  }

  // ┌─ test_deployInitCode_InitCodeDeploymentFailed ─────
  function test_deployInitCode_InitCodeDeploymentFailed() external {
    bytes memory data = new bytes(24_576);
    vm.expectRevert(LibStoredInitCode.InitCodeDeploymentFailed.selector);
    lib.deployInitCode{ gas: 24_576 * 200 }(data);
  }

  // ░░▒▒▓▓██ [ CREATE DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ test_createWithStoredInitCode ─────
  function test_createWithStoredInitCode() external {
    address initCodeStorage = lib.deployInitCode(type(TestContract).creationCode);
    address deployed = lib.createWithStoredInitCode(initCodeStorage, 0);
    assertEq(deployed.codehash, address(new TestContract()).codehash);
  }

  // ┌─ test_createWithStoredInitCode_WithValue ─────
  function test_createWithStoredInitCode_WithValue() external {
    vm.deal(address(lib), 1e18);
    address initCodeStorage = lib.deployInitCode(type(TestContract).creationCode);
    address deployed = lib.createWithStoredInitCode(initCodeStorage, 1e18);
    assertEq(deployed.codehash, address(new TestContract()).codehash);
    assertEq(deployed.balance, 1e18);
  }

  // ┌─ test_createWithStoredInitCode_DeploymentFailed ─────
  function test_createWithStoredInitCode_DeploymentFailed() external {
    address initCodeStorage = lib.deployInitCode(type(Undeployable).creationCode);

    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    lib.createWithStoredInitCode(initCodeStorage);
  }

  // ░░▒▒▓▓██ [ CREATE2 ADDRESSES ] ────────────────────────────────────────────

  // ┌─ test_getCreate2Prefix ─────
  function test_getCreate2Prefix(address deployer) external view {
    assertEq(lib.getCreate2Prefix(deployer), uint256(uint160(deployer)) | (0xff << 160));
  }

  // ┌─ test_getCreate2Prefix ─────
  function test_getCreate2Prefix() external view {
    address deployer = 0x1111111111111111111111111111111111111111;
    assertEq(lib.getCreate2Prefix(deployer), 0xff1111111111111111111111111111111111111111);
  }

  // ┌─ test_calculateCreate2Address ─────
  function test_calculateCreate2Address(uint256 create2Prefix, bytes32 salt, uint256 initCodeHash) external view {
    assertEq(
      lib.calculateCreate2Address(create2Prefix, salt, initCodeHash),
      address(uint160(uint256(keccak256(abi.encodePacked(uint168(create2Prefix), salt, initCodeHash)))))
    );
  }

  // ┌─ test_calculateCreate2Address ─────
  function test_calculateCreate2Address() external {
    uint256 create2Prefix = lib.getCreate2Prefix(address(this));
    bytes32 salt = keccak256('salt');
    uint256 initCodeHash = uint256(keccak256(type(TestContract).creationCode));
    address actual = address(new TestContract{ salt: salt }());
    assertEq(lib.calculateCreate2Address(create2Prefix, salt, initCodeHash), actual);
  }

  // ░░▒▒▓▓██ [ CREATE2 DEPLOYMENT ] ───────────────────────────────────────────

  // ┌─ test_create2WithStoredInitCode ─────
  function test_create2WithStoredInitCode(bytes32 salt) external {
    uint256 create2Prefix = lib.getCreate2Prefix(address(lib));
    address initCodeStorage = lib.deployInitCode(type(TestContract).creationCode);
    uint256 initCodeHash = uint256(keccak256(type(TestContract).creationCode));

    address deployed = lib.create2WithStoredInitCode(initCodeStorage, salt);
    assertEq(deployed.codehash, address(new TestContract()).codehash, 'codehash');
    assertEq(deployed.balance, 0, 'balance');
    assertEq(
      deployed, address(uint160(uint256(keccak256(abi.encodePacked(uint168(create2Prefix), salt, initCodeHash)))))
    );
  }

  // ┌─ test_create2WithStoredInitCode_DeploymentFailed ─────
  function test_create2WithStoredInitCode_DeploymentFailed(bytes32 salt) external {
    address initCodeStorage = lib.deployInitCode(type(TestContract).creationCode);

    lib.create2WithStoredInitCode(initCodeStorage, salt);
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    lib.create2WithStoredInitCode(initCodeStorage, salt);
  }

  // ┌─ test_create2WithStoredInitCode_WithValue ─────
  function test_create2WithStoredInitCode_WithValue(bytes32 salt) external {
    vm.deal(address(lib), 1e18);
    uint256 create2Prefix = lib.getCreate2Prefix(address(lib));
    address initCodeStorage = lib.deployInitCode(type(TestContract).creationCode);
    uint256 initCodeHash = uint256(keccak256(type(TestContract).creationCode));

    address deployed = lib.create2WithStoredInitCode(initCodeStorage, salt, 1e18);
    assertEq(deployed.codehash, address(new TestContract()).codehash, 'codehash');
    assertEq(deployed.balance, 1e18, 'balance');
    assertEq(
      deployed, address(uint160(uint256(keccak256(abi.encodePacked(uint168(create2Prefix), salt, initCodeHash)))))
    );
  }

  // ┌─ test_create2WithStoredInitCodeCD_DeploymentFailed ─────
  function test_create2WithStoredInitCodeCD_DeploymentFailed(bytes32 salt) external {
    address initCodeStorage = lib.deployInitCode(type(TestContract).creationCode);

    lib.create2WithStoredInitCodeCD(initCodeStorage, salt, '');
    vm.expectRevert(LibStoredInitCode.DeploymentFailed.selector);
    lib.create2WithStoredInitCodeCD(initCodeStorage, salt, '');
  }

  // ┌─ test_create2WithStoredInitCode_MemoryConstructorArgs ─────
  function test_create2WithStoredInitCode_MemoryConstructorArgs(bytes32 salt) external {
    address initCodeStorage = lib.deployInitCode(type(TestContract).creationCode);
    bytes memory constructorArgs = hex'aabbccdd';

    address deployed = lib.create2WithStoredInitCode(initCodeStorage, salt, constructorArgs);

    assertEq(deployed.codehash, address(new TestContract()).codehash, 'codehash');
    assertEq(TestContract(deployed).getValue(), getContractParameters, 'immutable value');
  }
}
