// // SPDX-License-Identifier: MIT
// pragma solidity >=0.8.20;

// import 'src/WildcatArchController.sol';
// import 'solady/utils/LibString.sol';
// import './MockERC20Factory.sol';
// import './MockArchControllerOwner.sol';
// import 'src/market/WildcatMarket.sol';
// import { OpenTermHooks, NameAndProviderInputs } from 'src/access/OpenTermHooks.sol';
// import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
// import 'src/HooksFactory.sol';
// import '../LibDeployment.sol';
// import '../DeployTypes.sol';

// using LibString for string;

// enum RepayKind {
//   RepayAndProcessUnpaidWithdrawalBatches,
//   Repay
// }

// enum TransferKind {
//   Transfer,
//   ApproveThenTransferFrom,
//   TransferFrom
// }

// enum DepositKind {
//   Deposit,
//   DepositUpTo
// }

// struct WithdrawalInfo {
//   WildcatMarket market;
//   uint32 expiry;
// }

// /*
// [+] executeWithdrawals: function executeWithdrawals(address[] accountAddresses, uint32[] expiries) returns (uint256[] amounts)
// [+] queueFullWithdrawal: function queueFullWithdrawal() returns (uint32 expiry)
// [+] repayAndProcessUnpaidWithdrawalBatches: function repayAndProcessUnpaidWithdrawalBatches(uint256 repayAmount, uint256 maxBatches)
// [+] rescueTokens: function rescueTokens(address token)
// [+] setAnnualInterestAndReserveRatioBips: function setAnnualInterestAndReserveRatioBips(uint16 _annualInterestBips, uint16 _reserveRatioBips)
// [+] setProtocolFeeBips: function setProtocolFeeBips(uint16 _protocolFeeBips)
// */

// contract MockBorrower {
//   uint internal marketIndex;
//   WildcatArchController internal immutable archController;
//   HooksFactory internal immutable hooksFactory;
//   IMockERC20Factory internal immutable erc20Factory;
//   address internal immutable deployer = msg.sender;

//   modifier onlyDeployer() {
//     require(msg.sender == deployer);
//     _;
//   }

//   mapping(WildcatMarket => uint32[]) public withdrawalsByMarket;

//   function getWithdrawalsByMarket(WildcatMarket market) external view returns (uint32[] memory) {
//     return withdrawalsByMarket[market];
//   }

//   constructor(
//     WildcatArchController archController_,
//     HooksFactory hooksFactory_,
//     IMockERC20Factory erc20Factory_
//   ) {
//     archController = archController_;
//     hooksFactory = hooksFactory_;
//     erc20Factory = erc20Factory_;
//   }

//   function forceBuyBack(
//     WildcatMarket market,
//     address lender,
//     uint256 normalizedAmount
//   ) external onlyDeployer {
//     market.forceBuyBack(lender, normalizedAmount);
//   }

//   // Requires existing hooks factory, hooks template, and mock token factory
//   function deployMarketAndHooks(
//     MarketConfig memory config,
//     address hooksTemplate,
//     NameAndProviderInputs memory hooksArgs
//   ) external onlyDeployer returns (OpenTermHooks hooks, WildcatMarket market, MockERC20 token) {
//     DeployMarketInputs memory inputs = DeployMarketInputs({
//       asset: erc20Factory.deployMockERC20(config.tokenName, config.tokenSymbol),
//       namePrefix: config.namePrefix,
//       symbolPrefix: config.symbolPrefix,
//       maxTotalSupply: config.maxTotalSupply,
//       annualInterestBips: config.annualInterestBips,
//       delinquencyFeeBips: config.delinquencyFeeBips,
//       withdrawalBatchDuration: config.withdrawalBatchDuration,
//       reserveRatioBips: config.reserveRatioBips,
//       delinquencyGracePeriod: config.delinquencyGracePeriod,
//       hooks: config.hooks.toHooksConfig()
//     });

//     bytes memory hookData = config.hooks.encodeHooksData();

//     (address marketAddress, address hooksInstance) = hooksFactory.deployMarketAndHooks({
//       hooksTemplate: hooksTemplate,
//       hooksTemplateArgs: abi.encode(hooksArgs),
//       parameters: inputs,
//       hooksData: hookData,
//       salt: config.salt,
//       originationFeeAsset: address(0),
//       originationFeeAmount: 0
//     });

//     hooks = OpenTermHooks(hooksInstance);
//     market = WildcatMarket(marketAddress);
//     token = MockERC20(inputs.asset);
//     token.mint(address(this), 1_000_000_000e18);
//     token.approve(address(market), type(uint256).max);
//     market.approve(address(this), type(uint256).max);
//   }

//   function depositAndTransfer(
//     WildcatMarket market,
//     DepositKind depositKind,
//     TransferKind transferKind,
//     uint256 amount
//   ) external onlyDeployer {
//     if (depositKind == DepositKind.DepositUpTo) {
//       market.depositUpTo(amount);
//     } else if (depositKind == DepositKind.Deposit) {
//       market.deposit(amount);
//     }
//     _transfer(market, transferKind, amount);
//   }

//   function _transfer(WildcatMarket market, TransferKind transferKind, uint256 amount) internal {
//     if (transferKind == TransferKind.ApproveThenTransferFrom) {
//       market.approve(address(this), type(uint256).max);
//       market.transferFrom(address(this), address(this), amount);
//     } else if (transferKind == TransferKind.TransferFrom) {
//       market.transferFrom(address(this), address(this), amount);
//     } else if (transferKind == TransferKind.Transfer) {
//       market.transfer(address(this), amount);
//     }
//   }

//   function _repay(WildcatMarket market, RepayKind repayKind, uint256 repayAmount) internal {
//     if (repayKind == RepayKind.RepayAndProcessUnpaidWithdrawalBatches) {
//       market.repayAndProcessUnpaidWithdrawalBatches(repayAmount, 3);
//     } else if (repayKind == RepayKind.Repay) {
//       market.repay(repayAmount);
//     }
//   }

//   function buyTokensAndQueueWithdrawal(
//     WildcatMarket market,
//     TransferKind transferKind,
//     uint256 amount
//   ) external onlyDeployer {
//     _transfer(market, transferKind, amount);
//     market.queueWithdrawal(amount);
//     uint32[] storage withdrawals = withdrawalsByMarket[market];
//     uint32 expiry = market.currentState().pendingWithdrawalExpiry;

//     if (withdrawals.length == 0) {
//       withdrawals.push(market.currentState().pendingWithdrawalExpiry);
//     } else if (withdrawals[withdrawals.length - 1] != expiry) {
//       withdrawals.push(expiry);
//     }
//   }

//   function queueWithdrawal(WildcatMarket market, uint256 amount) external onlyDeployer {
//     market.queueWithdrawal(amount);
//   }

//   function queueFullWithdrawal(WildcatMarket market) external onlyDeployer {
//     market.queueFullWithdrawal();
//   }

//   function repayAndCloseMarket(
//     WildcatMarket market,
//     RepayKind repayKind,
//     uint256 repayAmount
//   ) external onlyDeployer {
//     _repay(market, repayKind, repayAmount);
//     market.closeMarket();
//   }

//   function closeMarket(WildcatMarket market) external onlyDeployer {
//     market.closeMarket();
//   }

//   function repayAndExecuteWithdrawals(
//     WildcatMarket market,
//     RepayKind repayKind,
//     uint256 repayAmount
//   ) external onlyDeployer {
//     _repay(market, repayKind, repayAmount);
//     uint32[] storage withdrawals = withdrawalsByMarket[market];
//     bool haveWithdrawal = withdrawals.length > 0;
//     address[] memory accountAddresses;
//     uint32[] memory expiries;
//     if (haveWithdrawal) {
//       uint32 expiry = withdrawals[withdrawals.length - 1];
//       accountAddresses = new address[](1);
//       expiries = new uint32[](1);
//       accountAddresses[0] = address(this);
//       expiries[0] = expiry;
//       withdrawals.pop();
//       market.executeWithdrawals(accountAddresses, expiries);
//     } else {
//       market.executeWithdrawals(accountAddresses, expiries);
//     }
//   }

//   function borrowMax(WildcatMarket market) external onlyDeployer {
//     market.borrow(market.borrowableAssets());
//   }

//   function collectFees(WildcatMarket market) external onlyDeployer {
//     market.collectFees();
//   }

//   function setMaxTotalSupply(WildcatMarket market, uint256 amount) external onlyDeployer {
//     market.setMaxTotalSupply(amount);
//   }

//   function setAnnualInterestBips(WildcatMarket market, uint16 amount) external onlyDeployer {
//     market.setAnnualInterestAndReserveRatioBips(amount, 0);
//   }
// }
