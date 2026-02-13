// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import "src/WildcatArchController.sol";
import "src/HooksFactoryRevolving.sol";
import "src/libraries/LibStoredInitCode.sol";
import "src/market/WildcatMarket.sol";
import "src/market/WildcatMarketRevolving.sol";
import "src/interfaces/IWildcatMarketRevolving.sol";
import "src/libraries/MathUtils.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "../shared/mocks/MockHooks.sol";
import {MockSanctionsSentinel} from "../shared/mocks/MockSanctionsSentinel.sol";
import {deployMockChainalysis} from "../shared/mocks/MockChainalysis.sol";

contract WildcatMarketRevolvingTest is Test {
    using MathUtils for uint256;

    WildcatArchController internal archController;
    HooksFactoryRevolving internal hooksFactoryRevolving;
    MockSanctionsSentinel internal sanctionsSentinel;
    MockERC20 internal underlying;

    address internal hooksTemplate;
    address internal hooksInstance;
    WildcatMarket internal market;
    IWildcatMarketRevolving internal revolvingMarket;

    address internal borrower;
    address internal constant lender = address(0xA11CE);

    uint16 internal constant commitmentFeeBips = 200;
    uint16 internal constant annualInterestBips = 1000;

    function _storeMarketInitCode() internal virtual returns (address initCodeStorage, uint256 initCodeHash) {
        bytes memory marketInitCode = type(WildcatMarketRevolving).creationCode;
        initCodeHash = uint256(keccak256(marketInitCode));
        initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
    }

    function setUp() public {
        borrower = address(this);
        deployMockChainalysis();
        archController = new WildcatArchController();
        sanctionsSentinel = new MockSanctionsSentinel(address(archController));
        (address marketTemplate, uint256 marketInitCodeHash) = _storeMarketInitCode();
        hooksFactoryRevolving = new HooksFactoryRevolving(
            address(archController), address(sanctionsSentinel), marketTemplate, marketInitCodeHash
        );
        archController.registerControllerFactory(address(hooksFactoryRevolving));
        hooksFactoryRevolving.registerWithArchController();

        hooksTemplate = LibStoredInitCode.deployInitCode(type(MockHooks).creationCode);
        hooksFactoryRevolving.addHooksTemplate(hooksTemplate, "revolving-template", address(0), address(0), 0, 0);

        underlying = new MockERC20("Underlying", "UND", 18);
        archController.registerBorrower(borrower);
        hooksInstance = hooksFactoryRevolving.deployHooksInstance(hooksTemplate, bytes(""));

        DeployMarketInputs memory params = DeployMarketInputs({
            asset: address(underlying),
            namePrefix: "Wildcat ",
            symbolPrefix: "wc",
            maxTotalSupply: 1_000_000e18,
            annualInterestBips: annualInterestBips,
            delinquencyFeeBips: 0,
            withdrawalBatchDuration: 1 days,
            reserveRatioBips: 2_000,
            delinquencyGracePeriod: 1 days,
            hooks: EmptyHooksConfig.setHooksAddress(hooksInstance)
        });

        address marketAddress = hooksFactoryRevolving.deployMarket(
            params, bytes(""), abi.encode(uint8(1), commitmentFeeBips), bytes32(uint256(1)), address(0), 0
        );
        market = WildcatMarket(marketAddress);
        revolvingMarket = IWildcatMarketRevolving(marketAddress);

        underlying.mint(lender, type(uint128).max);
        vm.prank(lender);
        underlying.approve(address(market), type(uint256).max);

        underlying.mint(borrower, type(uint128).max);
        underlying.approve(address(market), type(uint256).max);
    }

    function _deposit(address account, uint256 amount) internal {
        vm.prank(account);
        market.depositUpTo(amount);
    }

    function test_commitmentFeeBips_initializesFromMarketData() external view {
        assertEq(revolvingMarket.commitmentFeeBips(), commitmentFeeBips);
        assertEq(revolvingMarket.drawnAmount(), 0);
    }

    function test_borrow_updatesDrawnAmount() external {
        _deposit(lender, 1_000e18);
        market.borrow(400e18);
        assertEq(revolvingMarket.drawnAmount(), 400e18);
    }

    function test_repay_updatesDrawnAmount_withSaturation() external {
        _deposit(lender, 1_000e18);
        market.borrow(400e18);

        market.repay(250e18);
        assertEq(revolvingMarket.drawnAmount(), 150e18);

        market.repay(1_000e18);
        assertEq(revolvingMarket.drawnAmount(), 0);
    }

    function test_repayAndProcessUnpaidWithdrawalBatches_updatesDrawnAmount() external {
        _deposit(lender, 1_000e18);
        market.borrow(400e18);

        market.repayAndProcessUnpaidWithdrawalBatches(100e18, 0);
        assertEq(revolvingMarket.drawnAmount(), 300e18);
    }

    function test_closeMarket_resetsDrawnAmount() external {
        _deposit(lender, 1_000e18);
        market.borrow(400e18);

        uint256 owed = market.totalDebts() - market.totalAssets();
        underlying.mint(borrower, owed);
        market.closeMarket();

        assertEq(revolvingMarket.drawnAmount(), 0);
        assertTrue(market.isClosed());
    }

    function test_updateState_usesCommitmentFeeAtZeroUtilization() external {
        _deposit(lender, 1_000e18);

        vm.warp(block.timestamp + 365 days);
        market.updateState();

        uint256 expectedBaseInterestRay = MathUtils.calculateLinearInterestFromBips(commitmentFeeBips, 365 days);
        uint256 expectedScaleFactor = RAY + expectedBaseInterestRay;
        assertEq(market.scaleFactor(), expectedScaleFactor);
    }

    function test_updateState_usesCommitmentPlusUtilizationInterest() external {
        _deposit(lender, 1_000e18);
        market.borrow(500e18);

        vm.warp(block.timestamp + 365 days);
        market.updateState();

        uint256 commitmentInterestRay = MathUtils.calculateLinearInterestFromBips(commitmentFeeBips, 365 days);
        uint256 annualInterestRay = MathUtils.calculateLinearInterestFromBips(annualInterestBips, 365 days);
        uint256 utilizationInterestRay = MathUtils.mulDiv(annualInterestRay, 500e18, 1_000e18);

        uint256 expectedScaleFactor = RAY + commitmentInterestRay + utilizationInterestRay;
        assertEq(market.scaleFactor(), expectedScaleFactor);
    }

    function test_updateState_zeroTimeDelta_doesNotAccrueInterest() external {
        _deposit(lender, 1_000e18);
        market.borrow(500e18);

        uint256 scaleFactorBefore = market.scaleFactor();
        market.updateState();

        assertEq(market.scaleFactor(), scaleFactorBefore);
        assertEq(revolvingMarket.drawnAmount(), 500e18);
    }

    function test_updateState_zeroSupply_doesNotAccrueInterest() external {
        uint256 initialScaleFactor = market.scaleFactor();

        vm.warp(block.timestamp + 365 days);
        market.updateState();

        assertEq(market.scaleFactor(), initialScaleFactor);
        assertEq(revolvingMarket.drawnAmount(), 0);
    }

    function test_updateState_clampsDrawnAmountToTotalSupply() external {
        _deposit(lender, 1_000e18);

        // Force drawnAmount > totalSupply so utilization is clamped to 100%.
        vm.store(address(market), bytes32(uint256(10)), bytes32(uint256(2_000e18)));

        vm.warp(block.timestamp + 365 days);
        market.updateState();

        uint256 commitmentInterestRay = MathUtils.calculateLinearInterestFromBips(commitmentFeeBips, 365 days);
        uint256 utilizationInterestRay = MathUtils.calculateLinearInterestFromBips(annualInterestBips, 365 days);
        uint256 expectedScaleFactor = RAY + commitmentInterestRay + utilizationInterestRay;
        assertEq(market.scaleFactor(), expectedScaleFactor);
    }
}
