// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseHooks } from 'src/access/BaseHooks.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { HookedMarket, OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_QueueWithdrawal } from 'src/types/HooksConfig.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract OpenTermHooksTest is TestKernel {
  address internal constant MarketA = address(0x1001);
  address internal constant MarketB = address(0x1002);
  address internal constant MarketC = address(0x1003);
  address internal constant MarketD = address(0x1004);
  address internal constant NewAdministrator = address(0xAD011);

  OpenTermHooks internal hooks;
  mapping(address account => bool registered) internal registeredBorrowers;
  address internal callbackPreviousAdministrator;
  address internal callbackNewAdministrator;

  function setUp() external {
    registeredBorrowers[address(this)] = true;
    NameAndProviderInputs memory inputs;
    hooks = _newHooks(address(this), inputs);
  }

  function archController() external view returns (address) {
    return address(this);
  }

  function isRegisteredBorrower(address account) external view returns (bool) {
    return registeredBorrowers[account];
  }

  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external {
    assertEq(msg.sender, address(hooks), 'callback caller');
    callbackPreviousAdministrator = previousAdministrator;
    callbackNewAdministrator = newAdministrator;
  }

  function _newHooks(
    address administrator,
    NameAndProviderInputs memory inputs
  ) internal returns (OpenTermHooks deployed) {
    deployed = OpenTermHooks(
      _deployCode(
        'src/access/OpenTermHooks.sol:OpenTermHooks',
        abi.encode(administrator, abi.encode(inputs))
      )
    );
  }

  function _requestedConfig(
    OpenTermHooks target,
    bool deposit,
    bool queueWithdrawal,
    bool transfer
  ) internal pure returns (HooksConfig config) {
    config = EmptyHooksConfig.setHooksAddress(address(target));
    if (deposit) config = config.setFlag(Bit_Enabled_Deposit);
    if (queueWithdrawal) config = config.setFlag(Bit_Enabled_QueueWithdrawal);
    if (transfer) config = config.setFlag(Bit_Enabled_Transfer);
  }

  function _createMarket(
    OpenTermHooks target,
    address market,
    HooksConfig requestedConfig,
    bytes memory hooksData
  ) internal returns (HooksConfig effectiveConfig) {
    DeployMarketInputs memory inputs;
    inputs.hooks = requestedConfig;
    effectiveConfig = target.onCreateMarket(address(this), market, inputs, hooksData);
  }

  function test_metadata_IsCanonical() external view {
    assertEq(hooks.version(), 'OpenTermHooks', 'version');
  }

  function test_getHookedMarkets_PreservesOrderAndUnknownValues() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint128(100))
    );
    _createMarket(
      hooks,
      MarketB,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint128(200), true)
    );
    address[] memory markets = new address[](3);
    markets[0] = MarketB;
    markets[1] = MarketC;
    markets[2] = MarketA;
    HookedMarket[] memory configs = hooks.getHookedMarkets(markets);
    assertEq(configs.length, 3, 'market count');
    assertEq(configs[0].minimumDeposit, 200, 'first minimum');
    assertTrue(configs[0].transfersDisabled, 'first transfer policy');
    assertEq(configs[2].minimumDeposit, 100, 'last minimum');
    HookedMarket memory empty;
    assertEq(abi.encode(configs[1]), abi.encode(empty), 'unknown batch configuration');
    assertEq(
      abi.encode(hooks.getHookedMarket(MarketC)),
      abi.encode(empty),
      'unknown single configuration'
    );
  }

  function test_administratorTransfer_PreservesMarketConfigurationAndMovesAuthority() external {
    _createMarket(
      hooks,
      MarketA,
      _requestedConfig(hooks, false, false, false),
      abi.encode(uint128(100), true)
    );
    bytes32 configBefore = keccak256(abi.encode(hooks.getHookedMarket(MarketA)));
    registeredBorrowers[NewAdministrator] = true;
    hooks.requestAdministratorTransfer(NewAdministrator);
    vm.prank(NewAdministrator);
    hooks.acceptAdministratorTransfer();

    assertEq(hooks.administrator(), NewAdministrator, 'administrator');
    assertEq(callbackPreviousAdministrator, address(this), 'callback previous administrator');
    assertEq(callbackNewAdministrator, NewAdministrator, 'callback new administrator');
    assertEq(keccak256(abi.encode(hooks.getHookedMarket(MarketA))), configBefore, 'market config');

    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    hooks.setMinimumDeposit(MarketA, 200);
    vm.prank(NewAdministrator);
    hooks.setMinimumDeposit(MarketA, 200);
    assertEq(hooks.getHookedMarket(MarketA).minimumDeposit, 200, 'updated minimum');
  }

  function test_onSetApr_DelegatesWithoutRegistration() external {
    MarketState memory state;
    state.annualInterestBips = 1_000;
    state.reserveRatioBips = 500;
    vm.prank(MarketA);
    (uint16 annualInterestBips, uint16 reserveRatioBips) = hooks
      .onSetAnnualInterestAndReserveRatioBips(1_000, 9_999, state, abi.encode('unused'));
    assertEq(annualInterestBips, 1_000, 'APR');
    assertEq(reserveRatioBips, 500, 'reserve ratio');
  }
}
