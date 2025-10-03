// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IVaultV2} from "lib/vault-v2/src/interfaces/IVaultV2.sol";
import {IERC20} from "lib/vault-v2/src/interfaces/IERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IWildcatMarket} from "../../../integrations/morpho/interfaces/IWildcatMarket.sol";
import {WildcatMarketV2Adapter} from "../../../integrations/morpho/WildcatMarketV2Adapter.sol";
import {IWildcatMarketV2Adapter} from "../../../integrations/morpho/interfaces/IWildcatMarketV2Adapter.sol";


contract MockWildcatMarket is IWildcatMarket {
    address public immutable override asset;
    mapping(address => uint256) internal _balances;
    uint32[] internal _unpaid;
    mapping(uint32 => mapping(address => uint256)) internal _owed; // expiry => account => amount
    uint32 public lastExpiry;

    constructor(address _asset) { asset = _asset; }

    function deposit(uint256 amount) external override {
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        _balances[msg.sender] += amount;
    }
    function balanceOf(address account) external view override returns (uint256) { return _balances[account]; }
    function queueWithdrawal(uint256 amount) external override returns (uint32 expiry) {
        if (amount == 0) return 0;
        // Simulate burn to pending
        require(_balances[msg.sender] >= amount, "insufficient");
        _balances[msg.sender] -= amount;
        expiry = uint32(block.timestamp + 1); // expires in the near future
        lastExpiry = expiry;
        _unpaid.push(expiry);
        _owed[expiry][msg.sender] += amount;
        return expiry;
    }
    function executeWithdrawal(address account, uint32 expiry) external override returns (uint256) {
        uint256 amt = _owed[expiry][account];
        if (amt == 0) return 0;
        _owed[expiry][account] = 0;
        IERC20(asset).transfer(account, amt);
        return amt;
    }
    function getUnpaidBatchExpiries() external view override returns (uint32[] memory) { return _unpaid; }
    function getAvailableWithdrawalAmount(address account, uint32 expiry) external view override returns (uint256) { return _owed[expiry][account]; }

    function clearUnpaid() external { delete _unpaid; }
}

contract VaultStub {
    address public immutable asset;
    address public immutable owner;
    mapping(bytes32=>uint256) public allocation;
    constructor(address _asset, address _owner){ asset=_asset; owner=_owner; }
}

contract WildcatMarketV2AdapterTest is Test {
    MockERC20 internal asset;
    address internal vault; // stubbed addy
    MockWildcatMarket internal market;
    WildcatMarketV2Adapter internal adapter;
    address internal vaultOwner = address(0xBEEF);

    function setUp() public {
        asset = new MockERC20("Mock", "MOCK", 18);
    market = new MockWildcatMarket(address(asset));

    // Deploy a minimal Vault stub with the same asset and an owner.
    vault = address(new VaultStub(address(asset), vaultOwner));

        vm.startPrank(address(this));
    adapter = new WildcatMarketV2Adapter(vault, address(market));
        vm.stopPrank();

        // fund the caller and approve adapter to pull during allocate via VaultV2.transfer to adapter
        asset.mint(address(adapter), 0); // ensure zero start
    }

    function test_allocate_noop_when_zero_assets() public {
        vm.prank(vault);
        (bytes32[] memory ids, int256 change) = adapter.allocate("", 0, bytes4(0), address(this));
        assertEq(ids.length, 1);
        assertEq(change, int256(0));
    }

    function test_skim_flow() public {
        
        vm.prank(vaultOwner);
        adapter.setSkimRecipient(address(0xCAFE));

       
        MockERC20 reward = new MockERC20("randomtoken", "RND", 18);
        reward.mint(address(adapter), 123e6);

        vm.prank(address(0xCAFE));
        adapter.skim(address(reward));
        assertEq(reward.balanceOf(address(0xCAFE)), 123e6);
    }

    function test_skim_rejects_market_address() public {
        vm.prank(vaultOwner);
        adapter.setSkimRecipient(address(this));
        vm.expectRevert(IWildcatMarketV2Adapter.CannotSkimWildcatMarketTokens.selector);
        adapter.skim(address(market));
    }

    function test_deallocate_reverts_without_liquidity() public {
        vm.expectRevert(IWildcatMarketV2Adapter.InsufficientImmediateLiquidity.selector);
        vm.prank(vault);
        adapter.deallocate("", 1, bytes4(0), address(this));
    }

    function test_allocate_deposits_and_reports_change() public {
        // mint assets to adapter so it can deposit into market during allocate
        asset.mint(address(adapter), 1_000e18);
        vm.prank(vault);
        (bytes32[] memory ids, int256 change) = adapter.allocate("", 1_000e18, bytes4(0), address(this));
        assertEq(ids.length, 1);
        assertEq(change, int256(1_000e18));
        assertEq(market.balanceOf(address(adapter)), 1_000e18);
    }

    function test_prepare_realize_then_deallocate() public {
        // start with market balance on adapter
        asset.mint(address(adapter), 1_000e18);
        vm.prank(vault);
        adapter.allocate("", 1_000e18, bytes4(0), address(this));
        assertEq(market.balanceOf(address(adapter)), 1_000e18);

        // queue a withdrawal for 600
        vm.prank(vaultOwner);
        adapter.queueAdapterWithdrawal(600e18);
        uint32 queuedExpiry = market.lastExpiry();
        assertTrue(queuedExpiry != 0);
        assertEq(adapter.pendingWithdrawals(queuedExpiry), 600e18);
        assertEq(adapter.totalPendingWithdrawals(), 600e18);

        // advance beyond expiry so withdrawals are claimable
        vm.warp(uint256(queuedExpiry) + 2);

        assertEq(asset.balanceOf(address(adapter)), 0);

        market.clearUnpaid();

        assertEq(adapter.getAvailableLiquidity(), 600e18);

        adapter.realizeClaimable(4);
        assertEq(asset.balanceOf(address(adapter)), 600e18);
        assertEq(adapter.totalPendingWithdrawals(), 0);
        assertEq(adapter.getAvailableLiquidity(), 600e18);

        // deallocate 600 should succeed 
        vm.prank(vault);
    (bytes32[] memory ids, int256 change) = adapter.deallocate("", 600e18, bytes4(0), address(this));
        assertEq(ids.length, 1);

    assertEq(change, int256(400e18));
    }

    function test_multiple_queue_updates_tracking() public {
        asset.mint(address(adapter), 1_000e18);
        vm.prank(vault);
        adapter.allocate("", 1_000e18, bytes4(0), address(this));

        vm.prank(vaultOwner);
        adapter.queueAdapterWithdrawal(250e18);
        uint32 expiry = market.lastExpiry();
        assertTrue(expiry != 0);
        assertEq(adapter.pendingWithdrawals(expiry), 250e18);
        assertEq(adapter.totalPendingWithdrawals(), 250e18);

        vm.prank(vaultOwner);
        adapter.queueAdapterWithdrawal(350e18);
        assertEq(market.lastExpiry(), expiry);
        assertEq(adapter.pendingWithdrawals(expiry), 600e18);
        assertEq(adapter.totalPendingWithdrawals(), 600e18);

        market.clearUnpaid();
        vm.warp(uint256(expiry) + 2);

        adapter.realizeClaimable(5);
        assertEq(adapter.totalPendingWithdrawals(), 0);
        assertEq(adapter.pendingWithdrawals(expiry), 0);
    }
}
