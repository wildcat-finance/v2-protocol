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
//  _prepareHookCalldata(...)
//  _callHookWithState(...)
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

  // ┌─ onDeposit ─────
  /// @dev call `onDeposit` when enabled and forward bytes appended after the deposit arguments.
  function onDeposit(HooksConfig self, address lender, uint256 scaledAmount, MarketState memory state) internal {
    if (self.useOnDeposit()) {
      assembly {
        let headPointer := add(mload(0x40), 0x20)
        mstore(headPointer, lender)
        mstore(add(headPointer, 0x20), scaledAmount)
      }
      _callHookWithState(self, uint32(IHooks.onDeposit.selector), 2, state, DepositCalldataSize);
    }
  }

  // ┌─ useOnDeposit ─────
  /// @dev whether to call the hook for deposit.
  function useOnDeposit(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Deposit);
  }

  // ░░▒▒▓▓██ [ WITHDRAWAL QUEUEING ] ──────────────────────────────────────────

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
    if (self.useOnQueueWithdrawal()) {
      assembly {
        let headPointer := add(mload(0x40), 0x20)
        mstore(headPointer, lender)
        mstore(add(headPointer, 0x20), expiry)
        mstore(add(headPointer, 0x40), scaledAmount)
      }
      _callHookWithState(self, uint32(IHooks.onQueueWithdrawal.selector), 3, state, baseCalldataSize);
    }
  }

  // ┌─ useOnQueueWithdrawal ─────
  /// @dev whether to call the hook for queueWithdrawal.
  function useOnQueueWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_QueueWithdrawal);
  }

  // ░░▒▒▓▓██ [ CLAIM COLLECTION ] ─────────────────────────────────────────────

  // ┌─ onExecuteWithdrawal ─────
  /// @dev v2.5 markets never enable this callback (the constructor rejects the flag); retained for
  ///      the shared encoder harness. forwards trailing `extraData` unchanged.
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
    if (self.useOnExecuteWithdrawal()) {
      assembly {
        let headPointer := add(mload(0x40), 0x20)
        mstore(headPointer, lender)
        mstore(add(headPointer, 0x20), expiry)
        mstore(add(headPointer, 0x40), normalizedAmountWithdrawn)
      }
      _callHookWithState(self, uint32(IHooks.onExecuteWithdrawal.selector), 3, state, baseCalldataSize);
    }
  }

  // ┌─ useOnExecuteWithdrawal ─────
  /// @dev whether the config enables the unsupported executeWithdrawal callback.
  function useOnExecuteWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_ExecuteWithdrawal);
  }

  // ░░▒▒▓▓██ [ TRANSFERS ] ────────────────────────────────────────────────────

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
    if (self.useOnTransfer()) {
      assembly {
        let headPointer := add(mload(0x40), 0x20)
        mstore(headPointer, caller())
        mstore(add(headPointer, 0x20), from)
        mstore(add(headPointer, 0x40), to)
        mstore(add(headPointer, 0x60), scaledAmount)
      }
      _callHookWithState(self, uint32(IHooks.onTransfer.selector), 4, state, baseCalldataSize);
    }
  }

  // ┌─ useOnTransfer ─────
  /// @dev whether to call the hook for transfer.
  function useOnTransfer(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Transfer);
  }

  // ░░▒▒▓▓██ [ BORROWING ] ────────────────────────────────────────────────────

  uint256 internal constant BorrowCalldataSize = 0x24;

  // ┌─ onBorrow ─────
  /// @dev call `onBorrow` when enabled and forward bytes appended after the borrow amount.
  function onBorrow(HooksConfig self, uint256 normalizedAmount, MarketState memory state) internal {
    if (self.useOnBorrow()) {
      assembly {
        mstore(add(mload(0x40), 0x20), normalizedAmount)
      }
      _callHookWithState(self, uint32(IHooks.onBorrow.selector), 1, state, BorrowCalldataSize);
    }
  }

  // ┌─ useOnBorrow ─────
  /// @dev whether to call the hook for borrow.
  function useOnBorrow(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_Borrow);
  }

  // ░░▒▒▓▓██ [ REPAYMENT ] ────────────────────────────────────────────────────

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
    if (self.useOnRepay()) {
      assembly {
        mstore(add(mload(0x40), 0x20), normalizedAmount)
      }
      _callHookWithState(self, uint32(IHooks.onRepay.selector), 1, state, baseCalldataSize);
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

  // ┌─ onCloseMarket ─────
  /// @dev call `onCloseMarket` when enabled and forward trailing `extraData` unchanged.
  function onCloseMarket(HooksConfig self, MarketState memory state) internal {
    if (self.useOnCloseMarket()) {
      _callHookWithState(self, uint32(IHooks.onCloseMarket.selector), 0, state, CloseMarketCalldataSize);
    }
  }

  // ┌─ useOnCloseMarket ─────
  /// @dev whether to call the hook for closeMarket.
  function useOnCloseMarket(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_CloseMarket);
  }

  // ░░▒▒▓▓██ [ SUPPLY CAPACITY ] ──────────────────────────────────────────────

  uint256 internal constant SetMaxTotalSupplyCalldataSize = 0x24;

  // ┌─ onSetMaxTotalSupply ─────
  /// @dev call `onSetMaxTotalSupply` when enabled; the hook may accept or revert, not rewrite it.
  function onSetMaxTotalSupply(HooksConfig self, uint256 maxTotalSupply, MarketState memory state) internal {
    if (self.useOnSetMaxTotalSupply()) {
      assembly {
        mstore(add(mload(0x40), 0x20), maxTotalSupply)
      }
      _callHookWithState(self, uint32(IHooks.onSetMaxTotalSupply.selector), 1, state, SetMaxTotalSupplyCalldataSize);
    }
  }

  // ┌─ useOnSetMaxTotalSupply ─────
  /// @dev whether to call the hook for setMaxTotalSupply.
  function useOnSetMaxTotalSupply(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetMaxTotalSupply);
  }

  // ░░▒▒▓▓██ [ INTEREST AND RESERVES ] ────────────────────────────────────────

  uint256 internal constant SetAnnualInterestAndReserveRatioBipsCalldataSize = 0x44;

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
    if (self.useOnSetAnnualInterestAndReserveRatioBips()) {
      assembly {
        let headPointer := add(mload(0x40), 0x20)
        mstore(headPointer, annualInterestBips)
        mstore(add(headPointer, 0x20), reserveRatioBips)
      }
      (uint256 calldataPointer, uint256 calldataSize) = _prepareHookCalldata(
        uint32(IHooks.onSetAnnualInterestAndReserveRatioBips.selector),
        2,
        state,
        SetAnnualInterestAndReserveRatioBipsCalldataSize
      );
      address target = self.hooksAddress();
      assembly {
        // the hook supplies both final terms. require two return words, then mask each to uint16.
        if or(lt(returndatasize(), 0x40), iszero(call(gas(), target, 0, calldataPointer, calldataSize, 0, 0x40))) {
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

  // ┌─ onSetProtocolFeeBips ─────
  /// @dev call `onSetProtocolFeeBips` when enabled and bubble any hook revert.
  function onSetProtocolFeeBips(HooksConfig self, uint256 protocolFeeBips, MarketState memory state) internal {
    if (self.useOnSetProtocolFeeBips()) {
      assembly {
        mstore(add(mload(0x40), 0x20), protocolFeeBips)
      }
      _callHookWithState(self, uint32(IHooks.onSetProtocolFeeBips.selector), 1, state, SetProtocolFeeBipsCalldataSize);
    }
  }

  // ┌─ useOnSetProtocolFeeBips ─────
  /// @dev whether to call the hook for setProtocolFeeBips.
  function useOnSetProtocolFeeBips(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_SetProtocolFeeBips);
  }

  // ░░▒▒▓▓██ [ SANCTIONS ] ────────────────────────────────────────────────────

  uint256 internal constant NukeFromOrbitCalldataSize = 0x24;

  // ┌─ onNukeFromOrbit ─────
  /// @dev call `onNukeFromOrbit` before the market quarantines a sanctioned lender.
  function onNukeFromOrbit(HooksConfig self, address lender, MarketState memory state) internal {
    if (self.useOnNukeFromOrbit()) {
      assembly {
        mstore(add(mload(0x40), 0x20), lender)
      }
      _callHookWithState(self, uint32(IHooks.onNukeFromOrbit.selector), 1, state, NukeFromOrbitCalldataSize);
    }
  }

  // ┌─ useOnNukeFromOrbit ─────
  /// @dev whether to call the hook when quarantining a sanctioned account.
  function useOnNukeFromOrbit(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(Bit_Enabled_NukeFromOrbit);
  }

  // ░░▒▒▓▓██ [ CALL DISPATCH ] ────────────────────────────────────────────────

  // ┌─ _prepareHookCalldata ─────
  /// @dev every market callback has the shape `(static args..., MarketState state, bytes extraData)`.
  ///      callers write the `headWords` static argument words at `mload(0x40) + 0x20` before calling.
  ///      this writes the selector before them, copies `state` after them, then appends the
  ///      `extraData` head, length, and the caller's trailing calldata past `baseCalldataSize`.
  ///      the buffer sits past the free memory pointer and is never reserved, so nothing may
  ///      allocate memory between the caller's head writes and this call.
  ///
  /// @return calldataPointer start of the ABI-encoded call, at the selector.
  /// @return calldataSize    total call size, including the selector.
  function _prepareHookCalldata(
    uint32 selector,
    uint256 headWords,
    MarketState memory state,
    uint256 baseCalldataSize
  )
    private
    pure
    returns (uint256 calldataPointer, uint256 calldataSize)
  {
    assembly {
      let cdPointer := mload(0x40)
      mstore(cdPointer, selector)
      let headSize := shl(5, headWords)
      let statePointer := add(add(cdPointer, 0x20), headSize)
      mcopy(statePointer, state, MarketStateSize)
      // `extraData` offset counts from the first head word: static args, the state block, and
      // the offset word itself.
      let extraDataLengthOffset := add(headSize, add(MarketStateSize, 0x20))
      let extraDataHeadPointer := add(statePointer, MarketStateSize)
      mstore(extraDataHeadPointer, extraDataLengthOffset)
      let extraCalldataBytes := sub(calldatasize(), baseCalldataSize)
      mstore(add(extraDataHeadPointer, 0x20), extraCalldataBytes)
      calldatacopy(add(extraDataHeadPointer, 0x40), baseCalldataSize, extraCalldataBytes)

      // the selector occupies the last four bytes of its word.
      calldataPointer := add(cdPointer, 0x1c)
      // selector + head + state + offset word + length word + extraData.
      calldataSize := add(add(0x24, extraDataLengthOffset), extraCalldataBytes)
    }
  }

  // ┌─ _callHookWithState ─────
  /// @dev build the callback and make the no-return hook call, bubbling any revert.
  function _callHookWithState(
    HooksConfig self,
    uint32 selector,
    uint256 headWords,
    MarketState memory state,
    uint256 baseCalldataSize
  )
    private
  {
    (uint256 calldataPointer, uint256 calldataSize) = _prepareHookCalldata(selector, headWords, state, baseCalldataSize);
    address target = self.hooksAddress();
    assembly {
      // forward remaining gas, no ETH, no return buffer.
      if iszero(call(gas(), target, 0, calldataPointer, calldataSize, 0, 0)) {
        // bubble the hook's exact error, including custom-error arguments.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }
}
