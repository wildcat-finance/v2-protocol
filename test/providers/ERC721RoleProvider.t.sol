// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MockERC721 } from 'solmate/test/utils/mocks/MockERC721.sol';

import '../BaseMarketTest.sol';
import 'src/providers/ERC721RoleProvider.sol';

contract ERC721RoleProviderTest is BaseMarketTest {
  MockERC721 internal nft;
  ERC721RoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    nft = new MockERC721('Access', 'ACCESS');
    provider = new ERC721RoleProvider(address(nft));
    nft.mint(approvedLender, 1);

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Holders of the configured ERC721 can deposit.
  function test_deposit_allows_erc721_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  /// @dev Non-holders are rejected even if they can fund the deposit.
  function test_deposit_reverts_erc721_nonholder() external {
    uint256 amount = 1e18;
    asset.mint(unapprovedLender, amount);
    assertEq(nft.balanceOf(unapprovedLender), 0, 'expected no ERC721 balance');

    vm.startPrank(unapprovedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }
}
