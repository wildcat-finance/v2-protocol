// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {MathUtils, RAY} from "src/libraries/MathUtils.sol";
import {Wildcat4626Wrapper} from "src/vault/Wildcat4626Wrapper.sol";
import {IWildcatMarketToken} from "src/vault/Wildcat4626Wrapper.sol";

contract MockErc20 {
    string public constant name = "HEX Token";
    string public constant symbol = "HEX";
    uint8 public constant decimals = 18;

    mapping(address => uint256) internal _balances;

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 balance = _balances[msg.sender];
        require(balance >= amount, "BALANCE");
        unchecked {
            _balances[msg.sender] = balance - amount;
            _balances[to] += amount;
        }
        return true;
    }
}

contract MockMarketToken is IWildcatMarketToken {
    using MathUtils for uint256;

    string public constant name = "Mock fries USDC";
    string public constant symbol = "friesUSDC";
    uint8 public immutable override decimals;

    uint256 public override scaleFactor;
    address public immutable override borrower;

    mapping(address => uint256) internal _scaledBalances;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 internal _scaledTotalSupply;

    constructor(uint8 tokenDecimals, address borrower_) {
        decimals = tokenDecimals;
        scaleFactor = RAY;
        borrower = borrower_;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _scaledBalances[account].rayMul(scaleFactor);
    }

    function totalSupply() external view returns (uint256) {
        return _scaledTotalSupply.rayMul(scaleFactor);
    }

    function scaledBalanceOf(address account) external view override returns (uint256) {
        return _scaledBalances[account];
    }

    function maxTotalSupply() external view override returns (uint256) {
        return uint256(type(uint128).max);
    }

    function setScaleFactor(uint256 newScaleFactor) external {
        require(newScaleFactor != 0, "ZERO_FACTOR");
        scaleFactor = newScaleFactor;
    }

    function mint(address to, uint256 assets) external {
        uint256 scaled = assets.rayDiv(scaleFactor);
        require(scaled != 0, "SCALED_ZERO");
        _scaledBalances[to] += scaled;
        _scaledTotalSupply += scaled;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOWANCE");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 scaled = amount.rayDiv(scaleFactor);
        require(scaled != 0, "SCALED_ZERO");
        uint256 fromBalance = _scaledBalances[from];
        require(fromBalance >= scaled, "BALANCE");
        unchecked {
            _scaledBalances[from] = fromBalance - scaled;
            _scaledBalances[to] += scaled;
        }
    }
}

contract Wildcat4626WrapperTest is Test {
    using MathUtils for uint256;

    MockMarketToken internal market;
    Wildcat4626Wrapper internal wrapper;

    address internal constant FED = address(0xFED);
    address internal constant BOB = address(0xB0B);
    address internal constant BORROWER = address(0xB0123123);

    uint256 internal constant INITIAL_ASSETS = 100e18;

    function setUp() external {
        market = new MockMarketToken(18, BORROWER);
        wrapper = new Wildcat4626Wrapper(address(market));

        market.mint(FED, INITIAL_ASSETS);
        market.mint(BOB, INITIAL_ASSETS);

        vm.prank(FED);
        market.approve(address(wrapper), type(uint256).max);

        vm.prank(BOB);
        market.approve(address(wrapper), type(uint256).max);
    }

    function test_metadataDerivedFromMarketSymbol() external view {
    assertEq(wrapper.name(), "friesUSDC [4626 Vault Shares]");
    assertEq(wrapper.symbol(), "v-friesUSDC");
    }

    function test_depositMintsScaledShares() external {
        vm.prank(FED);
        uint256 shares = wrapper.deposit(50e18, FED);

        assertEq(shares, 50e18, "scaled mismatch");
        assertEq(wrapper.balanceOf(FED), shares, "share balance");
        assertEq(wrapper.totalSupply(), shares, "total supply");
        assertEq(wrapper.totalAssets(), 50e18, "total assets");
        assertEq(market.scaledBalanceOf(address(wrapper)), shares, "market scaled balance");
    }

    function test_withdrawBurnsScaledShares() external {
        vm.prank(FED);
        wrapper.deposit(40e18, FED);

        vm.prank(FED);
        uint256 sharesBurned = wrapper.withdraw(15e18, FED, FED);

        assertEq(sharesBurned, 15e18, "shares burned");
        assertEq(wrapper.balanceOf(FED), 25e18, "remaining shares");
        assertEq(wrapper.totalAssets(), 25e18, "assets after withdraw");
        assertEq(market.balanceOf(FED), INITIAL_ASSETS - 25e18, "fed normalized balance");
    }

    function test_mintConsumesExpectedAssets() external {
        vm.prank(FED);
        uint256 assetsSpent = wrapper.mint(20e18, FED);

        assertEq(assetsSpent, 20e18, "assets spent");
        assertEq(wrapper.balanceOf(FED), 20e18, "share balance");
        assertEq(market.balanceOf(FED), INITIAL_ASSETS - 20e18, "fed outstanding assets");
    }

    function test_redeemAfterScaleFactorChange() external {
        vm.prank(FED);
        wrapper.deposit(10e18, FED);

        market.setScaleFactor(RAY * 2);

        uint256 expectedAssets = MathUtils.rayMul(10e18, RAY * 2);
        vm.prank(FED);
        uint256 assetsReturned = wrapper.redeem(10e18, FED, FED);

        assertEq(assetsReturned, expectedAssets, "redeemed assets");
        assertEq(wrapper.totalSupply(), 0, "zero supply");
        assertEq(market.scaledBalanceOf(address(wrapper)), 0, "wrapper scaled balance");
    }

    function test_withdrawBySpenderUsesAllowance() external {
        vm.startPrank(FED);
        wrapper.deposit(30e18, FED);
        wrapper.approve(BOB, 10e18);
        vm.stopPrank();

        vm.prank(BOB);
        uint256 sharesBurned = wrapper.withdraw(10e18, BOB, FED);

        assertEq(sharesBurned, 10e18, "burned by spender");
        assertEq(wrapper.balanceOf(FED), 20e18, "fed residual shares");
    }

    function test_multipleDepositorsAccrual() external {
        vm.prank(FED);
        uint256 fedShares = wrapper.deposit(20e18, FED);
        assertEq(fedShares, 20e18, "fed shares");

        uint256 newScale = RAY + (RAY / 2);
        market.setScaleFactor(newScale);

        vm.prank(BOB);
        uint256 bobShares = wrapper.deposit(30e18, BOB);

        assertEq(bobShares, 20e18, "bob shares");
        assertEq(wrapper.balanceOf(FED), 20e18, "fed share balance");
        assertEq(wrapper.balanceOf(BOB), 20e18, "bob share balance");
        assertEq(wrapper.totalSupply(), 40e18, "total share supply");
        assertEq(wrapper.totalAssets(), 60e18, "vault assets after deposits");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(FED)), 30e18, "fed assets");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(BOB)), 30e18, "bob assets");
        assertEq(market.scaledBalanceOf(address(wrapper)), 40e18, "scaled balance");
    }

    function test_multipleDepositorsWithdrawals() external {
        vm.prank(FED);
        wrapper.deposit(30e18, FED);

        vm.prank(BOB);
        wrapper.deposit(30e18, BOB);

        uint256 doubledScale = RAY * 2;
        market.setScaleFactor(doubledScale);

        vm.prank(FED);
        uint256 sharesBurned = wrapper.withdraw(30e18, FED, FED);

        assertEq(sharesBurned, 15e18, "fed burned shares");
        assertEq(wrapper.balanceOf(FED), 15e18, "fed remaining shares");
        assertEq(wrapper.balanceOf(BOB), 30e18, "bob shares");
        assertEq(wrapper.totalAssets(), 90e18, "vault assets after withdraw");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(BOB)), 60e18, "bob assets after interest");
        assertEq(market.scaledBalanceOf(address(wrapper)), 45e18, "scaled balance after withdraw");
    }

    function test_totalAssetsTracksDirectTransfers() external {
        uint256 strayAssets = 5e18;

        vm.prank(FED);
        market.transfer(address(wrapper), strayAssets);

        assertEq(wrapper.totalAssets(), strayAssets, "stray assets counted");

        vm.prank(FED);
        uint256 sharesMinted = wrapper.deposit(10e18, FED);
        assertEq(sharesMinted, 10e18, "deposit shares unaffected by stray");

        assertEq(wrapper.totalAssets(), strayAssets + 10e18, "total assets include stray and deposit");

        vm.prank(FED);
        uint256 sharesBurned = wrapper.withdraw(10e18, FED, FED);

        assertEq(sharesBurned, 10e18, "withdraw burns expected shares");
        assertEq(wrapper.totalAssets(), strayAssets, "stray assets remain after withdrawal");
    }

    function test_sweepRevertsForNonMarketOwner() external {
        MockErc20 stray = new MockErc20();
        uint256 strayAmount = 25e18;
        stray.mint(address(wrapper), strayAmount);

        vm.expectRevert(Wildcat4626Wrapper.NotMarketOwner.selector);
        vm.prank(FED);
        wrapper.sweep(address(stray), FED);
    }

    function test_sweepRevertsForMarketAsset() external {
        vm.expectRevert(Wildcat4626Wrapper.CannotSweepMarketAsset.selector);
        vm.prank(BORROWER);
        wrapper.sweep(address(market), BORROWER);
    }

    function test_sweepSendsBalanceToBorrower() external {
        MockErc20 stray = new MockErc20();
        uint256 strayAmount = 42e18;
        stray.mint(address(wrapper), strayAmount);

        vm.prank(BORROWER);
        uint256 swept = wrapper.sweep(address(stray), BORROWER);

        assertEq(swept, strayAmount, "swept amount");
        assertEq(stray.balanceOf(BORROWER), strayAmount, "borrower received stray tokens");
    }

    function test_inflationAttackDoesNotWork() external {
        address attacker = address(0xa77ac8e5);
        address victim = address(0xbad);

        market.mint(attacker, 10e18);
        market.mint(victim, 10e18);

        vm.prank(attacker);
        market.approve(address(wrapper), type(uint256).max);
        vm.prank(victim);
        market.approve(address(wrapper), type(uint256).max);

        uint256 attackerDeposit = 1e9;
        vm.prank(attacker);
        uint256 attackerShares = wrapper.deposit(attackerDeposit, attacker);
        
        assertEq(attackerShares, attackerDeposit, "attacker shares = scaled deposit");

        uint256 donation = 1e18;
        vm.prank(attacker);
        market.transfer(address(wrapper), donation);

        assertEq(wrapper.totalAssets(), attackerDeposit + donation, "totalAssets includes donation");

        uint256 victimDeposit = 2e18;
        vm.prank(victim);
        uint256 victimShares = wrapper.deposit(victimDeposit, victim);

        assertEq(victimShares, victimDeposit, "victim shares = their full scaled deposit");

        uint256 attackerRedeemValue = wrapper.convertToAssets(attackerShares);
        uint256 victimRedeemValue = wrapper.convertToAssets(victimShares);

        assertEq(attackerRedeemValue, attackerDeposit, "attacker can only redeem their deposit");
        
        assertEq(victimRedeemValue, victimDeposit, "victim can redeem their full deposit");

        uint256 strandedAssets = wrapper.totalAssets() - attackerRedeemValue - victimRedeemValue;
        assertEq(strandedAssets, donation, "donation is stranded, attack failed");

        vm.prank(attacker);
        uint256 attackerReceived = wrapper.redeem(attackerShares, attacker, attacker);

        assertEq(attackerReceived, attackerDeposit, "attacker receives only their original deposit");
        
        uint256 attackerTotalSpent = attackerDeposit + donation;
        uint256 attackerLoss = attackerTotalSpent - attackerReceived;
        assertEq(attackerLoss, donation, "attacker loses fullstack");
    }


    function test_inflationWithScaleSchange() external {
        address attacker = address(0xa77ac8e5);
        address victim = address(0xbad);

        market.mint(attacker, 100e18);
        market.mint(victim, 100e18);

        vm.prank(attacker);
        market.approve(address(wrapper), type(uint256).max);
        vm.prank(victim);
        market.approve(address(wrapper), type(uint256).max);

        vm.prank(attacker);
        uint256 attackerShares = wrapper.deposit(10e18, attacker);

        vm.prank(attacker);
        market.transfer(address(wrapper), 50e18);

        uint256 newScale = RAY + (RAY / 2); // 1.5x
        market.setScaleFactor(newScale);

        vm.prank(victim);
        uint256 victimShares = wrapper.deposit(15e18, victim); // 15e18 / 1.5 = 10e18 scaled

        assertEq(attackerShares, 10e18, "attacker scaled shares");
        assertEq(victimShares, 10e18, "victim scaled shares (15e18 assets at 1.5x scale)");

        uint256 attackerValue = wrapper.convertToAssets(attackerShares);
        uint256 victimValue = wrapper.convertToAssets(victimShares);

        assertEq(attackerValue, 15e18, "attacker value after interest");
        assertEq(victimValue, 15e18, "victim value matches their deposit");
    }

    function test_depositWithNonTrivialScaleFactor() external {
        uint256 scaleFactor = RAY + (RAY / 10); // 1.1e27
        market.setScaleFactor(scaleFactor);

        market.mint(FED, 100e18);
        vm.prank(FED);
        market.approve(address(wrapper), type(uint256).max);

        uint256 assets = 10e18;

        uint256 expectedShares = (assets * RAY + scaleFactor / 2) / scaleFactor;

        vm.prank(FED);
        uint256 shares = wrapper.deposit(assets, FED);

        assertEq(shares, expectedShares, "shares match");
        assertEq(wrapper.balanceOf(FED), expectedShares, "wrapper balance correct");
    }

    function test_withdrawWithNonTrivialScaleFactor() external {
        uint256 setupScale = RAY + (RAY / 2); // 1.5e27
        market.setScaleFactor(setupScale);

        market.mint(FED, 100e18);
        vm.prank(FED);
        market.approve(address(wrapper), type(uint256).max);

        vm.prank(FED);
        wrapper.deposit(30e18, FED); // 30e18 / 1.5 = 20e18 shares
        assertEq(wrapper.balanceOf(FED), 20e18, "fed has shares");

        // change to 1.1x scale factor for withdraw
        uint256 scaleFactor = RAY + (RAY / 10); // 1.1e27
        market.setScaleFactor(scaleFactor);

        uint256 assets = 10e18;
        uint256 expectedSharesBurned = (assets * RAY + scaleFactor / 2) / scaleFactor;
        uint256 fedSharesBefore = wrapper.balanceOf(FED);

        vm.prank(FED);
        uint256 sharesBurned = wrapper.withdraw(assets, FED, FED);

        assertEq(sharesBurned, expectedSharesBurned, "shares burned match market's half-up rounding");
        assertEq(wrapper.balanceOf(FED), fedSharesBefore - expectedSharesBurned, "balance decreased correctly");
    }
}