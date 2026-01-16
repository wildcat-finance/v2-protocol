// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MockERC1155 } from 'solmate/test/utils/mocks/MockERC1155.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/providers/ERC1155RoleProvider.sol';

contract NonERC1155 {}

contract ERC1155RoleProviderTest is BaseMarketTest {
  MockERC1155 internal token;
  ERC1155RoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;
  uint256 internal constant tokenId = 1;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    token = new MockERC1155();
    provider = new ERC1155RoleProvider(address(token), tokenId);
    token.mint(approvedLender, tokenId, 1, '');

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Holders of the configured ERC1155 tokenId can deposit.
  function test_deposit_allows_erc1155_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  /// @dev Non-holders are rejected even if they can fund the deposit.
  function test_deposit_reverts_erc1155_nonholder() external {
    uint256 amount = 1e18;
    asset.mint(unapprovedLender, amount);
    assertEq(token.balanceOf(unapprovedLender, tokenId), 0, 'expected no ERC1155 balance');

    vm.startPrank(unapprovedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }

  /// @dev Holding a different tokenId does not grant access.
  function test_deposit_reverts_erc1155_wrong_token_id() external {
    uint256 otherTokenId = tokenId + 1;
    token.mint(unapprovedLender, otherTokenId, 1, '');

    uint256 amount = 1e18;
    asset.mint(unapprovedLender, amount);

    assertEq(token.balanceOf(unapprovedLender, tokenId), 0, 'expected no configured balance');
    assertEq(token.balanceOf(unapprovedLender, otherTokenId), 1, 'expected other token balance');

    vm.startPrank(unapprovedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }

  /// @dev Pull-provider credentials remain valid until TTL expiry.
  function test_deposit_erc1155_expires_after_ttl() external {
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    token.safeTransferFrom(approvedLender, unapprovedLender, tokenId, 1, '');

    _deposit(approvedLender, 1e18, false);

    fastForward(2);

    uint256 amount = 1e18;
    asset.mint(approvedLender, amount);

    vm.startPrank(approvedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }

  function test_constructor_reverts_without_code() external {
    vm.expectRevert(ERC1155RoleProvider.InvalidTokenAddress.selector);
    new ERC1155RoleProvider(address(0), tokenId);
  }

  function test_constructor_reverts_without_erc1155_interface() external {
    NonERC1155 nonErc1155 = new NonERC1155();
    vm.expectRevert(ERC1155RoleProvider.InvalidERC1155.selector);
    new ERC1155RoleProvider(address(nonErc1155), tokenId);
  }
}
