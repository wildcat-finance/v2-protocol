// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // LibStoredInitCodeExternal
//  \ ^ /   Stored-initcode deployment adapters and constructor probes.
//    V
//
//  INITCODE STORAGE
//  deployInitCode(...)
//
//  CREATE DEPLOYMENT
//  createWithStoredInitCode(...)
//  createWithStoredInitCode(...)
//
//  CREATE2 ADDRESSES
//  getCreate2Prefix(...)
//  calculateCreate2Address(...)
//
//  CREATE2 DEPLOYMENT
//  create2WithStoredInitCode(...)
//  create2WithStoredInitCode(...)
//  create2WithStoredInitCode(...)
//  create2WithStoredInitCodeCD(...)
//
//  CONSTRUCTOR PARAMETERS
//  getContractParameters()
//
//  CONSTRUCTOR PROBE
//  constructor()
//  getValue()
// ═════

import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';

// ┌─ LibStoredInitCodeExternal ────────────────────────────────────────────────
contract LibStoredInitCodeExternal {
  uint256 public immutable getContractParameters = 123;

  // ░░▒▒▓▓██ [ INITCODE STORAGE ] ─────────────────────────────────────────────

  // ┌─ deployInitCode ─────
  function deployInitCode(bytes memory data) external returns (address initCodeStorage) {
    return LibStoredInitCode.deployInitCode(data);
  }

  // ░░▒▒▓▓██ [ CREATE DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ createWithStoredInitCode ─────
  function createWithStoredInitCode(address initCodeStorage) external returns (address deployment) {
    return LibStoredInitCode.createWithStoredInitCode(initCodeStorage);
  }

  // ┌─ createWithStoredInitCode ─────
  function createWithStoredInitCode(address initCodeStorage, uint256 value) external returns (address deployment) {
    return LibStoredInitCode.createWithStoredInitCode(initCodeStorage, value);
  }

  // ░░▒▒▓▓██ [ CREATE2 ADDRESSES ] ────────────────────────────────────────────

  // ┌─ getCreate2Prefix ─────
  /// @dev return the CREATE2 prefix for a given deployer address.
  /// equivalent to `uint256(uint160(deployer)) | (0xff << 160)`
  function getCreate2Prefix(address deployer) external pure returns (uint256 create2Prefix) {
    return LibStoredInitCode.getCreate2Prefix(deployer);
  }

  // ┌─ calculateCreate2Address ─────
  function calculateCreate2Address(
    uint256 create2Prefix,
    bytes32 salt,
    uint256 initCodeHash
  )
    external
    pure
    returns (address create2Address)
  {
    return LibStoredInitCode.calculateCreate2Address(create2Prefix, salt, initCodeHash);
  }

  // ░░▒▒▓▓██ [ CREATE2 DEPLOYMENT ] ───────────────────────────────────────────

  // ┌─ create2WithStoredInitCode ─────
  function create2WithStoredInitCode(address initCodeStorage, bytes32 salt) external returns (address deployment) {
    return LibStoredInitCode.create2WithStoredInitCode(initCodeStorage, salt);
  }

  // ┌─ create2WithStoredInitCode ─────
  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    uint256 value
  )
    external
    returns (address deployment)
  {
    return LibStoredInitCode.create2WithStoredInitCode(initCodeStorage, salt, value);
  }

  // ┌─ create2WithStoredInitCode ─────
  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    bytes memory constructorArgs
  )
    external
    returns (address deployment)
  {
    return LibStoredInitCode.create2WithStoredInitCode(initCodeStorage, salt, constructorArgs);
  }

  // ┌─ create2WithStoredInitCodeCD ─────
  function create2WithStoredInitCodeCD(
    address initCodeStorage,
    bytes32 salt,
    bytes calldata constructorArgs
  )
    external
    returns (address deployment)
  {
    return LibStoredInitCode.create2WithStoredInitCodeCD(initCodeStorage, salt, constructorArgs);
  }
}

// ┌─ ITestDeployer ────────────────────────────────────────────────────────────
interface ITestDeployer {
  // ░░▒▒▓▓██ [ CONSTRUCTOR PARAMETERS ] ───────────────────────────────────────

  // ┌─ getContractParameters ─────
  function getContractParameters() external view returns (uint256);
}

// ┌─ TestContract ─────────────────────────────────────────────────────────────
contract TestContract {
  uint256 internal immutable x;

  // ░░▒▒▓▓██ [ CONSTRUCTOR PROBE ] ────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() payable {
    x = ITestDeployer(msg.sender).getContractParameters();
  }

  // ┌─ getValue ─────
  function getValue() external view returns (uint256) {
    return x;
  }
}
