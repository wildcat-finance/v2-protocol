// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import 'src/WildcatArchController.sol';
import 'src/HooksFactory.sol';

contract MockArchControllerOwner {
  WildcatArchController internal immutable archController;
  HooksFactory internal immutable hooksFactory;

  mapping(address => bool) public authorizedAccounts;

  constructor(address _archController, address _hooksFactory) {
    archController = WildcatArchController(_archController);
    hooksFactory = HooksFactory(_hooksFactory);
    authorizedAccounts[msg.sender] = true;
  }

  modifier onlyAuthorized() {
    require(authorizedAccounts[msg.sender], 'not authorized');
    _;
  }

  function authorizeAccount(address account) external onlyAuthorized {
    authorizedAccounts[account] = true;
  }

  function returnOwnership() external onlyAuthorized {
    archController.transferOwnership(msg.sender);
  }

  function registerBorrower(address borrower) external {
    archController.registerBorrower(borrower);
  }

  function registerBorrowers(address[] calldata borrowers) external {
    for (uint256 i; i < borrowers.length; i++) {
      archController.registerBorrower(borrowers[i]);
    }
  }
  function addHooksTemplate(
    address hooksTemplate,
    string calldata name,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external {
    hooksFactory.addHooksTemplate(
      hooksTemplate,
      name,
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external onlyAuthorized {
    hooksFactory.updateHooksTemplateFees(
      hooksTemplate,
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function disableHooksTemplate(address hooksTemplate) external onlyAuthorized {
    hooksFactory.disableHooksTemplate(hooksTemplate);
  }
}

//     // function setProtocolFeeConfiguration(
//     //     WildcatMarketControllerFactory factory,
//     //     address feeRecipient,
//     //     address originationFeeAsset,
//     //     uint80 originationFeeAmount,
//     //     uint16 protocolFeeBips
//     // ) external {
//     //     require(authorizedAccounts[msg.sender], "not authorized");
//     //     factory.setProtocolFeeConfiguration(feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips);
//     // }
// }
