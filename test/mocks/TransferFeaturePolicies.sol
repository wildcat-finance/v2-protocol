// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

/// @dev the concrete hook delegates this to its existing administrator and registration checks.
abstract contract FeatureAuthority {
  function _authorizeFeatureManagement(address market) internal view virtual;
}

/// @dev test-only recipient rule. it owns no credentials or term state.
abstract contract RecipientRestrictionPolicy is FeatureAuthority {
  error RecipientRestricted();

  event RecipientRestrictionUpdated(address indexed market, address recipient);

  mapping(address => address) public restrictedRecipient;

  function setRestrictedRecipient(address market, address recipient) external {
    _authorizeFeatureManagement(market);
    restrictedRecipient[market] = recipient;
    emit RecipientRestrictionUpdated(market, recipient);
  }

  function _recipientAllowed(address market, address recipient) internal view returns (bool) {
    address restricted = restrictedRecipient[market];
    return restricted == address(0) || restricted != recipient;
  }

  function _checkTransferRecipient(address market, address recipient) internal view {
    if (!_recipientAllowed(market, recipient)) revert RecipientRestricted();
  }
}

/// @dev test-only per-transfer limit. cumulative volume records activity; it isn't a quota.
abstract contract TransferAmountPolicy is FeatureAuthority {
  error ZeroTransferAmountLimit();
  error TransferAmountLimitExceeded();

  event TransferAmountLimitUpdated(address indexed market, uint256 maximumScaledAmount);
  event TransferVolumeRecorded(address indexed market, uint256 scaledAmount, uint256 total);

  mapping(address => uint256) public maximumScaledTransfer;
  mapping(address => uint256) public scaledTransferVolume;

  function setTransferAmountLimit(address market, uint256 maximumScaledAmount) external {
    _authorizeFeatureManagement(market);
    _setTransferAmountLimit(market, maximumScaledAmount);
  }

  function _setTransferAmountLimit(address market, uint256 maximumScaledAmount) internal {
    if (maximumScaledAmount == 0) revert ZeroTransferAmountLimit();
    maximumScaledTransfer[market] = maximumScaledAmount;
    emit TransferAmountLimitUpdated(market, maximumScaledAmount);
  }

  function _recordTransferAmount(address market, uint256 scaledAmount) internal {
    if (scaledAmount > maximumScaledTransfer[market]) revert TransferAmountLimitExceeded();
    uint256 previous = scaledTransferVolume[market];
    uint256 total;
    // don't turn this observational total into a global transfer lock if it overflows.
    unchecked {
      total = previous + scaledAmount;
      if (total < previous) total = type(uint256).max;
    }
    scaledTransferVolume[market] = total;
    emit TransferVolumeRecorded(market, scaledAmount, total);
  }
}

/// @dev explicit integration of two independent rules. term behavior stays with the term policy.
abstract contract TransferFeatures is RecipientRestrictionPolicy, TransferAmountPolicy {
  function _applyTransferFeatures(
    address market,
    address recipient,
    uint256 scaledAmount
  ) internal {
    // default credentials have already run. a recipient rejection must undo this volume write too.
    _recordTransferAmount(market, scaledAmount);
    _checkTransferRecipient(market, recipient);
  }
}
