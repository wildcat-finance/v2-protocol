// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * Direct-only fork/testnet canary. Deploys and closes one dust market through
 * each v2.5 hooks factory using the v2.5 OpenTermHooks template.
 *
 * Environment:
 * - Required: OWNER_MODE=direct, DEPLOYMENTS_NETWORK, BORROWER, and RPC_URL.
 * - Optional: RELEASE_TAG (default v2-5), CANARY_ASSET, and
 *   PVT_KEY_<NETWORK>. Without a private key, the RPC must expose BORROWER as
 *   an unlocked account (anvil --auto-impersonate does this). CANARY_PHASE is
 *   set to prepare or finalize by 09-canary-market.sh.
 *
 * Register BORROWER on an anvil fork before running this script. ARCH_OWNER is
 * the value returned by archController.owner():
 *   cast send "$ARCH_CONTROLLER" 'registerBorrower(address)' "$BORROWER" --from "$ARCH_OWNER" --unlocked --rpc-url "$RPC_URL"
 *
 * This script does not impersonate or register the borrower itself.
 */

import { console } from 'forge-std/console.sol';
import { LibString } from 'solady/utils/LibString.sol';

import { IHooksFactory } from 'src/IHooksFactory.sol';
import { IHooksFactoryRevolving } from 'src/IHooksFactoryRevolving.sol';
import { IERC20 } from 'src/interfaces/IERC20.sol';
import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { WildcatMarket } from 'src/market/WildcatMarket.sol';
import { EmptyHooksConfig } from 'src/types/HooksConfig.sol';

import '../../common/DeployScriptBase.sol';

contract CanaryMarketsV25 is V25DeployScriptBase {
  using LibString for string;

  uint256 internal constant DUST_DEPOSIT = 1e15;
  uint256 internal constant MAX_TOTAL_SUPPLY = 1e18;

  function _marketSalt(address marketDeployer, uint96 nonce) internal pure returns (bytes32) {
    return bytes32((uint256(uint160(marketDeployer)) << 96) | uint256(nonce));
  }

  function _broadcastAsBorrower(Deployments memory deployments, address borrower) internal {
    uint256 privateKey = vm.envOr(deployments.privateKeyVarName, uint256(0));
    if (privateKey == 0) {
      vm.broadcast(borrower);
      return;
    }
    if (vm.addr(privateKey) != borrower) {
      revert('BORROWER does not match the configured deployment private key');
    }
    vm.broadcast(privateKey);
  }

  function _marketInputs(
    address asset,
    string memory namePrefix,
    string memory symbolPrefix
  ) internal pure returns (DeployMarketInputs memory inputs) {
    inputs = DeployMarketInputs({
      asset: asset,
      namePrefix: namePrefix,
      symbolPrefix: symbolPrefix,
      maxTotalSupply: uint128(MAX_TOTAL_SUPPLY),
      annualInterestBips: 0,
      delinquencyFeeBips: 0,
      withdrawalBatchDuration: 1,
      reserveRatioBips: 10_000,
      delinquencyGracePeriod: 0,
      hooks: EmptyHooksConfig
    });
  }

  function _ensureCanaryBalance(
    Deployments memory deployments,
    IERC20 asset,
    address borrower
  ) internal {
    if (asset.balanceOf(borrower) >= DUST_DEPOSIT * 2) return;
    _broadcastAsBorrower(deployments, borrower);
    (bool success, ) = address(asset).call(abi.encodeWithSignature('faucet()'));
    if (!success || asset.balanceOf(borrower) < DUST_DEPOSIT * 2) {
      revert('Canary asset balance is insufficient and faucet() failed');
    }
  }

  function _resolveCanaryAsset(Deployments memory deployments) internal returns (address asset) {
    asset = vm.envOr('CANARY_ASSET', address(0));
    if (asset != address(0)) return asset;

    string[] memory args = new string[](5);
    args[0] = 'node';
    args[1] = '-e';
    args[
      2
    ] = "const fs=require('fs');const value=JSON.parse(fs.readFileSync(process.argv[1],'utf8'))[process.argv[2]];if(typeof value!=='string')process.exit(1);process.stdout.write('ADDRESS:'+value)";
    args[3] = deployments.filePath;
    args[4] = 'MockERC20:Token';
    string memory value = string(vm.ffi(args));
    if (!value.startsWith('ADDRESS:')) {
      revert('Invalid default canary asset resolver output');
    }
    try vm.parseAddress(value.slice(8)) returns (address parsed) {
      if (parsed == address(0)) revert('Default canary asset is zero');
      return parsed;
    } catch {
      revert('Set CANARY_ASSET or add MockERC20:Token to deployments.json');
    }
  }

  function _prepareMarket(
    Deployments memory deployments,
    IERC20 asset,
    address borrower,
    address marketAddress,
    string memory label
  ) internal {
    WildcatMarket market = WildcatMarket(marketAddress);
    _broadcastAsBorrower(deployments, borrower);
    if (!asset.approve(marketAddress, type(uint256).max)) revert('Canary asset approval failed');
    _broadcastAsBorrower(deployments, borrower);
    uint256 deposited = market.depositUpTo(DUST_DEPOSIT);
    if (deposited == 0) revert('Canary deposit minted zero');

    _broadcastAsBorrower(deployments, borrower);
    market.queueFullWithdrawal();
    // Close immediately so the borrower deterministically settles and clears
    // the pending batch in both Foundry's same-timestamp broadcast simulation
    // and on public testnets. The lender can then execute without waiting for
    // a chain-specific time-advance RPC.
    _broadcastAsBorrower(deployments, borrower);
    market.closeMarket();
    if (!market.isClosed()) revert('Canary market did not close');
    console.log(string.concat(label, ' canary market:'), marketAddress);
    console.log(string.concat(label, ' canary deposited:'), deposited);
    console.log(string.concat(label, ' canary queued and closed:'), true);
  }

  function _findQueuedExpiry(
    address market,
    address borrower
  ) internal view returns (uint32 expiry) {
    uint256 upperBound = block.timestamp + 2;
    uint256 lowerBound = upperBound > 600 ? upperBound - 600 : 1;
    for (uint256 candidate = upperBound; candidate >= lowerBound; candidate--) {
      (bool success, bytes memory data) = market.staticcall(
        abi.encodeWithSignature(
          'getAccountWithdrawalStatus(address,uint32)',
          borrower,
          uint32(candidate)
        )
      );
      if (success && data.length >= 64) {
        (uint104 scaledAmount, uint128 normalizedAmountWithdrawn) = abi.decode(
          data,
          (uint104, uint128)
        );
        if (scaledAmount > 0 && normalizedAmountWithdrawn == 0) return uint32(candidate);
      }
      if (candidate == lowerBound) break;
    }
    revert('Could not find an unexecuted canary withdrawal batch');
  }

  function _finalizeMarket(
    Deployments memory deployments,
    address borrower,
    address marketAddress,
    string memory label
  ) internal {
    WildcatMarket market = WildcatMarket(marketAddress);
    if (!market.isClosed()) revert('Canary market must be closed before finalization');
    uint32 expiry = _findQueuedExpiry(marketAddress, borrower);
    _broadcastAsBorrower(deployments, borrower);
    uint256 withdrawn = market.executeWithdrawal(borrower, expiry);
    if (withdrawn == 0) revert('Canary withdrawal returned zero');
    console.log(string.concat(label, ' canary finalized:'), marketAddress);
    console.log(string.concat(label, ' canary withdrawn:'), withdrawn);
  }

  function _deployStandardMarket(
    Deployments memory deployments,
    address borrower,
    address factory,
    address template,
    address asset
  ) internal returns (address market) {
    _broadcastAsBorrower(deployments, borrower);
    (market, ) = IHooksFactory(factory).deployMarketAndHooks(
      template,
      '',
      _marketInputs(asset, 'V2.5 Standard Canary ', 'v25sc'),
      abi.encode(uint128(0), false),
      _marketSalt(borrower, 0),
      address(0),
      0
    );
  }

  function _deployRevolvingMarket(
    Deployments memory deployments,
    address borrower,
    address factory,
    address template,
    address asset
  ) internal returns (address market) {
    _broadcastAsBorrower(deployments, borrower);
    (market, ) = IHooksFactoryRevolving(factory).deployMarketAndHooks(
      template,
      '',
      _marketInputs(asset, 'V2.5 Revolving Canary ', 'v25rc'),
      abi.encode(uint128(0), false),
      abi.encode(uint8(1), uint16(0)),
      _marketSalt(borrower, 0),
      address(0),
      0
    );
  }

  function _latestTemplateMarket(
    address factory,
    address template
  ) internal view returns (address market) {
    address[] memory markets = IHooksFactory(factory).getMarketsForHooksTemplate(template);
    if (markets.length == 0) revert('No canary market found for template');
    return markets[markets.length - 1];
  }

  function run() external {
    string memory ownerMode = _ownerMode();
    if (_isPlanMode(ownerMode)) revert('Canary script is direct mode only');
    string memory phase = vm.envOr('CANARY_PHASE', string(''));
    if (!_sameStrings(phase, 'prepare') && !_sameStrings(phase, 'finalize')) {
      revert("CANARY_PHASE must be 'prepare' or 'finalize'");
    }
    uint256 plasmaMainnetChainId = vm.envOr(
      'PLASMA_MAINNET_CHAIN_ID',
      DEFAULT_PLASMA_MAINNET_CHAIN_ID
    );
    if (block.chainid == ETHEREUM_MAINNET_CHAIN_ID || block.chainid == plasmaMainnetChainId) {
      revert('Canary script refuses mainnet chain ids');
    }

    (Deployments memory deployments, ) = _resolveDeployments();
    address borrower = vm.envOr('BORROWER', address(0));
    if (borrower == address(0)) revert('BORROWER is required');
    address archController = _resolveExisting(
      deployments,
      'WildcatArchController',
      'ARCH_CONTROLLER'
    );
    if (!IWildcatArchController(archController).isRegisteredBorrower(borrower)) {
      revert('BORROWER is not registered on the ArchController');
    }

    string memory standardFactoryLabel = _label('HooksFactory');
    string memory revolvingFactoryLabel = _label('HooksFactoryRevolving');
    string memory openTemplateLabel = _label('OpenTermHooks_initCodeStorage');
    if (
      !deployments.has(standardFactoryLabel) ||
      !deployments.has(revolvingFactoryLabel) ||
      !deployments.has(openTemplateLabel)
    ) revert('Missing finalized v2.5 deployment labels');
    address standardFactory = deployments.get(standardFactoryLabel);
    address revolvingFactory = deployments.get(revolvingFactoryLabel);
    address openTemplate = deployments.get(openTemplateLabel);
    if (
      !IHooksFactory(standardFactory).isHooksTemplate(openTemplate) ||
      !IHooksFactoryRevolving(revolvingFactory).isHooksTemplate(openTemplate)
    ) revert('OpenTermHooks is not registered on both v2.5 factories');

    if (_sameStrings(phase, 'finalize')) {
      _finalizeMarket(
        deployments,
        borrower,
        _latestTemplateMarket(standardFactory, openTemplate),
        'Standard'
      );
      _finalizeMarket(
        deployments,
        borrower,
        _latestTemplateMarket(revolvingFactory, openTemplate),
        'Revolving'
      );
      return;
    }

    address assetAddress = _resolveCanaryAsset(deployments);
    IERC20 asset = IERC20(assetAddress);
    _ensureCanaryBalance(deployments, asset, borrower);
    address standardMarket = _deployStandardMarket(
      deployments,
      borrower,
      standardFactory,
      openTemplate,
      assetAddress
    );
    _prepareMarket(deployments, asset, borrower, standardMarket, 'Standard');

    address revolvingMarket = _deployRevolvingMarket(
      deployments,
      borrower,
      revolvingFactory,
      openTemplate,
      assetAddress
    );
    _prepareMarket(deployments, asset, borrower, revolvingMarket, 'Revolving');
  }
}
