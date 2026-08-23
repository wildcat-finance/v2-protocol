// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooksFactory, IHooksFactoryEventsAndErrors } from 'src/IHooksFactory.sol';
import { IHooksFactoryRevolving } from 'src/IHooksFactoryRevolving.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { ExistingProviderInputs, NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { IWildcatMarketRevolving } from 'src/interfaces/IWildcatMarketRevolving.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { LibStoredInitCode } from 'src/libraries/LibStoredInitCode.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { HooksConfig, HooksDeploymentConfig } from 'src/types/HooksConfig.sol';
import { CredentialedBorrowHooksMock, ExecutingBorrowerAccountFactoryMock, ExecutingBorrowerAccountMock } from '../mocks/BorrowerAccountMocks.sol';
import { ProductionMatrixFixture } from '../shared/ProductionMatrixFixture.sol';

interface IAccountMarketActions {
  function setMaxTotalSupply(uint256 maxTotalSupply) external;

  function borrow(uint256 amount) external;

  function repay(uint256 amount) external;

  function closeMarket() external;

  function requestBorrowerTransfer(address newBorrower) external;

  function acceptBorrowerTransfer() external;
}

interface IAccountTokenActions {
  function transfer(address recipient, uint256 amount) external returns (bool);

  function approve(address spender, uint256 amount) external returns (bool);
}

contract BorrowerAccountCompatibilityTest is ProductionMatrixFixture {
  address internal constant SecondPrincipal = address(0x5EC0AD);

  struct AccountContext {
    ExecutingBorrowerAccountFactoryMock factory;
    ExecutingBorrowerAccountMock account;
  }

  function test_accountExecutionComposesAcrossTheProductionSixCellMatrix() external {
    ProductionStack memory stack = _deployProductionStack();
    AccountContext memory accountContext = _deployAccount(stack, MatrixBorrower);

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      for (uint256 hooksKind; hooksKind < 3; hooksKind++) {
        MatrixOptions memory options = _defaultMatrixOptions(
          MatrixHooksKind(hooksKind),
          MatrixMarketKind(marketKind)
        );
        MatrixCell memory cell = _deployCellThroughAccount(
          stack,
          accountContext.account,
          options,
          uint96(300 + hooksKind)
        );

        assertEq(cell.market.borrower(), address(accountContext.account), 'account borrower');
        assertEq(cell.market.borrowerPrincipal(), MatrixBorrower, 'resolved principal');
        assertEq(cell.hooks.administrator(), MatrixBorrower, 'hook administrator');

        _authorize(stack, cell, MatrixAlice);
        _deposit(stack, cell, MatrixAlice, 10e18);
        vm.prank(address(stack.roleProvider));
        cell.hooks.revokeRole(MatrixAlice);
        stack.asset.mint(MatrixAlice, 1e18);
        vm.prank(MatrixAlice);
        vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
        cell.market.deposit(1e18);

        vm.prank(MatrixBorrower);
        cell.hooks.setName('Principal policy');
        _expectAccountRevert(
          accountContext.account,
          address(cell.hooks),
          abi.encodeCall(BaseAccessControls.setName, ('Account policy')),
          BaseAccessControls.CallerNotAdministrator.selector
        );

        uint256 newMaximum = cell.market.maxTotalSupply() - 1;
        vm.prank(MatrixBorrower);
        vm.expectRevert(IMarketEventsAndErrors.NotApprovedBorrower.selector);
        cell.market.setMaxTotalSupply(newMaximum);
        _execute(
          accountContext.account,
          address(cell.market),
          abi.encodeCall(IAccountMarketActions.setMaxTotalSupply, (newMaximum))
        );
        assertEq(cell.market.maxTotalSupply(), newMaximum, 'account market authority');
      }
    }

    vm.prank(MatrixCaller);
    vm.expectRevert(ExecutingBorrowerAccountMock.CallerNotPrincipal.selector);
    accountContext.account.execute(address(stack.asset), 0, '');
  }

  function test_accountExecutesCompleteLifecycleAcrossBothMarketTypes() external {
    ProductionStack memory stack = _deployProductionStack();
    AccountContext memory accountContext = _deployAccount(stack, MatrixBorrower);

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      MatrixCell memory cell = _deployCellThroughAccount(
        stack,
        accountContext.account,
        _defaultMatrixOptions(MatrixHooksKind.OpenTerm, MatrixMarketKind(marketKind)),
        uint96(310 + marketKind)
      );
      _authorize(stack, cell, MatrixAlice);
      _deposit(stack, cell, MatrixAlice, 100e18);

      uint256 draw = cell.market.borrowableAssets() / 2;
      _execute(
        accountContext.account,
        address(cell.market),
        abi.encodeCall(IAccountMarketActions.borrow, (draw))
      );
      assertEq(stack.asset.balanceOf(address(accountContext.account)), draw, 'draw recipient');

      _execute(
        accountContext.account,
        address(stack.asset),
        abi.encodeCall(IAccountTokenActions.transfer, (MatrixBorrower, draw))
      );
      vm.prank(MatrixBorrower);
      stack.asset.transfer(address(accountContext.account), draw);
      _execute(
        accountContext.account,
        address(stack.asset),
        abi.encodeCall(IAccountTokenActions.approve, (address(cell.market), type(uint256).max))
      );
      _execute(
        accountContext.account,
        address(cell.market),
        abi.encodeCall(IAccountMarketActions.repay, (draw / 2))
      );
      _execute(
        accountContext.account,
        address(cell.market),
        abi.encodeCall(IAccountMarketActions.closeMarket, ())
      );

      assertTrue(cell.market.isClosed(), 'account close');
      assertEq(stack.asset.balanceOf(address(accountContext.account)), 0, 'account remainder');
      if (marketKind == uint256(MatrixMarketKind.Revolving)) {
        assertEq(
          IWildcatMarketRevolving(address(cell.market)).drawnAmount(),
          0,
          'revolving principal'
        );
      }
    }
  }

  function test_credentialedBorrowTracksAccountAndPrincipalMigrationAcrossFactories() external {
    for (uint256 marketKind; marketKind < 2; marketKind++) {
      _runCredentialedBorrowMigration(MatrixMarketKind(marketKind), uint96(320 + marketKind));
    }
  }

  function test_marketSaltIsBoundToTheOperationalAccountAcrossFactories() external {
    ProductionStack memory stack = _deployProductionStack();
    AccountContext memory accountContext = _deployAccount(stack, MatrixBorrower);

    for (uint256 marketKind; marketKind < 2; marketKind++) {
      MatrixOptions memory options = _defaultMatrixOptions(
        MatrixHooksKind.OpenTerm,
        MatrixMarketKind(marketKind)
      );
      BaseAccessControls hooks = _deployHooksThroughAccount(
        stack,
        accountContext.account,
        options.marketKind,
        stack.hooksTemplates[uint256(MatrixHooksKind.OpenTerm)],
        ''
      );
      DeployMarketInputs memory inputs = _marketInputs(stack, options, _requestedHooks(hooks));
      bytes memory callData = _marketDeploymentCall(
        options,
        inputs,
        _hooksData(options, vm.getBlockTimestamp()),
        _marketSalt(MatrixBorrower, uint96(330 + marketKind))
      );

      _expectAccountRevert(
        accountContext.account,
        address(_factoryFor(stack, options.marketKind)),
        callData,
        IHooksFactoryEventsAndErrors.SaltDoesNotContainSender.selector
      );
    }
  }

  function _runCredentialedBorrowMigration(MatrixMarketKind marketKind, uint96 nonce) private {
    ProductionStack memory stack = _deployProductionStack();
    AccountContext memory accountContext = _deployAccount(stack, MatrixBorrower);
    stack.roleProvider.setIsPullProvider(true);
    MatrixCell memory cell = _deployCredentialedBorrowCell(
      stack,
      accountContext.account,
      marketKind,
      nonce
    );
    _deposit(stack, cell, MatrixAlice, 100e18);

    _expectAccountRevert(
      accountContext.account,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.borrow, (10e18)),
      CredentialedBorrowHooksMock.BorrowCredentialRequired.selector
    );
    stack.roleProvider.setCredential(MatrixBorrower, uint32(vm.getBlockTimestamp()));
    _execute(
      accountContext.account,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.borrow, (10e18))
    );
    _assertCredentialedBorrow(cell, address(accountContext.account), MatrixBorrower);

    ExecutingBorrowerAccountMock nextAccount = ExecutingBorrowerAccountMock(
      payable(accountContext.factory.deployAccount(MatrixBorrower))
    );
    _execute(
      accountContext.account,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.requestBorrowerTransfer, (address(nextAccount)))
    );
    _execute(
      nextAccount,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.acceptBorrowerTransfer, ())
    );
    _execute(
      nextAccount,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.borrow, (10e18))
    );
    _assertCredentialedBorrow(cell, address(nextAccount), MatrixBorrower);

    stack.archController.registerBorrower(SecondPrincipal);
    vm.prank(MatrixBorrower);
    stack.registry.requestBorrowerAccountPrincipalTransfer(address(nextAccount), SecondPrincipal);
    vm.prank(SecondPrincipal);
    stack.registry.acceptBorrowerAccountPrincipalTransfer(address(nextAccount));
    _execute(
      nextAccount,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.requestBorrowerTransfer, (address(nextAccount)))
    );
    _execute(
      nextAccount,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.acceptBorrowerTransfer, ())
    );
    assertEq(cell.market.borrowerPrincipal(), SecondPrincipal, 'migrated market principal');

    _expectAccountRevert(
      nextAccount,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.borrow, (10e18)),
      CredentialedBorrowHooksMock.BorrowCredentialRequired.selector
    );
    stack.roleProvider.setCredential(SecondPrincipal, uint32(vm.getBlockTimestamp()));
    _execute(
      nextAccount,
      address(cell.market),
      abi.encodeCall(IAccountMarketActions.borrow, (10e18))
    );
    _assertCredentialedBorrow(cell, address(nextAccount), SecondPrincipal);
  }

  function _deployAccount(
    ProductionStack memory stack,
    address principal
  ) private returns (AccountContext memory accountContext) {
    accountContext.factory = ExecutingBorrowerAccountFactoryMock(
      _deployCode(
        'test-next/mocks/BorrowerAccountMocks.sol:ExecutingBorrowerAccountFactoryMock',
        abi.encode(address(stack.registry))
      )
    );
    stack.registry.addAccountFactory(address(accountContext.factory));
    accountContext.account = ExecutingBorrowerAccountMock(
      payable(accountContext.factory.deployAccount(principal))
    );
  }

  function _deployCellThroughAccount(
    ProductionStack memory stack,
    ExecutingBorrowerAccountMock account,
    MatrixOptions memory options,
    uint96 nonce
  ) private returns (MatrixCell memory cell) {
    cell.options = options;
    cell.operationalBorrower = address(account);
    cell.borrowerPrincipal = account.principal();
    cell.deployedAt = vm.getBlockTimestamp();
    cell.hooksTemplate = stack.hooksTemplates[uint256(options.hooksKind)];
    cell.hooks = _deployHooksThroughAccount(
      stack,
      account,
      options.marketKind,
      cell.hooksTemplate,
      ''
    );
    vm.prank(cell.borrowerPrincipal);
    cell.hooks.addRoleProvider(address(stack.roleProvider), type(uint32).max);

    DeployMarketInputs memory inputs = _marketInputs(stack, options, _requestedHooks(cell.hooks));
    bytes memory result = _execute(
      account,
      address(_factoryFor(stack, options.marketKind)),
      _marketDeploymentCall(
        options,
        inputs,
        _hooksData(options, cell.deployedAt),
        _marketSalt(address(account), nonce)
      )
    );
    cell.market = WildcatMarket(abi.decode(result, (address)));
  }

  function _deployCredentialedBorrowCell(
    ProductionStack memory stack,
    ExecutingBorrowerAccountMock account,
    MatrixMarketKind marketKind,
    uint96 nonce
  ) private returns (MatrixCell memory cell) {
    address template = LibStoredInitCode.deployInitCode(
      vm.getCode('test-next/mocks/BorrowerAccountMocks.sol:CredentialedBorrowHooksMock')
    );
    IHooksFactory factory = _factoryFor(stack, marketKind);
    factory.addHooksTemplate(template, 'Credentialed Borrow', address(0), address(0), 0, 0);

    NameAndProviderInputs memory constructorInputs;
    constructorInputs.name = 'Borrower credential';
    constructorInputs.existingProviders = new ExistingProviderInputs[](1);
    constructorInputs.existingProviders[0] = ExistingProviderInputs({
      providerAddress: address(stack.roleProvider),
      timeToLive: 0
    });

    cell.options = _defaultMatrixOptions(MatrixHooksKind.OpenTerm, marketKind);
    cell.operationalBorrower = address(account);
    cell.borrowerPrincipal = account.principal();
    cell.deployedAt = vm.getBlockTimestamp();
    cell.hooksTemplate = template;
    cell.hooks = _deployHooksThroughAccount(
      stack,
      account,
      marketKind,
      template,
      abi.encode(constructorInputs)
    );

    DeployMarketInputs memory inputs = _marketInputs(
      stack,
      cell.options,
      _requestedHooks(cell.hooks)
    );
    bytes memory result = _execute(
      account,
      address(factory),
      _marketDeploymentCall(cell.options, inputs, '', _marketSalt(address(account), nonce))
    );
    cell.market = WildcatMarket(abi.decode(result, (address)));
  }

  function _deployHooksThroughAccount(
    ProductionStack memory stack,
    ExecutingBorrowerAccountMock account,
    MatrixMarketKind marketKind,
    address template,
    bytes memory constructorArgs
  ) private returns (BaseAccessControls hooks) {
    bytes memory result = _execute(
      account,
      address(_factoryFor(stack, marketKind)),
      abi.encodeCall(IHooksFactory.deployHooksInstance, (template, constructorArgs))
    );
    hooks = BaseAccessControls(abi.decode(result, (address)));
  }

  function _requestedHooks(
    BaseAccessControls hooks
  ) private view returns (HooksConfig requestedHooks) {
    HooksDeploymentConfig deploymentConfig = IHooks(address(hooks)).config();
    requestedHooks = deploymentConfig.optionalFlags().setHooksAddress(address(hooks)).mergeAllFlags(
      deploymentConfig.requiredFlags()
    );
  }

  function _marketDeploymentCall(
    MatrixOptions memory options,
    DeployMarketInputs memory inputs,
    bytes memory hooksData,
    bytes32 salt
  ) private pure returns (bytes memory callData) {
    if (options.marketKind == MatrixMarketKind.Standard) {
      return abi.encodeCall(IHooksFactory.deployMarket, (inputs, hooksData, salt, address(0), 0));
    }
    return
      abi.encodeCall(
        IHooksFactoryRevolving.deployMarket,
        (inputs, hooksData, abi.encode(uint8(1), options.commitmentFeeBips), salt, address(0), 0)
      );
  }

  function _execute(
    ExecutingBorrowerAccountMock account,
    address target,
    bytes memory data
  ) private returns (bytes memory result) {
    vm.prank(account.principal());
    result = account.execute(target, 0, data);
  }

  function _expectAccountRevert(
    ExecutingBorrowerAccountMock account,
    address target,
    bytes memory data,
    bytes4 selector
  ) private {
    vm.prank(account.principal());
    vm.expectRevert(selector);
    account.execute(target, 0, data);
  }

  function _assertCredentialedBorrow(
    MatrixCell memory cell,
    address expectedBorrower,
    address expectedPrincipal
  ) private view {
    CredentialedBorrowHooksMock hooks = CredentialedBorrowHooksMock(address(cell.hooks));
    assertEq(hooks.lastBorrower(address(cell.market)), expectedBorrower, 'hook borrower');
    assertEq(
      hooks.lastBorrowerPrincipal(address(cell.market)),
      expectedPrincipal,
      'hook principal'
    );
  }
}
