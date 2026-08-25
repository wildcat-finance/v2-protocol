// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { Test as ForgeTest } from 'forge-std/Test.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { MockERC4626 } from 'lib/solady/test/utils/mocks/MockERC4626.sol';

import '../BaseMarketTest.sol';
import { fastForward } from '../helpers/VmUtils.sol';
import 'src/access/BaseAccessControls.sol';
import 'src/providers/ERC4626AssetsRoleProvider.sol';
import 'src/providers/IERC4626AssetsRoleProvider.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';

contract ZeroBalanceRevertingConversionVault {
  function balanceOf(address) external pure returns (uint256) {
    return 0;
  }

  function convertToAssets(uint256) external pure returns (uint256) {
    revert('CONVERSION_CALLED');
  }
}

contract BalanceRevertingERC4626Vault {
  function balanceOf(address) external pure returns (uint256) {
    revert('BALANCE_REVERTED');
  }

  function convertToAssets(uint256) external pure returns (uint256) {
    return 1;
  }
}

contract ConversionRevertingERC4626Vault {
  function balanceOf(address) external pure returns (uint256) {
    return 1;
  }

  function convertToAssets(uint256) external pure returns (uint256) {
    revert('CONVERSION_REVERTED');
  }
}

contract ERC4626AssetsRoleProviderPropertyTest is ForgeTest {
  address internal constant Holder = address(0xA11CE);
  address internal constant Recipient = address(0xB0B);

  function setUp() external {
    vm.warp(1_714_737_030);
  }

  function _createVault(
    uint256 depositedAssets,
    uint256 donatedAssets
  ) internal returns (MockERC4626 vault) {
    MockERC20 underlying = new MockERC20('Underlying', 'UND', 18);
    vault = new MockERC4626(address(underlying), 'Vault', 'VLT', false, 0);
    underlying.mint(Holder, depositedAssets);
    vm.startPrank(Holder);
    underlying.approve(address(vault), depositedAssets);
    vault.deposit(depositedAssets, Holder);
    vm.stopPrank();
    if (donatedAssets > 0) underlying.mint(address(vault), donatedAssets);
  }

  function testFuzz_credentialMatchesCurrentConvertedAssets(
    uint96 depositedAssetsSeed,
    uint96 donatedAssets,
    uint96 minimumAssetsSeed
  ) external {
    uint256 depositedAssets = bound(uint256(depositedAssetsSeed), 1, type(uint96).max);
    MockERC4626 vault = _createVault(depositedAssets, donatedAssets);
    uint256 currentAssets = vault.convertToAssets(vault.balanceOf(Holder));
    uint256 minimumAssets = bound(uint256(minimumAssetsSeed), 1, currentAssets + 1);
    ERC4626AssetsRoleProvider provider = new ERC4626AssetsRoleProvider(
      address(vault),
      minimumAssets
    );
    uint32 expectedCredential = currentAssets >= minimumAssets ? uint32(block.timestamp) : 0;

    assertEq(provider.getCredential(Holder), expectedCredential, 'pull credential');
    assertEq(
      provider.validateCredential(Holder, hex'deadbeef'),
      expectedCredential,
      'validated credential'
    );
  }

  function testFuzz_exactConvertedAssetBoundary(
    uint96 depositedAssetsSeed,
    uint96 donatedAssets
  ) external {
    uint256 depositedAssets = bound(uint256(depositedAssetsSeed), 1, type(uint96).max);
    MockERC4626 vault = _createVault(depositedAssets, donatedAssets);
    uint256 currentAssets = vault.convertToAssets(vault.balanceOf(Holder));
    ERC4626AssetsRoleProvider exactProvider = new ERC4626AssetsRoleProvider(
      address(vault),
      currentAssets
    );
    ERC4626AssetsRoleProvider aboveProvider = new ERC4626AssetsRoleProvider(
      address(vault),
      currentAssets + 1
    );

    assertEq(exactProvider.getCredential(Holder), uint32(block.timestamp), 'exact threshold');
    assertEq(aboveProvider.getCredential(Holder), 0, 'above threshold');
  }

  function testFuzz_shareTransferMovesCredential(uint96 depositedAssetsSeed) external {
    uint256 depositedAssets = bound(uint256(depositedAssetsSeed), 1, type(uint96).max);
    MockERC4626 vault = _createVault(depositedAssets, 0);
    ERC4626AssetsRoleProvider provider = new ERC4626AssetsRoleProvider(address(vault), 1);

    assertEq(provider.getCredential(Holder), uint32(block.timestamp), 'original credential');
    uint256 shares = vault.balanceOf(Holder);
    vm.prank(Holder);
    vault.transfer(Recipient, shares);

    assertEq(provider.getCredential(Holder), 0, 'stale credential');
    assertEq(provider.getCredential(Recipient), uint32(block.timestamp), 'new credential');
  }

  function test_zeroShareBalanceSkipsConversion() external {
    ZeroBalanceRevertingConversionVault vault = new ZeroBalanceRevertingConversionVault();
    ERC4626AssetsRoleProvider provider = new ERC4626AssetsRoleProvider(address(vault), 1);

    assertEq(provider.getCredential(Holder), 0, 'credential');
  }
}

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

    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 0);
  }

  function test_getCredential_exactThreshold() external view {
    assertEq(provider.getCredential(approvedLender), uint32(block.timestamp), 'credential');
  }

  function test_getCredential_rejectsOneAssetBelowThreshold() external {
    ERC4626AssetsRoleProvider higherThresholdProvider = new ERC4626AssetsRoleProvider(
      address(vault),
      minAssets + 1
    );
    assertEq(higherThresholdProvider.getCredential(approvedLender), 0, 'credential');
  }

  function test_deposit_allows_erc4626_assets_holder() external {
    _deposit(approvedLender, 1e18, false);
  }

  function test_deposit_reverts_erc4626_below_min_assets() external {
    _expectDepositRevertNotApproved(unapprovedLender, 1e18);
  }

  function test_deposit_zeroTtlRechecksWithinSameBlock() external {
    _deposit(approvedLender, 1e18, false);

    vm.startPrank(approvedLender);
    vault.redeem(vault.balanceOf(approvedLender), approvedLender, approvedLender);
    vm.stopPrank();

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_deposit_positiveTtlDelaysRemoval() external {
    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 1);

    _deposit(approvedLender, 1e18, false);

    vm.startPrank(approvedLender);
    vault.redeem(vault.balanceOf(approvedLender), approvedLender, approvedLender);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);
    fastForward(2);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_eligibleAccountRemainsHookBlocked() external {
    _blockLender(approvedLender);
    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_balanceRevertingVaultFailsClosed() external {
    BalanceRevertingERC4626Vault revertingVault = new BalanceRevertingERC4626Vault();
    ERC4626AssetsRoleProvider revertingProvider = new ERC4626AssetsRoleProvider(
      address(revertingVault),
      1
    );
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    vm.stopPrank();

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_conversionRevertingVaultFailsClosed() external {
    ConversionRevertingERC4626Vault revertingVault = new ConversionRevertingERC4626Vault();
    ERC4626AssetsRoleProvider revertingProvider = new ERC4626AssetsRoleProvider(
      address(revertingVault),
      1
    );
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    vm.stopPrank();

    _expectDepositRevertNotApproved(approvedLender, 1e18);
  }

  function test_revertingVaultDoesNotBlockLaterProvider() external {
    ConversionRevertingERC4626Vault revertingVault = new ConversionRevertingERC4626Vault();
    ERC4626AssetsRoleProvider revertingProvider = new ERC4626AssetsRoleProvider(
      address(revertingVault),
      1
    );
    vm.startPrank(parameters.borrower);
    hooks.removeRoleProvider(address(provider));
    hooks.addRoleProvider(address(revertingProvider), 0);
    hooks.addRoleProvider(address(provider), 0);
    vm.stopPrank();

    _deposit(approvedLender, 1e18, false);
  }

  function test_constructor_reverts_without_code() external {
    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidVaultAddress.selector);
    new ERC4626AssetsRoleProvider(address(0), minAssets);
  }

  function test_constructor_reverts_with_zero_minimum() external {
    vm.expectRevert(IERC4626AssetsRoleProvider.InvalidMinimumAssets.selector);
    new ERC4626AssetsRoleProvider(address(vault), 0);
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

contract ERC4626AssetsRoleProviderWildcatWrapperTest is BaseMarketTest {
  function test_wildcatWrapperInterestCanAuthorizeAnotherMarket() external {
    uint256 wrappedAssets = 100e18;
    _deposit(alice, wrappedAssets, false);
    _borrow(market.borrowableAssets());

    WildcatMarket sourceMarket = market;
    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(
      wrapperFactory.createWrapper(address(sourceMarket))
    );
    _authorizeLender(address(wrapper));

    vm.startPrank(alice);
    sourceMarket.approve(address(wrapper), wrappedAssets);
    uint256 shares = wrapper.deposit(wrappedAssets, alice);
    vm.stopPrank();

    uint256 minimumAssets = wrapper.convertToAssets(shares) + 1e18;
    ERC4626AssetsRoleProvider provider = new ERC4626AssetsRoleProvider(
      address(wrapper),
      minimumAssets
    );

    MockERC20 targetAsset = new MockERC20('Target Token', 'TGT', 18);
    MarketInputParameters memory targetParameters = parameters;
    targetParameters.asset = address(targetAsset);
    WildcatMarket targetMarket = deployMarket(targetParameters);

    vm.prank(parameters.borrower);
    hooks.addRoleProvider(address(provider), 0);
    _deauthorizeLender(alice);

    assertEq(provider.getCredential(alice), 0, 'credential before interest');
    targetAsset.mint(alice, 1e18);
    vm.startPrank(alice);
    targetAsset.approve(address(targetMarket), 1e18);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    targetMarket.depositUpTo(1e18);
    vm.stopPrank();

    fastForward(365 days);
    sourceMarket.updateState();

    assertGe(wrapper.convertToAssets(shares), minimumAssets, 'wrapped claim');
    assertEq(provider.getCredential(alice), uint32(block.timestamp), 'credential after interest');
    vm.prank(alice);
    targetMarket.depositUpTo(1e18);
  }
}
