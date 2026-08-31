// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '../HooksFactory.sol';
import './TokenData.sol';

using HooksTemplateDataLib for HooksTemplateData global;
using HooksTemplateDataLib for FeeConfiguration global;

/// @notice metadata, fees, and deployment count for one hooks template.
struct HooksTemplateData {
  address hooksTemplate;
  FeeConfiguration fees;
  bool exists;
  bool enabled;
  uint24 index;
  string name;
  uint256 totalMarkets;
}

/// @notice template fee terms, with optional balance and allowance data for one borrower.
struct FeeConfiguration {
  address feeRecipient;
  /// @dev basis points of lender interest charged to markets using this template.
  uint16 protocolFeeBips;
  /// @dev metadata for the origination-fee asset. zeroed when there is no fee asset.
  TokenMetadata originationFeeToken;
  /// @dev amount of the origination-fee asset required for market deployment.
  uint256 originationFeeAmount;
  /// @dev borrower balance in the fee asset. zero when no borrower was requested.
  uint256 borrowerOriginationFeeBalance;
  /// @dev borrower allowance to the hooks factory. zero when no borrower was requested.
  uint256 borrowerOriginationFeeApproval;
}

/// @notice fillers for hooks-template metadata and borrower fee readiness.
library HooksTemplateDataLib {
  /// @notice fills template metadata and fee readiness for `borrower`.
  /// @dev pass a zero borrower to skip balance and allowance reads.
  function fill(
    HooksTemplateData memory data,
    IHooksFactory factory,
    address hooksTemplate,
    address borrower
  ) internal view {
    HooksTemplate memory template = factory.getHooksTemplateDetails(hooksTemplate);
    data.hooksTemplate = hooksTemplate;
    data.exists = template.exists;
    data.enabled = template.enabled;
    data.index = template.index;
    data.name = template.name;
    data.totalMarkets = factory.getMarketsForHooksTemplateCount(hooksTemplate);
    data.fees.fill(template, factory, borrower);
  }

  /// @notice fills the fee tuple from an already-loaded template.
  function fill(
    FeeConfiguration memory data,
    HooksTemplate memory template,
    IHooksFactory factory,
    address borrower
  ) internal view {
    data.feeRecipient = template.feeRecipient;
    data.protocolFeeBips = template.protocolFeeBips;
    data.originationFeeAmount = template.originationFeeAmount;
    if (template.originationFeeAsset != address(0)) {
      data.originationFeeToken.fill(template.originationFeeAsset);
      if (borrower != address(0)) {
        IERC20 feeAsset = IERC20(template.originationFeeAsset);
        data.borrowerOriginationFeeBalance = feeAsset.balanceOf(borrower);
        data.borrowerOriginationFeeApproval = feeAsset.allowance(borrower, address(factory));
      }
    }
  }
}
