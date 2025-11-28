// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MathUtils, RAY} from "src/libraries/MathUtils.sol";
import {Wildcat4626Wrapper} from "src/vault/Wildcat4626Wrapper.sol";
import {IWildcatMarketToken} from "src/vault/Wildcat4626Wrapper.sol";

contract MockMarketToken is IWildcatMarketToken {
    using MathUtils for uint256;

    string public constant name = "HEX Token";
    string public constant symbol = "HEX";
    uint8 public constant override decimals = 18;

    uint256 public override scaleFactor = RAY;
    address public immutable override borrower;

    mapping(address => uint256) internal _scaledBalances;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(address borrower_) {
        borrower = borrower_;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _scaledBalances[account].rayMul(scaleFactor);
    }

    function totalSupply() external view returns (uint256) {
        return 0;
    }

    function scaledBalanceOf(address account) external view override returns (uint256) {
        return _scaledBalances[account];
    }

    function maxTotalSupply() external pure override returns (uint256) {
        return type(uint128).max;
    }

    function setScaleFactor(uint256 newScaleFactor) external {
        scaleFactor = newScaleFactor;
    }

    function mint(address to, uint256 assets) external {
        uint256 scaled = assets.rayDiv(scaleFactor);
        _scaledBalances[to] += scaled;
    }

    function approve(address, uint256) external pure returns (bool) { return true; }
    function transfer(address, uint256) external pure returns (bool) { return true; }
    function transferFrom(address, address, uint256) external pure returns (bool) { return true; }
}

contract Wildcat4626WrapperRoundingTest is Test {
    MockMarketToken internal market;
    Wildcat4626Wrapper internal wrapper;
    address internal constant ALICE = address(0xA11CE);

    function setUp() external {
        market = new MockMarketToken(address(this));
        wrapper = new Wildcat4626Wrapper(address(market));
    }

    // mostly utils for making sure that the conversions match eip-4626 rounding rules

    function test_previewRedeem_RoundsDown() external {
        market.setScaleFactor(RAY + 1e7);
        uint256 shares = 50e18;
        uint256 expectedAssets = 50e18;
        uint256 assets = wrapper.previewRedeem(shares);
        assertEq(assets, expectedAssets, "previewRedeem should round down (floor)");
    }

    function test_previewDeposit_RoundsDown() external {
        market.setScaleFactor(RAY - 1e7);
        uint256 assets = 50e18;
        uint256 expectedShares = 50e18;
        uint256 shares = wrapper.previewDeposit(assets);
        assertEq(shares, expectedShares, "previewDeposit should round down (floor)");
    }

    function test_previewMint_RoundsUp() external {
        market.setScaleFactor(RAY - 1e7);
        uint256 shares = 50e18;
        
        // We need assets A such that A.rayDiv(scale) >= shares
        // mulDiv(shares, scale, RAY) gives 50e18 - 1 (Floor of 50e18 - 0.5)
        // (50e18 - 1).rayDiv(scale) rounds to 50e18 - 1 (insufficient)
        // So it increments to 50e18
        uint256 expectedAssets = 50e18;
        uint256 assets = wrapper.previewMint(shares);
        assertEq(assets, expectedAssets, "previewMint should round up to ensure sufficient assets");
        uint256 resultingShares = MathUtils.rayDiv(assets, market.scaleFactor());
        assertGe(resultingShares, shares, "returned assets must yield at least requested shares");
    }

    function test_previewWithdraw_RoundsUp() external {
        market.setScaleFactor(RAY + 1e7);
        uint256 assets = 50e18;
        uint256 expectedShares = 50e18;
        uint256 shares = wrapper.previewWithdraw(assets);
        assertEq(shares, expectedShares, "previewWithdraw should round up (ceiling)");
    }


    /// @notice convertToShares MUST round DOWN per EIP-4626
    function test_EIP4626_convertToShares_roundsDown() external {
        market.setScaleFactor(RAY + 1e7);
        
        uint256 assets = 50e18;
        uint256 actualShares = wrapper.convertToShares(assets);
        uint256 floorShares = MathUtils.mulDiv(assets, RAY, market.scaleFactor());
        
        assertEq(actualShares, floorShares, "convertToShares must equal floor");
    }

    /// @notice convertToAssets MUST round DOWN per EIP-4626
    function test_EIP4626_convertToAssets_roundsDown() external {
        market.setScaleFactor(RAY + 1e7);
        
        uint256 shares = 50e18;
        uint256 actualAssets = wrapper.convertToAssets(shares);
        uint256 floorAssets = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);
        
        assertEq(actualAssets, floorAssets, "convertToAssets must equal floor");
    }

    /// @notice previewDeposit MUST round DOWN (user gets ≤ previewed shares)
    function test_EIP4626_previewDeposit_roundsDown() external {
        market.setScaleFactor(RAY + 1e7);
        
        uint256 assets = 50e18;
        uint256 previewShares = wrapper.previewDeposit(assets);
        uint256 floorShares = MathUtils.mulDiv(assets, RAY, market.scaleFactor());
        
        assertEq(previewShares, floorShares, "previewDeposit must equal floor");
    }

    /// @notice previewMint MUST round UP (user pays ≥ previewed assets)
    function test_EIP4626_previewMint_roundsUp() external {
        market.setScaleFactor(RAY + 1e7);
        
        uint256 shares = 50e18;
        uint256 previewAssets = wrapper.previewMint(shares);
        uint256 ceilingAssets = MathUtils.mulDivUp(shares, market.scaleFactor(), RAY);
        
        assertEq(previewAssets, ceilingAssets, "previewMint must equal ceiling");
    }

    /// @notice previewWithdraw MUST round UP (user burns ≥ previewed shares)
    function test_EIP4626_previewWithdraw_roundsUp() external {
        market.setScaleFactor(RAY + 4e8);
        
        uint256 assets = 100e18;
        uint256 previewShares = wrapper.previewWithdraw(assets);
        uint256 ceilingShares = MathUtils.mulDivUp(assets, RAY, market.scaleFactor());
        
        assertEq(previewShares, ceilingShares, "previewWithdraw must equal ceiling");
    }

    /// @notice previewRedeem MUST round DOWN (user receives ≤ previewed assets)
    function test_EIP4626_previewRedeem_roundsDown() external {
        market.setScaleFactor(RAY + 1e7);
        
        uint256 shares = 50e18;
        uint256 previewAssets = wrapper.previewRedeem(shares);
        uint256 floorAssets = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);
        
        assertEq(previewAssets, floorAssets, "previewRedeem must equal floor");
    }

    // fuzzzzzes (not perfect)

    /// @notice Fuzz: convertToShares always equals floor
    function testFuzz_EIP4626_convertToShares_equalsFloor(uint256 assets, uint256 scaleOffset) external {
        assets = bound(assets, 1, 1e30);
        scaleOffset = bound(scaleOffset, 1, RAY / 2);
        market.setScaleFactor(RAY + scaleOffset);
        
        uint256 actual = wrapper.convertToShares(assets);
        uint256 floor = MathUtils.mulDiv(assets, RAY, market.scaleFactor());
        
        assertEq(actual, floor, "convertToShares must equal floor");
    }

    /// @notice Fuzz: convertToAssets always equals floor
    function testFuzz_EIP4626_convertToAssets_equalsFloor(uint256 shares, uint256 scaleOffset) external {
        shares = bound(shares, 1, 1e30);
        scaleOffset = bound(scaleOffset, 1, RAY / 2);
        market.setScaleFactor(RAY + scaleOffset);
        
        uint256 actual = wrapper.convertToAssets(shares);
        uint256 floor = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);
        
        assertEq(actual, floor, "convertToAssets must equal floor");
    }

    /// @notice Fuzz: previewMint always equals ceiling
    function testFuzz_EIP4626_previewMint_equalsCeiling(uint256 shares, uint256 scaleOffset) external {
        shares = bound(shares, 1, 1e30);
        scaleOffset = bound(scaleOffset, 1, RAY / 2);
        market.setScaleFactor(RAY + scaleOffset);
        
        uint256 actual = wrapper.previewMint(shares);
        uint256 ceiling = MathUtils.mulDivUp(shares, market.scaleFactor(), RAY);
        
        assertEq(actual, ceiling, "previewMint must equal ceiling");
    }

    /// @notice Fuzz: previewWithdraw always equals ceiling
    function testFuzz_EIP4626_previewWithdraw_equalsCeiling(uint256 assets, uint256 scaleOffset) external {
        assets = bound(assets, 1, 1e30);
        scaleOffset = bound(scaleOffset, 1, RAY / 2);
        market.setScaleFactor(RAY + scaleOffset);
        
        uint256 actual = wrapper.previewWithdraw(assets);
        uint256 ceiling = MathUtils.mulDivUp(assets, RAY, market.scaleFactor());
        
        assertEq(actual, ceiling, "previewWithdraw must equal ceiling");
    }

    /// @notice Fuzz: previewRedeem always equals floor
    function testFuzz_EIP4626_previewRedeem_equalsFloor(uint256 shares, uint256 scaleOffset) external {
        shares = bound(shares, 1, 1e30);
        scaleOffset = bound(scaleOffset, 1, RAY / 2);
        market.setScaleFactor(RAY + scaleOffset);
        
        uint256 actual = wrapper.previewRedeem(shares);
        uint256 floor = MathUtils.mulDiv(shares, market.scaleFactor(), RAY);
        
        assertEq(actual, floor, "previewRedeem must equal floor");
    }
}
