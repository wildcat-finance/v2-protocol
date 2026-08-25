// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import {IAdapter} from "lib/vault-v2/src/interfaces/IAdapter.sol";
import {LibERC20} from "src/libraries/LibERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {WildcatMarketV2Adapter} from "../../integrations/morpho/WildcatMarketV2Adapter.sol";
import {WildcatMarketV2AdapterFactory} from "../../integrations/morpho/WildcatMarketV2AdapterFactory.sol";
import {IWildcatMarketV2Adapter} from "../../integrations/morpho/interfaces/IWildcatMarketV2Adapter.sol";
import {IWildcatMarketV2AdapterFactory} from "../../integrations/morpho/interfaces/IWildcatMarketV2AdapterFactory.sol";
import {MarketFixture} from "../shared/MarketFixture.sol";

contract MorphoVaultV2CallbackMock {
    using LibERC20 for address;

    address public immutable asset;
    address public immutable owner;

    mapping(address account => bool) public isAllocator;
    mapping(bytes32 id => uint256 assets) public allocation;

    constructor(address _asset, address _owner) {
        asset = _asset;
        owner = _owner;
    }

    function setIsAllocator(address account, bool status) external {
        require(msg.sender == owner, "not owner");
        isAllocator[account] = status;
    }

    function allocate(IAdapter adapter, uint256 assets) external returns (bytes32[] memory ids, int256 change) {
        asset.safeTransfer(address(adapter), assets);
        (ids, change) = adapter.allocate("", assets, msg.sig, msg.sender);
        _applyChange(ids, change);
    }

    function deallocate(IAdapter adapter, uint256 assets) external returns (bytes32[] memory ids, int256 change) {
        (ids, change) = adapter.deallocate("", assets, msg.sig, msg.sender);
        _applyChange(ids, change);
        asset.safeTransferFrom(address(adapter), address(this), assets);
    }

    function _applyChange(bytes32[] memory ids, int256 change) internal {
        for (uint256 i; i < ids.length; ++i) {
            int256 newAllocation = int256(allocation[ids[i]]) + change;
            require(newAllocation >= 0, "negative allocation");
            allocation[ids[i]] = uint256(newAllocation);
        }
    }
}

contract PreV25MarketMock {
    address public immutable archController;

    constructor(address _archController) {
        archController = _archController;
    }

    function scaledTransferRounding() external pure returns (bytes32) {
        return keccak256("scaleAmountHalfUp");
    }
}

contract WildcatMarketV2AdapterTest is MarketFixture {
    address internal constant VaultOwner = address(0xBEEF);
    address internal constant Allocator = address(0xA110C4);
    address internal constant SkimRecipient = address(0xCAFE);
    address internal constant Outsider = address(0xBAD5);

    Fixture internal wildcat;
    MorphoVaultV2CallbackMock internal vault;
    WildcatMarketV2AdapterFactory internal adapterFactory;
    WildcatMarketV2Adapter internal adapter;

    function setUp() external {
        Options memory options = _defaultOptions(HooksKind.OpenTerm);
        options.protocolFeeBips = 0;
        options.annualInterestBips = 0;
        options.delinquencyFeeBips = 0;
        wildcat = _newMarket(options);
        _registerMarket(wildcat);

        vault = new MorphoVaultV2CallbackMock(address(wildcat.asset), VaultOwner);
        adapterFactory = new WildcatMarketV2AdapterFactory(address(wildcat.archController));
        adapter = WildcatMarketV2Adapter(
            adapterFactory.createWildcatMarketV2Adapter(address(vault), address(wildcat.market))
        );

        vm.prank(VaultOwner);
        vault.setIsAllocator(Allocator, true);
    }

    function _registerMarket(Fixture memory fixture) internal {
        fixture.archController.registerControllerFactory(address(fixture.factory));
        vm.prank(address(fixture.factory));
        fixture.archController.registerController(address(fixture.factory));
        vm.prank(address(fixture.factory));
        fixture.archController.registerMarket(address(fixture.market));
    }

    function _allocate(uint256 assets) internal returns (int256 change) {
        wildcat.asset.mint(address(vault), assets);
        (, change) = vault.allocate(adapter, assets);
    }

    function _queue(uint256 assets) internal returns (uint32 expiry) {
        vm.prank(VaultOwner);
        adapter.queueAdapterWithdrawal(assets);
        expiry = adapter.trackedWithdrawalExpiryAt(adapter.trackedWithdrawalExpiriesLength() - 1);
    }

    function _mature(uint32 expiry) internal {
        vm.warp(uint256(expiry) + 1);
    }

    function testFactoryAndConstructorPinTheV25Position() external view {
        assertEq(adapter.factory(), address(adapterFactory));
        assertEq(adapter.parentVault(), address(vault));
        assertEq(adapter.market(), address(wildcat.market));
        assertEq(adapter.asset(), address(wildcat.asset));
        assertEq(adapterFactory.archController(), address(wildcat.archController));
        assertEq(adapterFactory.wildcatMarketV2Adapter(address(vault), address(wildcat.market)), address(adapter));
        assertTrue(adapterFactory.isWildcatMarketV2Adapter(address(adapter)));
        assertEq(wildcat.asset.allowance(address(adapter), address(vault)), type(uint256).max);
        assertEq(wildcat.asset.allowance(address(adapter), address(wildcat.market)), type(uint256).max);
    }

    function testFactoryRejectsDuplicateAndNonV25Markets() external {
        vm.expectRevert(IWildcatMarketV2AdapterFactory.AdapterAlreadyExists.selector);
        adapterFactory.createWildcatMarketV2Adapter(address(vault), address(wildcat.market));

        vm.expectRevert(IWildcatMarketV2AdapterFactory.NotRegisteredMarket.selector);
        adapterFactory.createWildcatMarketV2Adapter(address(vault), address(0x1234));

        PreV25MarketMock oldMarket = new PreV25MarketMock(address(wildcat.archController));
        vm.prank(address(wildcat.factory));
        wildcat.archController.registerMarket(address(oldMarket));
        vm.expectRevert(IWildcatMarketV2AdapterFactory.UnsupportedMarketVersion.selector);
        adapterFactory.createWildcatMarketV2Adapter(address(vault), address(oldMarket));
    }

    function testFactoryRejectsAssetMismatch() external {
        MockERC20 otherAsset = new MockERC20("Other", "OTHER", 18);
        MorphoVaultV2CallbackMock otherVault = new MorphoVaultV2CallbackMock(address(otherAsset), VaultOwner);

        vm.expectRevert(IWildcatMarketV2Adapter.AssetMismatch.selector);
        adapterFactory.createWildcatMarketV2Adapter(address(otherVault), address(wildcat.market));
    }

    function testCallbacksAndQueueRequireTheirIntendedCallers() external {
        vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
        adapter.allocate("", 0, bytes4(0), address(0));

        vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
        adapter.deallocate("", 0, bytes4(0), address(0));

        vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
        adapter.queueAdapterWithdrawal(1);

        _allocate(3e18);
        vm.prank(Allocator);
        adapter.queueAdapterWithdrawal(1e18);
        vm.prank(VaultOwner);
        adapter.queueAdapterWithdrawal(1e18);
        assertEq(adapter.trackedWithdrawalExpiriesLength(), 1);
    }

    function testQueuedAssetsRemainInRealAssets() external {
        _allocate(1_000e18);
        uint32 expiry = _queue(600e18);

        assertEq(wildcat.market.balanceOf(address(adapter)), 400e18);
        assertEq(adapter.pendingWithdrawals(expiry), 600e18);
        assertEq(adapter.totalPendingWithdrawals(), 600e18);
        assertEq(adapter.realAssets(), 1_000e18);
    }

    function testDeallocateReportsThePostPullPositionWhenClaimExceedsRequest() external {
        _allocate(1_000e18);
        uint32 expiry = _queue(600e18);
        _mature(expiry);

        (, int256 change) = vault.deallocate(adapter, 400e18);

        vm.assertEq(change, -int256(400e18));
        assertEq(vault.allocation(adapter.adapterId()), 600e18);
        assertEq(adapter.realAssets(), 600e18);
        assertEq(adapter.idleAssets(), 200e18);
        assertEq(wildcat.asset.balanceOf(address(vault)), 400e18);
        assertEq(wildcat.asset.balanceOf(address(adapter)), 200e18);
        assertEq(wildcat.market.balanceOf(address(adapter)), 400e18);
        assertEq(adapter.totalPendingWithdrawals(), 0);
    }

    function testDirectMarketExecutionCannotMakeClaimProceedsDisappear() external {
        _allocate(1_000e18);
        uint32 expiry = _queue(600e18);
        _mature(expiry);

        vm.prank(Outsider);
        wildcat.market.executeWithdrawal(address(adapter), expiry);

        assertEq(adapter.pendingWithdrawals(expiry), 0);
        assertEq(adapter.idleAssets(), 600e18);
        assertEq(adapter.realAssets(), 1_000e18);

        vault.deallocate(adapter, 400e18);
        assertEq(adapter.trackedWithdrawalExpiriesLength(), 0);
        assertEq(adapter.idleAssets(), 200e18);
        assertEq(adapter.realAssets(), 600e18);
    }

    function testPartialBatchPaymentRemainsPendingAfterAvailableCashIsDeallocated() external {
        _allocate(1_000e18);
        uint256 borrowable = wildcat.market.borrowableAssets();
        vm.prank(Borrower);
        wildcat.market.borrow(borrowable);

        uint32 expiry = _queue(600e18);
        _mature(expiry);
        assertEq(adapter.getAvailableLiquidity(), 200e18);

        vault.deallocate(adapter, 200e18);

        assertEq(vault.allocation(adapter.adapterId()), 800e18);
        assertEq(adapter.pendingWithdrawals(expiry), 400e18);
        assertEq(adapter.realAssets(), 800e18);
        assertEq(adapter.idleAssets(), 0);
        assertEq(adapter.trackedWithdrawalExpiriesLength(), 1);
    }

    function testUnderlyingSkimOnlyTransfersSurplus() external {
        _allocate(1_000e18);
        uint32 expiry = _queue(600e18);
        _mature(expiry);
        adapter.realizeClaimable(1);
        assertEq(adapter.idleAssets(), 600e18);

        wildcat.asset.mint(address(adapter), 25e18);
        vm.prank(VaultOwner);
        adapter.setSkimRecipient(SkimRecipient);
        vm.prank(SkimRecipient);
        adapter.skim(address(wildcat.asset));

        assertEq(wildcat.asset.balanceOf(SkimRecipient), 25e18);
        assertEq(wildcat.asset.balanceOf(address(adapter)), 600e18);
        assertEq(adapter.idleAssets(), 600e18);

        vm.expectRevert(IWildcatMarketV2Adapter.CannotSkimWildcatMarketTokens.selector);
        vm.prank(SkimRecipient);
        adapter.skim(address(wildcat.market));
    }

    function testQueueFullWithdrawalUsesExactScaledBalance() external {
        _allocate(123e18);
        vm.prank(VaultOwner);
        adapter.queueAdapterFullWithdrawal();

        assertEq(wildcat.market.scaledBalanceOf(address(adapter)), 0);
        assertEq(adapter.totalPendingWithdrawals(), 123e18);
        assertEq(adapter.realAssets(), 123e18);
    }

    function testTrackedExpiryCountIsHardBounded() external {
        _allocate(9e18);
        for (uint256 i; i < adapter.MAX_TRACKED_WITHDRAWAL_EXPIRIES(); ++i) {
            uint32 expiry = _queue(1e18);
            _mature(expiry);
        }

        assertEq(adapter.trackedWithdrawalExpiriesLength(), adapter.MAX_TRACKED_WITHDRAWAL_EXPIRIES());
        vm.expectRevert(IWildcatMarketV2Adapter.TooManyTrackedWithdrawalExpiries.selector);
        vm.prank(VaultOwner);
        adapter.queueAdapterWithdrawal(1e18);
    }

    function testRealAssetsAccruesInterestOnUnpaidScaledWithdrawals() external {
        Options memory options = _defaultOptions(HooksKind.OpenTerm);
        Fixture memory interestMarket = _newMarket(options);
        _registerMarket(interestMarket);

        MorphoVaultV2CallbackMock interestVault =
            new MorphoVaultV2CallbackMock(address(interestMarket.asset), VaultOwner);
        WildcatMarketV2AdapterFactory interestFactory =
            new WildcatMarketV2AdapterFactory(address(interestMarket.archController));
        WildcatMarketV2Adapter interestAdapter = WildcatMarketV2Adapter(
            interestFactory.createWildcatMarketV2Adapter(address(interestVault), address(interestMarket.market))
        );

        interestMarket.asset.mint(address(interestVault), 1_000e18);
        interestVault.allocate(interestAdapter, 1_000e18);
        uint256 borrowable = interestMarket.market.borrowableAssets();
        vm.prank(Borrower);
        interestMarket.market.borrow(borrowable);

        vm.prank(VaultOwner);
        interestAdapter.queueAdapterWithdrawal(600e18);
        uint32 expiry = interestAdapter.trackedWithdrawalExpiryAt(0);
        vm.warp(uint256(expiry) + 30 days);

        assertTrue(interestAdapter.totalPendingWithdrawals() > 600e18);
        assertTrue(interestAdapter.realAssets() > 1_000e18);
    }

    function testFuzzQueueAndDeallocatePreserveManagedValue(
        uint256 depositSeed,
        uint256 queueSeed,
        uint256 deallocateSeed
    ) external {
        uint256 deposit = bound(depositSeed, 1e12, 1e24);
        uint256 queued = bound(queueSeed, 1, deposit);
        uint256 deallocated = bound(deallocateSeed, 1, queued);

        _allocate(deposit);
        uint32 expiry = _queue(queued);
        assertEq(adapter.realAssets(), deposit);
        _mature(expiry);
        vault.deallocate(adapter, deallocated);

        uint256 remaining = deposit - deallocated;
        assertEq(vault.allocation(adapter.adapterId()), remaining);
        assertEq(adapter.realAssets(), remaining);
        assertEq(wildcat.asset.balanceOf(address(vault)) + adapter.realAssets(), deposit);
    }
}
