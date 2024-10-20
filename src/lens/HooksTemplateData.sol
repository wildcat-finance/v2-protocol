// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '../HooksFactory.sol';
import './TokenData.sol';

using HooksTemplateDataLib for HooksTemplateData global;
using HooksTemplateDataLib for FeeConfiguration global;

struct HooksTemplateData {
  address hooksTemplate;
  FeeConfiguration fees;
  bool exists;
  bool enabled;
  uint24 index;
  string name;
  uint256 totalMarkets;
}

struct FeeConfiguration {
  address feeRecipient;
  /// @dev Basis points paid on interest for markets deployed using hooks
  ///      based on this template
  uint16 protocolFeeBips;
  /// @dev Asset used to pay origination fee
  TokenMetadata originationFeeToken;
  /// @dev Amount of `originationFeeAsset` paid to deploy a new market using
  ///      an instance of this template.
  uint256 originationFeeAmount;
  /// @dev Balance of the borrower in `originationFeeAsset`
  uint256 borrowerOriginationFeeBalance;
  /// @dev Approval from the borrower for the hooks factory to transfer `originationFeeAsset`
  uint256 borrowerOriginationFeeApproval;
}

library HooksTemplateDataLib {
  function fill(
    HooksTemplateData memory data,
    HooksFactory factory,
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

  function fill(
    FeeConfiguration memory data,
    HooksTemplate memory template,
    HooksFactory factory,
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
