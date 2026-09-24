// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { FeatureAuthority } from './TransferFeaturePolicies.sol';

/// @dev test-only per-borrow limit, in underlying asset units. no scaled-balance conversion here.
abstract contract BorrowAmountPolicy is FeatureAuthority {
  error BorrowAmountLimitExceeded();

  event BorrowAmountLimitUpdated(address indexed market, uint256 maximumNormalizedAmount);
  event BorrowAmountRecorded(address indexed market, uint256 normalizedAmount);

  mapping(address => uint256) public maximumNormalizedBorrow;
  mapping(address => uint256) public lastNormalizedBorrow;

  function setBorrowAmountLimit(address market, uint256 maximumNormalizedAmount) external {
    _authorizeFeatureManagement(market);
    _setBorrowAmountLimit(market, maximumNormalizedAmount);
  }

  function _setBorrowAmountLimit(address market, uint256 maximumNormalizedAmount) internal {
    // zero disables positive borrows. it doesn't affect deposits, transfers, or withdrawals.
    maximumNormalizedBorrow[market] = maximumNormalizedAmount;
    emit BorrowAmountLimitUpdated(market, maximumNormalizedAmount);
  }

  function _recordBorrowAmount(address market, uint256 normalizedAmount) internal {
    if (normalizedAmount > maximumNormalizedBorrow[market]) revert BorrowAmountLimitExceeded();
    lastNormalizedBorrow[market] = normalizedAmount;
    emit BorrowAmountRecorded(market, normalizedAmount);
  }
}
