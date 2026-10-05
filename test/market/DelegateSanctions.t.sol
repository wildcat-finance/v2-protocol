// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { WildcatSanctionsSentinel } from 'src/WildcatSanctionsSentinel.sol';
import { IERC20 } from 'src/interfaces/IERC20.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { AccessListRoleProvider } from 'src/providers/AccessListRoleProvider.sol';
import { Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { HookDispatchSentinelMock } from '../mocks/HookDispatchMocks.sol';
import { SanctionsListMock } from '../mocks/SanctionsMocks.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

contract DelegateSanctionsTest is MarketFixture {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);
  address internal constant Delegate = address(0x5EED);
  address internal constant NewPrincipal = address(0xCAFE);
  uint256 internal constant Unit = 1e18;

  struct Scenario {
    Fixture fixture;
    WildcatSanctionsSentinel sentinel;
    SanctionsListMock sanctionsList;
    IERC20 token;
  }

  function _deployFixtureDependencies() internal override returns (Fixture memory fixture) {
    fixture = super._deployFixtureDependencies();
    SanctionsListMock sanctionsList = SanctionsListMock(_deployCode('test/mocks/SanctionsMocks.sol:SanctionsListMock'));
    fixture.sentinel = HookDispatchSentinelMock(
      _deployCode(
        'src/WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel',
        abi.encode(address(fixture.archController), address(sanctionsList))
      )
    );
  }

  function _newScenario(
    HooksKind kind,
    bool revolving,
    bool transferHook,
    bool wrapped
  )
    private
    returns (Scenario memory scenario)
  {
    Options memory options = _defaultOptions(kind);
    options.revolving = revolving;
    options.annualInterestBips = 0;
    options.commitmentFeeBips = 0;
    if (transferHook) options.requestedHooks = options.requestedHooks.setFlag(Bit_Enabled_Transfer);
    scenario.fixture = _newMarket(options);
    scenario.sentinel = WildcatSanctionsSentinel(address(scenario.fixture.sentinel));
    scenario.sanctionsList = SanctionsListMock(scenario.sentinel.chainalysisSanctionsList());
    if (transferHook) {
      address[] memory members = new address[](2);
      members[0] = Holder;
      members[1] = Recipient;
      AccessListRoleProvider provider = AccessListRoleProvider(
        _deployCode('src/providers/AccessListRoleProvider.sol:AccessListRoleProvider', abi.encode(Borrower, members))
      );
      vm.prank(Borrower);
      BaseAccessControls(address(scenario.fixture.hooks)).addRoleProvider(address(provider), type(uint32).max);
    }
    _deposit(scenario.fixture, Holder, 10 * Unit);
    scenario.token = IERC20(address(scenario.fixture.market));

    if (wrapped) {
      vm.startPrank(WrapperFactory);
      Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(
        _deployCode('src/vault/Wildcat4626Wrapper.sol:Wildcat4626Wrapper', abi.encode(address(scenario.fixture.market)))
      );
      scenario.fixture.market.registerWrapper(address(wrapper));
      vm.stopPrank();
      vm.startPrank(Holder);
      scenario.token.approve(address(wrapper), 10 * Unit);
      wrapper.deposit(10 * Unit, Holder);
      vm.stopPrank();
      scenario.token = IERC20(address(wrapper));
    }
  }

  function test_marketTransferFromRejectsSanctionedDelegateAcrossConfigurations() external {
    _assertDelegateSanctions(false);
  }

  function test_wrapperTransferFromRejectsSanctionedDelegateAcrossConfigurations() external {
    _assertDelegateSanctions(true);
  }

  function _assertDelegateSanctions(bool wrapped) private {
    // Exercise both market types and hook families, with transfer hooks on/off and finite/infinite approval.
    for (uint256 i; i < 16; i++) {
      bool infiniteApproval = i & 1 != 0;
      Scenario memory scenario = _newScenario(HooksKind(i >> 3), i & 2 != 0, i & 4 != 0, wrapped);
      uint256 approval = infiniteApproval ? type(uint256).max : 5 * Unit;
      vm.prank(Holder);
      scenario.token.approve(Delegate, approval);
      _delegateTransfer(scenario.token, Recipient);

      scenario.sanctionsList.sanction(Delegate);
      _expectBlockedTransfer(scenario.token, Recipient, Unit, wrapped);
      _expectBlockedTransfer(scenario.token, Holder, Unit, wrapped);
      _expectBlockedTransfer(scenario.token, Recipient, 0, wrapped);
      assertEq(scenario.token.balanceOf(Holder), 9 * Unit, 'blocked owner balance');
      assertEq(scenario.token.balanceOf(Recipient), Unit, 'blocked recipient balance');
      assertEq(scenario.token.totalSupply(), 10 * Unit, 'blocked supply');
      assertEq(scenario.token.allowance(Holder, Delegate), infiniteApproval ? approval : 4 * Unit, 'blocked allowance');

      // A blocked spender does not immobilize the unsanctioned holders' balances.
      vm.prank(Recipient);
      assertTrue(scenario.token.transfer(Holder, Unit), 'holder transfer');

      vm.prank(Borrower);
      scenario.sentinel.overrideSanction(Delegate);
      _delegateTransfer(scenario.token, Recipient);
      vm.prank(Borrower);
      scenario.sentinel.removeSanctionOverride(Delegate);
      _expectBlockedTransfer(scenario.token, Recipient, Unit, wrapped);

      scenario.sanctionsList.unsanction(Delegate);
      _delegateTransfer(scenario.token, Recipient);
      assertEq(scenario.token.balanceOf(Holder), 8 * Unit, 'recovered owner balance');
      assertEq(scenario.token.balanceOf(Recipient), 2 * Unit, 'recovered recipient balance');
      assertEq(scenario.token.totalSupply(), 10 * Unit, 'recovered supply');
      assertEq(
        scenario.token.allowance(Holder, Delegate), infiniteApproval ? approval : 2 * Unit, 'recovered allowance'
      );
    }
  }

  function test_delegateSanctionsFollowCurrentBorrowerPrincipal() external {
    for (uint256 i; i < 4; i++) {
      bool wrapped = i & 1 != 0;
      Scenario memory scenario = _newScenario(HooksKind.OpenTerm, i & 2 != 0, true, wrapped);
      vm.prank(Holder);
      scenario.token.approve(Delegate, 5 * Unit);
      scenario.sanctionsList.sanction(Delegate);
      vm.prank(Borrower);
      scenario.sentinel.overrideSanction(Delegate);
      _delegateTransfer(scenario.token, Recipient);

      scenario.fixture.archController.registerBorrower(NewPrincipal);
      vm.prank(Borrower);
      scenario.fixture.market.requestBorrowerTransfer(NewPrincipal);
      vm.prank(NewPrincipal);
      scenario.fixture.market.acceptBorrowerTransfer();
      assertFalse(scenario.sentinel.isSanctioned(Borrower, Delegate), 'old principal override retained');
      _expectBlockedTransfer(scenario.token, Recipient, Unit, wrapped);
      assertEq(scenario.token.allowance(Holder, Delegate), 4 * Unit, 'handoff preserves allowance');

      vm.prank(NewPrincipal);
      scenario.sentinel.overrideSanction(Delegate);
      _delegateTransfer(scenario.token, Recipient);
      assertEq(scenario.token.balanceOf(Holder), 8 * Unit, 'new principal owner balance');
      assertEq(scenario.token.balanceOf(Recipient), 2 * Unit, 'new principal recipient balance');
      assertEq(scenario.token.allowance(Holder, Delegate), 3 * Unit, 'new principal allowance');
    }
  }

  function _delegateTransfer(IERC20 token, address to) private {
    vm.prank(Delegate);
    assertTrue(token.transferFrom(Holder, to, Unit), 'delegate transfer');
  }

  function _expectBlockedTransfer(IERC20 token, address to, uint256 amount, bool wrapped) private {
    vm.prank(Delegate);
    if (wrapped) {
      vm.expectRevert(abi.encodeWithSelector(Wildcat4626Wrapper.SanctionedAccount.selector, Delegate));
    } else {
      vm.expectRevert(IMarketEventsAndErrors.AccountBlocked.selector);
    }
    token.transferFrom(Holder, to, amount);
  }
}
