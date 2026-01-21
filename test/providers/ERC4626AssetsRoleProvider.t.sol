// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { MockERC4626 } from 'lib/solady/test/utils/mocks/MockERC4626.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/providers/ERC4626AssetsRoleProvider.sol';

contract ERC4626AssetsRoleProviderTest is BaseMarketTest {
  MockERC20 internal underlying;
  MockERC4626 internal vault;
  ERC4626AssetsRoleProvider internal provider;

  address internal approvedLender;
  address internal unapprovedLender;

  uint256 internal minAssets = 100e18;

  function setUp() public override {
    super.setUp();
    _deauthorizeLender(alice);

    approvedLender = alice;
    unapprovedLender = bob;

    underlying = new MockERC20('Underlying', 'UND', 18);
    vault = new MockERC4626(address(underlying), 'Vault', 'VLT', false, 0);
    provider = new ERC4626AssetsRoleProvider(address(vault), minAssets);

    underlying.mint(approvedLender, minAssets);
    vm.startPrank(approvedLender);
    underlying.approve(address(vault), minAssets);
    vault.deposit(minAssets, approvedLender);
    vm.stopPrank();

    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), type(uint32).max);
    vm.stopPrank();
  }

  /// @dev Holders with enough assets in the vault can deposit.
  function test_deposit_allows_erc4626_assets_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  /// @dev Accounts below the asset threshold are rejected.
  function test_deposit_reverts_erc4626_below_min_assets() external {
    uint256 amount = 1e18;
    asset.mint(unapprovedLender, amount);

    vm.startPrank(unapprovedLender);
    asset.approve(address(market), amount);
    vm.expectRevert(AccessControlHooks.NotApprovedLender.selector);
    market.depositUpTo(amount);
    vm.stopPrank();
  }

  /// @dev Pull-provider credentials remain valid until TTL expiry.
  function test_deposit_erc4626_expires_after_ttl() external {
    vm.startPrank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);

    vm.startPrank(approvedLender);
    vault.redeem(vault.balanceOf(approvedLender), approvedLender, approvedLender);
    vm.stopPrank();

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
    vm.expectRevert(ERC4626AssetsRoleProvider.InvalidVaultAddress.selector);
    new ERC4626AssetsRoleProvider(address(0), minAssets);
  }
}
