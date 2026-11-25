// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderHooks.t
//  \ ^ /   Shared KYC policies, entitlement gating, and OR-composition on hooks.
//    V
//
//  HOOK FIXTURE
//  setUp()
//  _createHooks(...)
//  _attachViaFactory(...)
//  _deposit(...)
//  _setAttr(...)
//
//  HOOK ACCESS
//  test_unapprovedHooks_FailsClosedUntilAuthorized()
//  test_sharedPolicies_OrCompositionZeroExtraSlots()
//  test_removeAttribute_EachHookKeepsItsOwnCache()
//  test_extraUnapprovedMarket_FreezesFreshCredentials()
//  test_extraUnapprovedMarket_PositiveTTLCacheOutlivesFreeze()
// ═════

import { Test } from 'forge-std/Test.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { IKYCRegistry, KYCAttributeInput } from 'src/providers/IKYCRegistry.sol';
import {
  ClosedMarketClaim,
  IKYCRoleProviderFactory,
  KYCRoleProviderAttachInputs
} from 'src/providers/IKYCRoleProviderFactory.sol';
import { IKYCRoleProvider } from 'src/providers/IKYCRoleProvider.sol';
import { EmptyHooksConfig, Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';

// ┌─ MockHooksFactoryForHooksTest ─────────────────────────────────────────────
contract MockHooksFactoryForHooksTest {
  mapping(address => bool) public isHooksInstance;
  mapping(address => address[]) internal _markets;

  function registerHooks(address hooks, address initialMarket) external {
    isHooksInstance[hooks] = true;
    if (initialMarket != address(0)) _markets[hooks].push(initialMarket);
  }

  function addMarket(address hooks, address market) external {
    _markets[hooks].push(market);
  }

  function getMarketsForHooksInstanceCount(address hooks) external view returns (uint256) {
    return _markets[hooks].length;
  }

  function getMarketsForHooksInstance(
    address hooks,
    uint256 start,
    uint256 end
  )
    external
    view
    returns (address[] memory arr)
  {
    address[] storage list = _markets[hooks];
    if (end > list.length) end = list.length;
    arr = new address[](end - start);
    for (uint256 i; i < arr.length; ++i) {
      arr[i] = list[start + i];
    }
  }
}

// ┌─ KYCRoleProviderHooksTest ─────────────────────────────────────────────────
contract KYCRoleProviderHooksTest is Test {
  string internal constant LegacyOpenTemplate =
    'deployments/mainnet/OpenTermHooks-0x4c62b4844c8371f321541e8d564a4b3896cecec7/output.json';
  string internal constant LegacyFixedTemplate =
    'deployments/mainnet/FixedTermHooks-0x7e49caba6fb53cdc70cd98829731a2b8d76dfc36/output.json';

  uint40 internal constant Start = 1_760_000_000;
  address internal constant NonUSLender = address(0xA11CE);
  address internal constant USAccreditedLender = address(0xB0B);
  address internal constant USRetailLender = address(0xCA201);
  address internal constant SecondNonUSLender = address(0xD00D);
  address internal constant OpenBorrower = address(0xB01);
  address internal constant FixedBorrower = address(0xB02);
  address internal constant OpenMarket = address(0xC01);
  address internal constant FixedMarket = address(0xC02);

  bytes32 internal constant AttrVerified = bytes32(uint256(1));
  bytes32 internal constant AttrAccredited = bytes32(uint256(2));
  bytes32 internal constant AttrUS = bytes32(uint256(3));

  IKYCRegistry internal registry;
  IKYCRoleProviderFactory internal factory;
  MockHooksFactoryForHooksTest internal hooksFactory;
  IKYCRoleProvider internal nonUSProvider;
  IKYCRoleProvider internal usAccreditedProvider;
  IHooks internal openHooks;
  IHooks internal fixedHooks;
  bool internal testingV25;

  // ░░▒▒▓▓██ [ HOOK FIXTURE ] ─────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    vm.warp(Start);
    address[] memory keepers = new address[](1);
    keepers[0] = address(this);

    hooksFactory = new MockHooksFactoryForHooksTest();
    address[] memory factories = new address[](1);
    factories[0] = address(hooksFactory);

    // v2.5 runs deploy canonical IR-built artifacts and verify their runtime code hashes.
    string memory registryArtifact = vm.envOr('KYC_V25_TEST_REGISTRY_ARTIFACT', string(''));
    testingV25 = bytes(registryArtifact).length != 0;
    if (testingV25) {
      string memory factoryArtifact = vm.envString('KYC_V25_TEST_FACTORY_ARTIFACT');
      string memory providerArtifact = vm.envString('KYC_V25_TEST_PROVIDER_ARTIFACT');

      registry = IKYCRegistry(deployCode(registryArtifact, abi.encode(address(this), keepers)));
      assertEq(address(registry).codehash, keccak256(vm.getDeployedCode(registryArtifact)), 'registry runtime');

      factory =
        IKYCRoleProviderFactory(deployCode(factoryArtifact, abi.encode(address(this), address(registry), factories)));
      assertEq(address(factory).codehash, keccak256(vm.getDeployedCode(factoryArtifact)), 'factory runtime');

      bytes32[] memory nonUSReq = new bytes32[](1);
      nonUSReq[0] = AttrVerified;
      bytes32[] memory nonUSForb = new bytes32[](1);
      nonUSForb[0] = AttrUS;
      nonUSProvider = IKYCRoleProvider(factory.deployRoleProvider('Non-US', nonUSReq, nonUSForb));
      assertEq(address(nonUSProvider).codehash, keccak256(vm.getDeployedCode(providerArtifact)), 'provider runtime');
    } else {
      registry = IKYCRegistry(
        deployCode('src/providers/KYCRegistry.sol:KYCRegistry', abi.encode(address(this), keepers))
      );
      factory = IKYCRoleProviderFactory(
        deployCode(
          'src/providers/KYCRoleProviderFactory.sol:KYCRoleProviderFactory',
          abi.encode(address(this), address(registry), factories)
        )
      );

      bytes32[] memory nonUSReq = new bytes32[](1);
      nonUSReq[0] = AttrVerified;
      bytes32[] memory nonUSForb = new bytes32[](1);
      nonUSForb[0] = AttrUS;
      nonUSProvider = IKYCRoleProvider(factory.deployRoleProvider('Non-US', nonUSReq, nonUSForb));
    }

    bytes32[] memory usAccReq = new bytes32[](3);
    usAccReq[0] = AttrVerified;
    usAccReq[1] = AttrAccredited;
    usAccReq[2] = AttrUS;
    usAccreditedProvider = IKYCRoleProvider(factory.deployRoleProvider('US Accredited', usAccReq, new bytes32[](0)));

    factory.setBorrowerAllowance(OpenBorrower, 2);
    factory.setBorrowerAllowance(FixedBorrower, 2);

    openHooks = _createHooks(
      testingV25 ? 'src/access/OpenTermHooks.sol:OpenTermHooks' : LegacyOpenTemplate, OpenBorrower, OpenMarket, ''
    );
    fixedHooks = _createHooks(
      testingV25 ? 'src/access/FixedTermHooks.sol:FixedTermHooks' : LegacyFixedTemplate,
      FixedBorrower,
      FixedMarket,
      abi.encode(Start + 7 days)
    );
    hooksFactory.registerHooks(address(openHooks), OpenMarket);
    hooksFactory.registerHooks(address(fixedHooks), FixedMarket);
  }

  // ┌─ _createHooks ─────
  function _createHooks(
    string memory artifact,
    address borrower,
    address market,
    bytes memory terms
  )
    internal
    returns (IHooks hooks)
  {
    hooks = IHooks(deployCode(artifact, abi.encode(borrower, bytes(''))));
    DeployMarketInputs memory inputs;
    inputs.hooks = EmptyHooksConfig.setHooksAddress(address(hooks)).setFlag(Bit_Enabled_Deposit);
    hooks.onCreateMarket(borrower, market, inputs, terms);
  }

  // ┌─ _attachViaFactory ─────
  function _attachViaFactory(
    IHooks hooks,
    address borrower,
    address provider,
    uint32 ttl,
    uint32 targetCount
  )
    internal
  {
    KYCRoleProviderAttachInputs memory inputs = KYCRoleProviderAttachInputs({
      hooksFactory: address(hooksFactory),
      provider: provider,
      targetApprovedMarketCount: targetCount,
      closedMarketsToReclaim: new ClosedMarketClaim[](0)
    });
    vm.prank(borrower);
    BaseAccessControls(address(hooks)).createRoleProvider(address(factory), ttl, abi.encode(inputs));
  }

  // ┌─ _deposit ─────
  function _deposit(IHooks hooks, address market, address lender, bytes memory data) internal {
    MarketState memory state;
    vm.prank(market);
    hooks.onDeposit(lender, 1, state, data);
  }

  // ┌─ _setAttr ─────
  function _setAttr(address lender, bytes32 attrId) internal {
    registry.setAttribute(KYCAttributeInput(lender, attrId, Start, 0, 2));
  }

  // ░░▒▒▓▓██ [ HOOK ACCESS ] ──────────────────────────────────────────────────

  // ┌─ test_unapprovedHooks_FailsClosedUntilAuthorized ─────
  function test_unapprovedHooks_FailsClosedUntilAuthorized() external {
    _setAttr(NonUSLender, AttrVerified);

    // borrower attaches shared provider directly without authorizing hooks -> still blocked.
    vm.prank(OpenBorrower);
    BaseAccessControls(address(openHooks)).addRoleProvider(address(nonUSProvider), 1 hours);

    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, NonUSLender, '');

    // once authorized, the already-attached provider immediately starts returning credentials.
    vm.prank(OpenBorrower);
    factory.authorizeHooks(address(hooksFactory), address(openHooks), 1);

    vm.expectCall(address(nonUSProvider), abi.encodeCall(IRoleProvider.getCredential, (NonUSLender)));
    _deposit(openHooks, OpenMarket, NonUSLender, '');
  }

  // ┌─ test_sharedPolicies_OrCompositionZeroExtraSlots ─────
  function test_sharedPolicies_OrCompositionZeroExtraSlots() external {
    _setAttr(NonUSLender, AttrVerified);
    _setAttr(USAccreditedLender, AttrVerified);
    _setAttr(USAccreditedLender, AttrUS);
    _setAttr(USAccreditedLender, AttrAccredited);
    _setAttr(USRetailLender, AttrVerified);
    _setAttr(USRetailLender, AttrUS);

    // attach both Reg S (Non-US) and Reg D (US Accredited) to one hooks instance -> 1 slot total.
    _attachViaFactory(openHooks, OpenBorrower, address(nonUSProvider), 0, 1);
    _attachViaFactory(openHooks, OpenBorrower, address(usAccreditedProvider), 0, 1);
    assertEq(factory.usedSlots(OpenBorrower), 1);

    // Non-US and US Accredited both pass via BaseAccessControls' pull-provider loop; US Retail fails.
    _deposit(openHooks, OpenMarket, NonUSLender, '');
    _deposit(openHooks, OpenMarket, USAccreditedLender, '');
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, USRetailLender, '');

    // fixedHooks hasn't opted in yet, so Non-US cannot deposit there.
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(fixedHooks, FixedMarket, NonUSLender, '');

    // explicit validateCredential calldata path on fixedHooks.
    _attachViaFactory(fixedHooks, FixedBorrower, address(nonUSProvider), 1 days, 1);
    bytes memory payload = abi.encode(uint256(7));
    vm.expectCall(address(nonUSProvider), abi.encodeCall(IRoleProvider.validateCredential, (NonUSLender, payload)));
    _deposit(fixedHooks, FixedMarket, NonUSLender, abi.encodePacked(address(nonUSProvider), payload));

    LenderStatus memory status = BaseAccessControls(address(fixedHooks)).getPreviousLenderStatus(NonUSLender);
    assertEq(status.lastProvider, address(nonUSProvider));
    assertEq(status.lastApprovalTimestamp, Start);
  }

  // ┌─ test_removeAttribute_EachHookKeepsItsOwnCache ─────
  function test_removeAttribute_EachHookKeepsItsOwnCache() external {
    _attachViaFactory(openHooks, OpenBorrower, address(nonUSProvider), 0, 1);
    _attachViaFactory(fixedHooks, FixedBorrower, address(nonUSProvider), 1 days, 1);
    _setAttr(NonUSLender, AttrVerified);

    _deposit(openHooks, OpenMarket, NonUSLender, '');
    _deposit(fixedHooks, FixedMarket, NonUSLender, '');

    // adding forbidden US flag revokes Non-US eligibility immediately.
    _setAttr(NonUSLender, AttrUS);
    assertFalse(nonUSProvider.meetsPolicy(NonUSLender));

    // at zero TTL, legacy hooks reuse same-timestamp cache; v2.5 checks the provider again.
    if (testingV25) vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, NonUSLender, '');

    vm.warp(Start + 1);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, NonUSLender, '');

    vm.warp(Start + 1 days);
    _deposit(fixedHooks, FixedMarket, NonUSLender, '');

    vm.warp(Start + 1 days + 1);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(fixedHooks, FixedMarket, NonUSLender, '');
  }

  // ┌─ test_extraUnapprovedMarket_FreezesFreshCredentials ─────
  function test_extraUnapprovedMarket_FreezesFreshCredentials() external {
    _setAttr(NonUSLender, AttrVerified);
    _attachViaFactory(openHooks, OpenBorrower, address(nonUSProvider), 0, 1);
    _deposit(openHooks, OpenMarket, NonUSLender, '');

    // borrower sneaks a 2nd market onto openHooks without spending a 2nd slot.
    hooksFactory.addMarket(address(openHooks), address(0xC99));
    vm.warp(Start + 1);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, NonUSLender, '');

    // authorizing the 2nd market restores fresh credentials immediately.
    vm.prank(OpenBorrower);
    factory.authorizeHooks(address(hooksFactory), address(openHooks), 2);
    _deposit(openHooks, OpenMarket, NonUSLender, '');
    assertEq(factory.usedSlots(OpenBorrower), 2);
  }

  // ┌─ test_extraUnapprovedMarket_PositiveTTLCacheOutlivesFreeze ─────
  function test_extraUnapprovedMarket_PositiveTTLCacheOutlivesFreeze() external {
    _setAttr(NonUSLender, AttrVerified);
    _setAttr(SecondNonUSLender, AttrVerified);

    _attachViaFactory(openHooks, OpenBorrower, address(nonUSProvider), 1 days, 1);
    _deposit(openHooks, OpenMarket, NonUSLender, '');

    // add an unapproved market onto the same hooks instance.
    hooksFactory.addMarket(address(openHooks), address(0xC99));

    // uncached lender is blocked immediately; already-cached lender survives until TTL expiry.
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, SecondNonUSLender, '');

    vm.warp(Start + 1 days);
    _deposit(openHooks, OpenMarket, NonUSLender, '');

    vm.warp(Start + 1 days + 1);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, NonUSLender, '');
  }
}
