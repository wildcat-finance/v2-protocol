// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // HooksConfig
//  \ ^ /   Hook configuration, activation flags, and callback dispatch.
//    V
//
//  ENCODING
//  encodeHooksDeploymentConfig(...)
//  encodeHooksConfig(...)
//
//  HOOK ADDRESS
//  setHooksAddress(...)
//  hooksAddress(...)
//
//  FLAG COMPOSITION
//  mergeFlags(...)
//  mergeSharedFlags(...)
//  mergeAllFlags(...)
//  optionalFlags(...)
//  requiredFlags(...)
//
//  FLAG OPERATIONS
//  setFlag(...)
//  clearFlag(...)
//  readFlag(...)
//
//  DEPOSITS
//  onDeposit(...)
//  useOnDeposit(...)
//
//  WITHDRAWAL QUEUEING
//  onQueueWithdrawal(...)
//  useOnQueueWithdrawal(...)
//
//  CLAIM COLLECTION
//  onExecuteWithdrawal(...)
//  useOnExecuteWithdrawal(...)
//
//  TRANSFERS
//  onTransfer(...)
//  useOnTransfer(...)
//
//  BORROWING
//  onBorrow(...)
//  useOnBorrow(...)
//
//  REPAYMENT
//  onRepay(...)
//  useOnRepay(...)
//
//  CLOSURE
//  onCloseMarket(...)
//  useOnCloseMarket(...)
//
//  SUPPLY CAPACITY
//  onSetMaxTotalSupply(...)
//  useOnSetMaxTotalSupply(...)
//
//  INTEREST AND RESERVES
//  onSetAnnualInterestAndReserveRatioBips(...)
//  useOnSetAnnualInterestAndReserveRatioBips(...)
//  useOnExecutePendingAnnualInterestBipsReduction(...)
//
//  PROTOCOL FEES
//  onSetProtocolFeeBips(...)
//  useOnSetProtocolFeeBips(...)
//
//  SANCTIONS
//  onNukeFromOrbit(...)
//  useOnNukeFromOrbit(...)
//
//  CALL DISPATCH
//  _callHook(...)
// ═════

import '../access/IHooks.sol';
import '../libraries/MarketState.sol';

/// @notice packed hook address and enabled market-callback flags.
/// @dev the address occupies the high 160 bits. callback flags sit below it.
type HooksConfig is uint256;

// zero address with every callback disabled.
HooksConfig constant EmptyHooksConfig = HooksConfig.wrap(0);

using LibHooksConfig for HooksConfig global;
using LibHooksConfig for HooksDeploymentConfig global;

/// @notice optional and required callback masks advertised by a hooks template.
/// @dev optional flags occupy the low 16 bits and required flags occupy the next 16.
type HooksDeploymentConfig is uint256;

// ░░▒▒▓▓██ [ BITS AFTER HOOK ACTIVATION FLAG ] ────────────────────────────────

// bit offsets count from the right.

uint256 constant Bit_Enabled_Deposit = 95;
uint256 constant Bit_Enabled_QueueWithdrawal = 94;
uint256 constant Bit_Enabled_ExecuteWithdrawal = 93;
uint256 constant Bit_Enabled_Transfer = 92;
uint256 constant Bit_Enabled_Borrow = 91;
uint256 constant Bit_Enabled_Repay = 90;
uint256 constant Bit_Enabled_CloseMarket = 89;
uint256 constant Bit_Enabled_NukeFromOrbit = 88;
uint256 constant Bit_Enabled_SetMaxTotalSupply = 87;
uint256 constant Bit_Enabled_SetAnnualInterestAndReserveRatioBips = 86;
uint256 constant Bit_Enabled_SetProtocolFeeBips = 85;
uint256 constant Bit_Enabled_ExecutePendingAnnualInterestBipsReduction = 84;

uint256 constant MarketStateSize = 0x01e0;

// ░░▒▒▓▓██ [ ENCODING ] ───────────────────────────────────────────────────────

// ┌─ encodeHooksDeploymentConfig ─────
/// @notice pack optional and required callback masks for a hooks template.
///
/// @dev ignores the address and any bits outside the callback range in each input.
function encodeHooksDeploymentConfig(
  HooksConfig optionalFlags,
  HooksConfig requiredFlags
)
  pure
  returns (HooksDeploymentConfig flags)
{
  assembly {
    let cleanedOptionalFlags := and(0xffff, shr(0x50, optionalFlags))
    let cleanedRequiredFlags := and(0xffff0000, shr(0x40, requiredFlags))
    flags := or(cleanedOptionalFlags, cleanedRequiredFlags)
  }
}

// ┌─ encodeHooksConfig ─────
/// @notice pack a hook address and the callback flags accepted by this legacy-shaped helper.
///
/// @dev the periodic APR execution flag isn't an argument here and remains disabled unless set
///      separately.
function encodeHooksConfig(
  address hooksAddress,
  bool useOnDeposit,
  bool useOnQueueWithdrawal,
  bool useOnExecuteWithdrawal,
  bool useOnTransfer,
  bool useOnBorrow,
  bool useOnRepay,
  bool useOnCloseMarket,
  bool useOnNukeFromOrbit,
  bool useOnSetMaxTotalSupply,
  bool useOnSetAnnualInterestAndReserveRatioBips,
  bool useOnSetProtocolFeeBips
)
  pure
  returns (HooksConfig hooks)
{
  assembly {
    hooks := shl(96, hooksAddress)
    hooks := or(hooks, shl(Bit_Enabled_Deposit, useOnDeposit))
    hooks := or(hooks, shl(Bit_Enabled_QueueWithdrawal, useOnQueueWithdrawal))
    hooks := or(hooks, shl(Bit_Enabled_ExecuteWithdrawal, useOnExecuteWithdrawal))
    hooks := or(hooks, shl(Bit_Enabled_Transfer, useOnTransfer))
    hooks := or(hooks, shl(Bit_Enabled_Borrow, useOnBorrow))
    hooks := or(hooks, shl(Bit_Enabled_Repay, useOnRepay))
    hooks := or(hooks, shl(Bit_Enabled_CloseMarket, useOnCloseMarket))
    hooks := or(hooks, shl(Bit_Enabled_NukeFromOrbit, useOnNukeFromOrbit))
    hooks := or(hooks, shl(Bit_Enabled_SetMaxTotalSupply, useOnSetMaxTotalSupply))
    hooks := or(hooks, shl(Bit_Enabled_SetAnnualInterestAndReserveRatioBips, useOnSetAnnualInterestAndReserveRatioBips))
    hooks := or(hooks, shl(Bit_Enabled_SetProtocolFeeBips, useOnSetProtocolFeeBips))
  }
}

// ┌─ LibHooksConfig ───────────────────────────────────────────────────────────
library LibHooksConfig {
  // ░░▒▒▓▓██ [ HOOK ADDRESS ] ─────────────────────────────────────────────────

  // ┌─ setHooksAddress ─────
  /// @dev return `hooks` with its address replaced and every flag left alone.
  function setHooksAddress(HooksConfig hooks, address _hooksAddress) internal pure returns (HooksConfig updatedHooks) {
    assembly {
      updatedHooks := shr(160, shl(160, hooks))
      updatedHooks := or(updatedHooks, shl(96, _hooksAddress))
    }
  }

  // ┌─ hooksAddress ─────
  /// @dev hook contract address.
  function hooksAddress(HooksConfig hooks) internal pure returns (address _hooks) {
    assembly {
      _hooks := shr(96, hooks)
    }
  }

  // ░░▒▒▓▓██ [ FLAG COMPOSITION ] ─────────────────────────────────────────────

  // ┌─ mergeFlags ─────
  /// @dev keep optional requested flags, enable every required flag, and preserve the
  ///      address from `config`.
  function mergeFlags(HooksConfig config, HooksDeploymentConfig flags) internal pure returns (HooksConfig merged) {
    assembly {
      let _hooksAddress := shl(96, shr(96, config))
      let configFlags := shr(0x50, config)
      // optional flags are already aligned. shift required flags down, then mask all three
      // inputs to the 16-bit callback range.
      let _optionalFlags := flags
      let _requiredFlags := shr(0x10, flags)
      let mergedFlags := and(0xffff, or(and(configFlags, _optionalFlags), _requiredFlags))

      merged := or(_hooksAddress, shl(0x50, mergedFlags))
    }
  }

  // ┌─ mergeSharedFlags ─────
  /// @dev intersect the flags of `a` and `b`; keep `a`'s address.
  function mergeSharedFlags(HooksConfig a, HooksConfig b) internal pure returns (HooksConfig merged) {
    assembly {
      let addressA := shl(0x60, shr(0x60, a))
      let flagsA := shl(0xa0, a)
      let flagsB := shl(0xa0, b)
      let mergedFlags := shr(0xa0, and(flagsA, flagsB))
      merged := or(addressA, mergedFlags)
    }
  }

  // ┌─ mergeAllFlags ─────
  /// @dev union the flags of `a` and `b`; keep `a`'s address.
  function mergeAllFlags(HooksConfig a, HooksConfig b) internal pure returns (HooksConfig merged) {
    assembly {
      let addressA := shl(0x60, shr(0x60, a))
      let flagsA := shl(0xa0, a)
      let flagsB := shl(0xa0, b)
      let mergedFlags := shr(0xa0, or(flagsA, flagsB))
      merged := or(addressA, mergedFlags)
    }
  }

  // ┌─ optionalFlags ─────
  /// @dev extract optional callback flags into their `HooksConfig` bit positions.
  function optionalFlags(HooksDeploymentConfig flags) internal pure returns (HooksConfig config) {
    assembly {
      config := shl(0x50, and(flags, 0xffff))
    }
  }

  // ┌─ requiredFlags ─────
  /// @dev extract required callback flags into their `HooksConfig` bit positions.
  function requiredFlags(HooksDeploymentConfig flags) internal pure returns (HooksConfig config) {
    assembly {
      config := shl(0x40, and(flags, 0xffff0000))
    }
  }

  // ░░▒▒▓▓██ [ FLAG OPERATIONS ] ──────────────────────────────────────────────

  // ┌─ setFlag ─────
  /// @dev return `hooks` with the flag at `bitsAfter` enabled.
  function setFlag(HooksConfig hooks, uint256 bitsAfter) internal pure returns (HooksConfig updatedHooks) {
    assembly {
      updatedHooks := or(hooks, shl(bitsAfter, 1))
    }
  }

  // ┌─ clearFlag ─────
  /// @dev return `hooks` with the flag at `bitsAfter` disabled.
  function clearFlag(HooksConfig hooks, uint256 bitsAfter) internal pure returns (HooksConfig updatedHooks) {
    assembly {
      updatedHooks := and(hooks, not(shl(bitsAfter, 1)))
    }
  }

  // ┌─ readFlag ─────
  /// @dev read the flag at `bitsAfter`; callers must supply a valid callback offset.
  function readFlag(HooksConfig hooks, uint256 bitsAfter) internal pure returns (bool flagged) {
    assembly {
      flagged := and(shr(bitsAfter, hooks), 1)
    }
  }

  // ░░▒▒▓▓██ [ DEPOSITS ] ─────────────────────────────────────────────────────

  uint256 internal constant DepositCalldataSize = 0x24;
  // fixed call size: selector + lender + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant DepositHook_Base_Size = 0x0264;
  uint256 internal constant DepositHook_ScaledAmount_Offset = 0x20;
  uint256 internal constant DepositHook_State_Offset = 0x40;
  uint256 internal constant DepositHook_ExtraData_Head_Offset = 0x0220;
  uint256 internal constant DepositHook_ExtraData_Length_Offset = 0x0240;
  uint256 internal constant DepositHook_ExtraData_TailOffset = 0x0260;

  // ┌─ onDeposit ─────
  /// @dev call `onDeposit` when enabled and forward bytes appended after the deposit arguments.
  function onDeposit(HooksConfig self, address lender, uint256 scaledAmount, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onDepositSelector = uint32(IHooks.onDeposit.selector);
    if (self.useOnDeposit()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onDepositSelector)
        mstore(headPointer, lender)
        mstore(add(headPointer, DepositHook_ScaledAmount_Offset), scaledAmount)
        mcopy(add(headPointer, DepositHook_State_Offset), state, MarketStateSize)
        mstore(add(headPointer, DepositHook_ExtraData_Head_Offset), DepositHook_ExtraData_Length_Offset)
        mstore(add(headPointer, DepositHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(add(headPointer, DepositHook_ExtraData_TailOffset), DepositCalldataSize, extraCalldataBytes)

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(DepositHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnDeposit ─────
  /// @dev whether to call the hook for deposit.
  function useOnDeposit(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Deposit);
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL QUEUEING ] ──────────────────────────────────────────

  // fixed call size: selector + lender + expiry + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant QueueWithdrawalHook_Base_Size = 0x0284;
  uint256 internal constant QueueWithdrawalHook_Expiry_Offset = 0x20;
  uint256 internal constant QueueWithdrawalHook_ScaledAmount_Offset = 0x40;
  uint256 internal constant QueueWithdrawalHook_State_Offset = 0x60;
  uint256 internal constant QueueWithdrawalHook_ExtraData_Head_Offset = 0x0240;
  uint256 internal constant QueueWithdrawalHook_ExtraData_Length_Offset = 0x0260;
  uint256 internal constant QueueWithdrawalHook_ExtraData_TailOffset = 0x0280;

  // ┌─ onQueueWithdrawal ─────
  /// @dev call `onQueueWithdrawal` when enabled and forward trailing `extraData` unchanged.
  function onQueueWithdrawal(
    HooksConfig self,
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState memory state,
    uint256 baseCalldataSize
  )
    internal
  {
    address target = self.hooksAddress();
    uint32 onQueueWithdrawalSelector = uint32(IHooks.onQueueWithdrawal.selector);
    if (self.useOnQueueWithdrawal()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onQueueWithdrawalSelector)
        mstore(headPointer, lender)
        mstore(add(headPointer, QueueWithdrawalHook_Expiry_Offset), expiry)
        mstore(add(headPointer, QueueWithdrawalHook_ScaledAmount_Offset), scaledAmount)
        mcopy(add(headPointer, QueueWithdrawalHook_State_Offset), state, MarketStateSize)
        mstore(add(headPointer, QueueWithdrawalHook_ExtraData_Head_Offset), QueueWithdrawalHook_ExtraData_Length_Offset)
        mstore(add(headPointer, QueueWithdrawalHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(add(headPointer, QueueWithdrawalHook_ExtraData_TailOffset), baseCalldataSize, extraCalldataBytes)

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(QueueWithdrawalHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnQueueWithdrawal ─────
  /// @dev whether to call the hook for queueWithdrawal.
  function useOnQueueWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_QueueWithdrawal);
  }

  // ░░▒▒▓▓██ [ CLAIM COLLECTION ] ─────────────────────────────────────────────

  // fixed call size: selector + lender + expiry + normalizedAmountWithdrawn + state + extraData.offset + extraData.length
  uint256 internal constant ExecuteWithdrawalHook_Base_Size = 0x0284;
  uint256 internal constant ExecuteWithdrawalHook_Expiry_Offset = 0x20;
  uint256 internal constant ExecuteWithdrawalHook_NormalizedAmount_Offset = 0x40;
  uint256 internal constant ExecuteWithdrawalHook_State_Offset = 0x60;
  uint256 internal constant ExecuteWithdrawalHook_ExtraData_Head_Offset = 0x0240;
  uint256 internal constant ExecuteWithdrawalHook_ExtraData_Length_Offset = 0x0260;
  uint256 internal constant ExecuteWithdrawalHook_ExtraData_TailOffset = 0x0280;

  // ┌─ onExecuteWithdrawal ─────
  /// @dev call `onExecuteWithdrawal` when enabled and forward trailing `extraData` unchanged.
  function onExecuteWithdrawal(
    HooksConfig self,
    address lender,
    uint32 expiry,
    uint256 normalizedAmountWithdrawn,
    MarketState memory state,
    uint256 baseCalldataSize
  )
    internal
  {
    address target = self.hooksAddress();
    uint32 onExecuteWithdrawalSelector = uint32(IHooks.onExecuteWithdrawal.selector);
    if (self.useOnExecuteWithdrawal()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onExecuteWithdrawalSelector)
        mstore(headPointer, lender)
        mstore(add(headPointer, ExecuteWithdrawalHook_Expiry_Offset), expiry)
        mstore(add(headPointer, ExecuteWithdrawalHook_NormalizedAmount_Offset), normalizedAmountWithdrawn)
        mcopy(add(headPointer, ExecuteWithdrawalHook_State_Offset), state, MarketStateSize)
        mstore(
          add(headPointer, ExecuteWithdrawalHook_ExtraData_Head_Offset),
          ExecuteWithdrawalHook_ExtraData_Length_Offset
        )
        mstore(add(headPointer, ExecuteWithdrawalHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(add(headPointer, ExecuteWithdrawalHook_ExtraData_TailOffset), baseCalldataSize, extraCalldataBytes)

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(ExecuteWithdrawalHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnExecuteWithdrawal ─────
  /// @dev whether to call the hook for executeWithdrawal.
  function useOnExecuteWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_ExecuteWithdrawal);
  }

  // ░░▒▒▓▓██ [ TRANSFERS ] ────────────────────────────────────────────────────

  // fixed call size: selector + caller + from + to + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant TransferHook_Base_Size = 0x02a4;
  uint256 internal constant TransferHook_From_Offset = 0x20;
  uint256 internal constant TransferHook_To_Offset = 0x40;
  uint256 internal constant TransferHook_ScaledAmount_Offset = 0x60;
  uint256 internal constant TransferHook_State_Offset = 0x80;
  uint256 internal constant TransferHook_ExtraData_Head_Offset = 0x0260;
  uint256 internal constant TransferHook_ExtraData_Length_Offset = 0x0280;
  uint256 internal constant TransferHook_ExtraData_TailOffset = 0x02a0;

  // ┌─ onTransfer ─────
  /// @dev call `onTransfer` when enabled and report the original market caller to the hook.
  function onTransfer(
    HooksConfig self,
    address from,
    address to,
    uint256 scaledAmount,
    MarketState memory state,
    uint256 baseCalldataSize
  )
    internal
  {
    address target = self.hooksAddress();
    uint32 onTransferSelector = uint32(IHooks.onTransfer.selector);
    if (self.useOnTransfer()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onTransferSelector)
        mstore(headPointer, caller())
        mstore(add(headPointer, TransferHook_From_Offset), from)
        mstore(add(headPointer, TransferHook_To_Offset), to)
        mstore(add(headPointer, TransferHook_ScaledAmount_Offset), scaledAmount)
        mcopy(add(headPointer, TransferHook_State_Offset), state, MarketStateSize)
        mstore(add(headPointer, TransferHook_ExtraData_Head_Offset), TransferHook_ExtraData_Length_Offset)
        mstore(add(headPointer, TransferHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(add(headPointer, TransferHook_ExtraData_TailOffset), baseCalldataSize, extraCalldataBytes)

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(TransferHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnTransfer ─────
  /// @dev whether to call the hook for transfer.
  function useOnTransfer(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Transfer);
  }

  // ░░▒▒▓▓██ [ BORROWING ] ────────────────────────────────────────────────────

  uint256 internal constant BorrowCalldataSize = 0x24;
  // fixed call size: selector + normalizedAmount + state + extraData.offset + extraData.length
  uint256 internal constant BorrowHook_Base_Size = 0x0244;
  uint256 internal constant BorrowHook_State_Offset = 0x20;
  uint256 internal constant BorrowHook_ExtraData_Head_Offset = 0x0200;
  uint256 internal constant BorrowHook_ExtraData_Length_Offset = 0x0220;
  uint256 internal constant BorrowHook_ExtraData_TailOffset = 0x0240;

  // ┌─ onBorrow ─────
  /// @dev call `onBorrow` when enabled and forward bytes appended after the borrow amount.
  function onBorrow(HooksConfig self, uint256 normalizedAmount, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onBorrowSelector = uint32(IHooks.onBorrow.selector);
    if (self.useOnBorrow()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), BorrowCalldataSize)
        let ptr := mload(0x40)
        let headPointer := add(ptr, 0x20)

        mstore(ptr, onBorrowSelector)
        mstore(headPointer, normalizedAmount)
        mcopy(add(headPointer, BorrowHook_State_Offset), state, MarketStateSize)
        mstore(add(headPointer, BorrowHook_ExtraData_Head_Offset), BorrowHook_ExtraData_Length_Offset)
        mstore(add(headPointer, BorrowHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(add(headPointer, BorrowHook_ExtraData_TailOffset), BorrowCalldataSize, extraCalldataBytes)

        calldataPointer := add(ptr, 0x1c)
        calldataSize := add(BorrowHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnBorrow ─────
  /// @dev whether to call the hook for borrow.
  function useOnBorrow(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Borrow);
  }

  // ░░▒▒▓▓██ [ REPAYMENT ] ────────────────────────────────────────────────────

  // fixed call size: selector + normalizedAmount + state + extraData.offset + extraData.length
  uint256 internal constant RepayHook_Base_Size = 0x0244;
  uint256 internal constant RepayHook_State_Offset = 0x20;
  uint256 internal constant RepayHook_ExtraData_Head_Offset = 0x0200;
  uint256 internal constant RepayHook_ExtraData_Length_Offset = 0x0220;
  uint256 internal constant RepayHook_ExtraData_TailOffset = 0x0240;

  // ┌─ onRepay ─────
  /// @dev call `onRepay` when enabled and forward trailing `extraData` unchanged.
  function onRepay(
    HooksConfig self,
    uint256 normalizedAmount,
    MarketState memory state,
    uint256 baseCalldataSize
  )
    internal
  {
    address target = self.hooksAddress();
    uint32 onRepaySelector = uint32(IHooks.onRepay.selector);
    if (self.useOnRepay()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let ptr := mload(0x40)
        let headPointer := add(ptr, 0x20)

        mstore(ptr, onRepaySelector)
        mstore(headPointer, normalizedAmount)
        mcopy(add(headPointer, RepayHook_State_Offset), state, MarketStateSize)
        mstore(add(headPointer, RepayHook_ExtraData_Head_Offset), RepayHook_ExtraData_Length_Offset)
        mstore(add(headPointer, RepayHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(add(headPointer, RepayHook_ExtraData_TailOffset), baseCalldataSize, extraCalldataBytes)

        calldataPointer := add(ptr, 0x1c)
        calldataSize := add(RepayHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnRepay ─────
  /// @dev whether to call the hook for repay.
  function useOnRepay(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Repay);
  }

  // ░░▒▒▓▓██ [ CLOSURE ] ──────────────────────────────────────────────────────

  // size of calldata to `market.closeMarket`
  uint256 internal constant CloseMarketCalldataSize = 0x04;

  // fixed calldata size for hooks.onCloseMarket().
  uint256 internal constant CloseMarketHook_Base_Size = 0x0224;
  uint256 internal constant CloseMarketHook_ExtraData_Head_Offset = MarketStateSize;
  uint256 internal constant CloseMarketHook_ExtraData_Length_Offset = 0x0200;
  uint256 internal constant CloseMarketHook_ExtraData_TailOffset = 0x0220;

  // ┌─ onCloseMarket ─────
  /// @dev call `onCloseMarket` when enabled and forward trailing `extraData` unchanged.
  function onCloseMarket(HooksConfig self, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onCloseMarketSelector = uint32(IHooks.onCloseMarket.selector);
    if (self.useOnCloseMarket()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), CloseMarketCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onCloseMarketSelector)
        mcopy(headPointer, state, MarketStateSize)
        mstore(add(headPointer, CloseMarketHook_ExtraData_Head_Offset), CloseMarketHook_ExtraData_Length_Offset)
        mstore(add(headPointer, CloseMarketHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(
          add(headPointer, CloseMarketHook_ExtraData_TailOffset),
          CloseMarketCalldataSize,
          extraCalldataBytes
        )

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(CloseMarketHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnCloseMarket ─────
  /// @dev whether to call the hook for closeMarket.
  function useOnCloseMarket(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_CloseMarket);
  }

  // ░░▒▒▓▓██ [ SUPPLY CAPACITY ] ──────────────────────────────────────────────

  uint256 internal constant SetMaxTotalSupplyCalldataSize = 0x24;
  // fixed call size: selector + maxTotalSupply + state + extraData.offset + extraData.length
  uint256 internal constant SetMaxTotalSupplyHook_Base_Size = 0x0244;
  uint256 internal constant SetMaxTotalSupplyHook_State_Offset = 0x20;
  uint256 internal constant SetMaxTotalSupplyHook_ExtraData_Head_Offset = 0x0200;
  uint256 internal constant SetMaxTotalSupplyHook_ExtraData_Length_Offset = 0x0220;
  uint256 internal constant SetMaxTotalSupplyHook_ExtraData_TailOffset = 0x0240;

  // ┌─ onSetMaxTotalSupply ─────
  /// @dev call `onSetMaxTotalSupply` when enabled; the hook may accept or revert, not rewrite it.
  function onSetMaxTotalSupply(HooksConfig self, uint256 maxTotalSupply, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onSetMaxTotalSupplySelector = uint32(IHooks.onSetMaxTotalSupply.selector);
    if (self.useOnSetMaxTotalSupply()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), SetMaxTotalSupplyCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onSetMaxTotalSupplySelector)
        mstore(headPointer, maxTotalSupply)
        mcopy(add(headPointer, SetMaxTotalSupplyHook_State_Offset), state, MarketStateSize)
        mstore(
          add(headPointer, SetMaxTotalSupplyHook_ExtraData_Head_Offset),
          SetMaxTotalSupplyHook_ExtraData_Length_Offset
        )
        mstore(add(headPointer, SetMaxTotalSupplyHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(
          add(headPointer, SetMaxTotalSupplyHook_ExtraData_TailOffset),
          SetMaxTotalSupplyCalldataSize,
          extraCalldataBytes
        )

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(SetMaxTotalSupplyHook_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnSetMaxTotalSupply ─────
  /// @dev whether to call the hook for setMaxTotalSupply.
  function useOnSetMaxTotalSupply(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetMaxTotalSupply);
  }

  // ░░▒▒▓▓██ [ INTEREST AND RESERVES ] ────────────────────────────────────────

  uint256 internal constant SetAnnualInterestAndReserveRatioBipsCalldataSize = 0x44;
  // fixed call size: selector + annualInterestBips + reserveRatioBips + state + extraData.offset + extraData.length
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_Base_Size = 0x0264;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ReserveRatioBips_Offset = 0x20;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_State_Offset = 0x40;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Head_Offset = 0x0220;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Length_Offset = 0x0240;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ExtraData_TailOffset = 0x0260;

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  /// @dev call the term-change hook when enabled and return its final APR and reserve ratio.
  ///      when disabled, return the caller's values unchanged.
  function onSetAnnualInterestAndReserveRatioBips(
    HooksConfig self,
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState memory state
  )
    internal
    returns (uint16 newAnnualInterestBips, uint16 newReserveRatioBips)
  {
    address target = self.hooksAddress();
    uint32 onSetAnnualInterestBipsSelector = uint32(IHooks.onSetAnnualInterestAndReserveRatioBips.selector);
    if (self.useOnSetAnnualInterestAndReserveRatioBips()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), SetAnnualInterestAndReserveRatioBipsCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onSetAnnualInterestBipsSelector)
        mstore(headPointer, annualInterestBips)
        mstore(add(headPointer, SetAnnualInterestAndReserveRatioBipsHook_ReserveRatioBips_Offset), reserveRatioBips)
        mcopy(add(headPointer, SetAnnualInterestAndReserveRatioBipsHook_State_Offset), state, MarketStateSize)
        mstore(
          add(headPointer, SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Head_Offset),
          SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Length_Offset
        )
        mstore(add(headPointer, SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(
          add(headPointer, SetAnnualInterestAndReserveRatioBipsHook_ExtraData_TailOffset),
          SetAnnualInterestAndReserveRatioBipsCalldataSize,
          extraCalldataBytes
        )

        let size := add(SetAnnualInterestAndReserveRatioBipsHook_Base_Size, extraCalldataBytes)

        // the hook supplies both final terms. require two return words, then mask each to uint16.
        if or(lt(returndatasize(), 0x40), iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0x40))) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }

        newAnnualInterestBips := and(mload(0), 0xffff)
        newReserveRatioBips := and(mload(0x20), 0xffff)
      }
    } else {
      (newAnnualInterestBips, newReserveRatioBips) = (annualInterestBips, reserveRatioBips);
    }
  }

  // ┌─ useOnSetAnnualInterestAndReserveRatioBips ─────
  /// @dev whether to call the hook for setAnnualInterestAndReserveRatioBips.
  function useOnSetAnnualInterestAndReserveRatioBips(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips);
  }

  // ┌─ useOnExecutePendingAnnualInterestBipsReduction ─────
  /// @dev whether to call the hook for executePendingAnnualInterestBipsReduction.
  function useOnExecutePendingAnnualInterestBipsReduction(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_ExecutePendingAnnualInterestBipsReduction);
  }

  // ░░▒▒▓▓██ [ PROTOCOL FEES ] ────────────────────────────────────────────────

  uint256 internal constant SetProtocolFeeBipsCalldataSize = 0x24;
  // fixed call size: selector + protocolFeeBips + state + extraData.offset + extraData.length
  uint256 internal constant SetProtocolFeeBips_Base_Size = 0x0244;
  uint256 internal constant SetProtocolFeeBips_State_Offset = 0x20;
  uint256 internal constant SetProtocolFeeBips_ExtraData_Head_Offset = 0x0200;
  uint256 internal constant SetProtocolFeeBips_ExtraData_Length_Offset = 0x0220;
  uint256 internal constant SetProtocolFeeBips_ExtraData_TailOffset = 0x0240;

  // ┌─ onSetProtocolFeeBips ─────
  /// @dev call `onSetProtocolFeeBips` when enabled and bubble any hook revert.
  function onSetProtocolFeeBips(HooksConfig self, uint256 protocolFeeBips, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onSetProtocolFeeBipsSelector = uint32(IHooks.onSetProtocolFeeBips.selector);
    if (self.useOnSetProtocolFeeBips()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), SetProtocolFeeBipsCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onSetProtocolFeeBipsSelector)
        mstore(headPointer, protocolFeeBips)
        mcopy(add(headPointer, SetProtocolFeeBips_State_Offset), state, MarketStateSize)
        mstore(add(headPointer, SetProtocolFeeBips_ExtraData_Head_Offset), SetProtocolFeeBips_ExtraData_Length_Offset)
        mstore(add(headPointer, SetProtocolFeeBips_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(
          add(headPointer, SetProtocolFeeBips_ExtraData_TailOffset),
          SetProtocolFeeBipsCalldataSize,
          extraCalldataBytes
        )

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(SetProtocolFeeBips_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnSetProtocolFeeBips ─────
  /// @dev whether to call the hook for setProtocolFeeBips.
  function useOnSetProtocolFeeBips(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetProtocolFeeBips);
  }

  // ░░▒▒▓▓██ [ SANCTIONS ] ────────────────────────────────────────────────────

  uint256 internal constant NukeFromOrbitCalldataSize = 0x24;
  // fixed call size: selector + lender + state + extraData.offset + extraData.length
  uint256 internal constant NukeFromOrbit_Base_Size = 0x0244;
  uint256 internal constant NukeFromOrbit_State_Offset = 0x20;
  uint256 internal constant NukeFromOrbit_ExtraData_Head_Offset = 0x0200;
  uint256 internal constant NukeFromOrbit_ExtraData_Length_Offset = 0x0220;
  uint256 internal constant NukeFromOrbit_ExtraData_TailOffset = 0x0240;

  // ┌─ onNukeFromOrbit ─────
  /// @dev call `onNukeFromOrbit` before the market quarantines a sanctioned lender.
  function onNukeFromOrbit(HooksConfig self, address lender, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onNukeFromOrbitSelector = uint32(IHooks.onNukeFromOrbit.selector);
    if (self.useOnNukeFromOrbit()) {
      uint256 calldataPointer;
      uint256 calldataSize;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), NukeFromOrbitCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        mstore(cdPointer, onNukeFromOrbitSelector)
        mstore(headPointer, lender)
        mcopy(add(headPointer, NukeFromOrbit_State_Offset), state, MarketStateSize)
        mstore(add(headPointer, NukeFromOrbit_ExtraData_Head_Offset), NukeFromOrbit_ExtraData_Length_Offset)
        mstore(add(headPointer, NukeFromOrbit_ExtraData_Length_Offset), extraCalldataBytes)
        calldatacopy(
          add(headPointer, NukeFromOrbit_ExtraData_TailOffset),
          NukeFromOrbitCalldataSize,
          extraCalldataBytes
        )

        calldataPointer := add(cdPointer, 0x1c)
        calldataSize := add(NukeFromOrbit_Base_Size, extraCalldataBytes)
      }
      _callHook(target, calldataPointer, calldataSize);
    }
  }

  // ┌─ useOnNukeFromOrbit ─────
  /// @dev whether to call the hook when quarantining a sanctioned account.
  function useOnNukeFromOrbit(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_NukeFromOrbit);
  }

  // ░░▒▒▓▓██ [ CALL DISPATCH ] ────────────────────────────────────────────────

  // ┌─ _callHook ─────
  /// @dev share the no-return hook call and revert path instead of cloning it for each callback.
  function _callHook(address target, uint256 calldataPointer, uint256 calldataSize) private {
    assembly {
      // callers built contiguous ABI calldata. the pointer usually skips 28 padding bytes
      // to reach the selector at word offset 0x1c. forward remaining gas, no ETH, no return buffer.
      if iszero(call(gas(), target, 0, calldataPointer, calldataSize, 0, 0)) {
        // bubble the hook's exact error, including custom-error arguments.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }
}
