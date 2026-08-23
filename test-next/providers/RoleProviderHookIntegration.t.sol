// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { encodeHooksConfig } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { RoleProviderTokenMock } from '../mocks/RoleProviderTokenMock.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract RoleProviderHookIntegrationTest is TestKernel {
  enum PullProviderKind {
    ERC20,
    ERC721,
    ERC1155,
    ERC4626
  }

  enum PushProviderKind {
    ERC5192,
    ERC5484
  }

  struct AccessFixture {
    OpenTermHooks hooks;
    RoleProviderTokenMock token;
    address provider;
    address market;
  }

  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);
  uint256 internal constant TokenId = 7;

  function setUp() external {
    vm.warp(1_714_737_030);
  }

  // ========================================================================== //
  //                            Fixture construction                            //
  // ========================================================================== //

  function _deployHooks(address market) internal returns (OpenTermHooks hooks) {
    hooks = OpenTermHooks(
      _deployCode(
        'src/access/OpenTermHooks.sol:OpenTermHooks',
        abi.encode(address(this), bytes(''))
      )
    );

    DeployMarketInputs memory parameters;
    parameters.hooks = encodeHooksConfig({
      hooksAddress: address(hooks),
      useOnDeposit: true,
      useOnQueueWithdrawal: false,
      useOnExecuteWithdrawal: false,
      useOnTransfer: false,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: false,
      useOnSetProtocolFeeBips: false
    });
    hooks.onCreateMarket(address(this), market, parameters, '');
  }

  function _deployPullProvider(
    PullProviderKind kind,
    RoleProviderTokenMock token
  ) internal returns (address provider) {
    if (kind == PullProviderKind.ERC20) {
      return
        _deployCode(
          'src/providers/ERC20RoleProvider.sol:ERC20RoleProvider',
          abi.encode(address(token), 1)
        );
    }
    if (kind == PullProviderKind.ERC721) {
      return
        _deployCode(
          'src/providers/ERC721RoleProvider.sol:ERC721RoleProvider',
          abi.encode(address(token), false)
        );
    }
    if (kind == PullProviderKind.ERC1155) {
      return
        _deployCode(
          'src/providers/ERC1155RoleProvider.sol:ERC1155RoleProvider',
          abi.encode(address(token), TokenId, false)
        );
    }
    return
      _deployCode(
        'src/providers/ERC4626AssetsRoleProvider.sol:ERC4626AssetsRoleProvider',
        abi.encode(address(token), 1)
      );
  }

  function _deployPushProvider(
    PushProviderKind kind,
    RoleProviderTokenMock token
  ) internal returns (address provider) {
    if (kind == PushProviderKind.ERC5192) {
      return
        _deployCode(
          'src/providers/ERC5192RoleProvider.sol:ERC5192RoleProvider',
          abi.encode(address(token), true, false)
        );
    }
    return
      _deployCode(
        'src/providers/ERC5484RoleProvider.sol:ERC5484RoleProvider',
        abi.encode(address(token), uint8(1), false)
      );
  }

  function _newPullFixture(
    PullProviderKind kind,
    uint32 timeToLive
  ) internal returns (AccessFixture memory fixture) {
    fixture.market = address(uint160(0xCAFE + uint8(kind)));
    fixture.hooks = _deployHooks(fixture.market);
    fixture.token = RoleProviderTokenMock(
      _deployCode('test-next/mocks/RoleProviderTokenMock.sol:RoleProviderTokenMock')
    );
    fixture.provider = _deployPullProvider(kind, fixture.token);
    fixture.hooks.addRoleProvider(fixture.provider, timeToLive);
  }

  function _newPushFixture(
    PushProviderKind kind,
    uint32 timeToLive
  ) internal returns (AccessFixture memory fixture) {
    fixture.market = address(uint160(0xBEEF + uint8(kind)));
    fixture.hooks = _deployHooks(fixture.market);
    fixture.token = RoleProviderTokenMock(
      _deployCode('test-next/mocks/RoleProviderTokenMock.sol:RoleProviderTokenMock')
    );
    fixture.provider = _deployPushProvider(kind, fixture.token);
    fixture.hooks.addRoleProvider(fixture.provider, timeToLive);
  }

  function _setPullEligibility(
    PullProviderKind kind,
    RoleProviderTokenMock token,
    address account,
    bool eligible
  ) internal {
    uint256 balance = eligible ? 1 : 0;
    if (kind == PullProviderKind.ERC1155) {
      token.setBalance(account, TokenId, balance);
    } else {
      token.setBalance(account, balance);
    }
  }

  function _setPullReadRevert(RoleProviderTokenMock token, bool shouldRevert) internal {
    token.setReadReverts(shouldRevert, false, false, false, false);
  }

  function _setPushEligibility(
    PushProviderKind kind,
    RoleProviderTokenMock token,
    address account
  ) internal {
    token.setOwner(TokenId, account);
    if (kind == PushProviderKind.ERC5192) {
      token.setLocked(TokenId, true);
    } else {
      token.setBurnAuth(TokenId, 0);
    }
  }

  function _deposit(AccessFixture memory fixture, address lender, bytes memory hooksData) internal {
    MarketState memory state;
    vm.prank(fixture.market);
    fixture.hooks.onDeposit(lender, 1, state, hooksData);
  }

  function _expectDepositDenied(
    AccessFixture memory fixture,
    address lender,
    bytes memory hooksData
  ) internal {
    MarketState memory state;
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    vm.prank(fixture.market);
    fixture.hooks.onDeposit(lender, 1, state, hooksData);
  }

  function _assertCredential(
    AccessFixture memory fixture,
    address lender,
    address expectedProvider
  ) internal view {
    LenderStatus memory status = fixture.hooks.getPreviousLenderStatus(lender);
    assertEq(status.lastProvider, expectedProvider, 'credential provider');
    assertEq(status.lastApprovalTimestamp, uint32(vm.getBlockTimestamp()), 'credential timestamp');
    assertTrue(fixture.hooks.isKnownLenderOnMarket(lender, fixture.market), 'known lender');
  }

  // ========================================================================== //
  //                             Pull-provider path                             //
  // ========================================================================== //

  function test_pullProviderMatrix_RoutesCurrentCredentialsIntoDeposit() external {
    for (uint8 i; i <= uint8(PullProviderKind.ERC4626); i++) {
      PullProviderKind kind = PullProviderKind(i);
      AccessFixture memory fixture = _newPullFixture(kind, 0);
      _setPullEligibility(kind, fixture.token, Holder, true);

      _deposit(fixture, Holder, '');
      _assertCredential(fixture, Holder, fixture.provider);
      _expectDepositDenied(fixture, Recipient, '');
    }
  }

  function test_pullProviderMatrix_ZeroTtlRechecksAndFollowsEligibility() external {
    for (uint8 i; i <= uint8(PullProviderKind.ERC4626); i++) {
      PullProviderKind kind = PullProviderKind(i);
      AccessFixture memory fixture = _newPullFixture(kind, 0);
      _setPullEligibility(kind, fixture.token, Holder, true);
      _deposit(fixture, Holder, '');

      _setPullEligibility(kind, fixture.token, Holder, false);
      _setPullEligibility(kind, fixture.token, Recipient, true);

      _expectDepositDenied(fixture, Holder, '');
      _deposit(fixture, Recipient, '');
      _assertCredential(fixture, Recipient, fixture.provider);
    }
  }

  function test_pullProviderMatrix_PositiveTtlDelaysRemoval() external {
    for (uint8 i; i <= uint8(PullProviderKind.ERC4626); i++) {
      PullProviderKind kind = PullProviderKind(i);
      AccessFixture memory fixture = _newPullFixture(kind, 1);
      _setPullEligibility(kind, fixture.token, Holder, true);
      _deposit(fixture, Holder, '');

      _setPullEligibility(kind, fixture.token, Holder, false);
      _deposit(fixture, Holder, '');
      vm.warp(vm.getBlockTimestamp() + 2);
      _expectDepositDenied(fixture, Holder, '');
    }
  }

  function test_pullProviderMatrix_FailedReadsFailClosedAndDoNotMaskLaterProviders() external {
    for (uint8 i; i <= uint8(PullProviderKind.ERC4626); i++) {
      PullProviderKind kind = PullProviderKind(i);
      AccessFixture memory fixture = _newPullFixture(kind, 0);
      _setPullEligibility(kind, fixture.token, Holder, true);
      _setPullReadRevert(fixture.token, true);

      _expectDepositDenied(fixture, Holder, '');

      RoleProviderTokenMock validToken = RoleProviderTokenMock(
        _deployCode('test-next/mocks/RoleProviderTokenMock.sol:RoleProviderTokenMock')
      );
      _setPullEligibility(kind, validToken, Holder, true);
      address validProvider = _deployPullProvider(kind, validToken);
      fixture.hooks.addRoleProvider(validProvider, 0);

      _deposit(fixture, Holder, '');
      _assertCredential(fixture, Holder, validProvider);
    }
  }

  function test_erc4626ConversionFailureAlsoFailsClosed() external {
    AccessFixture memory fixture = _newPullFixture(PullProviderKind.ERC4626, 0);
    fixture.token.setBalance(Holder, 1);
    fixture.token.setReadReverts(false, true, false, false, false);
    _expectDepositDenied(fixture, Holder, '');
  }

  function test_hookBlockOverridesAnEligibleProvider() external {
    AccessFixture memory fixture = _newPullFixture(PullProviderKind.ERC20, 0);
    _setPullEligibility(PullProviderKind.ERC20, fixture.token, Holder, true);
    fixture.hooks.blockFromDeposits(Holder);

    _expectDepositDenied(fixture, Holder, '');
  }

  // ========================================================================== //
  //                             Push-provider path                             //
  // ========================================================================== //

  function test_pushProviderMatrix_RoutesPackedCredentialsIntoDeposit() external {
    for (uint8 i; i <= uint8(PushProviderKind.ERC5484); i++) {
      PushProviderKind kind = PushProviderKind(i);
      AccessFixture memory fixture = _newPushFixture(kind, 0);
      _setPushEligibility(kind, fixture.token, Holder);
      bytes memory hooksData = abi.encodePacked(fixture.provider, abi.encode(TokenId));

      _deposit(fixture, Holder, hooksData);
      _assertCredential(fixture, Holder, fixture.provider);
      _expectDepositDenied(fixture, Recipient, hooksData);
    }
  }

  function test_pushProviderMatrix_ExpiredCredentialsRequireFreshOwnership() external {
    for (uint8 i; i <= uint8(PushProviderKind.ERC5484); i++) {
      PushProviderKind kind = PushProviderKind(i);
      AccessFixture memory fixture = _newPushFixture(kind, 0);
      _setPushEligibility(kind, fixture.token, Holder);
      bytes memory hooksData = abi.encodePacked(fixture.provider, abi.encode(TokenId));
      _deposit(fixture, Holder, hooksData);

      _setPushEligibility(kind, fixture.token, Recipient);
      vm.warp(vm.getBlockTimestamp() + 1);

      _expectDepositDenied(fixture, Holder, hooksData);
      _deposit(fixture, Recipient, hooksData);
      _assertCredential(fixture, Recipient, fixture.provider);
    }
  }

  function test_pushProviderMatrix_MalformedCredentialDataFailsClosed() external {
    for (uint8 i; i <= uint8(PushProviderKind.ERC5484); i++) {
      PushProviderKind kind = PushProviderKind(i);
      AccessFixture memory fixture = _newPushFixture(kind, 0);
      _setPushEligibility(kind, fixture.token, Holder);

      _expectDepositDenied(fixture, Holder, abi.encodePacked(fixture.provider, hex'01'));
    }
  }
}
