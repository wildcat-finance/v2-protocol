// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';

contract BaseAccessControlsHarness is BaseAccessControls {
  constructor(
    address administrator,
    NameAndProviderInputs memory inputs
  ) BaseAccessControls(administrator) {
    _initialize(inputs);
  }

  function tryValidateAccess(
    address accountAddress,
    bytes calldata hooksData
  ) external returns (bool hasValidCredential, bool wasUpdated) {
    bytes32 beforeHash = keccak256(abi.encode(_lenderStatus[accountAddress]));
    hasValidCredential = _tryValidateAccess(
      _lenderStatus[accountAddress],
      accountAddress,
      hooksData
    );
    wasUpdated = beforeHash != keccak256(abi.encode(_lenderStatus[accountAddress]));
  }

  function setIsKnownLender(address account, address market, bool isKnownLender) external {
    isKnownLenderOnMarket[account][market] = isKnownLender;
  }

  function isMarketTransferRecipientAllowed(
    address market,
    address recipient,
    bool transferRequiresAccess
  ) external view returns (bool) {
    return _isMarketTransferRecipientAllowed(market, recipient, transferRequiresAccess);
  }
}
