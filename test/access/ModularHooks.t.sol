// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../integration/MarketConfigMatrix.sol';
import { ICovenantEvents } from 'src/access/covenants/lib/CovenantEvents.sol';
import { CovenantModuleRegistry } from 'src/access/covenants/CovenantModuleRegistry.sol';
import { ICovenantModule } from 'src/access/covenants/lib/ICovenantModule.sol';
import { MaxDrawnModule } from 'src/access/covenants/modules/MaxDrawnModule.sol';
import { ModularHooks } from 'src/access/ModularHooks.sol';
import { ModularCovenants } from 'src/access/covenants/ModularCovenants.sol';

/// @dev Test-only hostile module: blocks every draw unconditionally.
contract PoisonModule is ICovenantModule {
  error Poisoned();

  function checkOnBorrow(address, uint256, uint256, bytes calldata) external pure {
    revert Poisoned();
  }

  function validateConfig(bytes calldata) external pure {}
}

contract ModularHooksTest is MarketConfigMatrix {
  uint256 internal constant DEPOSIT = 1_000_000e18;

  CovenantModuleRegistry internal registry;
  MaxDrawnModule internal maxDrawn;
  PoisonModule internal poison;
  address internal template;
  ModularHooks internal hooksInstance;
  bytes32 internal waiver;

  function setUp() public override {
    super.setUp();
    registry = new CovenantModuleRegistry(address(archController));
    waiver = registry.WAIVER_HASH();
    maxDrawn = new MaxDrawnModule();
    poison = new PoisonModule();
    _register(address(maxDrawn), 'max drawn');
    _register(address(poison), 'poison');

    template = LibStoredInitCode.deployInitCode(type(ModularHooks).creationCode);
    _registerTemplate(template, 'modular template');
    startPrank(borrower);
    address instance = revolvingFactory.deployHooksInstance(template, '');
    hooksInstance = ModularHooks(instance);
    market = _deployOne(instance, 'Wildcat ', 'wc');
    BaseAccessControls(instance).grantRole(alice, uint32(block.timestamp));
    stopPrank();
    _approveMarket(alice, address(market));
    _approveMarket(borrower, address(market));
    vm.prank(alice);
    market.depositUpTo(DEPOSIT);
  }

  function _register(address module, string memory name) internal asSelf {
    registry.registerModule(module, name);
  }

  function _registerTemplate(address t, string memory name) internal asSelf {
    revolvingFactory.addHooksTemplate(t, name, address(0), address(0), 0, 0);
  }

  function _deployOne(
    address instance,
    string memory namePrefix,
    string memory symbolPrefix
  ) internal returns (WildcatMarket m) {
    HooksDeploymentConfig dc = IHooks(instance).config();
    HooksConfig hc = dc.optionalFlags().setHooksAddress(instance).mergeAllFlags(
      dc.requiredFlags()
    );
    DeployMarketInputs memory inputs = DeployMarketInputs({
      asset: address(asset),
      namePrefix: namePrefix,
      symbolPrefix: symbolPrefix,
      maxTotalSupply: 1_000_000e18,
      annualInterestBips: 1_000,
      delinquencyFeeBips: 1_000,
      withdrawalBatchDuration: 1 days,
      reserveRatioBips: 0,
      delinquencyGracePeriod: 1 days,
      hooks: hc
    });
    m = WildcatMarket(
      revolvingFactory.deployMarket(
        inputs,
        abi.encode(uint128(0), false, address(registry)),
        abi.encode(uint8(1), uint16(200)),
        _nextSalt(borrower),
        address(0),
        0
      )
    );
  }

  function _append(address module, bytes memory config) internal {
    vm.prank(borrower);
    hooksInstance.appendCovenantModule(address(market), module, config, waiver);
  }

  // ------------------------------ registry ------------------------------

  function test_registerModule_CallerNotArchControllerOwner() external {
    vm.prank(alice);
    vm.expectRevert(CovenantModuleRegistry.CallerNotArchControllerOwner.selector);
    registry.registerModule(address(0xBEEF), 'nope');
  }

  function test_registerModule_AppendOnly() external asSelf {
    vm.expectRevert(CovenantModuleRegistry.ModuleAlreadyRegistered.selector);
    registry.registerModule(address(maxDrawn), 'again');
  }

  function test_registerModule_ModuleHasNoCode() external asSelf {
    vm.expectRevert(CovenantModuleRegistry.ModuleHasNoCode.selector);
    registry.registerModule(address(0xBEEF), 'eoa');
  }

  // ------------------------------- append -------------------------------

  function test_appendCovenantModule_CallerNotCovenantBorrower() external {
    vm.prank(alice);
    vm.expectRevert(ICovenantEvents.CallerNotCovenantBorrower.selector);
    hooksInstance.appendCovenantModule(
      address(market),
      address(maxDrawn),
      abi.encode(uint256(1e18)),
      waiver
    );
  }

  function test_appendCovenantModule_WaiverNotAcknowledged() external {
    vm.prank(borrower);
    vm.expectRevert(ICovenantEvents.WaiverNotAcknowledged.selector);
    hooksInstance.appendCovenantModule(
      address(market),
      address(maxDrawn),
      abi.encode(uint256(1e18)),
      bytes32(0)
    );
  }

  function test_appendCovenantModule_ModuleNotRegistered() external {
    MaxDrawnModule rogue = new MaxDrawnModule();
    vm.prank(borrower);
    vm.expectRevert(ICovenantEvents.ModuleNotRegistered.selector);
    hooksInstance.appendCovenantModule(
      address(market),
      address(rogue),
      abi.encode(uint256(1e18)),
      waiver
    );
  }

  function test_appendCovenantModule_NotOwnMarket() external {
    vm.prank(borrower);
    vm.expectRevert(ICovenantEvents.NotOwnMarket.selector);
    hooksInstance.appendCovenantModule(
      address(0xD00D),
      address(maxDrawn),
      abi.encode(uint256(1e18)),
      waiver
    );
  }

  function test_appendCovenantModule_InvalidConfigRejected() external {
    vm.prank(borrower);
    vm.expectRevert(MaxDrawnModule.InvalidCeiling.selector);
    hooksInstance.appendCovenantModule(
      address(market),
      address(maxDrawn),
      abi.encode(uint256(0)),
      waiver
    );
  }

  function test_appendCovenantModule_ModuleAlreadyAppended() external {
    _append(address(maxDrawn), abi.encode(uint256(100_000e18)));
    vm.prank(borrower);
    vm.expectRevert(ICovenantEvents.ModuleAlreadyAppended.selector);
    hooksInstance.appendCovenantModule(
      address(market),
      address(maxDrawn),
      abi.encode(uint256(200_000e18)),
      waiver
    );
  }

  // ------------------------------ dispatch ------------------------------

  function test_onBorrow_NoModulesIsFree() external {
    vm.prank(borrower);
    market.borrow(500_000e18);
  }

  function test_onBorrow_AmendmentTightensLiveMarket() external {
    // the point of the whole design: draw freely, self-bind, next draw gated
    vm.prank(borrower);
    market.borrow(150_000e18);
    _append(address(maxDrawn), abi.encode(uint256(200_000e18)));
    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(
        MaxDrawnModule.DrawnCeilingExceeded.selector,
        250_000e18,
        200_000e18
      )
    );
    market.borrow(100_000e18);
    vm.prank(borrower);
    market.borrow(50_000e18); // exactly at the ceiling passes
  }

  function test_onBorrow_PoisonModuleBricksDrawsOnly() external {
    vm.prank(borrower);
    market.borrow(100_000e18);
    _append(address(poison), '');
    // draws are dead, permanently
    vm.prank(borrower);
    vm.expectRevert(PoisonModule.Poisoned.selector);
    market.borrow(1);
    // but repayment and closure never consult modules: the market unwinds
    vm.startPrank(borrower);
    asset.approve(address(market), type(uint256).max);
    market.repay(100_000e18);
    market.closeMarket();
    vm.stopPrank();
    assertTrue(market.currentState().isClosed);
  }

  function test_onBorrow_ModuleCodehashMismatch_FailsClosed() external {
    _append(address(maxDrawn), abi.encode(uint256(500_000e18)));
    vm.etch(address(maxDrawn), hex'600160005260206000f3');
    vm.prank(borrower);
    vm.expectRevert(ICovenantEvents.ModuleCodehashMismatch.selector);
    market.borrow(1e18);
  }

  function test_getAppendedModules_ReportsPinAndConfig() external {
    _append(address(maxDrawn), abi.encode(uint256(42e18)));
    ModularCovenants.AppendedModule[] memory mods = hooksInstance.getAppendedModules(
      address(market)
    );
    assertEq(mods.length, 1);
    assertEq(mods[0].module, address(maxDrawn));
    assertEq(mods[0].codehash, address(maxDrawn).codehash);
    assertEq(abi.decode(mods[0].config, (uint256)), 42e18);
  }
}
