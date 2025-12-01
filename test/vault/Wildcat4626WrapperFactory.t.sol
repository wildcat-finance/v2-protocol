// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';

import { Wildcat4626Wrapper, IWildcatMarketToken } from 'src/vault/Wildcat4626Wrapper.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { RAY } from 'src/libraries/MathUtils.sol';

contract StubMarketToken is IWildcatMarketToken {
  string public constant name = 'Stub Market';
  string public constant symbol = 'stubUSDC';
  uint8 public constant override decimals = 18;

  uint256 public override scaleFactor = RAY;
  address public immutable override borrower;

  mapping(address => uint256) internal _balances;
  mapping(address => mapping(address => uint256)) public override allowance;

  constructor(address borrower_) {
    borrower = borrower_;
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account];
  }

  function totalSupply() external pure override returns (uint256) {
    return 0;
  }

  function scaledBalanceOf(address account) external view override returns (uint256) {
    return _balances[account];
  }

  function maxTotalSupply() external pure override returns (uint256) {
    return uint256(type(uint128).max);
  }

  function transfer(address, uint256) external pure override returns (bool) {
    revert('UNSUPPORTED');
  }

  function approve(address spender, uint256 amount) external override returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transferFrom(address, address, uint256) external pure override returns (bool) {
    revert('UNSUPPORTED');
  }
}

contract Wildcat4626WrapperFactoryTest is Test {
  Wildcat4626WrapperFactory internal factory;
  StubMarketToken internal market;

  address internal constant BORROWER = address(0xB0123);

  function setUp() external {
    factory = new Wildcat4626WrapperFactory();
    market = new StubMarketToken(BORROWER);
  }

  function test_createWrapperDeploysAndRecords() external {
    address wrapperAddr = factory.createWrapper(address(market));

    assertEq(factory.wrapperForMarket(address(market)), wrapperAddr, 'wrapper recorded');
    assertEq(Wildcat4626Wrapper(wrapperAddr).asset(), address(market), 'wrapper asset');
  }

  function test_createWrapperRevertsIfExists() external {
    factory.createWrapper(address(market));

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.WrapperAlreadyExists.selector,
        address(market)
      )
    );
    factory.createWrapper(address(market));
  }

  function test_createWrapperRevertsOnZeroMarket() external {
    vm.expectRevert(Wildcat4626WrapperFactory.ZeroAddress.selector);
    factory.createWrapper(address(0));
  }
}
