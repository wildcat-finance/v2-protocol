// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

type HooksConfig is uint256;

using LibHooksConfig for HooksConfig global;

uint256 constant BitsAfterUseDepositHook = 95;
uint256 constant BitsAfterUseQueueWithdrawalHook = 94;
uint256 constant BitsAfterUseExecuteWithdrawalHook = 93;
uint256 constant BitsAfterUseTransferHook = 92;
uint256 constant BitsAfterUseBorrowHook = 91;
uint256 constant BitsAfterUseRepayHook = 90;
uint256 constant BitsAfterUseCloseMarketHook = 89;
uint256 constant BitsAfterUseAssetsSentToEscrowHook = 88;
uint256 constant BitsAfterSetMaxTotalSupplyHook = 87;
uint256 constant BitsAfterSetAnnualInterestBipsHook = 86;

uint256 constant DepositCalldataSize = 0x24;
uint256 constant QueueWithdrawalCalldataSize = 0x24;
uint256 constant BorrowCalldataSize = 0x24;
uint256 constant RepayCalldataSize = 0x24;

library LibHooksConfig {
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
  function useDepositHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseDepositHook);
  }

  /// @dev Whether to call hook contract for QueueWithdrawal
  function useQueueWithdrawalHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseQueueWithdrawalHook);
  }

  /// @dev Whether to call hook contract for executeWithdrawal
  function useExecuteWithdrawalHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseExecuteWithdrawalHook);
  }

  /// @dev Whether to call hook contract for transfer
  function useTransferHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseTransferHook);
  }

  /// @dev Whether to call hook contract for borrow
  function useBorrowHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseBorrowHook);
  }

  /// @dev Whether to call hook contract for repay
  function useRepayHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseRepayHook);
  }

  /// @dev Whether to call hook contract for closeMarket
  function useCloseMarketHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseCloseMarketHook);
  }

  /// @dev Whether to call hook contract when account sanctioned
  function useAssetsSentToEscrowHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseAssetsSentToEscrowHook);
  }

  function useSetMaxTotalSupplyHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterSetMaxTotalSupplyHook);
  }

  function useSetAnnualInterestBipsHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterSetAnnualInterestBipsHook);
  }

  /// @dev Base size of calldata in a call to `deposit(uint amount)`
  /// Any bytes added to the end of the calldata will be passed to the
  /// deposit hook if the market is set to use it.
  uint internal constant DepositCalldataSize = 0x24;

  function depositHook(HooksConfig hooks, address lender, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint depositHookSelector = 0x00;
    if (hooks.useDepositHook()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, depositHookSelector)
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

  function queueWithdrawalHook(
    HooksConfig hooks,
    address lender,
    uint256 scaledAmount
  ) internal {
    address target = hooks.hooksAddress();
    uint queueWithdrawalHookSelector = 0x00;
    if (hooks.useQueueWithdrawalHook()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), QueueWithdrawalCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, queueWithdrawalHookSelector)
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

  function transferHook(HooksConfig hooks, address from, address to, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint transferHookSelector = 0x00;
    if (hooks.useTransferHook()) {
      assembly {
        let ptr := mload(0x40)
        mstore(ptr, transferHookSelector)
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

  
  function executeWithdrawalHook(HooksConfig hooks, address lender, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint depositHookSelector = 0x00;
    if (hooks.useExecuteWithdrawalHook()) {
      assembly {
        // @todo determine if any extra data is even needed for things not triggered by lenders
        // let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, depositHookSelector)
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

  function borrowHook(HooksConfig hooks, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint borrowHookSelector = 0x00;
    if (hooks.useBorrowHook()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), BorrowCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, borrowHookSelector)
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

  function repayHook(HooksConfig hooks, uint256 amount) internal {
    address target = hooks.hooksAddress();
    uint repayHookSelector = 0x00;
    if (hooks.useRepayHook()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), RepayCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, repayHookSelector)
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


}
