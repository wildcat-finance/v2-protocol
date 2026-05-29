// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import 'forge-std/Script.sol';
import { console } from 'forge-std/console.sol';

import { IWildcatArchController } from 'src/interfaces/IWildcatArchController.sol';
import { Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';

interface IERC20 {
  function balanceOf(address account) external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function transfer(address to, uint256 amount) external returns (bool);
}

interface IWildcatMarket is IERC20 {
  function asset() external view returns (address);

  function borrower() external view returns (address);

  function hooks() external view returns (HooksConfig);

  function deposit(uint256 amount) external;
}

contract DeployAndExercise4626 is Script {
  error MissingTestUser();

  struct Config {
    address archController;
    address market;
    address expectedHooks;
    uint256 deployerPrivateKey;
    address deployer;
    uint256 testUserPrivateKey;
    address testUser;
    address underlying;
    uint256 underlyingAmount;
    uint256 wrapAssets;
    uint256 transferShares;
    uint256 redeemShares;
    uint256 testUserEth;
  }

  function run() external {
    Config memory cfg = _loadConfig();
    _preflight(cfg);
    _execute(cfg);
  }

  function _loadConfig() internal returns (Config memory cfg) {
    cfg.archController = vm.envAddress('ARCH_CONTROLLER');
    cfg.market = vm.envAddress('MARKET');

    cfg.expectedHooks = vm.envOr('EXPECTED_HOOKS', address(0));
    cfg.deployerPrivateKey = vm.envOr('PVT_KEY', uint256(0));
    cfg.deployer = vm.envAddress('DEPLOYER_ADDRESS');

    cfg.testUserPrivateKey = vm.envOr('TEST_USER_PRIVATE_KEY', uint256(0));
    cfg.testUser = vm.envOr('TEST_USER_ADDRESS', address(0));
    if (cfg.testUserPrivateKey != 0) {
      cfg.testUser = vm.addr(cfg.testUserPrivateKey);
    }

    cfg.underlying = IWildcatMarket(cfg.market).asset();

    cfg.underlyingAmount = vm.envOr('UNDERLYING_AMOUNT', uint256(10e18));
    cfg.wrapAssets = vm.envOr('WRAP_ASSETS', uint256(0));
    cfg.transferShares = vm.envOr('TRANSFER_SHARES', uint256(0));
    cfg.redeemShares = vm.envOr('REDEEM_SHARES', uint256(0));
    cfg.testUserEth = vm.envOr('TEST_USER_ETH', uint256(0.01 ether));
  }

  function _preflight(Config memory cfg) internal view {
    if (cfg.deployerPrivateKey != 0) {
      address derivedDeployer = vm.addr(cfg.deployerPrivateKey);
      console.log('Deployer:', derivedDeployer);
      require(derivedDeployer == cfg.deployer, 'PVT_KEY does not match DEPLOYER_ADDRESS');
    } else {
      console.log('Deployer (from DEPLOYER_ADDRESS):', cfg.deployer);
    }

    if (cfg.testUser == address(0)) revert MissingTestUser();
    console.log('Test user:', cfg.testUser);

    if (cfg.expectedHooks != address(0)) {
      address actualHooks = IWildcatMarket(cfg.market).hooks().hooksAddress();
      require(actualHooks == cfg.expectedHooks, 'Unexpected market hooks');
    }

    require(
      IWildcatArchController(cfg.archController).isRegisteredMarket(cfg.market),
      'Market is not registered in arch controller'
    );

    console.log('Underlying asset:', cfg.underlying);
    console.log('Market borrower:', IWildcatMarket(cfg.market).borrower());
  }

  function _execute(Config memory cfg) internal {
    _startBroadcast(cfg.deployerPrivateKey);

    uint256 marketBalance = _mintMarketTokens(cfg);
    address wrapperAddr = _deployFactoryAndWrapper(cfg);

    uint256 sharesMinted = _wrapInto4626(cfg, wrapperAddr, marketBalance);
    _transferShares(cfg, wrapperAddr, sharesMinted);
    _exerciseAsTestUser(cfg, wrapperAddr);
    _redeemAllAsDeployer(cfg, wrapperAddr);

    vm.stopBroadcast();

    _logFinalBalances(cfg, wrapperAddr);
  }

  function _mintMarketTokens(Config memory cfg) internal returns (uint256 marketBalance) {
    _ensureUnderlyingBalance(cfg.underlying, cfg.deployer, cfg.underlyingAmount);

    IERC20(cfg.underlying).approve(cfg.market, cfg.underlyingAmount);
    IWildcatMarket(cfg.market).deposit(cfg.underlyingAmount);

    marketBalance = IERC20(cfg.market).balanceOf(cfg.deployer);
    console.log('Market token balance after deposit:', marketBalance);
  }

  function _deployFactoryAndWrapper(Config memory cfg) internal returns (address wrapperAddr) {
    Wildcat4626WrapperFactory factory = new Wildcat4626WrapperFactory(cfg.archController);
    console.log('Wrapper factory:', address(factory));

    wrapperAddr = factory.createWrapper(cfg.market);
    console.log('Wrapper deployed:', wrapperAddr);

    require(Wildcat4626Wrapper(wrapperAddr).asset() == cfg.market, 'Wrapper asset mismatch');
  }

  function _wrapInto4626(
    Config memory cfg,
    address wrapperAddr,
    uint256 marketBalance
  ) internal returns (uint256 sharesMinted) {
    uint256 assetsToWrap = cfg.wrapAssets == 0 ? marketBalance : cfg.wrapAssets;
    require(assetsToWrap != 0, 'No market tokens to wrap');
    require(assetsToWrap <= marketBalance, 'Insufficient market tokens to wrap');

    IERC20(cfg.market).approve(wrapperAddr, assetsToWrap);
    sharesMinted = Wildcat4626Wrapper(wrapperAddr).deposit(assetsToWrap, cfg.deployer);
    console.log('Shares minted:', sharesMinted);
  }

  function _transferShares(
    Config memory cfg,
    address wrapperAddr,
    uint256 sharesMinted
  ) internal {
    uint256 sharesToTransfer = cfg.transferShares == 0 ? sharesMinted / 2 : cfg.transferShares;
    require(sharesToTransfer <= sharesMinted, 'TRANSFER_SHARES too high');

    Wildcat4626Wrapper(wrapperAddr).transfer(cfg.testUser, sharesToTransfer);
    console.log('Transferred shares:', sharesToTransfer);
  }

  function _exerciseAsTestUser(Config memory cfg, address wrapperAddr) internal {
    if (cfg.testUserPrivateKey == 0) return;

    _fundTestUser(cfg.testUser, cfg.testUserEth);
    vm.stopBroadcast();
    vm.startBroadcast(cfg.testUserPrivateKey);

    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(wrapperAddr);
    uint256 userShares = wrapper.balanceOf(cfg.testUser);
    uint256 sharesToRedeem = cfg.redeemShares == 0 ? userShares : cfg.redeemShares;
    require(sharesToRedeem <= userShares, 'REDEEM_SHARES too high');

    uint256 assetsReceived = wrapper.redeem(sharesToRedeem, cfg.testUser, cfg.testUser);
    console.log('Test user redeemed assets:', assetsReceived);

    uint256 remainingUserShares = wrapper.balanceOf(cfg.testUser);
    if (remainingUserShares > 0) {
      wrapper.transfer(cfg.deployer, remainingUserShares);
      console.log('Returned remaining shares:', remainingUserShares);
    }

    vm.stopBroadcast();
    _startBroadcast(cfg.deployerPrivateKey);
  }

  function _redeemAllAsDeployer(Config memory cfg, address wrapperAddr) internal {
    Wildcat4626Wrapper wrapper = Wildcat4626Wrapper(wrapperAddr);
    uint256 remainingDeployerShares = wrapper.balanceOf(cfg.deployer);
    if (remainingDeployerShares == 0) return;

    uint256 assetsReceived = wrapper.redeem(
      remainingDeployerShares,
      cfg.deployer,
      cfg.deployer
    );
    console.log('Deployer redeemed assets:', assetsReceived);
  }

  function _logFinalBalances(Config memory cfg, address wrapperAddr) internal view {
    console.log('Final deployer market token balance:', IERC20(cfg.market).balanceOf(cfg.deployer));
    console.log(
      'Final deployer wrapper share balance:',
      Wildcat4626Wrapper(wrapperAddr).balanceOf(cfg.deployer)
    );
  }

  function _startBroadcast(uint256 deployerPrivateKey) internal {
    if (deployerPrivateKey != 0) {
      vm.startBroadcast(deployerPrivateKey);
    } else {
      vm.startBroadcast();
    }
  }

  function _ensureUnderlyingBalance(address token, address deployer, uint256 minBalance) internal {
    uint256 balance = IERC20(token).balanceOf(deployer);
    if (balance >= minBalance) return;

    (bool ok, ) = token.call(abi.encodeWithSignature('faucet()'));
    if (!ok) {
      balance = IERC20(token).balanceOf(deployer);
      require(balance >= minBalance, 'Insufficient underlying balance and faucet() failed');
    }
  }

  function _fundTestUser(address testUser, uint256 value) internal {
    if (value == 0) return;
    (bool ok, ) = testUser.call{ value: value }('');
    require(ok, 'Failed to fund test user');
    console.log('Funded test user (wei):', value);
  }
}
