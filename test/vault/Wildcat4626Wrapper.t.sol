// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {MathUtils, RAY} from "src/libraries/MathUtils.sol";
import {Wildcat4626Wrapper} from "src/vault/Wildcat4626Wrapper.sol";
import {IWildcatMarketToken} from "src/vault/Wildcat4626Wrapper.sol";

contract MockMarketToken is IWildcatMarketToken {
    using MathUtils for uint256;

    string public constant name = "Mock Wildcat Market Token";
    string public constant symbol = "mwcUSDC";
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

    uint256 internal constant INITIAL_ASSETS = 1000e6;

    function setUp() external {
        market = new MockMarketToken(6);
        wrapper = new Wildcat4626Wrapper(address(market), "wcUSDC Vault Share", "wcUSDC-v", address(this));

    market.mint(ALICE, INITIAL_ASSETS);
    market.mint(BOB, INITIAL_ASSETS);

    vm.prank(ALICE);
    market.approve(address(wrapper), type(uint256).max);

    vm.prank(BOB);
    market.approve(address(wrapper), type(uint256).max);
    }

    function test_depositMintsScaledShares() external {
        vm.prank(ALICE);
        uint256 shares = wrapper.deposit(500e6, ALICE);

        assertEq(shares, 500e6, "scaled mismatch");
        assertEq(wrapper.balanceOf(ALICE), shares, "share balance");
        assertEq(wrapper.totalSupply(), shares, "total supply");
        assertEq(wrapper.totalAssets(), 500e6, "total assets");
        assertEq(market.scaledBalanceOf(address(wrapper)), shares, "market scaled balance");
    }

    function test_withdrawBurnsScaledShares() external {
        vm.prank(ALICE);
        wrapper.deposit(400e6, ALICE);

        vm.prank(ALICE);
        uint256 sharesBurned = wrapper.withdraw(150e6, ALICE, ALICE);

        assertEq(sharesBurned, 150e6, "shares burned");
        assertEq(wrapper.balanceOf(ALICE), 250e6, "remaining shares");
        assertEq(wrapper.totalAssets(), 250e6, "assets after withdraw");
        assertEq(market.balanceOf(ALICE), INITIAL_ASSETS - 250e6, "alice normalized balance");
    }

    function test_mintConsumesExpectedAssets() external {
        vm.prank(ALICE);
        uint256 assetsSpent = wrapper.mint(200e6, ALICE);

        assertEq(assetsSpent, 200e6, "assets spent");
        assertEq(wrapper.balanceOf(ALICE), 200e6, "share balance");
        assertEq(market.balanceOf(ALICE), INITIAL_ASSETS - 200e6, "alice outstanding assets");
    }

    function test_redeemAfterScaleFactorChange() external {
        vm.prank(ALICE);
        wrapper.deposit(100e6, ALICE);

        market.setScaleFactor(RAY * 2);

        uint256 expectedAssets = MathUtils.rayMul(100e6, RAY * 2);
        vm.prank(ALICE);
        uint256 assetsReturned = wrapper.redeem(100e6, ALICE, ALICE);

        assertEq(assetsReturned, expectedAssets, "redeemed assets");
        assertEq(wrapper.totalSupply(), 0, "zero supply");
        assertEq(market.scaledBalanceOf(address(wrapper)), 0, "wrapper scaled balance");
    }

    function test_withdrawBySpenderUsesAllowance() external {
        vm.startPrank(ALICE);
        wrapper.deposit(300e6, ALICE);
        wrapper.approve(BOB, 100e6);
        vm.stopPrank();

        vm.prank(BOB);
        uint256 sharesBurned = wrapper.withdraw(100e6, BOB, ALICE);

        assertEq(sharesBurned, 100e6, "burned by spender");
        assertEq(wrapper.balanceOf(ALICE), 200e6, "alice residual shares");
    }

    function test_multipleDepositorsAccrual() external {
        vm.prank(ALICE);
        uint256 aliceShares = wrapper.deposit(200e6, ALICE);
        assertEq(aliceShares, 200e6, "alice shares");

        uint256 newScale = RAY + (RAY / 2);
        market.setScaleFactor(newScale);

        vm.prank(BOB);
        uint256 bobShares = wrapper.deposit(300e6, BOB);

        assertEq(bobShares, 200e6, "bob shares");
        assertEq(wrapper.balanceOf(ALICE), 200e6, "alice share balance");
        assertEq(wrapper.balanceOf(BOB), 200e6, "bob share balance");
        assertEq(wrapper.totalSupply(), 400e6, "total share supply");
        assertEq(wrapper.totalAssets(), 600e6, "vault assets after deposits");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(ALICE)), 300e6, "alice assets");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(BOB)), 300e6, "bob assets");
        assertEq(market.scaledBalanceOf(address(wrapper)), 400e6, "scaled balance");
    }

    function test_multipleDepositorsWithdrawals() external {
        vm.prank(ALICE);
        wrapper.deposit(300e6, ALICE);

        vm.prank(BOB);
        wrapper.deposit(300e6, BOB);

        uint256 doubledScale = RAY * 2;
        market.setScaleFactor(doubledScale);

        vm.prank(ALICE);
        uint256 sharesBurned = wrapper.withdraw(300e6, ALICE, ALICE);

        assertEq(sharesBurned, 150e6, "alice burned shares");
        assertEq(wrapper.balanceOf(ALICE), 150e6, "alice remaining shares");
        assertEq(wrapper.balanceOf(BOB), 300e6, "bob shares");
        assertEq(wrapper.totalAssets(), 900e6, "vault assets after withdraw");
        assertEq(wrapper.convertToAssets(wrapper.balanceOf(BOB)), 600e6, "bob assets after interest");
        assertEq(market.scaledBalanceOf(address(wrapper)), 450e6, "scaled balance after withdraw");
    }

    function test_capEnforced() external {
        wrapper.setWrapperCap(200e6);

        vm.prank(ALICE);
        wrapper.deposit(150e6, ALICE);

        vm.prank(ALICE);
        vm.expectRevert(Wildcat4626Wrapper.CapExceeded.selector);
        wrapper.deposit(100e6, ALICE);
    }

    function test_ownerControls() external {
        wrapper.setWrapperCap(123);
        assertEq(wrapper.wrapperCap(), 123, "cap updated");

        wrapper.setOwner(BOB);
        assertEq(wrapper.owner(), BOB, "owner updated");

        vm.prank(BOB);
        wrapper.setWrapperCap(456);
        assertEq(wrapper.wrapperCap(), 456, "cap by new owner");
    }

    function test_nonOwnerCannotUpdate() external {
        vm.prank(ALICE);
        vm.expectRevert(Wildcat4626Wrapper.NotOwner.selector);
        wrapper.setWrapperCap(10);

        vm.prank(ALICE);
        vm.expectRevert(Wildcat4626Wrapper.NotOwner.selector);
        wrapper.setOwner(ALICE);
    }
}
