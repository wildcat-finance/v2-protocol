// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { EmptyHooksConfig, Bit_Enabled_Transfer } from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { RecipientRestrictionHooks } from '../mocks/RecipientRestrictionHooks.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { HookTemplateFixture } from '../shared/HookTemplateFixture.sol';

contract HookExtensionsTest is HookTemplateFixture {
  address internal constant Allowed = address(0xA11CE);
  address internal constant Restricted = address(0xB0B);
  RecipientRestrictionHooks internal target;
  MockRoleProvider internal provider;

  function setUp() external {
    vm.warp(StartTimestamp);
    target = RecipientRestrictionHooks(
      _deployCode(
        'test/mocks/RecipientRestrictionHooks.sol:RecipientRestrictionHooks',
        abi.encode(address(this), MarketA, Restricted)
      )
    );
    provider = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));
    provider.setIsPullProvider(true);
    target.addRoleProvider(address(provider), type(uint32).max);
    _createMarket(target, MarketA, EmptyHooksConfig.setFlag(Bit_Enabled_Transfer), '');
    _createMarket(target, MarketB, EmptyHooksConfig.setFlag(Bit_Enabled_Transfer), '');
  }

  function test_transferRule_AcceptsAndRejectsAfterCredentialProcessingWithRollback() external {
    MarketState memory state;
    vm.prank(MarketA);
    vm.expectRevert(BaseAccessControls.NotApprovedLender.selector);
    target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');

    bytes memory credential = abi.encode('recipient rule');
    provider.approveCredentialData(keccak256(credential), uint32(block.timestamp));
    bytes memory data = abi.encodePacked(address(provider), credential);
    vm.prank(MarketA);
    target.onTransfer(Allowed, Allowed, Allowed, 1, state, data);
    assertTrue(target.isKnownLenderOnMarket(Allowed, MarketA), 'accepted entry');
    assertTrue(target.isMarketTransferRecipientAllowed(MarketA, Allowed), 'accepted view');

    // make the default no-data view accept too, so only the feature can explain this denial.
    provider.setCredential(Restricted, uint32(block.timestamp));
    assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Restricted), 'feature view');
    LenderStatus memory beforeStatus = target.getPreviousLenderStatus(Restricted);
    vm.prank(MarketA);
    vm.expectRevert(RecipientRestrictionHooks.RecipientRestricted.selector);
    target.onTransfer(Allowed, Allowed, Restricted, 1, state, data);
    assertEq(abi.encode(target.getPreviousLenderStatus(Restricted)), abi.encode(beforeStatus));
    assertFalse(target.isKnownLenderOnMarket(Restricted, MarketA), 'entry rolled back');
    assertTrue(target.isKnownLenderOnMarket(Allowed, MarketA), 'other entry retained');
  }

  function test_transferRule_StillChecksKnownRecipientsWithoutCredentials() external {
    MarketState memory state;
    provider.setCredential(Restricted, uint32(block.timestamp));
    vm.prank(MarketA);
    target.onDeposit(Restricted, 1, state, '');
    target.blockFromDeposits(Restricted);
    assertTrue(target.isKnownLenderOnMarket(Restricted, MarketA), 'known before transfer');
    assertFalse(target.getPreviousLenderStatus(Restricted).hasCredential(), 'credential cleared');
    assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Restricted), 'feature view');
    vm.prank(MarketA);
    vm.expectRevert(RecipientRestrictionHooks.RecipientRestricted.selector);
    target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');
    assertTrue(target.isKnownLenderOnMarket(Restricted, MarketA), 'prior known state retained');
  }

  function test_transferRule_StillChecksTheRegisteredWrapper() external {
    MarketState memory state;
    target.blockFromDeposits(Restricted);
    vm.mockCall(MarketA, abi.encodeWithSignature('registeredWrapper()'), abi.encode(Restricted));
    assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Restricted), 'restricted wrapper');
    vm.prank(MarketA);
    vm.expectRevert(RecipientRestrictionHooks.RecipientRestricted.selector);
    target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');

    target.blockFromDeposits(Allowed);
    vm.mockCall(MarketA, abi.encodeWithSignature('registeredWrapper()'), abi.encode(Allowed));
    assertTrue(target.isMarketTransferRecipientAllowed(MarketA, Allowed), 'allowed wrapper');
    vm.prank(MarketA);
    target.onTransfer(Allowed, Allowed, Allowed, 1, state, '');
    assertFalse(target.isKnownLenderOnMarket(Allowed, MarketA), 'wrapper stays unknown');
    assertFalse(
      target.getPreviousLenderStatus(Allowed).hasCredential(),
      'wrapper stays uncredentialed'
    );
    assertFalse(target.isMarketTransferDisabled(MarketA), 'recipient rule keeps global promise');
  }

  function test_transferRule_IsScopedToItsMarket() external {
    MarketState memory state;
    provider.setCredential(Restricted, uint32(block.timestamp));
    assertFalse(target.isMarketTransferRecipientAllowed(MarketA, Restricted), 'restricted market');
    assertTrue(target.isMarketTransferRecipientAllowed(MarketB, Restricted), 'other market');
    vm.prank(MarketB);
    target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');
    assertTrue(target.isKnownLenderOnMarket(Restricted, MarketB), 'other market entry');
    assertFalse(
      target.isKnownLenderOnMarket(Restricted, MarketA),
      'restricted market still unknown'
    );
    vm.prank(MarketA);
    vm.expectRevert(RecipientRestrictionHooks.RecipientRestricted.selector);
    target.onTransfer(Allowed, Allowed, Restricted, 1, state, '');
    assertFalse(target.isKnownLenderOnMarket(Restricted, MarketA), 'cached entry rolled back');
  }
}
