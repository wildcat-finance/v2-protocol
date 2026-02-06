// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../access/IHooks.sol';
import '../libraries/MarketState.sol';

type HooksConfig is uint256;

HooksConfig constant EmptyHooksConfig = HooksConfig.wrap(0);

using LibHooksConfig for HooksConfig global;
using LibHooksConfig for HooksDeploymentConfig global;

// Type that contains only the flags for a specific hooks contract, with one
// set of flags for optional hooks and one set of flags for required hooks.
type HooksDeploymentConfig is uint256;

function encodeHooksDeploymentConfig(
  HooksConfig optionalFlags,
  HooksConfig requiredFlags
) pure returns (HooksDeploymentConfig flags) {
  assembly {
    let cleanedOptionalFlags := and(0xffff, shr(0x50, optionalFlags)) // using 12 of 16 now
    let cleanedRequiredFlags := and(0xffff0000, shr(0x40, requiredFlags))
    flags := or(cleanedOptionalFlags, cleanedRequiredFlags)
  }
}

// --------------------- Bits after hook activation flag -------------------- //

// Offsets are from the right

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
uint256 constant Bit_Enabled_SetCommitmentFeeBips = 84;

uint256 constant MarketStateSize = 0x0200;
uint256 constant WordSize = 0x20;
uint256 constant SelectorSize = 0x04;

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
  bool useOnSetProtocolFeeBips,
  bool useOnSetCommitmentFeeBips
) pure returns (HooksConfig hooks) {
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
    hooks := or(
      hooks,
      shl(
        Bit_Enabled_SetAnnualInterestAndReserveRatioBips,
        useOnSetAnnualInterestAndReserveRatioBips
      )
    )
    hooks := or(hooks, shl(Bit_Enabled_SetProtocolFeeBips, useOnSetProtocolFeeBips))
    hooks := or(hooks, shl(Bit_Enabled_SetCommitmentFeeBips, useOnSetCommitmentFeeBips))
  }
}

library LibHooksConfig {
  function setHooksAddress(
    HooksConfig hooks,
    address _hooksAddress
  ) internal pure returns (HooksConfig updatedHooks) {
    assembly {
      // Shift twice to clear the address
      updatedHooks := shr(96, shl(96, hooks))
      // Set the new address
      updatedHooks := or(updatedHooks, shl(96, _hooksAddress))
    }
  }

  /**
   * @dev Create a merged HooksConfig with the shared flags of `a` and `b`
   *      and the address of `a`.
   */
  function mergeSharedFlags(
    HooksConfig a,
    HooksConfig b
  ) internal pure returns (HooksConfig merged) {
    assembly {
      let addressA := shl(0x60, shr(0x60, a))
      let flagsA := shl(0xa0, a)
      let flagsB := shl(0xa0, b)
      let mergedFlags := shr(0xa0, and(flagsA, flagsB))
      merged := or(addressA, mergedFlags)
    }
  }

  /**
   * @dev Create a merged HooksConfig with the shared flags of `a` and `b`
   *      and the address of `a`.
   */
  function mergeAllFlags(HooksConfig a, HooksConfig b) internal pure returns (HooksConfig merged) {
    assembly {
      let addressA := shl(0x60, shr(0x60, a))
      let flagsA := shl(0xa0, a)
      let flagsB := shl(0xa0, b)
      let mergedFlags := shr(0xa0, or(flagsA, flagsB))
      merged := or(addressA, mergedFlags)
    }
  }

  function mergeFlags(
    HooksConfig config,
    HooksDeploymentConfig flags
  ) internal pure returns (HooksConfig merged) {
    assembly {
      let _hooksAddress := shl(96, shr(96, config))
      // Position flags at the end of the word
      let configFlags := shr(0x50, config)
      // Optional flags are already in the right position, required flags must be
      // shifted to align with the other flags. The leading and trailing bits for all 3
      // words will be masked out at the end
      let _optionalFlags := flags
      let _requiredFlags := shr(0x10, flags)
      let mergedFlags := and(0xffff, or(and(configFlags, _optionalFlags), _requiredFlags))

      merged := or(_hooksAddress, shl(0x50, mergedFlags))
    }
  }

  function optionalFlags(HooksDeploymentConfig flags) internal pure returns (HooksConfig config) {
    assembly {
      config := shl(0x50, and(flags, 0xffff))
    }
  }

  function requiredFlags(HooksDeploymentConfig flags) internal pure returns (HooksConfig config) {
    assembly {
      config := shl(0x40, and(flags, 0xffff0000))
    }
  }

  // ========================================================================== //
  //                              Parameter Readers                             //
  // ========================================================================== //

  function readFlag(HooksConfig hooks, uint256 bitsAfter) internal pure returns (bool flagged) {
    assembly {
      flagged := and(shr(bitsAfter, hooks), 1)
    }
  }

  function setFlag(
    HooksConfig hooks,
    uint256 bitsAfter
  ) internal pure returns (HooksConfig updatedHooks) {
    assembly {
      updatedHooks := or(hooks, shl(bitsAfter, 1))
    }
  }

  function clearFlag(
    HooksConfig hooks,
    uint256 bitsAfter
  ) internal pure returns (HooksConfig updatedHooks) {
    assembly {
      updatedHooks := and(hooks, not(shl(bitsAfter, 1)))
    }
  }

  /// @dev Address of the hooks contract
  function hooksAddress(HooksConfig hooks) internal pure returns (address _hooks) {
    assembly {
      _hooks := shr(96, hooks)
    }
  }

  /// @dev Whether to call hook contract for deposit
  function useOnDeposit(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Deposit);
  }

  /// @dev Whether to call hook contract for queueWithdrawal
  function useOnQueueWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_QueueWithdrawal);
  }

  /// @dev Whether to call hook contract for executeWithdrawal
  function useOnExecuteWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_ExecuteWithdrawal);
  }

  /// @dev Whether to call hook contract for transfer
  function useOnTransfer(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Transfer);
  }

  /// @dev Whether to call hook contract for borrow
  function useOnBorrow(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Borrow);
  }

  /// @dev Whether to call hook contract for repay
  function useOnRepay(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Repay);
  }

  /// @dev Whether to call hook contract for closeMarket
  function useOnCloseMarket(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_CloseMarket);
  }

  /// @dev Whether to call hook contract when account sanctioned
  function useOnNukeFromOrbit(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_NukeFromOrbit);
  }

  /// @dev Whether to call hook contract for setMaxTotalSupply
  function useOnSetMaxTotalSupply(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetMaxTotalSupply);
  }

  /// @dev Whether to call hook contract for setAnnualInterestAndReserveRatioBips
  function useOnSetAnnualInterestAndReserveRatioBips(
    HooksConfig hooks
  ) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips);
  }

  /// @dev Whether to call hook contract for setProtocolFeeBips
  function useOnSetProtocolFeeBips(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetProtocolFeeBips);
  }

  /// @dev Whether to call hook contract for setCommitmentFeeBips
  function useOnSetCommitmentFeeBips(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetCommitmentFeeBips);
  }

  // ========================================================================== //
  //                              Hook for deposit                              //
  // ========================================================================== //

  uint256 internal constant DepositCalldataSize = 0x24;
  uint256 internal constant DepositHook_ScaledAmount_Offset = 0x20;
  uint256 internal constant DepositHook_State_Offset = 0x40;
  uint256 internal constant DepositHook_ExtraData_Head_Offset =
    DepositHook_State_Offset + MarketStateSize;
  uint256 internal constant DepositHook_ExtraData_Length_Offset =
    DepositHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant DepositHook_ExtraData_TailOffset =
    DepositHook_ExtraData_Length_Offset + WordSize;
  // Size of lender + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant DepositHook_Base_Size = DepositHook_ExtraData_TailOffset + SelectorSize;

  function onDeposit(
    HooksConfig self,
    address lender,
    uint256 scaledAmount,
    MarketState memory state
  ) internal {
    address target = self.hooksAddress();
    uint32 onDepositSelector = uint32(IHooks.onDeposit.selector);
    if (self.useOnDeposit()) {
      uint256 extraDataHeadOffset = DepositHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = DepositHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = DepositHook_ExtraData_TailOffset;
      uint256 baseSize = DepositHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onDeposit`
        mstore(cdPointer, onDepositSelector)
        // Write `lender` to hook calldata
        mstore(headPointer, lender)
        // Write `scaledAmount` to hook calldata
        mstore(add(headPointer, DepositHook_ScaledAmount_Offset), scaledAmount)
        // Copy market state to hook calldata
        mcopy(add(headPointer, DepositHook_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          DepositCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                          Hook for queueWithdrawal                          //
  // ========================================================================== //

  uint256 internal constant QueueWithdrawalHook_Expiry_Offset = 0x20;
  uint256 internal constant QueueWithdrawalHook_ScaledAmount_Offset = 0x40;
  uint256 internal constant QueueWithdrawalHook_State_Offset = 0x60;
  uint256 internal constant QueueWithdrawalHook_ExtraData_Head_Offset =
    QueueWithdrawalHook_State_Offset + MarketStateSize;
  uint256 internal constant QueueWithdrawalHook_ExtraData_Length_Offset =
    QueueWithdrawalHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant QueueWithdrawalHook_ExtraData_TailOffset =
    QueueWithdrawalHook_ExtraData_Length_Offset + WordSize;
  // Size of lender + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant QueueWithdrawalHook_Base_Size =
    QueueWithdrawalHook_ExtraData_TailOffset + SelectorSize;

  function onQueueWithdrawal(
    HooksConfig self,
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState memory state,
    uint256 baseCalldataSize
  ) internal {
    address target = self.hooksAddress();
    uint32 onQueueWithdrawalSelector = uint32(IHooks.onQueueWithdrawal.selector);
    if (self.useOnQueueWithdrawal()) {
      uint256 extraDataHeadOffset = QueueWithdrawalHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = QueueWithdrawalHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = QueueWithdrawalHook_ExtraData_TailOffset;
      uint256 baseSize = QueueWithdrawalHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onQueueWithdrawal`
        mstore(cdPointer, onQueueWithdrawalSelector)
        // Write `lender` to hook calldata
        mstore(headPointer, lender)
        // Write `expiry` to hook calldata
        mstore(add(headPointer, QueueWithdrawalHook_Expiry_Offset), expiry)
        // Write `scaledAmount` to hook calldata
        mstore(add(headPointer, QueueWithdrawalHook_ScaledAmount_Offset), scaledAmount)
        // Copy market state to hook calldata
        mcopy(add(headPointer, QueueWithdrawalHook_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          baseCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                         Hook for executeWithdrawal                         //
  // ========================================================================== //

  uint256 internal constant ExecuteWithdrawalHook_ScaledAmount_Offset = 0x20;
  uint256 internal constant ExecuteWithdrawalHook_State_Offset = 0x40;
  uint256 internal constant ExecuteWithdrawalHook_ExtraData_Head_Offset =
    ExecuteWithdrawalHook_State_Offset + MarketStateSize;
  uint256 internal constant ExecuteWithdrawalHook_ExtraData_Length_Offset =
    ExecuteWithdrawalHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant ExecuteWithdrawalHook_ExtraData_TailOffset =
    ExecuteWithdrawalHook_ExtraData_Length_Offset + WordSize;
  // Size of lender + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant ExecuteWithdrawalHook_Base_Size =
    ExecuteWithdrawalHook_ExtraData_TailOffset + SelectorSize;

  function onExecuteWithdrawal(
    HooksConfig self,
    address lender,
    uint256 scaledAmount,
    MarketState memory state,
    uint256 baseCalldataSize
  ) internal {
    address target = self.hooksAddress();
    uint32 onExecuteWithdrawalSelector = uint32(IHooks.onExecuteWithdrawal.selector);
    if (self.useOnExecuteWithdrawal()) {
      uint256 extraDataHeadOffset = ExecuteWithdrawalHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = ExecuteWithdrawalHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = ExecuteWithdrawalHook_ExtraData_TailOffset;
      uint256 baseSize = ExecuteWithdrawalHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onExecuteWithdrawal`
        mstore(cdPointer, onExecuteWithdrawalSelector)
        // Write `lender` to hook calldata
        mstore(headPointer, lender)
        // Write `scaledAmount` to hook calldata
        mstore(add(headPointer, ExecuteWithdrawalHook_ScaledAmount_Offset), scaledAmount)
        // Copy market state to hook calldata
        mcopy(add(headPointer, ExecuteWithdrawalHook_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          baseCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                              Hook for transfer                             //
  // ========================================================================== //

  uint256 internal constant TransferHook_From_Offset = 0x20;
  uint256 internal constant TransferHook_To_Offset = 0x40;
  uint256 internal constant TransferHook_ScaledAmount_Offset = 0x60;
  uint256 internal constant TransferHook_State_Offset = 0x80;
  uint256 internal constant TransferHook_ExtraData_Head_Offset =
    TransferHook_State_Offset + MarketStateSize;
  uint256 internal constant TransferHook_ExtraData_Length_Offset =
    TransferHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant TransferHook_ExtraData_TailOffset =
    TransferHook_ExtraData_Length_Offset + WordSize;
  // Size of caller + from + to + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant TransferHook_Base_Size = TransferHook_ExtraData_TailOffset + SelectorSize;

  function onTransfer(
    HooksConfig self,
    address from,
    address to,
    uint256 scaledAmount,
    MarketState memory state,
    uint256 baseCalldataSize
  ) internal {
    address target = self.hooksAddress();
    uint32 onTransferSelector = uint32(IHooks.onTransfer.selector);
    if (self.useOnTransfer()) {
      uint256 extraDataHeadOffset = TransferHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = TransferHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = TransferHook_ExtraData_TailOffset;
      uint256 baseSize = TransferHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onTransfer`
        mstore(cdPointer, onTransferSelector)
        // Write `caller` to hook calldata
        mstore(headPointer, caller())
        // Write `from` to hook calldata
        mstore(add(headPointer, TransferHook_From_Offset), from)
        // Write `to` to hook calldata
        mstore(add(headPointer, TransferHook_To_Offset), to)
        // Write `scaledAmount` to hook calldata
        mstore(add(headPointer, TransferHook_ScaledAmount_Offset), scaledAmount)
        // Copy market state to hook calldata
        mcopy(add(headPointer, TransferHook_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          baseCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                               Hook for borrow                              //
  // ========================================================================== //

  uint256 internal constant BorrowCalldataSize = 0x24;
  uint256 internal constant BorrowHook_State_Offset = 0x20;
  uint256 internal constant BorrowHook_ExtraData_Head_Offset =
    BorrowHook_State_Offset + MarketStateSize;
  uint256 internal constant BorrowHook_ExtraData_Length_Offset =
    BorrowHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant BorrowHook_ExtraData_TailOffset =
    BorrowHook_ExtraData_Length_Offset + WordSize;
  // Size of normalizedAmount + state + extraData.offset + extraData.length
  uint256 internal constant BorrowHook_Base_Size = BorrowHook_ExtraData_TailOffset + SelectorSize;

  function onBorrow(HooksConfig self, uint256 normalizedAmount, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onBorrowSelector = uint32(IHooks.onBorrow.selector);
    if (self.useOnBorrow()) {
      uint256 extraDataHeadOffset = BorrowHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = BorrowHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = BorrowHook_ExtraData_TailOffset;
      uint256 baseSize = BorrowHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), BorrowCalldataSize)
        let ptr := mload(0x40)
        let headPointer := add(ptr, 0x20)

        mstore(ptr, onBorrowSelector)
        // Copy `normalizedAmount` to hook calldata
        mstore(headPointer, normalizedAmount)
        // Copy market state to hook calldata
        mcopy(add(headPointer, BorrowHook_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          BorrowCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)
        if iszero(call(gas(), target, 0, add(ptr, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                               Hook for repay                               //
  // ========================================================================== //

  uint256 internal constant RepayHook_State_Offset = 0x20;
  uint256 internal constant RepayHook_ExtraData_Head_Offset =
    RepayHook_State_Offset + MarketStateSize;
  uint256 internal constant RepayHook_ExtraData_Length_Offset =
    RepayHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant RepayHook_ExtraData_TailOffset =
    RepayHook_ExtraData_Length_Offset + WordSize;
  // Size of normalizedAmount + state + extraData.offset + extraData.length
  uint256 internal constant RepayHook_Base_Size = RepayHook_ExtraData_TailOffset + SelectorSize;

  function onRepay(
    HooksConfig self,
    uint256 normalizedAmount,
    MarketState memory state,
    uint256 baseCalldataSize
  ) internal {
    address target = self.hooksAddress();
    uint32 onRepaySelector = uint32(IHooks.onRepay.selector);
    if (self.useOnRepay()) {
      uint256 extraDataHeadOffset = RepayHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = RepayHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = RepayHook_ExtraData_TailOffset;
      uint256 baseSize = RepayHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
        let ptr := mload(0x40)
        let headPointer := add(ptr, 0x20)

        mstore(ptr, onRepaySelector)
        // Copy `normalizedAmount` to hook calldata
        mstore(headPointer, normalizedAmount)
        // Copy market state to hook calldata
        mcopy(add(headPointer, RepayHook_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(add(headPointer, extraDataHeadOffset), extraDataLengthOffset)
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          baseCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)
        if iszero(call(gas(), target, 0, add(ptr, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                            Hook for closeMarket                            //
  // ========================================================================== //

  // Size of calldata to `market.closeMarket`
  uint256 internal constant CloseMarketCalldataSize = 0x04;

  uint256 internal constant CloseMarketHook_ExtraData_Head_Offset = MarketStateSize;
  uint256 internal constant CloseMarketHook_ExtraData_Length_Offset =
    CloseMarketHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant CloseMarketHook_ExtraData_TailOffset =
    CloseMarketHook_ExtraData_Length_Offset + WordSize;
  // Base size of calldata for `hooks.onCloseMarket()`
  uint256 internal constant CloseMarketHook_Base_Size =
    CloseMarketHook_ExtraData_TailOffset + SelectorSize;

  function onCloseMarket(HooksConfig self, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onCloseMarketSelector = uint32(IHooks.onCloseMarket.selector);
    if (self.useOnCloseMarket()) {
      uint256 extraDataLengthOffset = CloseMarketHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = CloseMarketHook_ExtraData_TailOffset;
      uint256 baseSize = CloseMarketHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), CloseMarketCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onCloseMarket`
        mstore(cdPointer, onCloseMarketSelector)
        // Copy market state to hook calldata
        mcopy(headPointer, state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, CloseMarketHook_ExtraData_Head_Offset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          CloseMarketCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                         Hook for setMaxTotalSupply                         //
  // ========================================================================== //

  uint256 internal constant SetMaxTotalSupplyCalldataSize = 0x24;
  uint256 internal constant SetMaxTotalSupplyHook_State_Offset = 0x20;
  uint256 internal constant SetMaxTotalSupplyHook_ExtraData_Head_Offset =
    SetMaxTotalSupplyHook_State_Offset + MarketStateSize;
  uint256 internal constant SetMaxTotalSupplyHook_ExtraData_Length_Offset =
    SetMaxTotalSupplyHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant SetMaxTotalSupplyHook_ExtraData_TailOffset =
    SetMaxTotalSupplyHook_ExtraData_Length_Offset + WordSize;
  // Size of maxTotalSupply + state + extraData.offset + extraData.length
  uint256 internal constant SetMaxTotalSupplyHook_Base_Size =
    SetMaxTotalSupplyHook_ExtraData_TailOffset + SelectorSize;

  function onSetMaxTotalSupply(
    HooksConfig self,
    uint256 maxTotalSupply,
    MarketState memory state
  ) internal {
    address target = self.hooksAddress();
    uint32 onSetMaxTotalSupplySelector = uint32(IHooks.onSetMaxTotalSupply.selector);
    if (self.useOnSetMaxTotalSupply()) {
      uint256 extraDataHeadOffset = SetMaxTotalSupplyHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = SetMaxTotalSupplyHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = SetMaxTotalSupplyHook_ExtraData_TailOffset;
      uint256 baseSize = SetMaxTotalSupplyHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), SetMaxTotalSupplyCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onSetMaxTotalSupply`
        mstore(cdPointer, onSetMaxTotalSupplySelector)
        // Write `maxTotalSupply` to hook calldata
        mstore(headPointer, maxTotalSupply)
        // Copy market state to hook calldata
        mcopy(add(headPointer, SetMaxTotalSupplyHook_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          SetMaxTotalSupplyCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                       Hook for setAnnualInterestBips                       //
  // ========================================================================== //

  uint256 internal constant SetAnnualInterestAndReserveRatioBipsCalldataSize = 0x44;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ReserveRatioBits_Offset = 0x20;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_State_Offset = 0x40;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Head_Offset =
    SetAnnualInterestAndReserveRatioBipsHook_State_Offset + MarketStateSize;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Length_Offset =
    SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Head_Offset + WordSize;
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_ExtraData_TailOffset =
    SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Length_Offset + WordSize;
  // Size of annualInterestBips + reserveRatioBips + state + extraData.offset + extraData.length
  uint256 internal constant SetAnnualInterestAndReserveRatioBipsHook_Base_Size =
    SetAnnualInterestAndReserveRatioBipsHook_ExtraData_TailOffset + SelectorSize;

  function onSetAnnualInterestAndReserveRatioBips(
    HooksConfig self,
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState memory state
  ) internal returns (uint16 newAnnualInterestBips, uint16 newReserveRatioBips) {
    address target = self.hooksAddress();
    uint32 onSetAnnualInterestBipsSelector = uint32(
      IHooks.onSetAnnualInterestAndReserveRatioBips.selector
    );
    if (self.useOnSetAnnualInterestAndReserveRatioBips()) {
      uint256 extraDataHeadOffset = SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset =
        SetAnnualInterestAndReserveRatioBipsHook_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = SetAnnualInterestAndReserveRatioBipsHook_ExtraData_TailOffset;
      uint256 baseSize = SetAnnualInterestAndReserveRatioBipsHook_Base_Size;
      assembly {
        let extraCalldataBytes := sub(
          calldatasize(),
          SetAnnualInterestAndReserveRatioBipsCalldataSize
        )
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onSetAnnualInterestBips`
        mstore(cdPointer, onSetAnnualInterestBipsSelector)
        // Write `annualInterestBips` to hook calldata
        mstore(headPointer, annualInterestBips)
        // Write `reserveRatioBips` to hook calldata
        mstore(
          add(headPointer, SetAnnualInterestAndReserveRatioBipsHook_ReserveRatioBits_Offset),
          reserveRatioBips
        )
        // Copy market state to hook calldata
        mcopy(
          add(headPointer, SetAnnualInterestAndReserveRatioBipsHook_State_Offset),
          state,
          MarketStateSize
        )
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          SetAnnualInterestAndReserveRatioBipsCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        // Returndata is expected to have the new values for `annualInterestBips` and `reserveRatioBips`
        if or(
          lt(returndatasize(), 0x40),
          iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0x40))
        ) {
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

  // ========================================================================== //
  //                     Hook for protocol fee bips updated                     //
  // ========================================================================== //

  uint256 internal constant SetProtocolFeeBipsCalldataSize = 0x24;
  uint256 internal constant SetProtocolFeeBips_State_Offset = 0x20;
  uint256 internal constant SetProtocolFeeBips_ExtraData_Head_Offset =
    SetProtocolFeeBips_State_Offset + MarketStateSize;
  uint256 internal constant SetProtocolFeeBips_ExtraData_Length_Offset =
    SetProtocolFeeBips_ExtraData_Head_Offset + WordSize;
  uint256 internal constant SetProtocolFeeBips_ExtraData_TailOffset =
    SetProtocolFeeBips_ExtraData_Length_Offset + WordSize;
  // Size of protocolFeeBips + state + extraData.offset + extraData.length
  uint256 internal constant SetProtocolFeeBips_Base_Size =
    SetProtocolFeeBips_ExtraData_TailOffset + SelectorSize;

  function onSetProtocolFeeBips(
    HooksConfig self,
    uint protocolFeeBips,
    MarketState memory state
  ) internal {
    address target = self.hooksAddress();
    uint32 onSetProtocolFeeBipsSelector = uint32(IHooks.onSetProtocolFeeBips.selector);
    if (self.useOnSetProtocolFeeBips()) {
      uint256 extraDataHeadOffset = SetProtocolFeeBips_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = SetProtocolFeeBips_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = SetProtocolFeeBips_ExtraData_TailOffset;
      uint256 baseSize = SetProtocolFeeBips_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), SetProtocolFeeBipsCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onSetProtocolFeeBips`
        mstore(cdPointer, onSetProtocolFeeBipsSelector)
        // Write `protocolFeeBips` to hook calldata
        mstore(headPointer, protocolFeeBips)
        // Copy market state to hook calldata
        mcopy(add(headPointer, SetProtocolFeeBips_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          SetProtocolFeeBipsCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

    // ========================================================================== //
  //                     Hook for commitment fee bips updated                     //
  // ========================================================================== //

  uint256 internal constant SetCommitmentFeeBipsCalldataSize = 0x24;
  uint256 internal constant SetCommitmentFeeBips_State_Offset = 0x20;
  uint256 internal constant SetCommitmentFeeBips_ExtraData_Head_Offset =
    SetCommitmentFeeBips_State_Offset + MarketStateSize;
  uint256 internal constant SetCommitmentFeeBips_ExtraData_Length_Offset =
    SetCommitmentFeeBips_ExtraData_Head_Offset + WordSize;
  uint256 internal constant SetCommitmentFeeBips_ExtraData_TailOffset =
    SetCommitmentFeeBips_ExtraData_Length_Offset + WordSize;
  // Size of commitmentFeeBips + state + extraData.offset + extraData.length
  uint256 internal constant SetCommitmentFeeBips_Base_Size =
    SetCommitmentFeeBips_ExtraData_TailOffset + SelectorSize;

  function onSetCommitmentFeeBips(
    HooksConfig self,
    uint commitmentFeeBips,
    MarketState memory state
  ) internal {
    address target = self.hooksAddress();
    uint32 onSetCommitmentFeeBipsSelector = uint32(IHooks.onSetCommitmentFeeBips.selector);
    if (self.useOnSetCommitmentFeeBips()) {
      uint256 extraDataHeadOffset = SetCommitmentFeeBips_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = SetCommitmentFeeBips_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = SetCommitmentFeeBips_ExtraData_TailOffset;
      uint256 baseSize = SetCommitmentFeeBips_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), SetCommitmentFeeBipsCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onSetCommitmentFeeBips`
        mstore(cdPointer, onSetCommitmentFeeBipsSelector)
        // Write `commitmentFeeBips` to hook calldata
        mstore(headPointer, commitmentFeeBips)
        // Copy market state to hook calldata
        mcopy(add(headPointer, SetCommitmentFeeBips_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          SetCommitmentFeeBipsCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // ========================================================================== //
  //                       Hook for assets sent to escrow                       //
  // ========================================================================== //

  uint256 internal constant NukeFromOrbitCalldataSize = 0x24;
  uint256 internal constant NukeFromOrbit_State_Offset = 0x20;
  uint256 internal constant NukeFromOrbit_ExtraData_Head_Offset =
    NukeFromOrbit_State_Offset + MarketStateSize;
  uint256 internal constant NukeFromOrbit_ExtraData_Length_Offset =
    NukeFromOrbit_ExtraData_Head_Offset + WordSize;
  uint256 internal constant NukeFromOrbit_ExtraData_TailOffset =
    NukeFromOrbit_ExtraData_Length_Offset + WordSize;
  // Size of lender + state + extraData.offset + extraData.length
  uint256 internal constant NukeFromOrbit_Base_Size =
    NukeFromOrbit_ExtraData_TailOffset + SelectorSize;

  function onNukeFromOrbit(HooksConfig self, address lender, MarketState memory state) internal {
    address target = self.hooksAddress();
    uint32 onNukeFromOrbitSelector = uint32(IHooks.onNukeFromOrbit.selector);
    if (self.useOnNukeFromOrbit()) {
      uint256 extraDataHeadOffset = NukeFromOrbit_ExtraData_Head_Offset;
      uint256 extraDataLengthOffset = NukeFromOrbit_ExtraData_Length_Offset;
      uint256 extraDataTailOffset = NukeFromOrbit_ExtraData_TailOffset;
      uint256 baseSize = NukeFromOrbit_Base_Size;
      assembly {
        let extraCalldataBytes := sub(calldatasize(), NukeFromOrbitCalldataSize)
        let cdPointer := mload(0x40)
        let headPointer := add(cdPointer, 0x20)
        // Write selector for `onNukeFromOrbit`
        mstore(cdPointer, onNukeFromOrbitSelector)
        // Write `lender` to hook calldata
        mstore(headPointer, lender)
        // Copy market state to hook calldata
        mcopy(add(headPointer, NukeFromOrbit_State_Offset), state, MarketStateSize)
        // Write bytes offset for `extraData`
        mstore(
          add(headPointer, extraDataHeadOffset),
          extraDataLengthOffset
        )
        // Write length for `extraData`
        mstore(add(headPointer, extraDataLengthOffset), extraCalldataBytes)
        // Copy `extraData` from end of calldata to hook calldata
        calldatacopy(
          add(headPointer, extraDataTailOffset),
          NukeFromOrbitCalldataSize,
          extraCalldataBytes
        )

        let size := add(baseSize, extraCalldataBytes)

        if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }
  
  /* DEV: hook removed as force buyback has been disabled in initial V2 launch
  // ========================================================================== //
  //                           Hook for forced buyback                          //
  // ========================================================================== //

  uint256 internal constant ForceBuyBackCalldataSize = 0x44;
  // Size of lender + scaledAmount + state + extraData.offset + extraData.length
  uint256 internal constant ForceBuyBackHook_Base_Size = 0x0244;
  uint256 internal constant ForceBuyBackHook_ScaledAmount_Offset = 0x20;
  uint256 internal constant ForceBuyBackHook_State_Offset = 0x40;
  uint256 internal constant ForceBuyBackHook_ExtraData_Head_Offset = 0x0200;
  uint256 internal constant ForceBuyBackHook_ExtraData_Length_Offset = 0x0220;
  uint256 internal constant ForceBuyBackHook_ExtraData_TailOffset = 0x0240;

  
  function onForceBuyBack(
    HooksConfig self,
    address lender,
    uint256 scaledAmount,
    MarketState memory state
  ) internal {
    address target = self.hooksAddress();
    uint32 onForceBuyBackSelector = uint32(IHooks.onForceBuyBack.selector);
    assembly {
      let extraCalldataBytes := sub(calldatasize(), ForceBuyBackCalldataSize)
      let cdPointer := mload(0x40)
      let headPointer := add(cdPointer, 0x20)
      // Write selector for `onForceBuyBack`
      mstore(cdPointer, onForceBuyBackSelector)
      // Write `lender` to hook calldata
      mstore(headPointer, lender)
      // Write `scaledAmount` to hook calldata
      mstore(add(headPointer, ForceBuyBackHook_ScaledAmount_Offset), scaledAmount)
      // Copy market state to hook calldata
      mcopy(add(headPointer, ForceBuyBackHook_State_Offset), state, MarketStateSize)
      // Write bytes offset for `extraData`
      mstore(
        add(headPointer, ForceBuyBackHook_ExtraData_Head_Offset),
        ForceBuyBackHook_ExtraData_Length_Offset
      )
      // Write length for `extraData`
      mstore(add(headPointer, ForceBuyBackHook_ExtraData_Length_Offset), extraCalldataBytes)
      // Copy `extraData` from end of calldata to hook calldata
      calldatacopy(
        add(headPointer, ForceBuyBackHook_ExtraData_TailOffset),
        ForceBuyBackCalldataSize,
        extraCalldataBytes
      )

      let size := add(ForceBuyBackHook_Base_Size, extraCalldataBytes)

      if iszero(call(gas(), target, 0, add(cdPointer, 0x1c), size, 0, 0)) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }
  */
}
