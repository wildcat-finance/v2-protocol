// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice deploys raw code storage and reads either raw or executable init-code stores.
library LibStoredInitCode {
  /// @notice deploying the inert init-code storage contract failed.
  error InitCodeDeploymentFailed();

  /// @notice CREATE or CREATE2 using stored init code failed.
  error DeploymentFailed();

  /// @notice deploys `data` as inert runtime code and returns its storage contract.
  /// @dev runtime code is `STOP || data`; deployment helpers skip the leading byte.
  function deployInitCode(bytes memory data) internal returns (address initCodeStorage) {
    assembly ('memory-safe') {
      let size := mload(data)
      let createSize := add(size, 0x0b)
      // Prefix code
      //
      // The creation program returns one extra byte: a leading STOP followed
      // by `data`. The STOP makes the storage contract inert if somebody calls
      // it directly. The deployment helpers below skip that byte when they
      // copy the stored init code back into memory.
      //
      // CODECOPY starts at byte 10 of this creation program. Byte 10 is the
      // STOP, and the original `data` begins immediately after it.
      //
      // Instruction                | Stack
      // ----------------------------------------------------------------
      // PUSH2 size + 1             | size + 1                     |
      // PUSH0                      | 0, size + 1                  |
      // DUP2                       | size + 1, 0, size + 1        |
      // PUSH1 10 (offset to STOP)  | 10, size + 1, 0, size + 1    |
      // PUSH0                      | 0, 10, size + 1, 0, size + 1 |
      // CODECOPY                   | 0, size + 1                  |
      // RETURN                     |                              |
      // STOP                       |                              |
      // ----------------------------------------------------------------

      // Put size + 1 into the PUSH2 immediate because the returned runtime
      // includes the leading STOP.
      // Reuse `data.length` memory for the create prefix to avoid
      // unnecessary memory allocation.
      mstore(data, or(shl(64, add(size, 1)), 0x6100005f81600a5f39f300))
      // Deploy the code storage
      initCodeStorage := create(0, add(data, 21), createSize)
      // if (initCodeStorage == address(0)) revert InitCodeDeploymentFailed();
      if iszero(initCodeStorage) {
        mstore(0, 0x11c8c3c0)
        revert(0x1c, 0x04)
      }
      // Restore `data.length`
      mstore(data, size)
    }
  }

  /// @dev raw stores start with STOP. executable stores return the original creation bytes
  ///      on STATICCALL, so compression stays inside that one storage contract. CREATE2 still
  ///      hashes the original init code, and old raw stores keep their existing format.
  ///      registration tooling must authenticate the stored runtime against the artifact;
  ///      a successful STATICCALL alone does not establish what code the reader will return.
  function getInitCode(address initCodeStorage) internal view returns (bytes memory initCode) {
    assembly ('memory-safe') {
      let size := extcodesize(initCodeStorage)
      if iszero(size) {
        mstore(0, 0x30116425) // DeploymentFailed()
        revert(0x1c, 4)
      }
      initCode := mload(0x40)
      let data := add(initCode, 0x20)
      extcodecopy(initCodeStorage, 0, 0, 1)
      switch byte(0, mload(0))
      case 0 {
        size := sub(size, 1)
        extcodecopy(initCodeStorage, data, 1, size)
      }
      default {
        if iszero(staticcall(gas(), initCodeStorage, 0, 0, 0, 0)) {
          mstore(0, 0x30116425)
          revert(0x1c, 4)
        }
        size := returndatasize()
        if gt(size, 49152) {
          mstore(0, 0x30116425)
          revert(0x1c, 4)
        }
        returndatacopy(data, 0, size)
      }
      mstore(initCode, size)
      mstore(add(data, size), 0)
      mstore(0x40, and(add(add(data, size), 31), not(31)))
    }
  }

  /**
   * @dev Returns the create2 prefix for a given deployer address.
   *      Equivalent to `uint256(uint160(deployer)) | (0xff << 160)`
   */
  function getCreate2Prefix(address deployer) internal pure returns (uint256 create2Prefix) {
    assembly ('memory-safe') {
      create2Prefix := or(deployer, 0xff0000000000000000000000000000000000000000)
    }
  }

  /// @dev calculates the CREATE2 address from a prefix returned by `getCreate2Prefix`, `salt`,
  ///      and the full init-code hash.
  function calculateCreate2Address(
    uint256 create2Prefix,
    bytes32 salt,
    uint256 initCodeHash
  ) internal pure returns (address create2Address) {
    assembly ('memory-safe') {
      // temporary hash input above the free memory pointer. don't borrow the pointer slot.
      let pointer := mload(0x40)
      mstore(pointer, create2Prefix)
      mstore(add(pointer, 0x20), salt)
      mstore(add(pointer, 0x40), initCodeHash)
      create2Address := and(
        keccak256(add(pointer, 0x0b), 0x55),
        0xffffffffffffffffffffffffffffffffffffffff
      )
    }
  }

  /// @dev deploys stored init code with CREATE and no ETH.
  function createWithStoredInitCode(address initCodeStorage) internal returns (address deployment) {
    deployment = createWithStoredInitCode(initCodeStorage, 0);
  }

  /// @dev deploys stored init code with CREATE and forwards `value` wei.
  function createWithStoredInitCode(
    address initCodeStorage,
    uint256 value
  ) internal returns (address deployment) {
    bytes memory initCode = getInitCode(initCodeStorage);
    assembly ('memory-safe') {
      let initCodePointer := add(initCode, 0x20)
      let initCodeSize := mload(initCode)
      deployment := create(value, initCodePointer, initCodeSize)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  /// @dev deploys stored init code with CREATE2, `salt`, and no ETH.
  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt
  ) internal returns (address deployment) {
    deployment = create2WithStoredInitCode(initCodeStorage, salt, 0);
  }

  /// @dev deploys stored init code with CREATE2 and forwards `value` wei.
  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    uint256 value
  ) internal returns (address deployment) {
    bytes memory initCode = getInitCode(initCodeStorage);
    return create2WithInitCode(initCode, salt, value);
  }

  /// @dev accepts already-read creation bytes so callers can verify their hash before CREATE2.
  function create2WithInitCode(
    bytes memory initCode,
    bytes32 salt,
    uint256 value
  ) internal returns (address deployment) {
    assembly ('memory-safe') {
      let initCodePointer := add(initCode, 0x20)
      let initCodeSize := mload(initCode)
      deployment := create2(value, initCodePointer, initCodeSize, salt)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  /// @dev appends memory `constructorArgs`, then deploys with CREATE2 and forwards `value` wei.
  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    uint256 value,
    bytes memory constructorArgs
  ) internal returns (address deployment) {
    bytes memory initCode = getInitCode(initCodeStorage);
    assembly ('memory-safe') {
      let initCodePointer := add(initCode, 0x20)
      let initCodeSize := mload(initCode)
      // Copy constructor args from memory to initcode
      let constructorArgsSize := mload(constructorArgs)
      mcopy(add(initCodePointer, initCodeSize), add(constructorArgs, 0x20), constructorArgsSize)
      let initCodeSizeWithArgs := add(initCodeSize, constructorArgsSize)
      deployment := create2(value, initCodePointer, initCodeSizeWithArgs, salt)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  /// @dev appends memory `constructorArgs`, then deploys with CREATE2 and no ETH.
  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    bytes memory constructorArgs
  ) internal returns (address deployment) {
    return create2WithStoredInitCode(initCodeStorage, salt, 0, constructorArgs);
  }

  /// @dev appends calldata `constructorArgs`, then deploys with CREATE2 and forwards `value` wei.
  function create2WithStoredInitCodeCD(
    address initCodeStorage,
    bytes32 salt,
    uint256 value,
    bytes calldata constructorArgs
  ) internal returns (address deployment) {
    bytes memory initCode = getInitCode(initCodeStorage);
    assembly ('memory-safe') {
      let initCodePointer := add(initCode, 0x20)
      let initCodeSize := mload(initCode)
      // Copy constructor args from calldata to end of initcode
      let constructorArgsSize := constructorArgs.length
      calldatacopy(add(initCodePointer, initCodeSize), constructorArgs.offset, constructorArgsSize)
      let initCodeSizeWithArgs := add(initCodeSize, constructorArgsSize)
      deployment := create2(value, initCodePointer, initCodeSizeWithArgs, salt)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  /// @dev appends calldata `constructorArgs`, then deploys with CREATE2 and no ETH.
  function create2WithStoredInitCodeCD(
    address initCodeStorage,
    bytes32 salt,
    bytes calldata constructorArgs
  ) internal returns (address deployment) {
    return create2WithStoredInitCodeCD(initCodeStorage, salt, 0, constructorArgs);
  }
}
