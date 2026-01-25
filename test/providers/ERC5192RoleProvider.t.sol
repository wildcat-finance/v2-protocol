// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MockERC721 } from 'solmate/test/utils/mocks/MockERC721.sol';

import '../BaseMarketTest.sol';
import 'src/providers/ERC5192RoleProvider.sol';

contract MockERC5192 is MockERC721 {
  mapping(uint256 => bool) internal lockedById;

  constructor() MockERC721('Access', 'ACCESS') {}

  function locked(uint256 tokenId) external view returns (bool) {
    return lockedById[tokenId];
  }

  function setLocked(uint256 tokenId, bool isLocked) external {
    lockedById[tokenId] = isLocked;
  }

  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return interfaceId == 0xb45a3c0e || super.supportsInterface(interfaceId);
  }
}

contract ERC5192RoleProviderTest is BaseMarketTest {
  MockERC5192 internal nft;
  ERC5192RoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;
  uint256 internal tokenId;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    tokenId = 1;
    nft = new MockERC5192();
    provider = new ERC5192RoleProvider(address(nft), true, false);
    nft.mint(approvedLender, tokenId);
    nft.setLocked(tokenId, true);

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Holders of the configured ERC5192 can deposit with a locked token.
  function test_deposit_allows_erc5192_holder_locked() external {
    bytes memory hooksData = _hooksData(address(provider), tokenId);
    _depositWithHooksData(approvedLender, 1e18, hooksData);
  }

  /// @dev Locked enforcement blocks deposits for unlocked tokens.
  function test_deposit_reverts_erc5192_unlocked_when_required() external {
    nft.setLocked(tokenId, false);
    bytes memory hooksData = _hooksData(address(provider), tokenId);
    _expectDepositRevertNotApproved(approvedLender, 1e18, hooksData);
  }

  /// @dev Tokens can be used without requiring locked enforcement.
  function test_deposit_allows_erc5192_unlocked_when_not_required() external {
    nft.setLocked(tokenId, false);
    ERC5192RoleProvider openProvider = new ERC5192RoleProvider(address(nft), false, false);
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(openProvider), type(uint32).max);
    vm.stopPrank();

    bytes memory hooksData = _hooksData(address(openProvider), tokenId);
    _depositWithHooksData(approvedLender, 1e18, hooksData);
  }

  /// @dev Non-holders are rejected even if they can fund the deposit.
  function test_deposit_reverts_erc5192_nonholder() external {
    bytes memory hooksData = _hooksData(address(provider), tokenId);
    _expectDepositRevertNotApproved(unapprovedLender, 1e18, hooksData);
  }

  function test_constructor_reverts_without_code() external {
    vm.expectRevert(ERC5192RoleProvider.InvalidTokenAddress.selector);
    new ERC5192RoleProvider(address(0), true, false);
  }

  function test_constructor_reverts_without_erc5192_interface() external {
    MockERC721 nonErc5192 = new MockERC721('Plain', 'PLN');
    vm.expectRevert(ERC5192RoleProvider.InvalidERC5192.selector);
    new ERC5192RoleProvider(address(nonErc5192), true, false);
  }

  function test_constructor_allows_skip_interface_check() external {
    MockERC721 nonErc5192 = new MockERC721('Plain', 'PLN');
    new ERC5192RoleProvider(address(nonErc5192), true, true);
  }

  function _depositWithHooksData(
    address from,
    uint256 amount,
    bytes memory hooksData
  ) internal returns (uint256) {
    MarketState memory state = pendingState();
    (uint256 currentScaledBalance, uint256 currentBalance) = _getBalance(state, from);

    asset.mint(from, amount);

    vm.startPrank(from);
    asset.approve(address(market), amount);

    (uint104 scaledAmount, uint256 expectedNormalizedAmount) = _trackDeposit(state, from, amount);

    bytes memory data = abi.encodePacked(
      abi.encodeWithSelector(WildcatMarket.depositUpTo.selector, amount),
      hooksData
    );
    (bool success, bytes memory returnData) = address(market).call(data);
    vm.stopPrank();

    if (!success) {
      assembly {
        revert(add(returnData, 0x20), mload(returnData))
      }
    }

    uint256 actualNormalizedAmount = abi.decode(returnData, (uint256));
    assertEq(actualNormalizedAmount, expectedNormalizedAmount, 'Actual amount deposited');
    _checkState(state);
    assertEq(
      market.balanceOf(from),
      currentBalance + state.normalizeAmount(scaledAmount),
      'Resulting balance != old balance + normalize(scale(deposit))'
    );
    assertApproxEqAbs(
      market.balanceOf(from),
      currentBalance + amount,
      1,
      'Resulting balance not within 1 wei of old balance + amount deposited'
    );
    assertEq(
      market.scaledBalanceOf(from),
      currentScaledBalance + scaledAmount,
      'Resulting scaled balance'
    );
    return actualNormalizedAmount;
  }

  function _expectDepositRevertNotApproved(
    address from,
    uint256 amount,
    bytes memory hooksData
  ) internal {
    asset.mint(from, amount);

    vm.startPrank(from);
    asset.approve(address(market), amount);

    bytes memory data = abi.encodePacked(
      abi.encodeWithSelector(WildcatMarket.depositUpTo.selector, amount),
      hooksData
    );
    (bool success, bytes memory returnData) = address(market).call(data);
    vm.stopPrank();

    assertFalse(success, 'expected deposit to revert');
    bytes4 selector;
    assembly {
      selector := mload(add(returnData, 0x20))
    }
    assertEq(selector, AccessControlHooks.NotApprovedLender.selector, 'expected NotApprovedLender');
  }

  function _hooksData(address providerAddress, uint256 id) internal pure returns (bytes memory) {
    return abi.encodePacked(providerAddress, abi.encode(id));
  }
}
