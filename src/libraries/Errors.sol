// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // Errors
// ║  ██▀▀     ▀▀██   Panic constants and compact custom-error revert helpers.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  CUSTOM ERRORS
// ║  revertWithSelector(...)
// ║  revertWithSelector(...)
// ║
// ║  ERROR ARGUMENTS
// ║  revertWithSelectorAndArgument(...)
// ║  revertWithSelectorAndArgument(...)
// ╚═════

uint256 constant Panic_CompilerPanic = 0x00;
uint256 constant Panic_AssertFalse = 0x01;
uint256 constant Panic_Arithmetic = 0x11;
uint256 constant Panic_DivideByZero = 0x12;
uint256 constant Panic_InvalidEnumValue = 0x21;
uint256 constant Panic_InvalidStorageByteArray = 0x22;
uint256 constant Panic_EmptyArrayPop = 0x31;
uint256 constant Panic_ArrayOutOfBounds = 0x32;
uint256 constant Panic_MemoryTooLarge = 0x41;
uint256 constant Panic_UninitializedFunctionPointer = 0x51;

uint256 constant Panic_ErrorSelector = 0x4e487b71;
uint256 constant Panic_ErrorCodePointer = 0x20;
uint256 constant Panic_ErrorLength = 0x24;
uint256 constant Error_SelectorPointer = 0x1c;

// ░░▒▒▓▓██ [ CUSTOM ERRORS ] ──────────────────────────────────────────────────

// ┌─ revertWithSelector ─────
/// @dev revert with the supplied error selector.
///
/// @param errorSelector left-aligned error selector.
function revertWithSelector(bytes4 errorSelector) pure {
  assembly {
    mstore(0, errorSelector)
    revert(0, 4)
  }
}

// ┌─ revertWithSelector ─────
/// @dev revert with the supplied error selector.
///
/// @param errorSelector error selector in the low four bytes of the word.
function revertWithSelector(uint256 errorSelector) pure {
  assembly {
    mstore(0, errorSelector)
    revert(Error_SelectorPointer, 4)
  }
}

// ░░▒▒▓▓██ [ ERROR ARGUMENTS ] ────────────────────────────────────────────────

// ┌─ revertWithSelectorAndArgument ─────
/// @dev revert with the supplied selector and one argument.
///
/// @param errorSelector left-aligned error selector.
/// @param argument      error argument.
function revertWithSelectorAndArgument(bytes4 errorSelector, uint256 argument) pure {
  assembly {
    mstore(0, errorSelector)
    mstore(4, argument)
    revert(0, 0x24)
  }
}

// ┌─ revertWithSelectorAndArgument ─────
/// @dev revert with the supplied selector and one argument.
///
/// @param errorSelector error selector in the low four bytes of the word.
/// @param argument      error argument.
function revertWithSelectorAndArgument(uint256 errorSelector, uint256 argument) pure {
  assembly {
    mstore(0, errorSelector)
    mstore(0x20, argument)
    revert(Error_SelectorPointer, 0x24)
  }
}
