// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';

/// @dev one extra recipient rule, shared by the callback and its no-data view.
contract RecipientRestrictionHooks is OpenTermHooks {
  error RecipientRestricted();

  address public immutable restrictedMarket;
  address public immutable restrictedRecipient;

  constructor(
    address administrator,
    address market,
    address recipient
  ) OpenTermHooks(administrator, '') {
    restrictedMarket = market;
    restrictedRecipient = recipient;
  }

  function _recipientAllowed(address market, address recipient) internal view returns (bool) {
    return market != restrictedMarket || recipient != restrictedRecipient;
  }

  function _checkTransfer(
    address,
    address,
    address to,
    uint256,
    MarketState calldata,
    bytes calldata
  ) internal view override {
    if (!_recipientAllowed(msg.sender, to)) revert RecipientRestricted();
  }

  function _featureTransferRecipientAllowed(
    address market,
    address recipient
  ) internal view override returns (bool) {
    return _recipientAllowed(market, recipient);
  }
}
