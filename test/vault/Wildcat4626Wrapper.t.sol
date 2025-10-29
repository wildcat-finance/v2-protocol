// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {MathUtils, RAY} from "src/libraries/MathUtils.sol";
import {Wildcat4626Wrapper} from "src/vault/Wildcat4626Wrapper.sol";
import {IWildcatMarketToken} from "src/vault/Wildcat4626Wrapper.sol";

contract MockMarketToken is IWildcatMarketToken {
    using MathUtils for uint256;

    string public constant name = "Mock fries USDC";
    string public constant symbol = "friesUSDC";
    uint8 public immutable override decimals;

    uint256 public override scaleFactor;

    mapping(address => uint256) internal _scaledBalances;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 internal _scaledTotalSupply;

    constructor(uint8 tokenDecimals) {
        decimals = tokenDecimals;
        scaleFactor = RAY;
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

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    uint256 internal constant INITIAL_ASSETS = 100e18;

    function setUp() external {
        market = new MockMarketToken(18);
        wrapper = new Wildcat4626Wrapper(address(market));

    market.mint(ALICE, INITIAL_ASSETS);
    market.mint(BOB, INITIAL_ASSETS);

    vm.prank(ALICE);
    market.approve(address(wrapper), type(uint256).max);

    vm.prank(BOB);
    market.approve(address(wrapper), type(uint256).max);
    }

    function test_metadataDerivedFromMarketSymbol() external {
    assertEq(wrapper.name(), "friesUSDCX [4626 Vault Shares]");
    assertEq(wrapper.symbol(), "v-friesUSDC");
    }

    function test_depositMintsScaledShares() external {
        vm.prank(ALICE);
        uint256 shares = wrapper.deposit(50e18, ALICE);

        assertEq(shares, 50e18, "scaled mismatch");
        assertEq(wrapper.balanceOf(ALICE), shares, "share balance");
        assertEq(wrapper.totalSupply(), shares, "total supply");
        assertEq(wrapper.totalAssets(), 50e18, "total assets");
        assertEq(market.scaledBalanceOf(address(wrapper)), shares, "market scaled balance");
    }

    function test_withdrawBurnsScaledShares() external {
        vm.prank(ALICE);
        wrapper.deposit(40e18, ALICE);

        vm.prank(ALICE);
        uint256 sharesBurned = wrapper.withdraw(15e18, ALICE, ALICE);

        assertEq(sharesBurned, 15e18, "shares burned");
        assertEq(wrapper.balanceOf(ALICE), 25e18, "remaining shares");
        assertEq(wrapper.totalAssets(), 25e18, "assets after withdraw");
        assertEq(market.balanceOf(ALICE), INITIAL_ASSETS - 25e18, "alice normalized balance");
    }

    function test_mintConsumesExpectedAssets() external {
        vm.prank(ALICE);
        uint256 assetsSpent = wrapper.mint(20e18, ALICE);

        assertEq(assetsSpent, 20e18, "assets spent");
        assertEq(wrapper.balanceOf(ALICE), 20e18, "share balance");
        assertEq(market.balanceOf(ALICE), INITIAL_ASSETS - 20e18, "alice outstanding assets");
    }

    function test_redeemAfterScaleFactorChange() external {
        vm.prank(ALICE);
        wrapper.deposit(10e18, ALICE);

        market.setScaleFactor(RAY * 2);

        uint256 expectedAssets = MathUtils.rayMul(10e18, RAY * 2);
        vm.prank(ALICE);
        uint256 assetsReturned = wrapper.redeem(10e18, ALICE, ALICE);

        assertEq(assetsReturned, expectedAssets, "redeemed assets");
        assertEq(wrapper.totalSupply(), 0, "zero supply");
        assertEq(market.scaledBalanceOf(address(wrapper)), 0, "wrapper scaled balance");
    }

    function test_withdrawBySpenderUsesAllowance() external {
        vm.startPrank(ALICE);
        wrapper.deposit(30e18, ALICE);
        wrapper.approve(BOB, 10e18);
        vm.stopPrank();

        vm.prank(BOB);
        uint256 sharesBurned = wrapper.withdraw(10e18, BOB, ALICE);

        assertEq(sharesBurned, 10e18, "burned by spender");
        assertEq(wrapper.balanceOf(ALICE), 20e18, "alice residual shares");
    }

    function test_multipleDepositorsAccrual() external {
        vm.prank(ALICE);
        uint256 aliceShares = wrapper.deposit(20e18, ALICE);
        assertEq(aliceShares, 20e18, "alice shares");

        uint256 newScale = RAY + (RAY / 2);
        market.setScaleFactor(newScale);

        vm.prank(BOB);
        uint256 bobShares = wrapper.deposit(30e18, BOB);

        assertEq(bobShares, 20e18, "bob shares");
        assertEq(wrapper.balanceOf(ALICE), 20e18, "alice share balance");
        assertEq(wrapper.balanceOf(BOB), 20e18, "bob share balance");
        assertEq(wrapper.totalSupply(), 40e18, "total share supply");
        assertEq(wrapper.totalAssets(), 60e18, "vault assets after deposits");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(ALICE)), 30e18, "alice assets");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(BOB)), 30e18, "bob assets");
        assertEq(market.scaledBalanceOf(address(wrapper)), 40e18, "scaled balance");
    }

    function test_multipleDepositorsWithdrawals() external {
        vm.prank(ALICE);
        wrapper.deposit(30e18, ALICE);

        vm.prank(BOB);
        wrapper.deposit(30e18, BOB);

        uint256 doubledScale = RAY * 2;
        market.setScaleFactor(doubledScale);

        vm.prank(ALICE);
        uint256 sharesBurned = wrapper.withdraw(30e18, ALICE, ALICE);

        assertEq(sharesBurned, 15e18, "alice burned shares");
        assertEq(wrapper.balanceOf(ALICE), 15e18, "alice remaining shares");
        assertEq(wrapper.balanceOf(BOB), 30e18, "bob shares");
        assertEq(wrapper.totalAssets(), 90e18, "vault assets after withdraw");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(BOB)), 60e18, "bob assets after interest");
        assertEq(market.scaledBalanceOf(address(wrapper)), 45e18, "scaled balance after withdraw");
    }

    function test_totalAssetsTracksDirectTransfers() external {
        uint256 strayAssets = 5e18;

        vm.prank(ALICE);
        market.transfer(address(wrapper), strayAssets);

        assertEq(wrapper.totalAssets(), strayAssets, "stray assets counted");

        vm.prank(ALICE);
        uint256 sharesMinted = wrapper.deposit(10e18, ALICE);
        assertEq(sharesMinted, 10e18, "deposit shares unaffected by stray");

        assertEq(wrapper.totalAssets(), strayAssets + 10e18, "total assets include stray and deposit");

        vm.prank(ALICE);
        uint256 sharesBurned = wrapper.withdraw(10e18, ALICE, ALICE);

        assertEq(sharesBurned, 10e18, "withdraw burns expected shares");
        assertEq(wrapper.totalAssets(), strayAssets, "stray assets remain after withdrawal");
    }
}