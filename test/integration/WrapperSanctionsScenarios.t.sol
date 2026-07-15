// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketConfigMatrix.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { IWildcatSanctionsEscrow } from 'src/interfaces/IWildcatSanctionsEscrow.sol';
import { IMarketEventsAndErrors } from 'src/interfaces/IMarketEventsAndErrors.sol';
import { MockChainalysis } from '../shared/mocks/MockChainalysis.sol';

contract WrapperSanctionsScenariosTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 100e18;

  function _configureWrapper(
    DeployedCell memory d,
    Wildcat4626Wrapper wrapper
  ) internal returns (Wildcat4626Wrapper) {
    startPrank(borrower);
    BaseAccessControls(d.hooksInstance).grantRole(address(wrapper), uint32(block.timestamp));
    stopPrank();
    return wrapper;
  }

  function _deployLateWrapper(DeployedCell memory d) internal returns (Wildcat4626Wrapper wrapper) {
    wrapper = Wildcat4626Wrapper(wrapperFactory.createWrapper(address(d.market)));
    return _configureWrapper(d, wrapper);
  }

  function _wrap(
    DeployedCell memory d,
    Wildcat4626Wrapper wrapper,
    address account,
    uint256 amount
  ) internal {
    _depositAs(d, account, amount);
    startPrank(account);
    d.market.approve(address(wrapper), amount);
    wrapper.deposit(amount, account);
    stopPrank();
  }

  function _clearChainalysisSanction(address account) internal {
    MockChainalysis(sanctionsSentinel.chainalysisSanctionsList()).unsanction(account);
  }

  function test_wrapperRegistrationIsFactoryOnlyAndOneTime() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );

    vm.expectRevert(IMarketEventsAndErrors.NotWrapperFactory.selector);
    d.market.registerWrapper(address(0xBEEF));

    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    assertEq(d.market.registeredWrapper(), address(wrapper), 'canonical wrapper not registered');

    vm.prank(address(wrapperFactory));
    vm.expectRevert(IMarketEventsAndErrors.WrapperAlreadyRegistered.selector);
    d.market.registerWrapper(address(0xBEEF));
  }

  function test_lateDeployedWrapperCoordinatesDirectAndShareQuarantine() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    _wrap(d, wrapper, alice, DEPOSIT);
    _wrap(d, wrapper, bob, DEPOSIT);
    _depositAs(d, alice, DEPOSIT);

    uint256 backingBefore = d.market.scaledBalanceOf(address(wrapper));
    uint256 supplyBefore = wrapper.totalSupply();
    uint256 bobSharesBefore = wrapper.balanceOf(bob);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));

    sanctionsSentinel.sanction(alice);
    vm.prank(address(0xCA11));
    wrapper.nukeFromOrbit(alice);

    assertEq(d.market.scaledBalanceOf(alice), 0, 'direct position not quarantined');
    assertEq(wrapper.balanceOf(alice), 0, 'wrapper shares not quarantined');
    assertEq(wrapper.balanceOf(escrow), DEPOSIT, 'escrow did not receive wrapper shares');
    assertEq(wrapper.balanceOf(bob), bobSharesBefore, 'unrelated holder balance changed');
    assertEq(wrapper.totalSupply(), supplyBefore, 'share supply changed');
    assertEq(
      d.market.scaledBalanceOf(address(wrapper)),
      backingBefore,
      'aggregate backing changed'
    );

    (address escrowedAsset, uint256 escrowedShares) = IWildcatSanctionsEscrow(escrow)
      .escrowedAsset();
    assertEq(escrowedAsset, address(wrapper), 'wrong escrow asset');
    assertEq(escrowedShares, DEPOSIT, 'wrong escrow balance');
  }

  function test_directMarketNukeCanBeCompletedThroughWrapper() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    _wrap(d, wrapper, alice, DEPOSIT);
    _depositAs(d, alice, DEPOSIT);

    sanctionsSentinel.sanction(alice);
    d.market.nukeFromOrbit(alice);

    assertEq(d.market.scaledBalanceOf(alice), 0, 'direct position not quarantined');
    assertEq(wrapper.balanceOf(alice), DEPOSIT, 'market call moved wrapper shares');

    startPrank(alice);
    vm.expectRevert(abi.encodeWithSelector(Wildcat4626Wrapper.SanctionedAccount.selector, alice));
    wrapper.transfer(bob, DEPOSIT);
    stopPrank();

    wrapper.nukeFromOrbit(alice);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));
    assertEq(wrapper.balanceOf(alice), 0, 'wrapper did not complete quarantine');
    assertEq(wrapper.balanceOf(escrow), DEPOSIT, 'wrapper escrow balance mismatch');
  }

  function test_unaffectedHolderCanRedeemAfterOtherHolderIsEscrowed() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    _wrap(d, wrapper, alice, DEPOSIT);
    _wrap(d, wrapper, bob, DEPOSIT);

    sanctionsSentinel.sanction(alice);
    wrapper.nukeFromOrbit(alice);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));
    uint256 bobMarketBalanceBefore = d.market.scaledBalanceOf(bob);

    vm.prank(bob);
    wrapper.redeem(DEPOSIT, bob, bob);

    assertEq(
      d.market.scaledBalanceOf(bob),
      bobMarketBalanceBefore + DEPOSIT,
      'unaffected holder could not redeem'
    );
    assertEq(wrapper.balanceOf(escrow), DEPOSIT, 'escrowed shares changed');
    assertEq(wrapper.totalSupply(), DEPOSIT, 'wrong remaining supply');
    assertEq(
      d.market.scaledBalanceOf(address(wrapper)),
      wrapper.totalSupply(),
      'remaining shares not fully backed'
    );
  }

  function test_escrowReleaseAfterSanctionClears() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    _wrap(d, wrapper, alice, DEPOSIT);

    sanctionsSentinel.sanction(alice);
    wrapper.nukeFromOrbit(alice);
    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));

    vm.expectRevert(IWildcatSanctionsEscrow.CanNotReleaseEscrow.selector);
    IWildcatSanctionsEscrow(escrow).releaseEscrow();

    _clearChainalysisSanction(alice);
    IWildcatSanctionsEscrow(escrow).releaseEscrow();

    assertEq(wrapper.balanceOf(alice), DEPOSIT, 'shares not returned after clear');
    assertEq(wrapper.balanceOf(escrow), 0, 'escrow retained shares');
    assertEq(
      d.market.scaledBalanceOf(address(wrapper)),
      wrapper.totalSupply(),
      'release changed wrapper backing'
    );
  }

  function test_shareNukeIsIdempotentAndNullBalanceDoesNotDeployEscrow() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);

    sanctionsSentinel.sanction(alice);
    address emptyEscrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));
    wrapper.nukeFromOrbit(alice);
    assertEq(emptyEscrow.code.length, 0, 'null balance deployed escrow');

    _wrap(d, wrapper, bob, DEPOSIT);
    sanctionsSentinel.sanction(bob);
    wrapper.nukeFromOrbit(bob);
    address bobEscrow = sanctionsSentinel.getEscrowAddress(borrower, bob, address(wrapper));
    wrapper.nukeFromOrbit(bob);

    assertEq(wrapper.balanceOf(bob), 0, 'repeat nuke restored shares');
    assertEq(wrapper.balanceOf(bobEscrow), DEPOSIT, 'repeat nuke changed escrow balance');
    assertEq(wrapper.totalSupply(), DEPOSIT, 'repeat nuke changed supply');
  }

  function test_wrapperEntryPointCannotNukeItself() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    _wrap(d, wrapper, alice, DEPOSIT);
    uint256 backingBefore = d.market.scaledBalanceOf(address(wrapper));

    sanctionsSentinel.sanction(address(wrapper));
    vm.expectRevert(Wildcat4626Wrapper.CannotNukeWrapper.selector);
    wrapper.nukeFromOrbit(address(wrapper));

    assertEq(
      d.market.scaledBalanceOf(address(wrapper)),
      backingBefore,
      'wrapper entrypoint changed backing'
    );
    assertEq(wrapper.totalSupply(), DEPOSIT, 'wrapper supply changed');
    assertEq(wrapper.maxRedeem(alice), 0, 'sanctioned wrapper remained operational');

    vm.prank(alice);
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626Wrapper.SanctionedAccount.selector, address(wrapper))
    );
    wrapper.redeem(DEPOSIT, alice, alice);

    _clearChainalysisSanction(address(wrapper));
    vm.prank(alice);
    wrapper.redeem(DEPOSIT, alice, alice);
    assertEq(wrapper.totalSupply(), 0, 'wrapper did not recover after clear');
  }

  function test_lateDeployedRevolvingWrapperCoordinatesQuarantine() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Revolving)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    _wrap(d, wrapper, alice, DEPOSIT);
    _depositAs(d, alice, DEPOSIT);

    sanctionsSentinel.sanction(alice);
    wrapper.nukeFromOrbit(alice);

    address escrow = sanctionsSentinel.getEscrowAddress(borrower, alice, address(wrapper));
    assertEq(d.market.scaledBalanceOf(alice), 0, 'revolving direct position remained');
    assertEq(wrapper.balanceOf(alice), 0, 'revolving wrapper shares remained');
    assertEq(wrapper.balanceOf(escrow), DEPOSIT, 'revolving escrow balance mismatch');
  }

  function test_directMarketNukeCannotRemoveWrapperBacking() external {
    DeployedCell memory d = deployCell(
      defaultCell(MatrixHooksKind.OpenTerm, MatrixMarketKind.Standard)
    );
    Wildcat4626Wrapper wrapper = _deployLateWrapper(d);
    _wrap(d, wrapper, alice, DEPOSIT);

    sanctionsSentinel.sanction(address(wrapper));
    vm.expectRevert(Wildcat4626Wrapper.CannotNukeWrapper.selector);
    d.market.nukeFromOrbit(address(wrapper));

    assertEq(
      d.market.scaledBalanceOf(address(wrapper)),
      wrapper.totalSupply(),
      'market nuke changed wrapper backing'
    );

    _clearChainalysisSanction(address(wrapper));
    vm.prank(alice);
    wrapper.redeem(DEPOSIT, alice, alice);
  }
}
