// SPDX-License-Identifier: UNLICENSED
// (c) SphereX 2023 Terms&Conditions
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // SphereXProtectedRegisteredBase
//  \ ^ /   ArchController-managed protection and call-state validation.
//    V
//
//  SETUP
//  __SphereXProtectedRegisteredBase_init(...)
//
//  ENGINE MANAGEMENT
//  spherexOnlyOperator()
//  changeSphereXEngine(...)
//  sphereXOperator()
//  sphereXEngine()
//
//  PROTECTED CALL FLOW
//  sphereXGuardExternal()
//  _sphereXValidateExternalPre()
//  returnsIfNotActivatedPre(...)
//  _getStorageSlotsAndPreparePostCalldata(...)
//  _sphereXValidateExternalPost(...)
//  returnsIfNotActivatedPost(...)
//  _callSphereXValidatePost(...)
//
//  STORAGE ACCESS
//  _setAddress(...)
//  _getAddress(...)
//  _readStorageTo(...)
//
//  CALL ADAPTERS
//  _getSelector()
//  _castFunctionToPointerOutput(...)
//  _castFunctionToPointerInput(...)
// ═════

import { ISphereXEngine, ModifierLocals } from './ISphereXEngine.sol';
import './SphereXProtectedEvents.sol';
import './SphereXProtectedErrors.sol';

// ┌─ SphereXProtectedRegisteredBase ───────────────────────────────────────────
/// @title SphereXProtectedBase adapted for Wildcat-registered contracts
///
/// @author Modified from https://github.com/spherex-xyz/spherex-protect-contracts/blob/main/src/SphereXProtectedBase.sol
///
/// @dev the immutable WildcatArchController is the operator and validates engine addresses.
///      there is no admin or operator-transfer path. admin functions, events, and errors were
///      removed to reduce contract size.
abstract contract SphereXProtectedRegisteredBase {
  // ░░▒▒▓▓██ [ CONFIGURATION ] ────────────────────────────────────────────────

  /// @dev storage slot for the SphereX engine address.
  bytes32 private constant SPHEREX_ENGINE_STORAGE_SLOT =
    bytes32(uint256(keccak256('eip1967.spherex.spherex_engine')) - 1);

  /// @dev immutable operator allowed to change the engine. the inheriting constructor must set it.
  address internal immutable _archController;

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  /// @dev the caller is not the immutable ArchController operator.
  error SphereXOperatorRequired();

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  /// @notice emitted when this registered contract records its ArchController operator.
  event ChangedSpherexOperator(address oldSphereXAdmin, address newSphereXAdmin);

  /// @notice emitted when the active SphereX engine changes.
  event ChangedSpherexEngineAddress(address oldEngineAddress, address newEngineAddress);

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ __SphereXProtectedRegisteredBase_init ─────
  /// @dev initialize the engine and emit the initial engine/operator configuration.
  function __SphereXProtectedRegisteredBase_init(address engine) internal virtual {
    emit_ChangedSpherexOperator(address(0), _archController);
    _setAddress(SPHEREX_ENGINE_STORAGE_SLOT, engine);
    emit_ChangedSpherexEngineAddress(address(0), engine);
  }

  // ░░▒▒▓▓██ [ ENGINE MANAGEMENT ] ────────────────────────────────────────────

  // ┌─ spherexOnlyOperator ─────
  modifier spherexOnlyOperator() {
    if (msg.sender != _archController) {
      revert_SphereXOperatorRequired();
    }
    _;
  }

  // ┌─ changeSphereXEngine ─────
  /// @notice replace the SphereX engine, or disable protection when set to zero.
  ///
  /// @dev only the immutable ArchController can call this. it validates the engine before
  ///      forwarding the update, so this size-reduced base does not validate it again.
  function changeSphereXEngine(address newSphereXEngine) external spherexOnlyOperator {
    address oldEngine = _getAddress(SPHEREX_ENGINE_STORAGE_SLOT);
    _setAddress(SPHEREX_ENGINE_STORAGE_SLOT, newSphereXEngine);
    emit_ChangedSpherexEngineAddress(oldEngine, newSphereXEngine);
  }

  // ┌─ sphereXOperator ─────
  /// @notice return the immutable ArchController operator.
  function sphereXOperator() public view returns (address) {
    return _archController;
  }

  // ┌─ sphereXEngine ─────
  /// @notice return the active engine, or zero when protection is disabled.
  function sphereXEngine() public view returns (address) {
    return _getAddress(SPHEREX_ENGINE_STORAGE_SLOT);
  }

  // ░░▒▒▓▓██ [ PROTECTED CALL FLOW ] ──────────────────────────────────────────

  // ┌─ sphereXGuardExternal ─────
  /// @dev wrap protected external non-view calls with engine validation.
  modifier sphereXGuardExternal() {
    uint256 localsPointer = _sphereXValidateExternalPre();
    _;
    _sphereXValidateExternalPost(localsPointer);
  }

  // ┌─ _sphereXValidateExternalPre ─────
  /// @dev return `_getStorageSlotsAndPreparePostCalldata`'s locals as a uint256 pointer.
  ///      a named struct return would allocate and zero fields before replacing the pointer.
  ///      the cast reuses the same struct without that redundant allocation.
  function _sphereXValidateExternalPre() internal returns (uint256 localsPointer) {
    return _castFunctionToPointerOutput(_getStorageSlotsAndPreparePostCalldata)(_getSelector());
  }

  // ┌─ returnsIfNotActivatedPre ─────
  modifier returnsIfNotActivatedPre(ModifierLocals memory locals) {
    locals.engine = sphereXEngine();
    if (locals.engine == address(0)) {
      return;
    }

    _;
  }

  // ┌─ _getStorageSlotsAndPreparePostCalldata ─────
  /// @dev run before the protected external body. sharing engine communication reduces code size.
  ///      sphereXValidatePre chooses `locals.storageSlots`; snapshot them into `locals.valuesBefore`.
  ///      allocate and prepare the post-call buffer now, leaving gas and valuesAfter for post-validation.
  ///
  /// @param num function identifier.
  function _getStorageSlotsAndPreparePostCalldata(int256 num)
    internal
    returnsIfNotActivatedPre(locals)
    returns (ModifierLocals memory locals)
  {
    assembly {
      // returnsIfNotActivatedPre already resolved locals.engine.
      let engineAddress := mload(add(locals, 0x60))

      // reuse the pre-call buffer for storageSlots and the later post-call calldata.
      let pointer := mload(0x40)

      // sphereXValidatePre(num, msg.sender, msg.data)
      mstore(pointer, 0x8925ca5a)
      mstore(add(pointer, 0x20), num)
      mstore(add(pointer, 0x40), caller())
      mstore(add(pointer, 0x60), 0x60)
      mstore(add(pointer, 0x80), calldatasize())
      calldatacopy(add(pointer, 0xa0), 0, calldatasize())
      let size := add(0xc4, calldatasize())

      if iszero(and(eq(mload(0), 0x20), call(gas(), engineAddress, 0, add(pointer, 28), size, 0, 0x40))) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      let length := mload(0x20)

      // memory after the locals allocation:
      // [0x00:0x20]: `storageSlots.length`
      // [0x20:0x20+(length * 0x20)]: `storageSlots` data
      // [0x20+(length*0x20):]: calldata for `sphereXValidatePost`

      // sphereXValidatePost arguments, excluding the selector:
      // [0x00:0x20]: num
      // [0x20:0x40]: gas
      // [0x40:0x60]: valuesBefore offset (0x80)
      // [0x60:0x80]: valuesAfter offset (0xa0 + (0x20 * length))
      // [0x80:0xa0]: valuesBefore length
      // [0xa0:0xa0+(0x20*length)]: valuesBefore data
      // [0xa0+(0x20*length):0xc0+(0x20*length)] valuesAfter length
      // [0xc0+(0x20*length):0xc0+(0x40*length)]: valuesAfter data
      //
      // argument size: 0xc0 + (0x40 * length); calldata adds a four-byte selector.
      //
      // size of allocation: 0xe0 + (0x60 * length)

      let arrayDataSize := shl(5, length)

      // reserve storageSlots plus the post-call argument buffer.
      mstore(0x40, add(pointer, add(0xe0, mul(arrayDataSize, 3))))

      // retain the engine's slot list at the start of the allocation.
      returndatacopy(pointer, 0x20, add(arrayDataSize, 0x20))
      mstore(locals, pointer)

      // post-call arguments start after the storageSlots array.
      // @todo placing valuesBefore first could let valuesAfter reuse the storageSlots buffer.
      let calldataPointer := add(pointer, add(arrayDataSize, 0x20))

      // post-validation uses the negated function identifier.
      mstore(calldataPointer, sub(0, num))

      mstore(add(calldataPointer, 0x40), 0x80)

      mstore(add(locals, 0x20), add(calldataPointer, 0x80))

      mstore(add(calldataPointer, 0x60), add(0xa0, arrayDataSize))

      mstore(add(locals, 0x40), gas())
    }
    _readStorageTo(locals.storageSlots, locals.valuesBefore);
  }

  // ┌─ _sphereXValidateExternalPost ─────
  /// @dev pass the existing locals pointer to `_callSphereXValidatePost` without a struct copy.
  function _sphereXValidateExternalPost(uint256 locals) internal {
    _castFunctionToPointerInput(_callSphereXValidatePost)(locals);
  }

  // ┌─ returnsIfNotActivatedPost ─────
  modifier returnsIfNotActivatedPost(ModifierLocals memory locals) {
    if (locals.engine == address(0)) {
      return;
    }

    _;
  }

  // ┌─ _callSphereXValidatePost ─────
  function _callSphereXValidatePost(ModifierLocals memory locals) internal returnsIfNotActivatedPost(locals) {
    uint256 length;
    bytes32[] memory storageSlots;
    bytes32[] memory valuesAfter;
    assembly {
      storageSlots := mload(locals)
      length := mload(storageSlots)
      valuesAfter := add(storageSlots, add(0xc0, shl(6, length)))
    }
    _readStorageTo(storageSlots, valuesAfter);
    assembly {
      let sphereXEngineAddress := mload(add(locals, 0x60))
      let arrayDataSize := shl(5, length)
      let calldataSize := add(0xc4, shl(1, arrayDataSize))

      let calldataPointer := add(storageSlots, add(arrayDataSize, 0x20))
      let gasDiff := sub(mload(add(locals, 0x40)), gas())
      mstore(add(calldataPointer, 0x20), gasDiff)
      let slotBefore := sub(calldataPointer, 32)
      let slotBeforeCache := mload(slotBefore)
      mstore(slotBefore, 0xf0bd9468)
      if iszero(call(gas(), sphereXEngineAddress, 0, add(slotBefore, 28), calldataSize, 0, 0)) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      mstore(slotBefore, slotBeforeCache)
    }
  }

  // ░░▒▒▓▓██ [ STORAGE ACCESS ] ───────────────────────────────────────────────

  // ┌─ _setAddress ─────
  /// @dev store an address in an arbitrary slot.
  function _setAddress(bytes32 slot, address newAddress) internal {
    assembly {
      sstore(slot, newAddress)
    }
  }

  // ┌─ _getAddress ─────
  /// @dev read an address from an arbitrary slot.
  function _getAddress(bytes32 slot) internal view returns (address addr) {
    assembly {
      addr := sload(slot)
    }
  }

  // ┌─ _readStorageTo ─────
  /// @dev snapshot the requested storage slots into a preallocated memory array.
  ///
  /// @param storageSlots storage slots to read, in output order.
  /// @param values       destination with room for the length and every requested value.
  function _readStorageTo(bytes32[] memory storageSlots, bytes32[] memory values) internal view {
    assembly {
      let length := mload(storageSlots)
      let arrayDataSize := shl(5, length)
      mstore(values, length)
      let nextSlotPointer := add(storageSlots, 0x20)
      let nextElementPointer := add(values, 0x20)
      let endPointer := add(nextElementPointer, shl(5, length))
      for { } lt(nextElementPointer, endPointer) { } {
        mstore(nextElementPointer, sload(mload(nextSlotPointer)))
        nextElementPointer := add(nextElementPointer, 0x20)
        nextSlotPointer := add(nextSlotPointer, 0x20)
      }
    }
  }

  // ░░▒▒▓▓██ [ CALL ADAPTERS ] ────────────────────────────────────────────────

  // ┌─ _getSelector ─────
  /// @dev read the current call's four-byte selector.
  function _getSelector() internal pure returns (int256 selector) {
    assembly {
      selector := shr(224, calldataload(0))
    }
  }

  // ┌─ _castFunctionToPointerOutput ─────
  function _castFunctionToPointerOutput(function(int256) internal returns (ModifierLocals memory) fnIn)
    internal
    pure
    returns (function(int256) internal returns (uint256) fnOut)
  {
    assembly {
      fnOut := fnIn
    }
  }

  // ┌─ _castFunctionToPointerInput ─────
  function _castFunctionToPointerInput(function(ModifierLocals memory) internal fnIn)
    internal
    pure
    returns (function(uint256) internal fnOut)
  {
    assembly {
      fnOut := fnIn
    }
  }
}
