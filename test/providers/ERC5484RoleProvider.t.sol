// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MockERC721 } from 'solmate/test/utils/mocks/MockERC721.sol';

import '../BaseMarketTest.sol';
import 'src/providers/ERC5484RoleProvider.sol';

contract MockERC5484 is MockERC721 {
  mapping(uint256 => uint256) internal burnAuthById;

  constructor() MockERC721('Access', 'ACCESS') {}

  function burnAuth(uint256 tokenId) external view returns (uint256) {
    return burnAuthById[tokenId];
  }

  function setBurnAuth(uint256 tokenId, uint256 value) external {
    burnAuthById[tokenId] = value;
  }

  function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
    return interfaceId == 0x0489b56f || super.supportsInterface(interfaceId);
  }
}

contract ERC5484RoleProviderTest is BaseMarketTest {
  MockERC5484 internal nft;
  ERC5484RoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;
  uint256 internal tokenId;

  uint8 internal issuerOnlyMask = 1 << 0;
  uint8 internal issuerOrOwnerMask = (1 << 0) | (1 << 1);

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    tokenId = 1;
    nft = new MockERC5484();
    provider = new ERC5484RoleProvider(address(nft), issuerOnlyMask, false);
    nft.mint(approvedLender, tokenId);
    nft.setBurnAuth(tokenId, 0);

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Holders with an allowed burnAuth can deposit.
  function test_deposit_allows_erc5484_allowed_burn_auth() external {
    bytes memory hooksData = _hooksData(address(provider), tokenId);
    _depositWithHooksData(approvedLender, 1e18, hooksData);
  }

  /// @dev Disallowed burnAuth values are rejected.
  function test_deposit_reverts_erc5484_disallowed_burn_auth() external {
    nft.setBurnAuth(tokenId, 1);
    bytes memory hooksData = _hooksData(address(provider), tokenId);
    _expectDepositRevertNotApproved(approvedLender, 1e18, hooksData);
  }

  /// @dev Multiple burnAuth values can be allowed via the mask.
  function test_deposit_allows_erc5484_multiple_burn_auth() external {
    ERC5484RoleProvider openProvider = new ERC5484RoleProvider(
      address(nft),
      issuerOrOwnerMask,
      false
    );
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(openProvider), type(uint32).max);
    vm.stopPrank();

    nft.setBurnAuth(tokenId, 1);
    bytes memory hooksData = _hooksData(address(openProvider), tokenId);
    _depositWithHooksData(approvedLender, 1e18, hooksData);
  }

  /// @dev Non-holders are rejected even if burnAuth is allowed.
  function test_deposit_reverts_erc5484_nonholder() external {
    bytes memory hooksData = _hooksData(address(provider), tokenId);
    _expectDepositRevertNotApproved(unapprovedLender, 1e18, hooksData);
  }

  function test_constructor_reverts_without_code() external {
    vm.expectRevert(ERC5484RoleProvider.InvalidTokenAddress.selector);
    new ERC5484RoleProvider(address(0), issuerOnlyMask, false);
  }

  function test_constructor_reverts_without_erc5484_interface() external {
    MockERC721 nonErc5484 = new MockERC721('Plain', 'PLN');
    vm.expectRevert(ERC5484RoleProvider.InvalidERC5484.selector);
    new ERC5484RoleProvider(address(nonErc5484), issuerOnlyMask, false);
  }

  function test_constructor_reverts_without_burn_auth_mask() external {
    vm.expectRevert(ERC5484RoleProvider.InvalidBurnAuthMask.selector);
    new ERC5484RoleProvider(address(nft), 0, false);
  }

  function test_constructor_allows_skip_interface_check() external {
    MockERC721 nonErc5484 = new MockERC721('Plain', 'PLN');
    new ERC5484RoleProvider(address(nonErc5484), issuerOnlyMask, true);
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
