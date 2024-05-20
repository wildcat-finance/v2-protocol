pragma solidity ^0.8.20;

import 'src/libraries/MarketState.sol';
import { StdAssertions } from 'forge-std/StdAssertions.sol';
import { LibString } from 'solady/utils/LibString.sol';
import 'src/types/HooksConfig.sol';
import './StandardStructs.sol';

using LibString for uint256;

contract Assertions is StdAssertions {
  function assertEq(
    MarketState memory actual,
    MarketState memory expected,
    string memory key
  ) internal {
    assertEq(actual.maxTotalSupply, expected.maxTotalSupply, string.concat(key, '.maxTotalSupply'));
    assertEq(
      actual.accruedProtocolFees,
      expected.accruedProtocolFees,
      string.concat(key, '.accruedProtocolFees')
    );
    assertEq(
      actual.normalizedUnclaimedWithdrawals,
      expected.normalizedUnclaimedWithdrawals,
      string.concat(key, '.normalizedUnclaimedWithdrawals')
    );
    assertEq(
      actual.scaledTotalSupply,
      expected.scaledTotalSupply,
      string.concat(key, '.scaledTotalSupply')
    );
    assertEq(
      actual.scaledPendingWithdrawals,
      expected.scaledPendingWithdrawals,
      string.concat(key, '.scaledPendingWithdrawals')
    );
    assertEq(
      actual.pendingWithdrawalExpiry,
      expected.pendingWithdrawalExpiry,
      string.concat(key, '.pendingWithdrawalExpiry')
    );
    assertEq(actual.isDelinquent, expected.isDelinquent, string.concat(key, '.isDelinquent'));
    assertEq(actual.timeDelinquent, expected.timeDelinquent, string.concat(key, '.timeDelinquent'));
    assertEq(
      actual.annualInterestBips,
      expected.annualInterestBips,
      string.concat(key, '.annualInterestBips')
    );
    assertEq(
      actual.reserveRatioBips,
      expected.reserveRatioBips,
      string.concat(key, '.reserveRatioBips')
    );
    assertEq(actual.scaleFactor, expected.scaleFactor, string.concat(key, '.scaleFactor'));
    assertEq(
      actual.lastInterestAccruedTimestamp,
      expected.lastInterestAccruedTimestamp,
      string.concat(key, '.lastInterestAccruedTimestamp')
    );
  }

  function assertEq(MarketState memory actual, MarketState memory expected) internal {
    assertEq(actual, expected, 'MarketState');
  }

  function assertEq(uint32[] memory actual, uint32[] memory expected, string memory key) internal {
    assertEq(actual.length, expected.length, string.concat(key, '.length'));
    for (uint256 i = 0; i < actual.length; i++) {
      assertEq(actual[i], expected[i], string.concat(key, '[', i.toString(), ']'));
    }
  }

  function assertEq(uint32[] memory actual, uint32[] memory expected) internal {
    assertEq(actual, expected, 'uint32[]');
  }

  function assertEq(
    RoleProvider actual,
    StandardRoleProvider memory expected,
    string memory labelPrefix
  ) internal {
    assertEq(
      actual.providerAddress(),
      expected.providerAddress,
      string.concat(labelPrefix, 'providerAddress')
    );
    assertEq(actual.timeToLive(), expected.timeToLive, string.concat(labelPrefix, 'timeToLive'));
    assertEq(
      actual.pullProviderIndex(),
      expected.pullProviderIndex,
      string.concat(labelPrefix, 'pullProviderIndex')
    );
  }

  function assertEq(RoleProvider actual, StandardRoleProvider memory expected) internal {
    assertEq(actual, expected, 'RoleProvider.');
  }

  function assertEq(
    HooksConfig actual,
    StandardHooksConfig memory expected,
    string memory labelPrefix
  ) internal {
    assertEq(
      actual.hooksAddress(),
      expected.hooksAddress,
      string.concat(labelPrefix, 'hooksAddress')
    );
    assertEq(
      actual.useOnDeposit(),
      expected.useOnDeposit,
      string.concat(labelPrefix, 'useOnDeposit')
    );
    assertEq(
      actual.useOnQueueWithdrawal(),
      expected.useOnQueueWithdrawal,
      string.concat(labelPrefix, 'useOnQueueWithdrawal')
    );
    assertEq(
      actual.useOnExecuteWithdrawal(),
      expected.useOnExecuteWithdrawal,
      string.concat(labelPrefix, 'useOnExecuteWithdrawal')
    );
    assertEq(
      actual.useOnTransfer(),
      expected.useOnTransfer,
      string.concat(labelPrefix, 'useOnTransfer')
    );
    assertEq(actual.useOnBorrow(), expected.useOnBorrow, string.concat(labelPrefix, 'useOnBorrow'));
    assertEq(actual.useOnRepay(), expected.useOnRepay, string.concat(labelPrefix, 'useOnRepay'));
    assertEq(
      actual.useOnCloseMarket(),
      expected.useOnCloseMarket,
      string.concat(labelPrefix, 'useOnCloseMarket')
    );
    assertEq(
      actual.useOnAssetsSentToEscrow(),
      expected.useOnAssetsSentToEscrow,
      string.concat(labelPrefix, 'useOnAssetsSentToEscrow')
    );
    assertEq(
      actual.useOnSetMaxTotalSupply(),
      expected.useOnSetMaxTotalSupply,
      string.concat(labelPrefix, 'useOnSetMaxTotalSupply')
    );
    assertEq(
      actual.useOnSetAnnualInterestAndReserveRatioBips(),
      expected.useOnSetAnnualInterestAndReserveRatioBips,
      string.concat(labelPrefix, 'useOnSetAnnualInterestAndReserveRatioBips')
    );
  }

  function assertEq(HooksConfig actual, StandardHooksConfig memory expected) internal {
    assertEq(actual, expected, 'HooksConfig.');
  }
}
