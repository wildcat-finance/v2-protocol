// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import './HooksTemplateData.sol';
import './HooksInstanceData.sol';
import '../IHooksFactory.sol';
import '../WildcatArchController.sol';

using HooksDataForBorrowerLib for HooksDataForBorrower global;

/// @notice borrower-facing hooks templates and instances from one factory.
/// @dev `isRegisteredBorrower` checks the address directly. it does not resolve borrower accounts.
struct HooksDataForBorrower {
  address borrower;
  bool isRegisteredBorrower;
  HooksTemplateData[] hooksTemplates;
  HooksInstanceData[] hooksInstances;
}

/// @notice builds one-factory hooks views for a borrower address.
library HooksDataForBorrowerLib {
  /// @notice fills borrower status plus every template and borrower-indexed instance in `factory`.
  function fill(
    HooksDataForBorrower memory data,
    WildcatArchController archController,
    IHooksFactory factory,
    address borrower
  ) internal view {
    data.borrower = borrower;
    data.isRegisteredBorrower = archController.isRegisteredBorrower(borrower);
    address[] memory hooksInstances = factory.getHooksInstancesForBorrower(borrower);
    data.hooksInstances = new HooksInstanceData[](hooksInstances.length);
    for (uint256 i; i < hooksInstances.length; i++) {
      address hooksInstance = hooksInstances[i];
      HooksInstanceKind kind = HooksConfigDataLib.kindForHooks(hooksInstance);
      data.hooksInstances[i].fill(hooksInstance, factory, borrower, kind);
    }
    address[] memory hooksTemplates = factory.getHooksTemplates();
    data.hooksTemplates = new HooksTemplateData[](hooksTemplates.length);
    for (uint256 i; i < hooksTemplates.length; i++) {
      data.hooksTemplates[i].fill(factory, hooksTemplates[i], borrower);
    }
  }
}
