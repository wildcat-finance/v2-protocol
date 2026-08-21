// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Test as ForgeTest } from 'forge-std/Test.sol';
import { MockERC721 } from 'solmate/test/utils/mocks/MockERC721.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/providers/ERC721RoleProvider.sol';
import 'src/providers/IERC721RoleProvider.sol';

contract NonERC721 {}

contract InvalidERC165ERC721 {
  function supportsInterface(bytes4) external pure returns (bool) {
    return true;
  }
}

contract MalformedERC165Response {
  uint256 internal immutable _value;
  uint256 internal immutable _length;

  constructor(uint256 value, uint256 length) {
    _value = value;
    _length = length;
  }

  fallback() external {
    uint256 value = _value;
    uint256 length = _length;
    assembly {
      mstore(0x00, value)
      return(0x00, length)
    }
  }
}

contract NonERC165ERC721BalanceToken {
  mapping(address account => uint256 balance) public balanceOf;

  function mint(address account) external {
    balanceOf[account] += 1;
  }
}

contract RevertingERC721BalanceToken {
  function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
    return interfaceId == 0x01ffc9a7 || interfaceId == 0x80ac58cd;
  }

  function balanceOf(address) external pure returns (uint256) {
    revert('BALANCE_REVERTED');
  }
}

contract ERC721RoleProviderPropertyTest is ForgeTest {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);

  function setUp() external {
    vm.warp(1_714_737_030);
  }

  function testFuzz_transferMovesCredential(uint256 tokenId) external {
    MockERC721 token = new MockERC721('Access', 'ACCESS');
    ERC721RoleProvider provider = new ERC721RoleProvider(address(token), false);
    token.mint(Holder, tokenId);

    assertEq(provider.getCredential(Holder), uint32(block.timestamp), 'original credential');
    assertEq(
      provider.validateCredential(Holder, hex'deadbeef'),
      uint32(block.timestamp),
      'validated credential'
    );

    vm.prank(Holder);
    token.transferFrom(Holder, Recipient, tokenId);

    assertEq(provider.getCredential(Holder), 0, 'stale credential');
    assertEq(provider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }
}

contract ERC721RoleProviderTest is BaseMarketTest {
  MockERC721 internal token;
  ERC721RoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    token = new MockERC721('Access', 'ACCESS');
    provider = new ERC721RoleProvider(address(token), false);
    token.mint(approvedLender, 1);

    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 0);
  }

  function test_getCredential_usesCollectionBalance() external view {
    assertEq(provider.getCredential(approvedLender), uint32(block.timestamp), 'credential');
    assertEq(provider.getCredential(unapprovedLender), 0, 'missing credential');
  }

  function test_deposit_allows_erc721_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  function test_deposit_reverts_erc721_nonholder() external {
    _expectDepositRevertNotApproved(unapprovedLender, 1e18);
  }

  function test_deposit_zeroTtlRechecksWithinSameBlock() external {
    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    token.transferFrom(approvedLender, unapprovedLender, 1);

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_deposit_zeroTtlFollowsTransferredToken() external {
    vm.prank(approvedLender);
    token.transferFrom(approvedLender, unapprovedLender, 1);

    _deposit(unapprovedLender, 1e18, false);
  }

  function test_deposit_positiveTtlDelaysRemoval() external {
    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);

    _deposit(approvedLender, 1e18, false);

    vm.prank(approvedLender);
    token.transferFrom(approvedLender, unapprovedLender, 1);

    _deposit(approvedLender, 1e18, false);
    fastForward(2);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_eligibleAccountRemainsHookBlocked() external {
    _blockLender(approvedLender);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_revertingTokenFailsClosed() external {
    RevertingERC721BalanceToken revertingToken = new RevertingERC721BalanceToken();
    ERC721RoleProvider revertingProvider = new ERC721RoleProvider(
      address(revertingToken),
      false
    );
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    vm.stopPrank();

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_revertingTokenDoesNotBlockLaterProvider() external {
    RevertingERC721BalanceToken revertingToken = new RevertingERC721BalanceToken();
    ERC721RoleProvider revertingProvider = new ERC721RoleProvider(
      address(revertingToken),
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
    vm.expectRevert(IERC721RoleProvider.InvalidTokenAddress.selector);
    new ERC721RoleProvider(address(0), false);
  }

  function test_constructor_reverts_without_erc721_interface() external {
    NonERC721 nonErc721 = new NonERC721();
    vm.expectRevert(IERC721RoleProvider.InvalidERC721.selector);
    new ERC721RoleProvider(address(nonErc721), false);
  }

  function test_constructor_reverts_with_invalid_erc165() external {
    InvalidERC165ERC721 invalidErc165 = new InvalidERC165ERC721();
    vm.expectRevert(IERC721RoleProvider.InvalidERC721.selector);
    new ERC721RoleProvider(address(invalidErc165), false);
  }

  function test_constructor_reverts_with_malformed_erc165_response() external {
    address shortResponse = address(new MalformedERC165Response(1, 0x1f));
    vm.expectRevert(IERC721RoleProvider.InvalidERC721.selector);
    new ERC721RoleProvider(shortResponse, false);

    address dirtyBoolean = address(new MalformedERC165Response(2, 0x20));
    vm.expectRevert(IERC721RoleProvider.InvalidERC721.selector);
    new ERC721RoleProvider(dirtyBoolean, false);
  }

  function test_constructor_allows_usable_token_without_erc165_when_skipped() external {
    NonERC165ERC721BalanceToken nonErc165 = new NonERC165ERC721BalanceToken();
    nonErc165.mint(approvedLender);
    ERC721RoleProvider skippedProvider = new ERC721RoleProvider(address(nonErc165), true);

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
