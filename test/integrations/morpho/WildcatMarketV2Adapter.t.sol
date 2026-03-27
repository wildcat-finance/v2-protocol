// SPDX-License-Identifier: TODO
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'lib/vault-v2/src/interfaces/IVaultV2.sol';
import 'lib/vault-v2/src/interfaces/IERC20.sol';
import 'solmate/test/utils/mocks/MockERC20.sol';

import '../../../integrations/morpho/interfaces/IWildcatMarket.sol';
import '../../../integrations/morpho/interfaces/IWildcatMarketV2Adapter.sol';
import '../../../integrations/morpho/WildcatMarketV2Adapter.sol';

contract MockWildcatMarket is IWildcatMarket {
  address public immutable override asset;
  mapping(address => uint256) internal balances;
  uint32[] internal unpaid;
  mapping(uint32 => mapping(address => uint256)) internal owed;
  uint32 public lastExpiry;

  constructor(address asset_) {
    asset = asset_;
  }

  function deposit(uint256 amount) external override {
    IERC20(asset).transferFrom(msg.sender, address(this), amount);
    balances[msg.sender] += amount;
  }

  function balanceOf(address account) external view override returns (uint256) {
    return balances[account];
  }

  function queueWithdrawal(uint256 amount) external override returns (uint32 expiry) {
    if (amount == 0) return 0;
    require(balances[msg.sender] >= amount, 'INSUFFICIENT_BALANCE');
    balances[msg.sender] -= amount;
    expiry = uint32(block.timestamp + 1);
    lastExpiry = expiry;
    unpaid.push(expiry);
    owed[expiry][msg.sender] += amount;
    return expiry;
  }

  function executeWithdrawal(address account, uint32 expiry) external override returns (uint256) {
    uint256 amount = owed[expiry][account];
    if (amount == 0) return 0;
    owed[expiry][account] = 0;
    IERC20(asset).transfer(account, amount);
    return amount;
  }

  function getUnpaidBatchExpiries() external view override returns (uint32[] memory) {
    return unpaid;
  }

  function getAvailableWithdrawalAmount(address account, uint32 expiry)
    external
    view
    override
    returns (uint256)
  {
    return owed[expiry][account];
  }

  function increaseOwed(uint32 expiry, address account, uint256 amount) external {
    owed[expiry][account] += amount;
  }
}

contract MockVaultV2 {
  address public immutable owner;
  address public immutable asset;
  mapping(address => bool) public allocators;
  mapping(bytes32 => uint256) public allocation;

  constructor(address asset_, address owner_) {
    asset = asset_;
    owner = owner_;
  }

  function setAllocator(address account, bool status) external {
    allocators[account] = status;
  }

  function isAllocator(address account) external view returns (bool) {
    return allocators[account];
  }

  function setAllocation(bytes32 id, uint256 amount) external {
    allocation[id] = amount;
  }
}

contract WildcatMarketV2AdapterTest is Test {
  MockERC20 internal asset;
  MockVaultV2 internal vault;
  MockWildcatMarket internal market;
  WildcatMarketV2Adapter internal adapter;

  address internal constant vaultOwner = address(0xBEEF);
  address internal constant allocator = address(0xA110C4);
  address internal constant skimRecipient = address(0xCAFE);
  address internal constant other = address(0xBAD5);

  function setUp() external {
    asset = new MockERC20('Mock Token', 'MOCK', 18);
    vault = new MockVaultV2(address(asset), vaultOwner);
    market = new MockWildcatMarket(address(asset));

    adapter = new WildcatMarketV2Adapter(address(vault), address(market));
  }

  function _allocate(uint256 amount) internal {
    asset.mint(address(adapter), amount);
    vm.prank(address(vault));
    adapter.allocate(new bytes(0), amount, bytes4(0), address(this));
    vm.prank(address(vault));
    vault.setAllocation(adapter.adapterId(), market.balanceOf(address(adapter)));
  }

  function _queue(uint256 amount) internal returns (uint32 expiry) {
    vm.prank(vaultOwner);
    adapter.queueAdapterWithdrawal(amount);
    expiry = market.lastExpiry();
  }

  function _mature(uint32 expiry) internal {
    vm.warp(uint256(expiry) + 2);
  }

  function test_constructor_sets_fields() external {
    assertEq(adapter.factory(), address(this));
    assertEq(adapter.parentVault(), address(vault));
    assertEq(adapter.market(), address(market));
    assertEq(adapter.asset(), address(asset));

    assertEq(asset.allowance(address(adapter), address(vault)), type(uint256).max);
    assertEq(asset.allowance(address(adapter), address(market)), type(uint256).max);
    assertTrue(adapter.adapterId() != bytes32(0));
  }

  function test_constructor_reverts_on_asset_mismatch() external {
    MockVaultV2 mismatchedVault = new MockVaultV2(address(new MockERC20('Other', 'OTH', 18)), vaultOwner);
    vm.expectRevert(IWildcatMarketV2Adapter.AssetMismatch.selector);
    new WildcatMarketV2Adapter(address(mismatchedVault), address(market));
  }

  function test_setSkimRecipient_only_owner() external {
    vm.prank(other);
    vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
    adapter.setSkimRecipient(skimRecipient);

    vm.expectEmit(address(adapter));
    emit IWildcatMarketV2Adapter.SetSkimRecipient(skimRecipient);
    vm.prank(vaultOwner);
    adapter.setSkimRecipient(skimRecipient);
    assertEq(adapter.skimRecipient(), skimRecipient);
  }

  function test_skim_enforces_recipient_and_token() external {
    vm.prank(vaultOwner);
    adapter.setSkimRecipient(skimRecipient);

    vm.prank(other);
    vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
    adapter.skim(address(asset));

    vm.expectRevert(IWildcatMarketV2Adapter.CannotSkimWildcatMarketTokens.selector);
    vm.prank(skimRecipient);
    adapter.skim(address(market));

    MockERC20 reward = new MockERC20('Reward', 'RWD', 18);
    reward.mint(address(adapter), 123e18);

    vm.expectEmit(address(adapter));
    emit IWildcatMarketV2Adapter.Skim(address(reward), 123e18);
    vm.prank(skimRecipient);
    adapter.skim(address(reward));
    assertEq(reward.balanceOf(skimRecipient), 123e18);
  }

  function test_allocate_reverts_on_invalid_data() external {
    vm.prank(address(vault));
    vm.expectRevert(IWildcatMarketV2Adapter.InvalidData.selector);
    adapter.allocate(hex'01', 0, bytes4(0), address(this));
  }

  function test_allocate_requires_parent_vault() external {
    vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
    adapter.allocate(new bytes(0), 0, bytes4(0), address(this));
  }

  function test_allocate_deposits_and_reports_change() external {
    asset.mint(address(adapter), 1_000e18);
    vm.prank(address(vault));
    (bytes32[] memory ids, int256 change) = adapter.allocate(new bytes(0), 1_000e18, bytes4(0), address(this));
    assertEq(ids.length, 1);
    assertEq(ids[0], adapter.adapterId());
    assertEq(change, int256(1_000e18));
    assertEq(market.balanceOf(address(adapter)), 1_000e18);
  }

  function test_deallocate_reverts_on_invalid_data() external {
    vm.prank(address(vault));
    vm.expectRevert(IWildcatMarketV2Adapter.InvalidData.selector);
    adapter.deallocate(hex'01', 0, bytes4(0), address(this));
  }

  function test_deallocate_requires_parent_vault() external {
    vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
    adapter.deallocate(new bytes(0), 0, bytes4(0), address(this));
  }

  function test_deallocate_reverts_on_insufficient_liquidity() external {
    _allocate(500e18);
    vm.prank(address(vault));
    vm.expectRevert(IWildcatMarketV2Adapter.InsufficientImmediateLiquidity.selector);
    adapter.deallocate(new bytes(0), 100e18, bytes4(0), address(this));
  }

  function test_deallocate_realizes_matured_liquidity() external {
    _allocate(1_000e18);
    uint32 expiry = _queue(600e18);
    _mature(expiry);

    vm.prank(address(vault));
    (bytes32[] memory ids, int256 change) = adapter.deallocate(new bytes(0), 400e18, bytes4(0), address(this));
    assertEq(ids.length, 1);
    assertEq(ids[0], adapter.adapterId());
    assertEq(change, -int256(600e18));
    assertEq(adapter.totalPendingWithdrawals(), 0);
    assertEq(asset.balanceOf(address(adapter)), 600e18);
  }

  function test_realAssets_counts_cash_and_balance() external {
    assertEq(adapter.realAssets(), 0);

    _allocate(1_000e18);
    vm.prank(address(vault));
    vault.setAllocation(adapter.adapterId(), 1);
    asset.mint(address(adapter), 50e18);
    assertEq(adapter.realAssets(), 1_050e18);
  }

  function test_realAssets_zero_until_allocation_recorded() external {
    asset.mint(address(adapter), 100e18);
    vm.prank(address(vault));
    adapter.allocate(new bytes(0), 100e18, bytes4(0), address(this));

    assertEq(IWildcatMarket(market).balanceOf(address(adapter)), 100e18);
    assertEq(adapter.realAssets(), 0);

    asset.mint(address(adapter), 20e18);
    assertEq(asset.balanceOf(address(adapter)), 20e18);
    assertEq(adapter.realAssets(), 0);
  }

  function test_realAssets_zero_after_allocation_cleared() external {
    _allocate(250e18);
    assertEq(adapter.realAssets(), 250e18);

    vm.prank(address(vault));
    vault.setAllocation(adapter.adapterId(), 0);
    assertEq(IWildcatMarket(market).balanceOf(address(adapter)), 250e18);
    assertEq(adapter.realAssets(), 0);
  }

  function test_realAssets_updates_across_queue_and_realize() external {
    _allocate(1_000e18);
    assertEq(adapter.realAssets(), 1_000e18);

    uint32 expiry = _queue(600e18);
    assertEq(IWildcatMarket(market).balanceOf(address(adapter)), 400e18);
    assertEq(adapter.realAssets(), 400e18); 

    _mature(expiry);
    adapter.realizeClaimable(5);
    assertEq(asset.balanceOf(address(adapter)), 600e18);
    assertEq(IWildcatMarket(market).balanceOf(address(adapter)), 400e18);
    assertEq(adapter.realAssets(), 1_000e18);
  }

  function test_allocate_reports_change_after_recording_allocation() external {
    _allocate(500e18);
    assertEq(adapter.realAssets(), 500e18);

    asset.mint(address(adapter), 200e18);
    vm.prank(address(vault));
    (bytes32[] memory ids, int256 change) = adapter.allocate(new bytes(0), 200e18, bytes4(0), address(this));
    assertEq(ids.length, 1);
    assertEq(ids[0], adapter.adapterId());
    assertEq(change, int256(200e18));

    vm.prank(address(vault));
    vault.setAllocation(adapter.adapterId(), IWildcatMarket(market).balanceOf(address(adapter)));
    assertEq(adapter.realAssets(), 700e18);
  }

  function test_ids_returns_single_adapter_id() external view {
    bytes32[] memory ids = adapter.ids();
    assertEq(ids.length, 1);
    assertEq(ids[0], adapter.adapterId());
  }

  function test_queueAdapterWithdrawal_access_control() external {
    vm.expectRevert(IWildcatMarketV2Adapter.NotAuthorized.selector);
    adapter.queueAdapterWithdrawal(1);

    _allocate(100e18);

    vm.prank(vaultOwner);
    adapter.queueAdapterWithdrawal(10e18);

    vm.prank(address(vault));
    vault.setAllocator(allocator, true);
    vm.prank(allocator);
    adapter.queueAdapterWithdrawal(5e18);
  }

  function test_queueAdapterWithdrawal_records_pending() external {
    _allocate(100e18);
    uint32 expiry = _queue(25e18);
    assertEq(adapter.pendingWithdrawals(expiry), 25e18);
    assertEq(adapter.totalPendingWithdrawals(), 25e18);
  }

  function test_realizeClaimable_clears_pending() external {
    _allocate(200e18);
    uint32 expiry = _queue(200e18);
    _mature(expiry);

    adapter.realizeClaimable(3);
    assertEq(adapter.totalPendingWithdrawals(), 0);
    assertEq(asset.balanceOf(address(adapter)), 200e18);
  }

  function test_getAvailableLiquidity_and_canWithdrawSync() external {
    _allocate(300e18);
    assertEq(adapter.getAvailableLiquidity(), 0);
    assertFalse(adapter.canWithdrawSync(1));

    uint32 expiry = _queue(200e18);
    _mature(expiry);

    adapter.realizeClaimable(1);
    assertEq(adapter.getAvailableLiquidity(), 200e18);
    assertTrue(adapter.canWithdrawSync(150e18));
    assertFalse(adapter.canWithdrawSync(300e18));

  }
}
