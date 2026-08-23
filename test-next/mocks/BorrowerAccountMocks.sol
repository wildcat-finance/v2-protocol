// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { IBorrowerIdentityRegistry } from 'src/interfaces/IBorrowerIdentityRegistry.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { Bit_Enabled_Borrow, EmptyHooksConfig, HooksConfig, HooksDeploymentConfig, encodeHooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';

contract ExecutingBorrowerAccountMock {
  error CallerNotPrincipal();

  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  receive() external payable {}

  function principal() public view returns (address) {
    return registry.principalOf(address(this));
  }

  function execute(
    address target,
    uint256 value,
    bytes calldata data
  ) external payable returns (bytes memory result) {
    if (msg.sender != principal()) revert CallerNotPrincipal();

    bool success;
    (success, result) = target.call{ value: value }(data);
    if (!success) {
      assembly ('memory-safe') {
        revert(add(result, 0x20), mload(result))
      }
    }
  }
}

contract ExecutingBorrowerAccountFactoryMock {
  IBorrowerIdentityRegistry public immutable registry;

  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  function deployAccount(address principal) external returns (address account) {
    account = address(new ExecutingBorrowerAccountMock(address(registry)));
    registry.registerBorrowerAccount(account, principal);
  }
}

interface ICredentialedBorrowMarket {
  function borrower() external view returns (address);

  function borrowerPrincipal() external view returns (address);
}

contract CredentialedBorrowHooksMock is IHooks, BaseAccessControls {
  error BorrowCredentialRequired();
  error NotHookedMarket();

  HooksDeploymentConfig public immutable override config;
  mapping(address market => bool) public isHookedMarket;
  mapping(address market => address) public lastBorrower;
  mapping(address market => address) public lastBorrowerPrincipal;

  constructor(
    address administrator_,
    bytes memory constructorArgs
  ) IHooks() BaseAccessControls(administrator_) {
    config = encodeHooksDeploymentConfig(
      EmptyHooksConfig,
      EmptyHooksConfig.setFlag(Bit_Enabled_Borrow)
    );
    if (constructorArgs.length != 0) {
      _initialize(abi.decode(constructorArgs, (NameAndProviderInputs)));
    }
  }

  function version() external pure override returns (string memory) {
    return 'credentialed-borrow-test-hook';
  }

  function _onCreateMarket(
    address marketAdministrator,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata
  ) internal override returns (HooksConfig) {
    if (marketAdministrator != administrator) revert CallerNotAdministrator();
    isHookedMarket[marketAddress] = true;
    return parameters.hooks.mergeFlags(config);
  }

  function onBorrow(uint256, MarketState calldata, bytes calldata extraData) external override {
    if (!isHookedMarket[msg.sender]) revert NotHookedMarket();

    ICredentialedBorrowMarket market = ICredentialedBorrowMarket(msg.sender);
    address account = market.borrower();
    address principal = market.borrowerPrincipal();
    LenderStatus memory status = _lenderStatus[principal];
    if (!_tryValidateAccess(status, principal, extraData)) revert BorrowCredentialRequired();

    lastBorrower[msg.sender] = account;
    lastBorrowerPrincipal[msg.sender] = principal;
  }

  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override {}

  function onQueueWithdrawal(
    address,
    uint32,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onExecuteWithdrawal(
    address,
    uint32,
    uint128,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onTransfer(
    address,
    address,
    address,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onRepay(uint256, MarketState calldata, bytes calldata) external override {}

  function onCloseMarket(MarketState calldata, bytes calldata) external override {}

  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override {}

  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override {}

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata,
    bytes calldata
  ) external pure override returns (uint16, uint16) {
    return (annualInterestBips, reserveRatioBips);
  }

  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override {}
}
