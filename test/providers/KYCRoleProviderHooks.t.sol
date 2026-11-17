// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // KYCRoleProviderHooks.t
//  \ ^ /   Shared KYC enrollment and credential expiry across hooks instances.
//    V
//
//  HOOK FIXTURE
//  setUp()
//  _createHooks(...)
//  _attach(...)
//  _deposit(...)
//
//  HOOK ACCESS
//  test_sharedProvider_EachBorrowerOptsIn()
//  test_removeMember_EachHookKeepsItsOwnCache()
// ═════

import { Test } from 'forge-std/Test.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { KYCRoleProvider } from 'src/providers/KYCRoleProvider.sol';
import { EmptyHooksConfig, Bit_Enabled_Deposit } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';

// ┌─ KYCRoleProviderHooksTest ─────────────────────────────────────────────────
contract KYCRoleProviderHooksTest is Test {
  string internal constant LegacyOpenTemplate =
    'deployments/mainnet/OpenTermHooks-0x4c62b4844c8371f321541e8d564a4b3896cecec7/output.json';
  string internal constant LegacyFixedTemplate =
    'deployments/mainnet/FixedTermHooks-0x7e49caba6fb53cdc70cd98829731a2b8d76dfc36/output.json';

  uint32 internal constant Start = 1_760_000_000;
  address internal constant Lender = address(0xA11CE);
  address internal constant OpenBorrower = address(0xB01);
  address internal constant FixedBorrower = address(0xB02);
  address internal constant OpenMarket = address(0xC01);
  address internal constant FixedMarket = address(0xC02);

  KYCRoleProvider internal provider;
  IHooks internal openHooks;
  IHooks internal fixedHooks;
  bool internal testingV25;

  // ░░▒▒▓▓██ [ HOOK FIXTURE ] ─────────────────────────────────────────────────

  // ┌─ setUp ─────
  function setUp() external {
    vm.warp(Start);

    // the v2.5 run uses the provider bytecode built on the legacy branch.
    string memory legacyArtifact = vm.envOr('KYC_V25_TEST_PROVIDER_ARTIFACT', string(''));
    testingV25 = bytes(legacyArtifact).length != 0;
    if (testingV25) {
      provider = KYCRoleProvider(deployCode(legacyArtifact, abi.encode(address(this))));
      assertEq(address(provider).codehash, keccak256(vm.getDeployedCode(legacyArtifact)));
    } else {
      provider = new KYCRoleProvider(address(this));
    }
    openHooks = _createHooks(
      testingV25 ? 'src/access/OpenTermHooks.sol:OpenTermHooks' : LegacyOpenTemplate, OpenBorrower, OpenMarket, ''
    );
    fixedHooks = _createHooks(
      testingV25 ? 'src/access/FixedTermHooks.sol:FixedTermHooks' : LegacyFixedTemplate,
      FixedBorrower,
      FixedMarket,
      abi.encode(Start + 7 days)
    );
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

  // ┌─ _attach ─────
  function _attach(IHooks hooks, address borrower, uint32 ttl) internal {
    vm.prank(borrower);
    BaseAccessControls(address(hooks)).addRoleProvider(address(provider), ttl);
  }

  // ┌─ _deposit ─────
  function _deposit(IHooks hooks, address market, bytes memory data) internal {
    MarketState memory state;
    vm.prank(market);
    hooks.onDeposit(Lender, 1, state, data);
  }

  // ░░▒▒▓▓██ [ HOOK ACCESS ] ──────────────────────────────────────────────────

  // ┌─ test_sharedProvider_EachBorrowerOptsIn ─────
  function test_sharedProvider_EachBorrowerOptsIn() external {
    provider.addMember(Lender);
    uint32 lookupTime = Start + 2 days;
    vm.warp(lookupTime);
    _attach(openHooks, OpenBorrower, 0);
    vm.expectCall(address(provider), abi.encodeCall(IRoleProvider.getCredential, (Lender)));
    _deposit(openHooks, OpenMarket, '');
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(fixedHooks, FixedMarket, '');

    _attach(fixedHooks, FixedBorrower, 1 days);
    bytes memory data = abi.encode(uint256(7));
    vm.expectCall(address(provider), abi.encodeCall(IRoleProvider.validateCredential, (Lender, data)));
    _deposit(fixedHooks, FixedMarket, abi.encodePacked(address(provider), data));

    LenderStatus memory openStatus = BaseAccessControls(address(openHooks)).getPreviousLenderStatus(Lender);
    LenderStatus memory fixedStatus = BaseAccessControls(address(fixedHooks)).getPreviousLenderStatus(Lender);
    assertEq(openStatus.lastProvider, address(provider));
    assertEq(fixedStatus.lastProvider, address(provider));
    assertEq(openStatus.lastApprovalTimestamp, lookupTime);
    assertEq(fixedStatus.lastApprovalTimestamp, lookupTime);
    assertEq(provider.addedAt(Lender), Start);

    vm.prank(FixedBorrower);
    BaseAccessControls(address(fixedHooks)).removeRoleProvider(address(provider));
    vm.warp(lookupTime + 1);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(fixedHooks, FixedMarket, '');
    _deposit(openHooks, OpenMarket, '');

    if (testingV25) {
      address periodicMarket = address(0xC03);
      IHooks periodicHooks = _createHooks(
        'src/access/PeriodicTermHooks.sol:PeriodicTermHooks',
        OpenBorrower,
        periodicMarket,
        abi.encode(lookupTime + 1 days, 7 days, 1 days)
      );
      _attach(periodicHooks, OpenBorrower, 0);
      _deposit(periodicHooks, periodicMarket, '');
      provider.removeMember(Lender);
      vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
      _deposit(periodicHooks, periodicMarket, '');
    }
  }

  // ┌─ test_removeMember_EachHookKeepsItsOwnCache ─────
  function test_removeMember_EachHookKeepsItsOwnCache() external {
    _attach(openHooks, OpenBorrower, 0);
    _attach(fixedHooks, FixedBorrower, 1 days);
    provider.addMember(Lender);
    _deposit(openHooks, OpenMarket, '');
    _deposit(fixedHooks, FixedMarket, '');
    provider.removeMember(Lender);
    assertEq(provider.getCredential(Lender), 0);

    // at zero TTL, legacy hooks can reuse this approval at the same timestamp. v2.5 checks the provider again.
    if (testingV25) vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, '');
    vm.warp(Start + 1);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(openHooks, OpenMarket, '');
    vm.warp(Start + 1 days);
    _deposit(fixedHooks, FixedMarket, '');
    vm.warp(Start + 1 days + 1);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    _deposit(fixedHooks, FixedMarket, '');
  }
}
