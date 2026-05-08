// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../BaseMarketTest.sol';
import '../shared/mocks/MockHooks.sol';
import 'src/ReentrancyGuard.sol';

contract ProtocolFeeReadOnDepositHooks is MockHooks {
  bool public protocolFeeReadSucceeded;
  uint128 public protocolFeeReadValue;
  bytes4 public protocolFeeReadRevertSelector;

  constructor(address _caller, bytes memory _constructorArgs) MockHooks(_caller, _constructorArgs) {}

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    (bool success, bytes memory data) = msg.sender.staticcall(
      abi.encodeWithSignature('withdrawableProtocolFees()')
    );
    protocolFeeReadSucceeded = success;
    if (success && data.length >= 0x20) {
      protocolFeeReadValue = abi.decode(data, (uint128));
    } else if (data.length >= 0x04) {
      bytes4 selector;
      assembly {
        selector := mload(add(data, 0x20))
      }
      protocolFeeReadRevertSelector = selector;
    }

    lastExtraData = extraData;
    lastCalldataHash = keccak256(msg.data);
    emit OnDepositCalled(lender, scaledAmount, intermediateState, extraData);
  }
}

contract WildcatMarketBaseTest is BaseMarketTest {
  // ===================================================================== //
  //                          coverageLiquidity()                          //
  // ===================================================================== //

  function test_coverageLiquidity() external view {
    market.coverageLiquidity();
  }

  // ===================================================================== //
  //                             scaleFactor()                             //
  // ===================================================================== //

  function test_scaleFactor() external {
    assertEq(market.scaleFactor(), 1e27, 'scaleFactor should be 1 ray');
    fastForward(365 days);
    assertEq(market.scaleFactor(), 1.1e27, 'scaleFactor should grow by 10% from APR');
    // Deposit one token
    _deposit(alice, 1e18);
    // Borrow 80% of market assets
    _borrow(8e17);
    assertEq(market.currentState().isDelinquent, false);
    // Withdraw 100% of deposits
    _requestWithdrawal(alice, 1e18);
    assertEq(market.scaleFactor(), 1.1e27);
    // Fast forward to delinquency grace period
    fastForward(2000);
    MarketState memory state = previousState;
    uint256 scaleFactorAtGracePeriodExpiry = uint(1.1e27) +
      MathUtils.rayMul(
        1.1e27,
        FeeMath.calculateLinearInterestFromBips(parameters.annualInterestBips, 2_000)
      );
    assertEq(market.scaleFactor(), scaleFactorAtGracePeriodExpiry);
  }

  // ===================================================================== //
  //                             totalAssets()                             //
  // ===================================================================== //

  function test_totalAssets() external view {
    market.totalAssets();
  }

  // ===================================================================== //
  //                          borrowableAssets()                           //
  // ===================================================================== //

  function test_borrowableAssets() external {
    assertEq(market.borrowableAssets(), 0, 'borrowable should be 0');

    _deposit(alice, 50_000e18);
    assertEq(market.borrowableAssets(), 40_000e18, 'borrowable should be 40k');
    // market.borrowableAssets();
  }

  // ===================================================================== //
  //                         accruedProtocolFees()                         //
  // ===================================================================== //

  function test_accruedProtocolFees() external view {
    market.accruedProtocolFees();
  }

  // ===================================================================== //
  //                            previousState()                            //
  // ===================================================================== //

  function test_previousState() external view {
    market.previousState();
  }

  // ===================================================================== //
  //                            currentState()                             //
  // ===================================================================== //

  function test_currentState() external view {
    market.currentState();
  }

  // ===================================================================== //
  //                          scaledTotalSupply()                          //
  // ===================================================================== //

  function test_scaledTotalSupply() external view {
    assertEq(market.currentState().scaledTotalSupply, market.scaledTotalSupply());
  }

  // ===================================================================== //
  //                       scaledBalanceOf(address)                        //
  // ===================================================================== //

  function test_scaledBalanceOf(address account) external view {
    market.scaledBalanceOf(account);
  }

  function test_scaledBalanceOf() external view {
    address account;
    market.scaledBalanceOf(account);
  }

  // ===================================================================== //
  //                      withdrawableProtocolFees()                       //
  // ===================================================================== //

  function test_withdrawableProtocolFees() external {
    assertEq(previousState.withdrawableProtocolFees(market.totalAssets()), 0);
    _deposit(alice, 1e18);
    fastForward(365 days);

    MarketState memory state = pendingState();
    assertEq(state.withdrawableProtocolFees(market.totalAssets()), 1e16);
  }

  function test_withdrawableProtocolFees_LessNormalizedUnclaimedWithdrawals() external {
    assertEq(market.currentState().withdrawableProtocolFees(market.totalAssets()), 0);
    _deposit(alice, 1e18);
    _borrow(8e17);
    fastForward(365 days);
    _requestWithdrawal(alice, 1e18);
    // MarketState memory state = market.currentState();
    assertEq(market.currentState().withdrawableProtocolFees(market.totalAssets()), 1e16);
    asset.mint(address(market), 8e17 + 1);
    assertEq(market.currentState().withdrawableProtocolFees(market.totalAssets()), 1e16);
    assertEq(market.withdrawableProtocolFees(), 1e16);
  }

  function test_withdrawableProtocolFees_RevertsDuringStateChangingReentrancy() external {
    parameters.hooksTemplate = LibStoredInitCode.deployInitCode(
      type(ProtocolFeeReadOnDepositHooks).creationCode
    );
    hooksFactory.addHooksTemplate(
      parameters.hooksTemplate,
      'ProtocolFeeReadOnDepositHooks',
      address(0),
      address(0),
      0,
      0
    );
    hooks = OpenTermHooks(address(0));
    parameters.deployHooksConstructorArgs = abi.encode(address(this), '');
    parameters.hooksConfig = EmptyHooksConfig;
    setUpContracts(false);

    ProtocolFeeReadOnDepositHooks testHooks =
      ProtocolFeeReadOnDepositHooks(parameters.hooksConfig.hooksAddress());
    _deposit(alice, 1e18);

    assertEq(testHooks.protocolFeeReadSucceeded(), false);
    assertEq(testHooks.protocolFeeReadRevertSelector(), ReentrancyGuard.NoReentrantCalls.selector);
  }
}
