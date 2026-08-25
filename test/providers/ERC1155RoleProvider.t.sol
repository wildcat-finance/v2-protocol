// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Test as ForgeTest } from 'forge-std/Test.sol';
import { MockERC1155 } from 'solmate/test/utils/mocks/MockERC1155.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/providers/ERC1155RoleProvider.sol';
import 'src/providers/IERC1155RoleProvider.sol';

contract NonERC1155 {}

contract InvalidERC165ERC1155 {
  function supportsInterface(bytes4) external pure returns (bool) {
    return true;
  }
}

contract NonERC165ERC1155BalanceToken {
  mapping(address account => mapping(uint256 tokenId => uint256 balance)) public balanceOf;

  function mint(address account, uint256 tokenId, uint256 amount) external {
    balanceOf[account][tokenId] += amount;
  }
}

contract RevertingERC1155BalanceToken {
  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == 0x01ffc9a7 || interfaceId == 0xd9b67a26;
  }

  function balanceOf(address, uint256) external pure returns (uint256) {
    revert('BALANCE_REVERTED');
  }
}

contract ERC1155RoleProviderPropertyTest is ForgeTest {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);

  function setUp() external {
    vm.warp(1_714_737_030);
  }

  function testFuzz_credentialMatchesConfiguredBalance(
    uint256 tokenId,
    uint96 balanceSeed
  ) external {
    MockERC1155 token = new MockERC1155();
    ERC1155RoleProvider provider = new ERC1155RoleProvider(address(token), tokenId, false);
    if (balanceSeed != 0) token.mint(Holder, tokenId, balanceSeed, '');
    uint32 expectedCredential = balanceSeed == 0 ? 0 : uint32(block.timestamp);

    assertEq(provider.getCredential(Holder), expectedCredential, 'pull credential');
    assertEq(
      provider.validateCredential(Holder, hex'deadbeef'),
      expectedCredential,
      'validated credential'
    );
  }

  function testFuzz_transferMovesCredential(uint256 tokenId, uint96 balanceSeed) external {
    uint256 balance = bound(uint256(balanceSeed), 1, type(uint96).max);
    MockERC1155 token = new MockERC1155();
    ERC1155RoleProvider provider = new ERC1155RoleProvider(address(token), tokenId, false);
    token.mint(Holder, tokenId, balance, '');

    assertEq(provider.getCredential(Holder), uint32(block.timestamp), 'original credential');
    vm.prank(Holder);
    token.safeTransferFrom(Holder, Recipient, tokenId, balance, '');

    assertEq(provider.getCredential(Holder), 0, 'stale credential');
    assertEq(provider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }

  function testFuzz_otherTokenIdDoesNotQualify(uint256 tokenId, uint96 balanceSeed) external {
    uint256 balance = bound(uint256(balanceSeed), 1, type(uint96).max);
    uint256 otherTokenId = tokenId ^ 1;
    MockERC1155 token = new MockERC1155();
    ERC1155RoleProvider provider = new ERC1155RoleProvider(address(token), tokenId, false);
    token.mint(Holder, otherTokenId, balance, '');

    assertEq(provider.getCredential(Holder), 0, 'credential');
  }
}

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
    provider = new ERC1155RoleProvider(address(token), tokenId, false);
    token.mint(approvedLender, tokenId, 1, '');

    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 0);
  }

  function test_getCredential_usesConfiguredTokenId() external view {
    assertEq(provider.getCredential(approvedLender), uint32(block.timestamp), 'credential');
    assertEq(provider.getCredential(unapprovedLender), 0, 'missing credential');
  }

  function test_deposit_allows_erc1155_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  function test_deposit_reverts_erc1155_nonholder() external {
    _expectDepositRevertNotApproved(unapprovedLender, 1e18);
  }

  function test_deposit_reverts_erc1155_wrong_token_id() external {
    token.mint(unapprovedLender, tokenId + 1, 1, '');
    _expectDepositRevertNotApproved(unapprovedLender, 1e18);
  }

  function test_deposit_zeroTtlRechecksWithinSameBlock() external {
    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    token.safeTransferFrom(approvedLender, unapprovedLender, tokenId, 1, '');

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_deposit_zeroTtlFollowsTransferredBalance() external {
    vm.prank(approvedLender);
    token.safeTransferFrom(approvedLender, unapprovedLender, tokenId, 1, '');

    _deposit(unapprovedLender, 1e18, false);
  }

  function test_deposit_positiveTtlDelaysRemoval() external {
    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);

    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    token.safeTransferFrom(approvedLender, unapprovedLender, tokenId, 1, '');

    _deposit(approvedLender, 1e18, false);
    fastForward(2);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_eligibleAccountRemainsHookBlocked() external {
    _blockLender(approvedLender);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_revertingTokenFailsClosed() external {
    RevertingERC1155BalanceToken revertingToken = new RevertingERC1155BalanceToken();
    ERC1155RoleProvider revertingProvider = new ERC1155RoleProvider(
      address(revertingToken),
      tokenId,
      false
    );
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    vm.stopPrank();

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_revertingTokenDoesNotBlockLaterProvider() external {
    RevertingERC1155BalanceToken revertingToken = new RevertingERC1155BalanceToken();
    ERC1155RoleProvider revertingProvider = new ERC1155RoleProvider(
      address(revertingToken),
      tokenId,
      false
    );
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    hooks.addRoleProvider(address(provider), 0);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);
  }

  function test_constructor_reverts_without_code() external {
    vm.expectRevert(IERC1155RoleProvider.InvalidTokenAddress.selector);
    new ERC1155RoleProvider(address(0), tokenId, false);
  }

  function test_constructor_reverts_without_erc1155_interface() external {
    NonERC1155 nonErc1155 = new NonERC1155();
    vm.expectRevert(IERC1155RoleProvider.InvalidERC1155.selector);
    new ERC1155RoleProvider(address(nonErc1155), tokenId, false);
  }

  function test_constructor_reverts_with_invalid_erc165() external {
    InvalidERC165ERC1155 invalidErc165 = new InvalidERC165ERC1155();
    vm.expectRevert(IERC1155RoleProvider.InvalidERC1155.selector);
    new ERC1155RoleProvider(address(invalidErc165), tokenId, false);
  }

  function test_constructor_allows_usable_token_without_erc165_when_skipped() external {
    NonERC165ERC1155BalanceToken nonErc165 = new NonERC165ERC1155BalanceToken();
    nonErc165.mint(approvedLender, tokenId, 1);
    ERC1155RoleProvider skippedProvider = new ERC1155RoleProvider(
      address(nonErc165),
      tokenId,
      true
    );

    assertEq(
      skippedProvider.getCredential(approvedLender),
      uint32(block.timestamp),
      'credential'
    );
  }

  function _expectDepositRevertNotApproved(address lender, uint256 amount) internal {
    asset.mint(lender, amount);
    vm.startPrank(lender);
    asset.approve(address(market), amount);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }
}
