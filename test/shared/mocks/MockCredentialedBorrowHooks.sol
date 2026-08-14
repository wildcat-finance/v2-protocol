// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'src/access/BaseAccessControls.sol';
import 'src/access/IHooks.sol';
import 'src/interfaces/WildcatStructsAndEnums.sol';
import 'src/libraries/MarketState.sol';
import 'src/types/HooksConfig.sol';
import 'src/types/LenderStatus.sol';

interface ICredentialedBorrowMarket {
  function borrower() external view returns (address);

  function borrowerPrincipal() external view returns (address);
}

/**
 * @dev Test-only borrow hook that uses the existing role-provider machinery
 *      to validate the market's current principal.
 */
contract MockCredentialedBorrowHooks is IHooks, BaseAccessControls {
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
    if (constructorArgs.length > 0) {
      _initialize(abi.decode(constructorArgs, (NameAndProviderInputs)));
    }
  }

  function version() external pure override returns (string memory) {
    return 'mock-credentialed-borrow-hooks';
  }

  function _onCreateMarket(
    address marketAdministrator,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata
  ) internal override returns (HooksConfig marketHooksConfig) {
    if (marketAdministrator != administrator) revert CallerNotAdministrator();
    isHookedMarket[marketAddress] = true;
    marketHooksConfig = parameters.hooks.mergeFlags(config);
  }

  function onDeposit(
    address,
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onQueueWithdrawal(
    address,
    uint32,
    uint,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onExecuteWithdrawal(
    address,
    uint128,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onTransfer(
    address,
    address,
    address,
    uint,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onRepay(
    uint,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onCloseMarket(
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onNukeFromOrbit(
    address,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onSetMaxTotalSupply(
    uint256,
    MarketState calldata,
    bytes calldata
  ) external override {}

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata,
    bytes calldata
  ) external pure override returns (uint16, uint16) {
    return (annualInterestBips, reserveRatioBips);
  }

  function onSetProtocolFeeBips(
    uint16,
    MarketState memory,
    bytes calldata
  ) external override {}

  function onBorrow(
    uint,
    MarketState calldata,
    bytes calldata extraData
  ) external override {
    if (!isHookedMarket[msg.sender]) revert NotHookedMarket();

    ICredentialedBorrowMarket market = ICredentialedBorrowMarket(msg.sender);
    address currentBorrower = market.borrower();
    address currentPrincipal = market.borrowerPrincipal();
    LenderStatus memory status = _lenderStatus[currentPrincipal];
    if (!_tryValidateAccess(status, currentPrincipal, extraData)) {
      revert BorrowCredentialRequired();
    }

    lastBorrower[msg.sender] = currentBorrower;
    lastBorrowerPrincipal[msg.sender] = currentPrincipal;
  }
}
