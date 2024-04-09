// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/types/HooksConfig.sol';
import 'forge-std/Test.sol';

struct HooksConfigFuzzInput {
  address hooksAddress;
  bool useOnDeposit;
  bool useOnQueueWithdrawal;
  bool useOnExecuteWithdrawal;
  bool useOnTransfer;
  bool useOnBorrow;
  bool useOnRepay;
  bool useOnCloseMarket;
  bool useOnAssetsSentToEscrow;
  bool useOnSetMaxTotalSupply;
  bool useOnSetAnnualInterestBips;
}

function toHooksConfig(HooksConfigFuzzInput memory input) pure returns (HooksConfig) {
  return
    encodeHooksConfig({
      hooksAddress: input.hooksAddress,
      useOnDeposit: input.useOnDeposit,
      useOnQueueWithdrawal: input.useOnQueueWithdrawal,
      useOnExecuteWithdrawal: input.useOnExecuteWithdrawal,
      useOnTransfer: input.useOnTransfer,
      useOnBorrow: input.useOnBorrow,
      useOnRepay: input.useOnRepay,
      useOnCloseMarket: input.useOnCloseMarket,
      useOnAssetsSentToEscrow: input.useOnAssetsSentToEscrow,
      useOnSetMaxTotalSupply: input.useOnSetMaxTotalSupply,
      useOnSetAnnualInterestBips: input.useOnSetAnnualInterestBips
    });
}

using { toHooksConfig } for HooksConfigFuzzInput;

contract HooksConfigTest is Test {
  function testEncode(HooksConfigFuzzInput memory input) external {
    HooksConfig hooks = input.toHooksConfig();
    assertEq(hooks.hooksAddress(), input.hooksAddress, 'Invalid hooksAddress');
    assertEq(hooks.useOnDeposit(), input.useOnDeposit, 'Invalid useOnDeposit');
    assertEq(
      hooks.useOnQueueWithdrawal(),
      input.useOnQueueWithdrawal,
      'Invalid useOnQueueWithdrawal'
    );
    assertEq(
      hooks.useOnExecuteWithdrawal(),
      input.useOnExecuteWithdrawal,
      'Invalid useOnExecuteWithdrawal'
    );
    assertEq(hooks.useOnTransfer(), input.useOnTransfer, 'Invalid useOnTransfer');
    assertEq(hooks.useOnBorrow(), input.useOnBorrow, 'Invalid useOnBorrow');
    assertEq(hooks.useOnRepay(), input.useOnRepay, 'Invalid useOnRepay');
    assertEq(hooks.useOnCloseMarket(), input.useOnCloseMarket, 'Invalid useOnCloseMarket');
    assertEq(
      hooks.useOnAssetsSentToEscrow(),
      input.useOnAssetsSentToEscrow,
      'Invalid useOnAssetsSentToEscrow'
    );
    assertEq(
      hooks.useOnSetMaxTotalSupply(),
      input.useOnSetMaxTotalSupply,
      'Invalid useOnSetMaxTotalSupply'
    );
    assertEq(
      hooks.useOnSetAnnualInterestBips(),
      input.useOnSetAnnualInterestBips,
      'Invalid useOnSetAnnualInterestBips'
    );
  }
}
