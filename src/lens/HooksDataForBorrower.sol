// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './HooksTemplateData.sol';
import './HooksInstanceData.sol';
import '../IHooksFactory.sol';
import '../WildcatArchController.sol';
import '../interfaces/IWildcatArchController.sol';
import '../libraries/LibFixedCall.sol';

using HooksDataForBorrowerLib for HooksDataForBorrower global;

struct HooksDataForBorrower {
  address borrower;
  bool isRegisteredBorrower;
  HooksTemplateData[] hooksTemplates;
  HooksInstanceData[] hooksInstances;
}

library HooksDataForBorrowerLib {
  function fill(
    HooksDataForBorrower memory data,
    WildcatArchController archController,
    IHooksFactory factory,
    address borrower
  ) internal view {
    data.borrower = borrower;
    data.isRegisteredBorrower = LibFixedCall.readBool(
      address(archController),
      IWildcatArchController.isRegisteredBorrower.selector,
      borrower
    );
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
