// SPDX-License-Identifier: UNLICENSED
// (c) SphereX 2023 Terms&Conditions
pragma solidity 0.8.25;

import { ISphereXEngine, ModifierLocals } from './ISphereXEngine.sol';
import './SphereXProtectedEvents.sol';
import './SphereXProtectedErrors.sol';

/// @title SphereX configuration
/// @notice manages the admin, operator, and engine used by a SphereX-protected contract.
/// @dev the admin changes the operator through a direct update. admin transfer is two-step. the
///      operator changes the engine, and setting it to zero disables protection.
abstract contract SphereXConfig {
  // ========================================================================== //
  //                                Storage Slots                               //
  // ========================================================================== //

  bytes32 private constant SPHEREX_ADMIN_STORAGE_SLOT =
    bytes32(uint256(keccak256('eip1967.spherex.spherex')) - 1);
  bytes32 private constant SPHEREX_PENDING_ADMIN_STORAGE_SLOT =
    bytes32(uint256(keccak256('eip1967.spherex.pending')) - 1);
  bytes32 private constant SPHEREX_OPERATOR_STORAGE_SLOT =
    bytes32(uint256(keccak256('eip1967.spherex.operator')) - 1);
  bytes32 private constant SPHEREX_ENGINE_STORAGE_SLOT =
    bytes32(uint256(keccak256('eip1967.spherex.spherex_engine')) - 1);

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  constructor(address admin, address operator, address engine) {
    _setAddress(SPHEREX_ADMIN_STORAGE_SLOT, admin);
    emit_SpherexAdminTransferCompleted(address(0), admin);

    _setAddress(SPHEREX_OPERATOR_STORAGE_SLOT, operator);
    emit_ChangedSpherexOperator(address(0), operator);

    _setSphereXEngine(engine);
    emit_ChangedSpherexEngineAddress(address(0), engine);
  }

  // ========================================================================== //
  //                              Events and Errors                             //
  // ========================================================================== //

  /// @notice emitted when the SphereX operator changes.
  event ChangedSpherexOperator(address oldSphereXAdmin, address newSphereXAdmin);
  /// @notice emitted when the active SphereX engine changes.
  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);
  /// @notice emitted when the admin starts or replaces a two-step transfer.
  event SpherexAdminTransferStarted(address currentAdmin, address pendingAdmin);
  /// @notice emitted when the pending admin accepts authority.
  event SpherexAdminTransferCompleted(address oldAdmin, address newAdmin);
  /// @notice emitted when this contract allows a sender on the active engine.
  event NewAllowedSenderOnchain(address sender);

  /// @dev the caller is not the SphereX operator.
  error SphereXOperatorRequired();
  /// @dev the caller is not the SphereX admin.
  error SphereXAdminRequired();
  /// @dev the caller is neither the SphereX operator nor admin.
  error SphereXOperatorOrAdminRequired();
  /// @dev the caller is not the pending SphereX admin.
  error SphereXNotPendingAdmin();
  /// @dev the proposed engine does not support `ISphereXEngine`.
  error SphereXNotEngine();

  // ========================================================================== //
  //                                  Modifiers                                 //
  // ========================================================================== //

  modifier onlySphereXAdmin() {
    if (msg.sender != sphereXAdmin()) {
      revert_SphereXAdminRequired();
    }
    _;
  }

  modifier spherexOnlyOperator() {
    if (msg.sender != sphereXOperator()) {
      revert_SphereXOperatorRequired();
    }
    _;
  }

  modifier spherexOnlyOperatorOrAdmin() {
    if (msg.sender != sphereXOperator() && msg.sender != sphereXAdmin()) {
      revert_SphereXOperatorOrAdminRequired();
    }
    _;
  }

  // ========================================================================== //
  //                               Config Getters                               //
  // ========================================================================== //

  /// @notice returns the address allowed to accept the pending admin transfer.
  function pendingSphereXAdmin() public view returns (address) {
    return _getAddress(SPHEREX_PENDING_ADMIN_STORAGE_SLOT);
  }

  /// @notice returns the current admin, which can replace the operator.
  function sphereXAdmin() public view returns (address) {
    return _getAddress(SPHEREX_ADMIN_STORAGE_SLOT);
  }

  /// @notice returns the current operator, which can replace the engine.
  function sphereXOperator() public view returns (address) {
    return _getAddress(SPHEREX_OPERATOR_STORAGE_SLOT);
  }

  /// @notice returns the active engine, or zero when protection is disabled.
  function sphereXEngine() public view returns (address) {
    return _getAddress(SPHEREX_ENGINE_STORAGE_SLOT);
  }

  // ========================================================================== //
  //                                 Management                                 //
  // ========================================================================== //

  /// @notice proposes `newAdmin` as the next SphereX admin.
  /// @dev only the current admin can call this. a new proposal replaces the old one.
  function transferSphereXAdminRole(address newAdmin) public virtual onlySphereXAdmin {
    _setAddress(SPHEREX_PENDING_ADMIN_STORAGE_SLOT, newAdmin);
    emit_SpherexAdminTransferStarted(sphereXAdmin(), newAdmin);
  }

  /// @notice accepts a pending admin transfer.
  /// @dev only the pending admin can call this.
  function acceptSphereXAdminRole() public virtual {
    if (msg.sender != pendingSphereXAdmin()) {
      revert_SphereXNotPendingAdmin();
    }
    address oldAdmin = sphereXAdmin();
    _setAddress(SPHEREX_ADMIN_STORAGE_SLOT, msg.sender);
    _setAddress(SPHEREX_PENDING_ADMIN_STORAGE_SLOT, address(0));
    emit_SpherexAdminTransferCompleted(oldAdmin, msg.sender);
  }

  /// @notice replaces the SphereX operator.
  /// @dev only the current admin can call this.
  function changeSphereXOperator(address newSphereXOperator) external onlySphereXAdmin {
    address oldSphereXOperator = _getAddress(SPHEREX_OPERATOR_STORAGE_SLOT);
    _setAddress(SPHEREX_OPERATOR_STORAGE_SLOT, newSphereXOperator);
    emit_ChangedSpherexOperator(oldSphereXOperator, newSphereXOperator);
  }

  /// @notice replaces the SphereX engine, or disables protection when set to zero.
  /// @dev only the operator can call this. nonzero engines must support `ISphereXEngine`.
  function changeSphereXEngine(address newSphereXEngine) external spherexOnlyOperator {
    address oldEngine = _getAddress(SPHEREX_ENGINE_STORAGE_SLOT);
    _setSphereXEngine(newSphereXEngine);
    emit_ChangedSpherexEngineAddress(oldEngine, newSphereXEngine);
  }

  /// @dev requires `newSphereXEngine` to be zero or report the `ISphereXEngine` interface.
  function _setSphereXEngine(address newSphereXEngine) internal {
    if (
      newSphereXEngine != address(0) &&
      !ISphereXEngine(newSphereXEngine).supportsInterface(type(ISphereXEngine).interfaceId)
    ) {
      revert_SphereXNotEngine();
    }
    _setAddress(SPHEREX_ENGINE_STORAGE_SLOT, newSphereXEngine);
  }

  // ========================================================================== //
  //                             Engine Interaction                             //
  // ========================================================================== //

  /// @dev allows `newSender` on the active engine. a disabled engine makes this a no-op.
  function _addAllowedSenderOnChain(address newSender) internal {
    ISphereXEngine engine = ISphereXEngine(sphereXEngine());
    if (address(engine) != address(0)) {
      engine.addAllowedSenderOnChain(newSender);
      emit_NewAllowedSenderOnchain(newSender);
    }
  }

  // ========================================================================== //
  //                          Internal Storage Helpers                          //
  // ========================================================================== //

  /// @dev stores an address in an arbitrary slot.
  function _setAddress(bytes32 slot, address newAddress) internal {
    assembly {
      sstore(slot, newAddress)
    }
  }

  /// @dev returns an address from an arbitrary slot.
  function _getAddress(bytes32 slot) internal view returns (address addr) {
    assembly {
      addr := sload(slot)
    }
  }
}
