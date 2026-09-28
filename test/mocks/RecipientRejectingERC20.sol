// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';

contract RecipientRejectingERC20 is MockERC20 {
  error RecipientRejected();

  address public rejectedRecipient;
  bool public returnsFalse;

  constructor() MockERC20('Token', 'TKN', 18) {}

  function rejectRecipient(address recipient, bool returnFalse) external {
    rejectedRecipient = recipient;
    returnsFalse = returnFalse;
  }

  function transfer(address to, uint256 amount) public override returns (bool) {
    if (to == rejectedRecipient) {
      if (returnsFalse) return false;
      revert RecipientRejected();
    }
    return super.transfer(to, amount);
  }

  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    if (to == rejectedRecipient) {
      if (returnsFalse) return false;
      revert RecipientRejected();
    }
    return super.transferFrom(from, to, amount);
  }
}
