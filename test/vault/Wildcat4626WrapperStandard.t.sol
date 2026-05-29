// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import "erc4626-tests/ERC4626.test.sol";
import "src/vault/Wildcat4626Wrapper.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { WildcatArchController } from "src/WildcatArchController.sol";
import { HooksFactory } from "src/HooksFactory.sol";
import { WildcatMarket } from "src/market/WildcatMarket.sol";
import { WildcatSanctionsSentinel } from "src/WildcatSanctionsSentinel.sol";
import { MockChainalysis } from "../shared/mocks/MockChainalysis.sol";
import { LibStoredInitCode } from "src/libraries/LibStoredInitCode.sol";
import { OpenTermHooks } from "src/access/OpenTermHooks.sol";
import { HooksConfig, LibHooksConfig as HooksConfigLib } from "src/types/HooksConfig.sol";
import { DeployMarketInputs } from "src/interfaces/WildcatStructsAndEnums.sol";

contract Wildcat4626WrapperStandardTest is ERC4626Test {
    using HooksConfigLib for HooksConfig;

    WildcatArchController internal archController;
    HooksFactory internal hooksFactory;
    WildcatSanctionsSentinel internal sanctionsSentinel;
    WildcatMarket internal market;
    OpenTermHooks internal hooks;
    
    address internal hooksTemplate;
    address internal borrower = address(0x123);
    address internal feeRecipient = address(0x456);
    
    function setUp() public override {
        archController = new WildcatArchController();
        MockChainalysis chainalysis = new MockChainalysis();
        sanctionsSentinel = new WildcatSanctionsSentinel(address(archController), address(chainalysis));
        
        bytes memory marketInitCode = type(WildcatMarket).creationCode;
        uint256 initCodeHash = uint256(keccak256(marketInitCode));
        address initCodeStorage = LibStoredInitCode.deployInitCode(marketInitCode);
        
        hooksFactory = new HooksFactory(
            address(archController),
            address(sanctionsSentinel),
            initCodeStorage,
            initCodeHash
        );
        
        archController.registerControllerFactory(address(hooksFactory));
        hooksFactory.registerWithArchController();
        
        hooksTemplate = LibStoredInitCode.deployInitCode(type(OpenTermHooks).creationCode);
        hooksFactory.addHooksTemplate(hooksTemplate, "OpenTermHooks", address(0), address(0), 0, 0);
        
        archController.registerBorrower(borrower);
        
        // Deploy Hooks Instance
        vm.startPrank(borrower);
        address hooksInstance = hooksFactory.deployHooksInstance(hooksTemplate, "");
        vm.stopPrank();
        
        // Deploy Market
        address asset = address(new MockERC20('Token', 'TKN', 18));
        
        DeployMarketInputs memory inputs = DeployMarketInputs({
            asset: asset,
            namePrefix: "Wildcat ",
            symbolPrefix: "WC",
            maxTotalSupply: type(uint128).max,
            annualInterestBips: 1000,
            delinquencyFeeBips: 1000,
            withdrawalBatchDuration: 0,
            reserveRatioBips: 1000,
            delinquencyGracePeriod: 0,
            hooks: HooksConfig.wrap(0).setHooksAddress(hooksInstance)
        });
        
        vm.startPrank(borrower);
        bytes memory hooksData = abi.encode(uint128(0), false);
        
        address marketAddress = hooksFactory.deployMarket(inputs, hooksData, bytes32(uint256(1)), address(0), 0);
        market = WildcatMarket(marketAddress);
        vm.stopPrank();
        
        // Deploy Wrapper
        Wildcat4626Wrapper wrapper = new Wildcat4626Wrapper(address(market));
        
        // Configure ERC4626Test variables
        _underlying_ = address(market);
        _vault_ = address(wrapper);
        _delta_ = 0;
        _vaultMayBeEmpty = true;
        _unlimitedAmount = false;
    }

    function _provideMarketTokens(address user, uint256 amount) internal {
        address underlyingAsset = market.asset();
        MockERC20(underlyingAsset).mint(user, amount);
        
        vm.startPrank(user);
        MockERC20(underlyingAsset).approve(address(market), amount);
        market.deposit(amount);
        vm.stopPrank();
    }

    function setUpVault(Init memory init) public override {
        uint256 maxSupply = type(uint104).max;

        for (uint i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));
            
            uint256 currentSupply = market.totalSupply();
            uint256 available = maxSupply > currentSupply ? maxSupply - currentSupply : 0;

            init.share[i] = bound(init.share[i], 0, available);
            uint256 assetsForShares = init.share[i];
            if (assetsForShares > 0) {
                _provideMarketTokens(user, assetsForShares);
                vm.startPrank(user);
                IERC20(_underlying_).approve(_vault_, assetsForShares);
                try IERC4626(_vault_).deposit(assetsForShares, user) {} catch { }
                vm.stopPrank();
            }
            
            currentSupply = market.totalSupply();
            available = maxSupply > currentSupply ? maxSupply - currentSupply : 0;

            init.asset[i] = bound(init.asset[i], 0, available);
            uint256 assetsHeld = init.asset[i];
            if (assetsHeld > 0) {
                _provideMarketTokens(user, assetsHeld);
            }
        }
        setUpYield(init);
    }

    function setUpYield(Init memory init) public override {
        if (init.yield >= 0) {
            uint gain = uint(init.yield);
            if (gain > 0) {
                uint256 currentSupply = market.totalSupply();
                uint256 maxSupply = type(uint104).max;
                uint256 available = maxSupply > currentSupply ? maxSupply - currentSupply : 0;
                
                gain = bound(gain, 0, available);
                if (gain > 0) {
                    _provideMarketTokens(address(this), gain);
                    IERC20(_underlying_).transfer(_vault_, gain);
                }
            }
        } else {
            vm.assume(init.yield >= 0);
        }
    }

    function _max_deposit(address from) internal override returns (uint) {
        uint256 balance = IERC20(_underlying_).balanceOf(from);
        return balance > type(uint104).max ? type(uint104).max : balance;
    }

    function _max_mint(address from) internal override returns (uint) {
        uint256 balance = IERC20(_underlying_).balanceOf(from);
        uint256 shares = vault_convertToShares(balance);
        return shares > type(uint104).max ? type(uint104).max : shares;
    }
}
