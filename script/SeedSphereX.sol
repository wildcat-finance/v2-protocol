// // SPDX-License-Identifier: MIT
// pragma solidity >=0.8.19;

// import 'src/WildcatSanctionsSentinel.sol';
// import 'src/WildcatArchController.sol';
// import 'forge-std/Script.sol';
// import 'solady/utils/LibString.sol';
// import 'src/libraries/LibERC20.sol';
// import 'src/access/IRoleProvider.sol';
// import 'src/access/OpenTermHooks.sol';
// import './LibDeployment.sol';
// import './mock/MockERC20Factory.sol';
// import './mock/MockBorrower.sol';
// import './mock/UniversalProvider.sol';

// using LibString for string;

// string constant DeploymentsJsonFilePath = 'sepolia-deployments.json';



// contract SeedSphereX is Script {
//   using LibDeployment for Deployments;
//   using LibERC20 for address;

//   function _getCreationCode(
//     Deployments memory deployments,
//     string memory namePath
//   ) internal returns (bytes memory) {
//     ContractArtifact memory artifact = parseContractNamePath(namePath);

//     string memory jsonPath = LibDeployment.findForgeArtifact(artifact, deployments.forgeOutDir);
//     Json memory forgeArtifact = JsonUtil.create(vm.readFile(jsonPath));
//     bytes memory creationCode = forgeArtifact.getBytes('bytecode.object');
//     return creationCode;
//   }

//   function deployBorrower() internal asDeployer returns (MockBorrower borrower) {
//     Deployments memory deployments;
//     address archController = deployments.get('WildcatArchController');
//     address hooksFactory = deployments.get('HooksFactory');
//     address erc20Factory = deployments.get('MockERC20Factory');
//     (address borrowerAddress, bool didDeployBorrower) = deployments.getOrDeploy(
//       'MockBorrower',
//       _getCreationCode(deployments, 'MockBorrower'),
//       abi.encode(archController, hooksFactory, erc20Factory),
//       false
//     );
//     MockBorrower borrower = MockBorrower(borrowerAddress);
//     if (didDeployBorrower) {
//       deployments.set('SeedSphereXMarket1', address(pre_market1(deployments, borrower)));
//       deployments.set('SeedSphereXMarket2', address(pre_market2(deployments, borrower)));
//       deployments.set('SeedSphereXMarket3', address(pre_market3(deployments, borrower)));
//       deployments.set('SeedSphereXMarket4', address(pre_market4(deployments, borrower)));
//     } else {
//       post_market1(borrower, WildcatMarket(deployments.get('SeedSphereXMarket1')));
//       post_market2(borrower, WildcatMarket(deployments.get('SeedSphereXMarket2')));
//       post_market3(borrower, WildcatMarket(deployments.get('SeedSphereXMarket3')));
//       post_market4(borrower, WildcatMarket(deployments.get('SeedSphereXMarket4')));
//     }
//     return borrower;
//   }

//   function run() public virtual {
//     Deployments memory deployments;

//     deployments.write();
//   }

//   modifier asDeployer() {
//     // ctx.startBroadcast(env.getUint('PVT_KEY_SEPOLIA'));
//     _;
//     // ctx.stopBroadcast();
//   }

//   modifier asBorrower() {
//     // ctx.startBroadcast(env.getUint('BORROWER_PVT_KEY'));
//     _;
//     // ctx.stopBroadcast();
//   }

//   function getHooksTemplateArgs(
//     Deployments memory deployments,
//     string memory hooksName
//   ) internal returns (bytes memory hooksTemplateArgs) {
//     (address providerAddress, ) = deployments.getOrDeploy(
//       'UniversalProvider',
//       _getCreationCode(deployments, 'UniversalProvider'),
//       false
//     );

//     NameAndProviderInputs memory hooksArgs;
//     hooksArgs.name = hooksName;
//     hooksArgs.existingProviders = new ExistingProviderInputs[](1);
//     hooksArgs.existingProviders[0].providerAddress = providerAddress;
//     hooksArgs.existingProviders[0].timeToLive = type(uint32).max;
//   }

//   function _createMarket(
//     MockBorrower borrower,
//     Deployments memory deployments,
//     address owner,
//     bool openTerm,
//     bool restrictive,
//     uint index
//   ) internal returns (OpenTermHooks hooks, WildcatMarket market, MockERC20 token) {
//     MarketConfig memory config = MarketConfig({
//       // token parameters
//       tokenName: 'Token',
//       tokenSymbol: 'TOK',
//       tokenDecimals: 18,
//       // market parameters
//       salt: openTerm ? bytes32(0) : bytes32(uint(1)),
//       namePrefix: openTerm ? 'Open V2 ' : 'Fixed V2 ',
//       symbolPrefix: openTerm ? 'v2_open_' : 'v2_fixed_',
//       maxTotalSupply: uint128(100_000e18),
//       annualInterestBips: 1_500,
//       delinquencyFeeBips: 1_000,
//       withdrawalBatchDuration: uint32(86400),
//       reserveRatioBips: 1_000,
//       delinquencyGracePeriod: uint32(86400),
//       hooks: MarketHooksOptions({
//         isOpenTerm: openTerm,
//         transferAccess: restrictive ? TransferAccess.Disabled : TransferAccess.Open,
//         depositAccess: restrictive ? DepositAccess.RequiresCredential : DepositAccess.Open,
//         withdrawalAccess: restrictive ? WithdrawalAccess.RequiresCredential : WithdrawalAccess.Open,
//         minimumDeposit: uint128(1e16),
//         allowForceBuyBacks: restrictive ? false : true,
//         fixedTermEndTime: openTerm ? 0 : uint32(block.timestamp + 100 days),
//         allowClosureBeforeTerm: restrictive ? false : true,
//         allowTermReduction: restrictive ? false : true
//       })
//     });
//     string memory marketLabel = string.concat('SeedSphereXMarket', index.toString());
//     string memory hooksName = string.concat(
//       marketLabel,
//       openTerm ? ' OpenTermHooks' : 'FixedTermHooks'
//     );
//     bytes memory hooksArgs = getHooksTemplateArgs(deployments, hooksName);

//     deployments.broadcast();
//     (hooks, market, token) = borrower.deployMarketAndHooks(config, owner, hooksArgs);
//     string memory hooksContractName = config.hooks.isOpenTerm ? 'OpenTermHooks' : 'FixedTermHooks';
//     // Add market artifact - takes no constructor args
//     deployments.addArtifactWithoutDeploying(
//       string.concat(marketLabel, '_market'),
//       'WildcatMarket',
//       address(market),
//       ''
//     );
//     // Add hooks artifact - takes constructor args (address borrower, bytes args)
//     deployments.addArtifactWithoutDeploying(
//       string.concat(marketLabel, '_hooks'),
//       hooksContractName,
//       address(hooks),
//       abi.encode(borrower, abi.encode(hooksArgs))
//     );
//   }

//   function pre_market1(
//     Deployments memory deployments,
//     MockBorrower borrower
//   ) internal asDeployer returns (WildcatMarket market) {
//     // market = borrower.init(AuthKind.Authorize);

//     borrower.depositAndTransfer(market, DepositKind.Deposit, TransferKind.Transfer, 2e18);
//     borrower.buyTokensAndQueueWithdrawal(market, TransferKind.Transfer, 0.5e18);
//     borrower.borrowMax(market);
//   }

//   function post_market1(MockBorrower borrower, WildcatMarket market) internal asDeployer {
//     borrower.repayAndExecuteWithdrawals(market, RepayKind.RepayOutstandingDebt, 1e18);
//     borrower.collectFees(market);
//     borrower.borrowMax(market);
//     borrower.repayAndCloseMarket(market, RepayKind.RepayOutstandingDebt, 1e18);
//   }

//   function pre_market2(
//     Deployments memory deployments,
//     MockBorrower borrower
//   ) internal asDeployer returns (WildcatMarket market) {
//     market = borrower.init(AuthKind.AuthorizeAndUpdate);
//     borrower.depositAndTransfer(
//       market,
//       DepositKind.Deposit,
//       TransferKind.ApproveThenTransferFrom,
//       1e18
//     );
//     borrower.depositAndTransfer(market, DepositKind.Deposit, TransferKind.TransferFrom, 1e18);
//     borrower.borrowMax(market);
//     borrower.buyTokensAndQueueWithdrawal(market, TransferKind.TransferFrom, 1e18);
//   }

//   function post_market2(MockBorrower borrower, WildcatMarket market) internal asDeployer {
//     borrower.repayAndExecuteWithdrawals(market, RepayKind.RepayDelinquentDebt, 1e18);
//     // Can not close market while only repaying delinquent debt
//   }

//   function pre_market3(
//     Deployments memory deployments,
//     MockBorrower borrower
//   ) internal asDeployer returns (WildcatMarket market) {
//     market = borrower.init(AuthKind.AuthorizeThenUpdate);
//     borrower.depositAndTransfer(market, DepositKind.DepositUpTo, TransferKind.Transfer, 1e18);
//     borrower.buyTokensAndQueueWithdrawal(market, TransferKind.ApproveThenTransferFrom, 1e18);
//     borrower.deauthorizeLenders(market, DeAuthKind.DeauthorizeAndUpdate);
//     borrower.authorizeLenders(market, AuthKind.AuthorizeAndUpdate);
//     borrower.borrowMax(market);
//   }

//   function post_market3(MockBorrower borrower, WildcatMarket market) internal asDeployer {
//     borrower.repayAndExecuteWithdrawals(
//       market,
//       RepayKind.RepayAndProcessUnpaidWithdrawalBatches,
//       1e18
//     );
//     borrower.borrowMax(market);
//     borrower.repayAndCloseMarket(market, RepayKind.RepayAndProcessUnpaidWithdrawalBatches, 1e18);
//   }

//   function pre_market4(
//     Deployments memory deployments,
//     MockBorrower borrower
//   ) internal asDeployer returns (WildcatMarket market) {
//     market = borrower.init(AuthKind.Update);
//     borrower.authorizeLenders(market, AuthKind.Authorize);
//     borrower.depositAndTransfer(
//       market,
//       DepositKind.DepositUpTo,
//       TransferKind.ApproveThenTransferFrom,
//       1e18
//     );
//     borrower.depositAndTransfer(market, DepositKind.DepositUpTo, TransferKind.TransferFrom, 1e18);
//     borrower.buyTokensAndQueueWithdrawal(market, TransferKind.Transfer, 1e18);
//     borrower.deauthorizeLenders(market, DeAuthKind.Update);
//     borrower.authorizeLenders(market, AuthKind.Update);
//     borrower.borrowMax(market);
//   }

//   function post_market4(MockBorrower borrower, WildcatMarket market) internal asDeployer {
//     borrower.repayAndExecuteWithdrawals(market, RepayKind.Repay, 1e18);
//     borrower.borrowMax(market);
//     borrower.repayAndCloseMarket(market, RepayKind.Repay, 1e18);
//   }
// }
