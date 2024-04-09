// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import '../access/IHooks.sol';

type HooksConfig is uint256;

using LibHooksConfig for HooksConfig global;

uint256 constant BitsAfterDeposit = 95;
uint256 constant BitsAfterQueueWithdrawal = 94;
uint256 constant BitsAfterExecuteWithdrawal = 93;
uint256 constant BitsAfterTransfer = 92;
uint256 constant BitsAfterBorrow = 91;
uint256 constant BitsAfterRepay = 90;
uint256 constant BitsAfterCloseMarket = 89;
uint256 constant BitsAfterAssetsSentToEscrow = 88;
uint256 constant BitsAfterSetMaxTotalSupply = 87;
uint256 constant BitsAfterSetAnnualInterestBips = 86;

uint256 constant DepositCalldataSize = 0x24;
uint256 constant QueueWithdrawalCalldataSize = 0x24;
uint256 constant BorrowCalldataSize = 0x24;
uint256 constant RepayCalldataSize = 0x24;

function encodeHooksConfig(
  address hooksAddress,
  bool useOnDeposit,
  bool useOnQueueWithdrawal,
  bool useOnExecuteWithdrawal,
  bool useOnTransfer,
  bool useOnBorrow,
  bool useOnRepay,
  bool useOnCloseMarket,
  bool useOnAssetsSentToEscrow,
  bool useOnSetMaxTotalSupply,
  bool useOnSetAnnualInterestBips
) pure returns (HooksConfig hooks) {
  assembly {
    hooks := shl(96, hooksAddress)
    hooks := or(hooks, shl(BitsAfterDeposit, useOnDeposit))
    hooks := or(hooks, shl(BitsAfterQueueWithdrawal, useOnQueueWithdrawal))
    hooks := or(hooks, shl(BitsAfterExecuteWithdrawal, useOnExecuteWithdrawal))
    hooks := or(hooks, shl(BitsAfterTransfer, useOnTransfer))
    hooks := or(hooks, shl(BitsAfterBorrow, useOnBorrow))
    hooks := or(hooks, shl(BitsAfterRepay, useOnRepay))
    hooks := or(hooks, shl(BitsAfterCloseMarket, useOnCloseMarket))
    hooks := or(hooks, shl(BitsAfterAssetsSentToEscrow, useOnAssetsSentToEscrow))
    hooks := or(hooks, shl(BitsAfterSetMaxTotalSupply, useOnSetMaxTotalSupply))
    hooks := or(hooks, shl(BitsAfterSetAnnualInterestBips, useOnSetAnnualInterestBips))
  }
}

library LibHooksConfig {
  // ========================================================================== //
  //                              Parameter Readers                             //
  // ========================================================================== //

  function readFlag(HooksConfig hooks, uint256 bitsAfter) internal pure returns (bool flagged) {
    assembly {
      flagged := and(shr(bitsAfter, hooks), 1)
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
    return hooks.readFlag(BitsAfterDeposit);
  }

  /// @dev Whether to call hook contract for queueWithdrawal
  function useOnQueueWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterQueueWithdrawal);
  }

  /// @dev Whether to call hook contract for executeWithdrawal
  function useOnExecuteWithdrawal(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterExecuteWithdrawal);
  }

  /// @dev Whether to call hook contract for transfer
  function useOnTransfer(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterTransfer);
  }

  /// @dev Whether to call hook contract for borrow
  function useOnBorrow(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterBorrow);
  }

  /// @dev Whether to call hook contract for repay
  function useOnRepay(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterRepay);
  }

  /// @dev Whether to call hook contract for closeMarket
  function useOnCloseMarket(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterCloseMarket);
  }

  /// @dev Whether to call hook contract when account sanctioned
  function useOnAssetsSentToEscrow(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterAssetsSentToEscrow);
  }

  /// @dev Whether to call hook contract for setMaxTotalSupply
  function useOnSetMaxTotalSupply(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterSetMaxTotalSupply);
  }

  /// @dev Whether to call hook contract for setAnnualInterestBips
  function useOnSetAnnualInterestBips(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterSetAnnualInterestBips);
  }

  function copyExtraData(
    uint256 extraDataPointer,
    uint256 baseCalldataSize
  ) internal pure returns (uint256 extraDataSize) {
    assembly {
      extraDataSize := sub(calldatasize(), baseCalldataSize)
      calldatacopy(extraDataPointer, baseCalldataSize, extraDataSize)
    }
  }

  function getFreePointer() internal pure returns (uint256 freePointer) {
    assembly {
      freePointer := mload(0x40)
    }
  }

  // ========================================================================== //
  //                              Hook Call Methods                             //
  // ========================================================================== //

  function onDeposit(HooksConfig hooks, address lender, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint32 onDepositSelector = uint32(IHooks.onDeposit.selector);
    if (hooks.useOnDeposit()) {
      uint256 freePointer = getFreePointer();

      assembly {
        let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, onDepositSelector)
        mstore(add(ptr, 0x20), lender)
        mstore(add(ptr, 0x40), scaledAmount)
        calldatacopy(add(ptr, 0x60), DepositCalldataSize, extraCalldataBytes)
        let size := add(0x44, extraCalldataBytes)
        if iszero(call(gas(), target, 0, ptr, size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onQueueWithdrawal(HooksConfig hooks, address lender, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint32 onQueueWithdrawalSelector = uint32(IHooks.onQueueWithdrawal.selector);
    if (hooks.useOnQueueWithdrawal()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), QueueWithdrawalCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, onQueueWithdrawalSelector)
        mstore(add(ptr, 0x20), lender)
        mstore(add(ptr, 0x40), scaledAmount)
        calldatacopy(add(ptr, 0x60), QueueWithdrawalCalldataSize, extraCalldataBytes)
        let size := add(0x44, extraCalldataBytes)
        if iszero(call(gas(), target, 0, add(ptr, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onExecuteWithdrawal(HooksConfig hooks, address lender, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint32 onDepositSelector = uint32(IHooks.onDeposit.selector);
    if (hooks.useOnExecuteWithdrawal()) {
      assembly {
        // @todo determine if any extra data is even needed for things not triggered by lenders
        // let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, onDepositSelector)
        mstore(add(ptr, 0x20), lender)
        mstore(add(ptr, 0x40), scaledAmount)
        // calldatacopy(add(ptr, 0x60), DepositCalldataSize, extraCalldataBytes)
        // let size := add(0x44, extraCalldataBytes)
        if iszero(call(gas(), target, 0, add(ptr, 0x1c), 0x44, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onTransfer(HooksConfig hooks, address from, address to, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint32 onTransferSelector = uint32(IHooks.onTransfer.selector);
    if (hooks.useOnTransfer()) {
      assembly {
        let ptr := mload(0x40)
        mstore(ptr, onTransferSelector)
        mstore(add(ptr, 0x20), from)
        mstore(add(ptr, 0x40), to)
        mstore(add(ptr, 0x60), scaledAmount)
        if iszero(call(gas(), target, 0, ptr, 0x80, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onBorrow(HooksConfig hooks, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint32 onBorrowSelector = uint32(IHooks.onBorrow.selector);
    if (hooks.useOnBorrow()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), BorrowCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, onBorrowSelector)
        mstore(add(ptr, 0x20), scaledAmount)
        calldatacopy(add(ptr, 0x40), BorrowCalldataSize, extraCalldataBytes)
        let size := add(0x44, extraCalldataBytes)
        if iszero(call(gas(), target, 0, add(ptr, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onRepay(HooksConfig hooks, uint256 amount) internal {
    address target = hooks.hooksAddress();
    uint32 onRepaySelector = uint32(IHooks.onRepay.selector);
    if (hooks.useOnRepay()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), RepayCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, onRepaySelector)
        mstore(add(ptr, 0x20), amount)
        calldatacopy(add(ptr, 0x40), RepayCalldataSize, extraCalldataBytes)
        let size := add(0x44, extraCalldataBytes)
        if iszero(call(gas(), target, 0, add(ptr, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onCloseMarket(HooksConfig hooks) internal {
    address target = hooks.hooksAddress();
    uint32 onCloseMarketSelector = uint32(IHooks.onCloseMarket.selector);
    if (hooks.useOnCloseMarket()) {
      assembly {
        let ptr := mload(0x40)
        mstore(ptr, onCloseMarketSelector)
        if iszero(call(gas(), target, 0, ptr, 0x20, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onSetMaxTotalSupply(HooksConfig hooks, uint256 maxTotalSupply) internal {
    address target = hooks.hooksAddress();
    uint32 onSetMaxTotalSupplySelector = uint32(IHooks.onSetMaxTotalSupply.selector);
    if (hooks.useOnSetMaxTotalSupply()) {
      assembly {
        let ptr := mload(0x40)
        mstore(ptr, onSetMaxTotalSupplySelector)
        mstore(add(ptr, 0x20), maxTotalSupply)
        if iszero(call(gas(), target, 0, ptr, 0x24, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onSetAnnualInterestBips(HooksConfig hooks, uint256 annualInterestBips) internal {
    address target = hooks.hooksAddress();
    uint32 onSetAnnualInterestBipsSelector = uint32(IHooks.onSetAnnualInterestBips.selector);
    if (hooks.useOnSetAnnualInterestBips()) {
      assembly {
        let ptr := mload(0x40)
        mstore(ptr, onSetAnnualInterestBipsSelector)
        mstore(add(ptr, 0x20), annualInterestBips)
        if iszero(call(gas(), target, 0, ptr, 0x24, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  function onAssetsSentToEscrow(
    HooksConfig hooks,
    address accountAddress,
    address asset,
    address escrow,
    uint scaledAmount
  ) internal {
    address target = hooks.hooksAddress();
    uint32 onAssetsSentToEscrowHookSelector = uint32(IHooks.onAssetsSentToEscrow.selector);
    if (hooks.useOnAssetsSentToEscrow()) {
      assembly {
        let ptr := mload(0x40)
        mstore(ptr, onAssetsSentToEscrowHookSelector)
        mstore(add(ptr, 0x20), accountAddress)
        if iszero(call(gas(), target, 0, ptr, 0x24, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }

  // function onSanctioned(HooksConfig hooks, address accountAddress) internal {
  //   address target = hooks.hooksAddress();
  //   uint32 onSanctionedSelector = uint32(IHooks.onSanctioned.selector);
  //   if (hooks.useOnSanctioned()) {
  //     assembly {
  //       let ptr := mload(0x40)
  //       mstore(ptr, onSanctionedSelector)
  //       mstore(add(ptr, 0x20), accountAddress)
  //       if iszero(call(gas(), target, 0, ptr, 0x24, 0, 0)) {
  //         returndatacopy(0, 0, returndatasize())
  //         revert(0, returndatasize())
  //       }
  //     }
  //   }
  // }
}
