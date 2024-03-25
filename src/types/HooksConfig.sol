// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

type HooksConfig is uint256;

using LibHooksConfig for HooksConfig global;

uint256 constant BitsAfterUseDepositHook = 95;
uint256 constant BitsAfterUseRequestWithdrawalHook = 94;
uint256 constant BitsAfterUseExecuteWithdrawalHook = 93;
uint256 constant BitsAfterUseTransferHook = 92;
uint256 constant BitsAfterUseBorrowHook = 91;
uint256 constant BitsAfterUseRepayHook = 90;
uint256 constant BitsAfterUseCloseMarketHook = 89;
uint256 constant BitsAfterUseAssetsSentToEscrowHook = 88;

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

  /// @dev Whether to call hook contract for requestWithdrawal
  function useRequestWithdrawalHook(HooksConfig hooks) internal pure returns (bool) {
    return hooks.readFlag(BitsAfterUseRequestWithdrawalHook);
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

  /// @dev Base size of calldata in a call to `deposit(uint amount)`
  /// Any bytes added to the end of the calldata will be passed to the
  /// deposit hook if the market is set to use it.
  uint internal constant DepositCalldataSize = 0x24;

  function executeDepositHook(HooksConfig hooks, address lender, uint256 scaledAmount) internal {
    address target = hooks.hooksAddress();
    uint depositSelector = 0x00;
    if (hooks.useDepositHook()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, depositSelector)
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

  function executeRequestWithdrawalHook(
    HooksConfig hooks,
    address lender,
    uint256 scaledAmount
  ) internal {
    address target = hooks.hooksAddress();
    uint depositSelector = 0x00;
    if (hooks.useRequestWithdrawalHook()) {
      assembly {
        let extraCalldataBytes := sub(calldatasize(), DepositCalldataSize)
        let ptr := mload(0x40)
        mstore(ptr, depositSelector)
        mstore(add(ptr, 0x20), lender)
        mstore(add(ptr, 0x40), scaledAmount)
        calldatacopy(add(ptr, 0x60), DepositCalldataSize, extraCalldataBytes)
        let size := add(0x44, extraCalldataBytes)
        if iszero(call(gas(), target, 0, add(ptr, 0x1c), size, 0, 0)) {
          returndatacopy(0, 0, returndatasize())
          revert(0, returndatasize())
        }
      }
    }
  }
}
