// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './WildcatMarketWithdrawals.t.sol';
import './WildcatMarketBase.t.sol';
import './WildcatMarketConfig.t.sol';
import './WildcatMarketToken.t.sol';
import './WildcatMarket.t.sol';
import { safeStartPrank, safeStopPrank } from '../helpers/VmUtils.sol';

contract FixedTermWildcatMarketTest is WildcatMarketTest {
  function setUp() public virtual override {
    parameters.hooksTemplate = fixedTermHooksTemplate;
    parameters.fixedTermEndTime = uint32(block.timestamp + 1 days);
    parameters.allowTermReduction = true;
    super.setUp();
    safeStartPrank(borrower);
    FixedTermHooks(address(hooks)).setFixedTermEndTime(
      address(market),
      uint32(block.timestamp)
    );
    safeStopPrank();
  }
}

contract FixedTermWithdrawalsTest is WithdrawalsTest {
  function setUp() public virtual override {
    parameters.hooksTemplate = fixedTermHooksTemplate;
    parameters.fixedTermEndTime = uint32(block.timestamp + 1 days);
    parameters.allowTermReduction = true;
    super.setUp();
    safeStartPrank(borrower);
    FixedTermHooks(address(hooks)).setFixedTermEndTime(
      address(market),
      uint32(block.timestamp)
    );
    safeStopPrank();
  }
}

contract FixedTermWildcatMarketBaseTest is WildcatMarketBaseTest {
  function setUp() public virtual override {
    parameters.hooksTemplate = fixedTermHooksTemplate;
    parameters.fixedTermEndTime = uint32(block.timestamp + 1 days);
    parameters.allowTermReduction = true;
    super.setUp();
    safeStartPrank(borrower);
    FixedTermHooks(address(hooks)).setFixedTermEndTime(
      address(market),
      uint32(block.timestamp)
    );
    safeStopPrank();
  }
}

contract FixedTermWildcatMarketConfigTest is WildcatMarketConfigTest {
  function setUp() public virtual override {
    parameters.hooksTemplate = fixedTermHooksTemplate;
    parameters.fixedTermEndTime = uint32(block.timestamp + 1 days);
    parameters.allowTermReduction = true;
    super.setUp();
    safeStartPrank(borrower);
    FixedTermHooks(address(hooks)).setFixedTermEndTime(
      address(market),
      uint32(block.timestamp)
    );
    safeStopPrank();
  }
}

contract FixedTermWildcatMarketTokenTest is WildcatMarketTokenTest {
  function setUp() public virtual override {
    parameters.hooksTemplate = fixedTermHooksTemplate;
    parameters.fixedTermEndTime = uint32(block.timestamp + 1 days);
    parameters.allowTermReduction = true;
    super.setUp();
    safeStartPrank(borrower);
    FixedTermHooks(address(hooks)).setFixedTermEndTime(
      address(market),
      uint32(block.timestamp)
    );
    safeStopPrank();
  }
}
