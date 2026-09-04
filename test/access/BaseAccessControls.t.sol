// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IRoleProvider } from 'src/access/IRoleProvider.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { MathUtils } from 'src/libraries/MathUtils.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';
import { NullProviderIndex, RoleProvider } from 'src/types/RoleProvider.sol';
import { BaseAccessControlsHarness } from './BaseAccessControlsHarness.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { MockRoleProviderFactory } from '../mocks/MockRoleProviderFactory.sol';
import { TestKernel } from '../shared/TestKernel.sol';
import { StandardRoleProvider } from '../shared/TestStructs.sol';

using MathUtils for uint256;

contract MockPullProviderResponse {
  uint256 internal immutable _value;
  uint256 internal immutable _length;
  bool internal immutable _shouldRevert;

  constructor(uint256 value, uint256 length, bool shouldRevert) {
    _value = value;
    _length = length;
    _shouldRevert = shouldRevert;
  }

  fallback() external {
    if (_shouldRevert) revert();
    uint256 value = _value;
    uint256 length = _length;
    assembly {
      mstore(0x00, value)
      return(0x00, length)
    }
  }
}

contract BaseAccessControlsTest is TestKernel {
  error AdministratorTransferCallbackFailed();

  uint24 internal numPullProviders;
  uint24 internal numPushProviders;
  StandardRoleProvider[] internal expectedRoleProviders;
  BaseAccessControlsHarness internal baseHooks;
  MockRoleProvider internal mockProvider1;
  MockRoleProvider internal mockProvider2;
  MockRoleProviderFactory internal providerFactory;
  mapping(address account => bool registered) internal registeredBorrowers;
  bool internal failAdministratorTransferCallback;
  address internal callbackPreviousAdministrator;
  address internal callbackNewAdministrator;

  function setUp() external {
    // expired-credential cases need two valid timestamps before the current block
    if (block.timestamp < 3) vm.warp(3);

    mockProvider1 = MockRoleProvider(
      _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    mockProvider2 = MockRoleProvider(
      _deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider')
    );
    providerFactory = MockRoleProviderFactory(
      _deployCode('test/mocks/MockRoleProviderFactory.sol:MockRoleProviderFactory')
    );
    registeredBorrowers[address(this)] = true;
    NameAndProviderInputs memory inputs;
    baseHooks = BaseAccessControlsHarness(
      _deployCode(
        'test/access/BaseAccessControlsHarness.sol:BaseAccessControlsHarness',
        abi.encode(address(this), inputs)
      )
    );
  }

  function archController() external view returns (address) {
    return address(this);
  }

  function isRegisteredBorrower(address account) external view returns (bool) {
    return registeredBorrowers[account];
  }

  function onHooksAdministratorTransferred(
    address previousAdministrator,
    address newAdministrator
  ) external {
    if (failAdministratorTransferCallback) revert AdministratorTransferCallbackFailed();
    assertEq(msg.sender, address(baseHooks), 'callback caller');
    callbackPreviousAdministrator = previousAdministrator;
    callbackNewAdministrator = newAdministrator;
  }

  function _registerAdministrator(address account) internal {
    registeredBorrowers[account] = true;
  }

  function _transferAdministrator(address newAdministrator) internal {
    _registerAdministrator(newAdministrator);
    baseHooks.requestAdministratorTransfer(newAdministrator);
    vm.prank(newAdministrator);
    baseHooks.acceptAdministratorTransfer();
  }

  // ========================================================================== //
  //                              State validation                              //
  // ========================================================================== //

  function _addExpectedProvider(
    MockRoleProvider mockProvider,
    uint32 timeToLive,
    bool isPullProvider
  ) internal returns (StandardRoleProvider storage) {
    if (address(mockProvider) != address(this) && address(mockProvider).code.length > 0) {
      mockProvider.setIsPullProvider(isPullProvider);
    }
    uint24 pullProviderIndex = isPullProvider ? numPullProviders++ : NullProviderIndex;
    uint24 pushProviderIndex = isPullProvider ? NullProviderIndex : numPushProviders++;
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider),
        timeToLive: timeToLive,
        pullProviderIndex: pullProviderIndex,
        pushProviderIndex: pushProviderIndex
      })
    );
    return expectedRoleProviders[expectedRoleProviders.length - 1];
  }

  function _validateRoleProviders() internal view {
    RoleProvider[] memory pullProviders = baseHooks.getPullProviders();
    RoleProvider[] memory pushProviders = baseHooks.getPushProviders();
    uint256 pullIndex;
    uint256 pushIndex;
    for (uint i; i < expectedRoleProviders.length; i++) {
      if (expectedRoleProviders[i].pullProviderIndex != NullProviderIndex) {
        assertTrue(pullIndex < pullProviders.length, 'missing pull provider');
        assertEq(pullProviders[pullIndex++], expectedRoleProviders[i], 'pull provider');
      }
      if (expectedRoleProviders[i].pushProviderIndex != NullProviderIndex) {
        assertTrue(pushIndex < pushProviders.length, 'missing push provider');
        assertEq(pushProviders[pushIndex++], expectedRoleProviders[i], 'push provider');
      }
      address providerAddress = expectedRoleProviders[i].providerAddress;
      // Check _roleProviders[provider] matches expected provider
      RoleProvider provider = baseHooks.getRoleProvider(providerAddress);
      assertEq(provider, expectedRoleProviders[i], 'provider mapping');
    }
    assertEq(pullIndex, pullProviders.length, 'pullProviders.length');
    assertEq(pushIndex, pushProviders.length, 'pushProviders.length');
  }

  function _expectRoleProviderAdded(
    address providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  ) internal {
    vm.expectEmit();
    emit BaseAccessControls.RoleProviderAdded(
      baseHooks.administrator(),
      providerAddress,
      timeToLive,
      pullProviderIndex,
      pushProviderIndex
    );
  }

  function _expectRoleProviderUpdated(
    address providerAddress,
    uint32 timeToLive,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  ) internal {
    RoleProvider previousProvider = baseHooks.getRoleProvider(providerAddress);
    vm.expectEmit();
    emit BaseAccessControls.RoleProviderUpdated(
      baseHooks.administrator(),
      providerAddress,
      previousProvider.timeToLive(),
      timeToLive,
      previousProvider.pullProviderIndex(),
      pullProviderIndex,
      previousProvider.pushProviderIndex(),
      pushProviderIndex
    );
  }

  function _expectRoleProviderRemoved(
    address providerAddress,
    uint24 pullProviderIndex,
    uint24 pushProviderIndex
  ) internal {
    RoleProvider provider = baseHooks.getRoleProvider(providerAddress);
    vm.expectEmit();
    emit BaseAccessControls.RoleProviderRemoved(
      baseHooks.administrator(),
      providerAddress,
      provider.timeToLive(),
      pullProviderIndex,
      pushProviderIndex
    );
  }

  function _expectAccountAccessGranted(
    address providerAddress,
    address accountAddress,
    uint32 credentialTimestamp
  ) internal {
    vm.expectEmit();
    emit BaseAccessControls.AccountAccessGranted(
      providerAddress,
      accountAddress,
      providerAddress,
      credentialTimestamp
    );
  }

  function _validTimestamp(uint32 timestamp, uint256 timeToLive) internal view returns (uint32) {
    uint256 minTimestamp = block.timestamp.satSub(timeToLive);
    if (minTimestamp == 0) minTimestamp = 1;
    return uint32(bound(timestamp, minTimestamp, block.timestamp));
  }

  function assertEq(
    RoleProvider actual,
    StandardRoleProvider memory expected,
    string memory message
  ) internal pure {
    assertEq(actual.providerAddress(), expected.providerAddress, message);
    assertEq(actual.timeToLive(), expected.timeToLive, message);
    assertEq(actual.pullProviderIndex(), expected.pullProviderIndex, message);
    assertEq(actual.pushProviderIndex(), expected.pushProviderIndex, message);
  }

  function assertEq(
    LenderStatus memory actual,
    LenderStatus memory expected,
    string memory message
  ) internal pure {
    assertEq(keccak256(abi.encode(actual)), keccak256(abi.encode(expected)), message);
  }

  // ========================================================================== //
  //                         Administrator transfer                             //
  // ========================================================================== //

  function test_constructor_DoesNotAddAdministratorAsProvider() external {
    assertTrue(baseHooks.getRoleProvider(address(this)).isNull(), 'administrator provider');
    assertEq(baseHooks.getPullProviders().length, 0, 'pull providers');
    assertEq(baseHooks.getPushProviders().length, 0, 'push providers');

    vm.expectRevert(BaseAccessControls.ProviderNotFound.selector);
    baseHooks.grantRole(address(1), uint32(block.timestamp));
  }

  function test_requestAdministratorTransfer() external {
    address newAdministrator = address(0xA11CE);
    _registerAdministrator(newAdministrator);

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AdministratorTransferRequested(
      address(this),
      address(0),
      newAdministrator
    );
    baseHooks.requestAdministratorTransfer(newAdministrator);

    assertEq(baseHooks.administrator(), address(this), 'administrator');
    assertEq(baseHooks.pendingAdministrator(), newAdministrator, 'pending administrator');
  }

  function test_requestAdministratorTransfer_ReplacesPendingAdministrator() external {
    address firstAdministrator = address(0xA11CE);
    address secondAdministrator = address(0xB0B);
    _registerAdministrator(firstAdministrator);
    _registerAdministrator(secondAdministrator);
    baseHooks.requestAdministratorTransfer(firstAdministrator);

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AdministratorTransferRequested(
      address(this),
      firstAdministrator,
      secondAdministrator
    );
    baseHooks.requestAdministratorTransfer(secondAdministrator);

    assertEq(baseHooks.pendingAdministrator(), secondAdministrator, 'pending administrator');
  }

  function test_requestAdministratorTransfer_InvalidTargets() external {
    vm.expectRevert(BaseAccessControls.InvalidAdministratorTransferTarget.selector);
    baseHooks.requestAdministratorTransfer(address(0));

    vm.expectRevert(BaseAccessControls.InvalidAdministratorTransferTarget.selector);
    baseHooks.requestAdministratorTransfer(address(this));

    vm.expectRevert(BaseAccessControls.AdministratorNotRegistered.selector);
    baseHooks.requestAdministratorTransfer(address(0xBAD));
  }

  function test_requestAdministratorTransfer_CallerNotAdministrator() external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.requestAdministratorTransfer(address(2));
  }

  function test_cancelAdministratorTransfer() external {
    address newAdministrator = address(0xA11CE);
    _registerAdministrator(newAdministrator);
    baseHooks.requestAdministratorTransfer(newAdministrator);

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AdministratorTransferCancelled(address(this), newAdministrator);
    baseHooks.cancelAdministratorTransfer();

    assertEq(baseHooks.pendingAdministrator(), address(0), 'pending administrator');
  }

  function test_cancelAdministratorTransfer_NoPendingTransfer() external {
    vm.expectRevert(BaseAccessControls.NoPendingAdministratorTransfer.selector);
    baseHooks.cancelAdministratorTransfer();
  }

  function test_cancelAdministratorTransfer_CallerNotAdministrator() external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.cancelAdministratorTransfer();
  }

  function test_acceptAdministratorTransfer() external {
    address newAdministrator = address(0xA11CE);
    _registerAdministrator(newAdministrator);
    baseHooks.requestAdministratorTransfer(newAdministrator);

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AdministratorTransferred(address(this), newAdministrator);
    vm.prank(newAdministrator);
    baseHooks.acceptAdministratorTransfer();

    assertEq(baseHooks.administrator(), newAdministrator, 'administrator');
    assertEq(baseHooks.borrower(), newAdministrator, 'borrower alias');
    assertEq(baseHooks.pendingAdministrator(), address(0), 'pending administrator');
    assertEq(callbackPreviousAdministrator, address(this), 'callback previous administrator');
    assertEq(callbackNewAdministrator, newAdministrator, 'callback new administrator');
  }

  function test_acceptAdministratorTransfer_PendingAdministratorHasNoAuthority() external {
    address newAdministrator = address(0xA11CE);
    _registerAdministrator(newAdministrator);
    baseHooks.requestAdministratorTransfer(newAdministrator);

    vm.prank(newAdministrator);
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.setName('too early');
  }

  function test_acceptAdministratorTransfer_OnlyPendingAdministratorCanAccept() external {
    address newAdministrator = address(0xA11CE);
    _registerAdministrator(newAdministrator);
    baseHooks.requestAdministratorTransfer(newAdministrator);

    vm.prank(address(0xB0B));
    vm.expectRevert(BaseAccessControls.NotPendingAdministrator.selector);
    baseHooks.acceptAdministratorTransfer();
  }

  function test_acceptAdministratorTransfer_RevalidatesRegistration() external {
    address newAdministrator = address(0xA11CE);
    _registerAdministrator(newAdministrator);
    baseHooks.requestAdministratorTransfer(newAdministrator);
    registeredBorrowers[newAdministrator] = false;

    vm.prank(newAdministrator);
    vm.expectRevert(BaseAccessControls.AdministratorNotRegistered.selector);
    baseHooks.acceptAdministratorTransfer();

    assertEq(baseHooks.administrator(), address(this), 'administrator');
    assertEq(baseHooks.pendingAdministrator(), newAdministrator, 'pending administrator');
  }

  function test_acceptAdministratorTransfer_CallbackFailureRevertsTransfer() external {
    address newAdministrator = address(0xA11CE);
    _registerAdministrator(newAdministrator);
    baseHooks.requestAdministratorTransfer(newAdministrator);
    failAdministratorTransferCallback = true;

    vm.prank(newAdministrator);
    vm.expectRevert(AdministratorTransferCallbackFailed.selector);
    baseHooks.acceptAdministratorTransfer();

    assertEq(baseHooks.administrator(), address(this), 'administrator');
    assertEq(baseHooks.pendingAdministrator(), newAdministrator, 'pending administrator');
  }

  function test_acceptAdministratorTransfer_PreservesAccessState() external {
    address lender = address(0x1EAD);
    address blockedLender = address(0xB10C);
    address market = address(0xCAFE);
    address newAdministrator = address(0xA11CE);
    mockProvider1.setIsPullProvider(true);
    mockProvider2.setIsPullProvider(false);
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);
    baseHooks.addRoleProvider(address(mockProvider2), 30 days);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(lender, uint32(block.timestamp));
    baseHooks.blockFromDeposits(blockedLender);
    baseHooks.setIsKnownLender(lender, market, true);

    bytes32 pullProvidersBefore = keccak256(abi.encode(baseHooks.getPullProviders()));
    bytes32 pushProvidersBefore = keccak256(abi.encode(baseHooks.getPushProviders()));
    RoleProvider pullProviderBefore = baseHooks.getRoleProvider(address(mockProvider1));
    RoleProvider pushProviderBefore = baseHooks.getRoleProvider(address(mockProvider2));
    LenderStatus memory statusBefore = baseHooks.getPreviousLenderStatus(lender);
    LenderStatus memory blockedStatusBefore = baseHooks.getPreviousLenderStatus(blockedLender);
    _transferAdministrator(newAdministrator);

    assertEq(
      RoleProvider.unwrap(baseHooks.getRoleProvider(address(mockProvider1))),
      RoleProvider.unwrap(pullProviderBefore),
      'pull provider'
    );
    assertEq(
      RoleProvider.unwrap(baseHooks.getRoleProvider(address(mockProvider2))),
      RoleProvider.unwrap(pushProviderBefore),
      'push provider'
    );
    assertEq(
      keccak256(abi.encode(baseHooks.getPullProviders())),
      pullProvidersBefore,
      'pull providers'
    );
    assertEq(
      keccak256(abi.encode(baseHooks.getPushProviders())),
      pushProvidersBefore,
      'push providers'
    );
    assertEq(baseHooks.getPreviousLenderStatus(lender), statusBefore, 'lender status');
    assertEq(
      baseHooks.getPreviousLenderStatus(blockedLender),
      blockedStatusBefore,
      'blocked lender status'
    );
    assertTrue(baseHooks.isKnownLenderOnMarket(lender, market), 'known lender');

    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.setName('old administrator');

    _registerAdministrator(address(0xB0B));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.requestAdministratorTransfer(address(0xB0B));

    vm.prank(newAdministrator);
    baseHooks.setName('new administrator');
    assertEq(baseHooks.name(), 'new administrator', 'name');

    vm.prank(newAdministrator);
    baseHooks.requestAdministratorTransfer(address(0xB0B));
    assertEq(baseHooks.pendingAdministrator(), address(0xB0B), 'next pending administrator');
  }

  function test_grantRole_PreservesDepositBlock() external {
    address lender = address(0x1EAD);
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);
    baseHooks.blockFromDeposits(lender);

    vm.prank(address(mockProvider1));
    baseHooks.grantRole(lender, uint32(block.timestamp));

    LenderStatus memory status = baseHooks.getPreviousLenderStatus(lender);
    assertTrue(status.isBlockedFromDeposits, 'deposit block');
    assertEq(status.lastProvider, address(mockProvider1), 'last provider');
  }

  function test_refreshRole_PreservesDepositBlock() external {
    address lender = address(0x1EAD);
    mockProvider1.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    baseHooks.blockFromDeposits(lender);
    mockProvider1.setCredential(lender, uint32(block.timestamp));

    baseHooks.tryValidateAccess(lender, '');

    LenderStatus memory status = baseHooks.getPreviousLenderStatus(lender);
    assertTrue(status.isBlockedFromDeposits, 'deposit block');
    assertEq(status.lastProvider, address(mockProvider1), 'last provider');
  }

  // ========================================================================== //
  //                                   setName                                  //
  // ========================================================================== //

  function test_setName_CallerNotAdministrator() external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.setName('');
  }

  function test_setName() external {
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.NameUpdated(address(this), baseHooks.name(), 'New Name');
    baseHooks.setName('New Name');
    assertEq(baseHooks.name(), 'New Name', 'name');
  }

  // ========================================================================== //
  //                          Role provider management                          //
  // ========================================================================== //

  function test_createRoleProvider_CallerNotAdministrator() external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.createRoleProvider(address(1), 0, '');
  }

  function test_createRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    bytes32 salt = bytes32(uint256(1));
    bytes memory factoryInput = abi.encode(salt, isPullProvider);
    address expectedProviderAddress = providerFactory.computeProviderAddress(salt);
    _addExpectedProvider(MockRoleProvider(expectedProviderAddress), timeToLive, isPullProvider);
    _expectRoleProviderAdded(
      expectedProviderAddress,
      timeToLive,
      isPullProvider ? 0 : NullProviderIndex,
      isPullProvider ? NullProviderIndex : 0
    );
    baseHooks.createRoleProvider(address(providerFactory), timeToLive, factoryInput);
  }

  function test_createRoleProvider_CreateRoleProviderFailed(
    bool isPullProvider,
    uint32 timeToLive
  ) external {
    bytes32 salt = bytes32(uint256(1));
    bytes memory factoryInput = abi.encode(salt, isPullProvider);
    providerFactory.setNextProviderAddress(address(0));
    vm.expectRevert(BaseAccessControls.CreateRoleProviderFailed.selector);
    baseHooks.createRoleProvider(address(providerFactory), timeToLive, factoryInput);
  }

  function test_addRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    mockProvider1.setIsPullProvider(isPullProvider);

    uint24 pullProviderIndex = isPullProvider ? 0 : NullProviderIndex;
    uint24 pushProviderIndex = isPullProvider ? NullProviderIndex : 0;
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider1),
        timeToLive: timeToLive,
        pullProviderIndex: pullProviderIndex,
        pushProviderIndex: pushProviderIndex
      })
    );

    _expectRoleProviderAdded(
      address(mockProvider1),
      timeToLive,
      pullProviderIndex,
      pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    _validateRoleProviders();
  }

  function test_addRoleProvider_CallerNotAdministrator() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.addRoleProvider(address(2), 1);
  }

  function test_addRoleProvider_NonInterfaceProviderIsPushProvider(uint32 timeToLive) external {
    address pushProvider = address(2);
    address account = address(3);
    uint32 timestamp = uint32(block.timestamp);
    StandardRoleProvider storage provider = _addExpectedProvider(
      MockRoleProvider(pushProvider),
      timeToLive,
      false
    );
    _expectRoleProviderAdded(
      pushProvider,
      timeToLive,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(pushProvider, timeToLive);
    _validateRoleProviders();

    _expectAccountAccessGranted(pushProvider, account, timestamp);
    vm.prank(pushProvider);
    baseHooks.grantRole(account, timestamp);
  }

  function test_addRoleProvider_onlyCleanBooleanTrueIsPullProvider() external {
    MockPullProviderResponse[6] memory providers = [
      new MockPullProviderResponse(1, 0x20, false),
      new MockPullProviderResponse(0, 0x20, false),
      new MockPullProviderResponse(2, 0x20, false),
      new MockPullProviderResponse(1, 0x1f, false),
      new MockPullProviderResponse(1, 0x40, false),
      new MockPullProviderResponse(1, 0x20, true)
    ];
    bool[6] memory expectedPull = [true, false, false, false, true, false];

    for (uint256 i; i < providers.length; i++) {
      address providerAddress = address(providers[i]);
      baseHooks.addRoleProvider(providerAddress, 1);
      RoleProvider provider = baseHooks.getRoleProvider(providerAddress);
      assertEq(
        provider.pullProviderIndex() != NullProviderIndex,
        expectedPull[i],
        'pull provider classification'
      );
    }
  }

  function test_addRoleProvider_updateTimeToLive(uint32 ttl1, uint32 ttl2) external {
    StandardRoleProvider storage provider = _addExpectedProvider(mockProvider1, ttl1, true);
    _expectRoleProviderAdded(
      address(mockProvider1),
      ttl1,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl1);

    // Validate the initial state
    _validateRoleProviders();

    // Update the TTL using `addRoleProvider`
    provider.timeToLive = ttl2;
    _expectRoleProviderUpdated(
      address(mockProvider1),
      ttl2,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl2);

    // Validate the updated state
    _validateRoleProviders();
  }

  function test_addRoleProvider_updateTimeToLive2(uint32 ttl1, uint32 ttl2) external {
    StandardRoleProvider storage provider = _addExpectedProvider(mockProvider1, ttl1, false);
    _expectRoleProviderAdded(
      address(mockProvider1),
      ttl1,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl1);

    // Validate the initial state
    _validateRoleProviders();

    // Update the TTL using `addRoleProvider`
    provider.timeToLive = ttl2;
    _expectRoleProviderUpdated(
      address(mockProvider1),
      ttl2,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl2);

    // Validate the updated state
    _validateRoleProviders();
  }

  function test_addRoleProvider_updateTimeToLive(
    bool isPullProvider,
    uint32 ttl1,
    uint32 ttl2
  ) external {
    StandardRoleProvider storage provider = _addExpectedProvider(
      mockProvider1,
      ttl1,
      isPullProvider
    );
    _expectRoleProviderAdded(
      address(mockProvider1),
      ttl1,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl1);

    // Validate the initial state
    _validateRoleProviders();

    // Update the TTL using `addRoleProvider`
    provider.timeToLive = ttl2;
    _expectRoleProviderUpdated(
      address(mockProvider1),
      ttl2,
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.addRoleProvider(address(mockProvider1), ttl2);

    // Validate the updated state
    _validateRoleProviders();
  }

  function test_removeRoleProvider(bool isPullProvider, uint32 timeToLive) external {
    StandardRoleProvider storage provider = _addExpectedProvider(
      mockProvider1,
      timeToLive,
      isPullProvider
    );

    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    _expectRoleProviderRemoved(
      address(mockProvider1),
      provider.pullProviderIndex,
      provider.pushProviderIndex
    );
    baseHooks.removeRoleProvider(address(mockProvider1));
    expectedRoleProviders.pop();

    _validateRoleProviders();
  }

  function test_removeRoleProvider_CallerNotAdministrator() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.removeRoleProvider(address(mockProvider1));
  }

  function test_removeRoleProvider_ProviderNotFound() external {
    vm.expectRevert(BaseAccessControls.ProviderNotFound.selector);
    baseHooks.removeRoleProvider(address(2));
  }

  /// @dev Remove the last pull provider. Should not cause any changes
  ///      to other pull providers.
  function test_removeRoleProvider_LastPullProvider() external {
    mockProvider1.setIsPullProvider(true);
    mockProvider2.setIsPullProvider(true);
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider1),
        timeToLive: 1,
        pullProviderIndex: 0,
        pushProviderIndex: NullProviderIndex
      })
    );
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    baseHooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider2), 1, NullProviderIndex);
    baseHooks.removeRoleProvider(address(mockProvider2));
    _validateRoleProviders();
  }

  /// @dev Remove a pull provider that is not the last pull provider.
  ///      Should cause the last pull provider to be moved to the
  ///      removed provider's index
  function test_removeRoleProvider_NotLastPullProvider() external {
    mockProvider1.setIsPullProvider(true);
    mockProvider2.setIsPullProvider(true);
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider2),
        timeToLive: 1,
        pullProviderIndex: 0,
        pushProviderIndex: NullProviderIndex
      })
    );

    // Add two pull providers
    _expectRoleProviderAdded(address(mockProvider1), 1, 0, NullProviderIndex);
    baseHooks.addRoleProvider(address(mockProvider1), 1);

    _expectRoleProviderAdded(address(mockProvider2), 1, 1, NullProviderIndex);
    baseHooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider1), 0, NullProviderIndex);
    _expectRoleProviderUpdated(address(mockProvider2), 1, 0, NullProviderIndex);

    baseHooks.removeRoleProvider(address(mockProvider1));
    _validateRoleProviders();
  }

  /// @dev Remove a push provider that is not the last push provider.
  ///      Should cause the last push provider to be moved to the
  ///      removed provider's index
  function test_removeRoleProvider_NotLastPushProvider() external {
    mockProvider1.setIsPullProvider(false);
    mockProvider2.setIsPullProvider(false);
    expectedRoleProviders.push(
      StandardRoleProvider({
        providerAddress: address(mockProvider2),
        timeToLive: 1,
        pullProviderIndex: NullProviderIndex,
        pushProviderIndex: 0
      })
    );

    // Add two pull providers
    _expectRoleProviderAdded(address(mockProvider1), 1, NullProviderIndex, 0);
    baseHooks.addRoleProvider(address(mockProvider1), 1);

    _expectRoleProviderAdded(address(mockProvider2), 1, NullProviderIndex, 1);
    baseHooks.addRoleProvider(address(mockProvider2), 1);

    _expectRoleProviderRemoved(address(mockProvider1), NullProviderIndex, 0);
    _expectRoleProviderUpdated(address(mockProvider2), 1, NullProviderIndex, 0);

    baseHooks.removeRoleProvider(address(mockProvider1));
    _validateRoleProviders();
  }

  // ========================================================================== //
  //                                  grantRole                                 //
  // ========================================================================== //

  /// @dev `grantRole` reverts if the provider is not found.
  function test_grantRole_ProviderNotFound(uint32 timestamp) external {
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.ProviderNotFound.selector);
    baseHooks.grantRole(address(2), timestamp);
  }

  /// @dev `grantRole` reverts if the timestamp + TTL is less than the current time.
  function test_grantRole_GrantedCredentialExpired(
    address account,
    bool isPullProvider,
    uint32 timeToLive,
    uint32 timestamp
  ) external {
    uint256 maxExpiry = block.timestamp - 1;
    timeToLive = uint32(bound(timeToLive, 0, maxExpiry - 1));
    timestamp = uint32(bound(timestamp, 1, maxExpiry - timeToLive));
    _addExpectedProvider(mockProvider1, timeToLive, isPullProvider);
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    vm.prank(address(mockProvider1));
    vm.expectRevert(BaseAccessControls.GrantedCredentialExpired.selector);
    baseHooks.grantRole(account, timestamp);
  }

  function test_grantRole_InvalidCredentialTimestamp_Zero(
    address account,
    bool isPullProvider,
    uint32 timeToLive
  ) external {
    _addExpectedProvider(mockProvider1, timeToLive, isPullProvider);
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    vm.prank(address(mockProvider1));
    vm.expectRevert(BaseAccessControls.InvalidCredentialTimestamp.selector);
    baseHooks.grantRole(account, 0);
  }

  function test_grantRole_InvalidCredentialTimestamp_Future(
    address account,
    bool isPullProvider,
    uint32 timeToLive
  ) external {
    _addExpectedProvider(mockProvider1, timeToLive, isPullProvider);
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);

    vm.prank(address(mockProvider1));
    vm.expectRevert(BaseAccessControls.InvalidCredentialTimestamp.selector);
    baseHooks.grantRole(account, uint32(block.timestamp + 1));
  }

  function test_grantRole(
    address account,
    bool isPullProvider,
    uint32 timeToLive,
    uint32 timestamp
  ) external {
    timestamp = _validTimestamp(timestamp, timeToLive);
    _addExpectedProvider(mockProvider1, timeToLive, isPullProvider);
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive);
    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);
  }

  /// @dev Provider can replace credentials with an earlier expiry
  function test_grantRole_laterExpiry(
    address account,
    uint32 timeToLive1,
    uint32 timeToLive2,
    uint32 timestamp
  ) external {
    timeToLive1 = uint32(bound(timeToLive1, 0, type(uint32).max - 2));
    timeToLive2 = uint32(bound(timeToLive2, timeToLive1 + 1, type(uint32).max));
    // Keep provider 1's expiry below max uint32 so provider 2 can extend it.
    uint256 minTimestamp = block.timestamp.satSub(timeToLive1);
    if (minTimestamp == 0) minTimestamp = 1;
    uint256 maxTimestamp = uint(type(uint32).max).satSub(timeToLive1) - 1;
    if (maxTimestamp > block.timestamp) maxTimestamp = block.timestamp;
    timestamp = uint32(bound(timestamp, minTimestamp, maxTimestamp));
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive1);
    baseHooks.addRoleProvider(address(mockProvider2), timeToLive2);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);

    _expectAccountAccessGranted(address(mockProvider2), account, timestamp);
    vm.prank(address(mockProvider2));
    baseHooks.grantRole(account, timestamp);
  }

  /// @dev Provider can replace credentials if the provider has been removed
  function test_grantRole_oldProviderRemoved(
    address account,
    uint32 timeToLive1,
    uint32 timeToLive2,
    uint32 timestamp
  ) external {
    // Keep the second TTL shorter so removing provider 1 is the reason replacement works.
    timeToLive2 = uint32(bound(timeToLive2, 0, type(uint32).max - 2));
    timeToLive1 = uint32(bound(timeToLive1, timeToLive2 + 1, type(uint32).max));
    // Make sure the timestamp won't result in an expired credential
    uint256 minTimestamp = block.timestamp.satSub(timeToLive2);
    if (minTimestamp == 0) minTimestamp = 1;
    uint256 maxTimestamp = uint(type(uint32).max).satSub(timeToLive2) - 1;
    if (maxTimestamp > block.timestamp) maxTimestamp = block.timestamp;
    timestamp = uint32(bound(timestamp, minTimestamp, maxTimestamp));
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive1);
    baseHooks.addRoleProvider(address(mockProvider2), timeToLive2);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);

    _expectRoleProviderRemoved(address(mockProvider1), NullProviderIndex, 0);
    _expectRoleProviderUpdated(address(mockProvider2), timeToLive2, NullProviderIndex, 0);
    baseHooks.removeRoleProvider(address(mockProvider1));

    _expectAccountAccessGranted(address(mockProvider2), account, timestamp);
    vm.prank(address(mockProvider2));
    baseHooks.grantRole(account, timestamp);
  }

  /// @dev Provider can not replace a credential from another provider unless it has
  ///      a greater expiry.
  function test_grantRole_ProviderCanNotReplaceCredential(
    address account,
    uint32 timeToLive1,
    uint32 timeToLive2,
    uint32 timestamp
  ) external {
    timeToLive1 = uint32(bound(timeToLive1, 0, type(uint32).max - 1));
    timeToLive2 = uint32(bound(timeToLive2, timeToLive1 + 1, type(uint32).max));
    uint256 minTimestamp = block.timestamp.satSub(timeToLive1);
    if (minTimestamp == 0) minTimestamp = 1;
    timestamp = uint32(bound(timestamp, minTimestamp, block.timestamp));
    baseHooks.addRoleProvider(address(mockProvider1), timeToLive2);
    baseHooks.addRoleProvider(address(mockProvider2), timeToLive1);

    _expectAccountAccessGranted(address(mockProvider1), account, timestamp);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, timestamp);

    vm.expectRevert(BaseAccessControls.ProviderCanNotReplaceCredential.selector);
    vm.prank(address(mockProvider2));
    baseHooks.grantRole(account, timestamp);
  }

  // ========================================================================== //
  //                               getLenderStatus                              //
  // ========================================================================== //

  function test_getLenderStatus_loop() external {
    address bob = address(0xb0b);
    mockProvider1.setIsPullProvider(false);
    mockProvider2.setIsPullProvider(true);
    mockProvider2.setCredential(bob, uint32(block.timestamp));
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);
    baseHooks.addRoleProvider(address(mockProvider2), type(uint32).max);
    LenderStatus memory status = baseHooks.getLenderStatus(bob);
    assertEq(status.lastProvider, address(mockProvider2), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, block.timestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, true, 'canRefresh');
    assertEq(status.isBlockedFromDeposits, false, 'isBlockedFromDeposits');
  }

  function test_getLenderStatus_refresh() external {
    address bob = address(0xb0b);
    mockProvider1.setIsPullProvider(false);
    mockProvider2.setIsPullProvider(true);
    mockProvider2.setCredential(bob, uint32(block.timestamp));
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);
    baseHooks.addRoleProvider(address(mockProvider2), 1);
    fastForward(2);
    uint32 newTimestamp = uint32(getTimestamp());
    mockProvider2.setCredential(bob, newTimestamp);
    LenderStatus memory status = baseHooks.getLenderStatus(bob);
    assertEq(status.lastProvider, address(mockProvider2), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, newTimestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, true, 'canRefresh');
    assertEq(status.isBlockedFromDeposits, false, 'isBlockedFromDeposits');
  }

  function test_getLenderStatus_RefreshesExpiredPullProviderCredential() external {
    address bob = address(0xb0b);
    mockProvider1.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(bob, uint32(block.timestamp));

    fastForward(2);
    uint32 newTimestamp = uint32(getTimestamp());
    mockProvider1.setCredential(bob, newTimestamp);

    LenderStatus memory status = baseHooks.getLenderStatus(bob);
    assertEq(status.lastProvider, address(mockProvider1), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, newTimestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, true, 'canRefresh');
    assertEq(status.isBlockedFromDeposits, false, 'isBlockedFromDeposits');
  }

  function test_getLenderStatus_ZeroTtlPullProviderRefreshesInSameBlock() external {
    address bob = address(0xb0b);
    mockProvider1.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(mockProvider1), 0);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(bob, uint32(block.timestamp));

    LenderStatus memory status = baseHooks.getLenderStatus(bob);
    assertEq(status.lastProvider, address(0), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, 0, 'lastApprovalTimestamp');
  }

  // ========================================================================== //
  //                           getOrValidateCredential                          //
  // ========================================================================== //

  function _grantExpiredCredential(MockRoleProvider provider, address account) internal {
    uint256 currentTimestamp = getTimestamp();
    provider.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(provider), 1);
    warp(currentTimestamp - 2);
    vm.prank(address(provider));
    baseHooks.grantRole(account, uint32(currentTimestamp - 2));
    warp(currentTimestamp);
  }

  function test_fuzz_getOrValidateCredential(uint8 scenarioSeed) external {
    uint256 scenario = scenarioSeed % 12;
    address account = address(50);
    uint32 currentTimestamp = uint32(getTimestamp());
    address expectedProvider;
    uint32 expectedTimestamp;
    address revokedProvider;
    bool expectedValid;
    bool expectedUpdated;
    bool expectedCanRefresh;
    bytes memory hooksData;

    if (scenario == 0) {
      // A supported, unexpired credential wins before hooks data is considered.
      baseHooks.addRoleProvider(address(mockProvider1), 1 days);
      vm.prank(address(mockProvider1));
      baseHooks.grantRole(account, currentTimestamp);
      hooksData = abi.encodePacked(address(mockProvider2), hex'aabbcc');
      expectedProvider = address(mockProvider1);
      expectedTimestamp = currentTimestamp;
      expectedValid = true;
    } else if (scenario == 1) {
      // Data after the provider address uses validateCredential, including for push providers.
      bytes memory credentialData = hex'aabbcc';
      baseHooks.addRoleProvider(address(mockProvider2), 1 days);
      mockProvider2.approveCredentialData(keccak256(credentialData), currentTimestamp);
      hooksData = abi.encodePacked(address(mockProvider2), credentialData);
      expectedProvider = address(mockProvider2);
      expectedTimestamp = currentTimestamp;
      expectedValid = true;
      expectedUpdated = true;
    } else if (scenario == 2) {
      // A bare provider address selects getCredential, but only for a pull provider.
      mockProvider2.setIsPullProvider(true);
      mockProvider2.setCredential(account, currentTimestamp);
      baseHooks.addRoleProvider(address(mockProvider2), 1 days);
      hooksData = abi.encodePacked(address(mockProvider2));
      expectedProvider = address(mockProvider2);
      expectedTimestamp = currentTimestamp;
      expectedValid = true;
      expectedUpdated = true;
      expectedCanRefresh = true;
    } else if (scenario == 3) {
      // An expired credential refreshes from its previous pull provider.
      _grantExpiredCredential(mockProvider1, account);
      mockProvider1.setCredential(account, currentTimestamp);
      expectedProvider = address(mockProvider1);
      expectedTimestamp = currentTimestamp;
      expectedValid = true;
      expectedUpdated = true;
      expectedCanRefresh = true;
    } else if (scenario == 4) {
      // With no selected provider, the pull-provider list is searched in order.
      mockProvider1.setIsPullProvider(true);
      mockProvider2.setIsPullProvider(true);
      mockProvider2.setCredential(account, currentTimestamp);
      baseHooks.addRoleProvider(address(mockProvider1), 1 days);
      baseHooks.addRoleProvider(address(mockProvider2), 1 days);
      expectedProvider = address(mockProvider2);
      expectedTimestamp = currentTimestamp;
      expectedValid = true;
      expectedUpdated = true;
      expectedCanRefresh = true;
    } else if (scenario == 5) {
      // Unknown providers in hooks data are ignored.
      hooksData = abi.encodePacked(address(0xBAD), hex'aabbcc');
    } else if (scenario == 6) {
      // Provider reverts are treated as failed credentials, not bubbled reverts.
      baseHooks.addRoleProvider(address(mockProvider2), 1 days);
      mockProvider2.setCallShouldRevert(true);
      hooksData = abi.encodePacked(address(mockProvider2), hex'aabbcc');
    } else if (scenario == 7) {
      // A successful stateful validation must return a complete word.
      baseHooks.addRoleProvider(address(mockProvider2), 1 days);
      mockProvider2.setCallShouldReturnCorruptedData(true);
      hooksData = abi.encodePacked(address(mockProvider2), hex'aabbcc');
      vm.expectRevert(BaseAccessControls.InvalidCredentialReturned.selector);
      baseHooks.tryValidateAccess(account, hooksData);
      return;
    } else if (scenario == 8) {
      // A correctly encoded credential is still rejected when its TTL has elapsed.
      bytes memory credentialData = hex'aabbcc';
      baseHooks.addRoleProvider(address(mockProvider2), 1);
      mockProvider2.approveCredentialData(keccak256(credentialData), currentTimestamp - 2);
      hooksData = abi.encodePacked(address(mockProvider2), credentialData);
    } else if (scenario == 9) {
      // An expired credential from a push provider is cleared when no replacement exists.
      uint256 nowBeforeWarp = getTimestamp();
      baseHooks.addRoleProvider(address(mockProvider1), 1);
      warp(nowBeforeWarp - 2);
      vm.prank(address(mockProvider1));
      baseHooks.grantRole(account, uint32(nowBeforeWarp - 2));
      warp(nowBeforeWarp);
      revokedProvider = address(mockProvider1);
      expectedUpdated = true;
    } else if (scenario == 10) {
      // A failed hooks-data pull does not prevent a different provider from succeeding.
      mockProvider1.setIsPullProvider(true);
      mockProvider2.setIsPullProvider(true);
      mockProvider1.setCredential(account, currentTimestamp);
      baseHooks.addRoleProvider(address(mockProvider1), 1 days);
      baseHooks.addRoleProvider(address(mockProvider2), 1 days);
      hooksData = abi.encodePacked(address(mockProvider2));
      expectedProvider = address(mockProvider1);
      expectedTimestamp = currentTimestamp;
      expectedValid = true;
      expectedUpdated = true;
      expectedCanRefresh = true;
    } else {
      // A failed refresh skips the previous provider, then continues through the list.
      _grantExpiredCredential(mockProvider1, account);
      mockProvider2.setIsPullProvider(true);
      mockProvider2.setCredential(account, currentTimestamp);
      baseHooks.addRoleProvider(address(mockProvider2), 1 days);
      expectedProvider = address(mockProvider2);
      expectedTimestamp = currentTimestamp;
      expectedValid = true;
      expectedUpdated = true;
      expectedCanRefresh = true;
    }

    if (expectedUpdated) {
      vm.expectEmit(address(baseHooks));
      if (expectedValid) {
        emit BaseAccessControls.AccountAccessGranted(
          expectedProvider,
          account,
          address(this),
          expectedTimestamp
        );
      } else {
        emit BaseAccessControls.AccountAccessRevoked(revokedProvider, account, address(this));
      }
    }

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, hooksData);
    assertEq(hasValidCredential, expectedValid, 'hasValidCredential');
    assertEq(wasUpdated, expectedUpdated, 'wasUpdated');

    LenderStatus memory status = baseHooks.getPreviousLenderStatus(account);
    assertEq(status.lastProvider, expectedProvider, 'lastProvider');
    assertEq(status.lastApprovalTimestamp, expectedTimestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, expectedCanRefresh, 'canRefresh');
    assertFalse(status.isBlockedFromDeposits, 'isBlockedFromDeposits');
  }

  // ========================================================================== //
  //                              tryValidateAccess                             //
  // ========================================================================== //

  function test_tryValidateAccess_existingCredential(address account) external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, '');
    assertTrue(hasValidCredential, 'hasValidCredential');
    assertFalse(wasUpdated, 'wasUpdated');
  }

  function test_tryValidateAccess_SkipsHooksDataPullProviderAfterFailedPull() external {
    address account = address(0xb0b);
    mockProvider1.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);

    bytes memory hooksData = abi.encodePacked(address(mockProvider1));

    vm.expectCall(
      address(mockProvider1),
      abi.encodeWithSelector(IRoleProvider.getCredential.selector, account),
      1
    );

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, hooksData);

    assertFalse(hasValidCredential, 'hasValidCredential');
    assertFalse(wasUpdated, 'wasUpdated');
  }

  function test_tryValidateAccess_SkipsHooksDataPullProviderAfterFailedValidation() external {
    address account = address(0xb0b);
    mockProvider1.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);

    bytes memory credentialData = hex'aabbcc';
    bytes memory hooksData = abi.encodePacked(address(mockProvider1), credentialData);
    bytes memory validateCredentialCalldata = abi.encodePacked(
      IRoleProvider.validateCredential.selector,
      bytes32(uint256(uint160(account))),
      bytes32(uint256(0x40)),
      bytes32(credentialData.length),
      credentialData
    );

    vm.expectCall(address(mockProvider1), validateCredentialCalldata, 1);
    vm.expectCall(
      address(mockProvider1),
      abi.encodeWithSelector(IRoleProvider.getCredential.selector, account),
      0
    );

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, hooksData);

    assertFalse(hasValidCredential, 'hasValidCredential');
    assertFalse(wasUpdated, 'wasUpdated');
  }

  function test_tryValidateAccess_HooksDataValidCredentialUpdatesStatus() external {
    address account = address(0xb0b);
    mockProvider1.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);

    bytes memory credentialData = hex'aabbcc';
    uint32 credentialTimestamp = uint32(block.timestamp);
    mockProvider1.approveCredentialData(keccak256(credentialData), credentialTimestamp);
    bytes memory hooksData = abi.encodePacked(address(mockProvider1), credentialData);

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, hooksData);

    assertTrue(hasValidCredential, 'hasValidCredential');
    assertTrue(wasUpdated, 'wasUpdated');
    LenderStatus memory status = baseHooks.getPreviousLenderStatus(account);
    assertEq(status.lastProvider, address(mockProvider1), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, credentialTimestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, true, 'canRefresh');
    assertFalse(status.isBlockedFromDeposits, 'isBlockedFromDeposits');
  }

  function test_tryValidateAccess_RefreshesExpiredCredentialFromLastProvider() external {
    address account = address(0xb0b);
    mockProvider1.setIsPullProvider(true);
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    fastForward(2);
    uint32 newTimestamp = uint32(getTimestamp());
    mockProvider1.setCredential(account, newTimestamp);

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, '');

    assertTrue(hasValidCredential, 'hasValidCredential');
    assertTrue(wasUpdated, 'wasUpdated');
    LenderStatus memory status = baseHooks.getPreviousLenderStatus(account);
    assertEq(status.lastProvider, address(mockProvider1), 'lastProvider');
    assertEq(status.lastApprovalTimestamp, newTimestamp, 'lastApprovalTimestamp');
    assertEq(status.canRefresh, true, 'canRefresh');
    assertFalse(status.isBlockedFromDeposits, 'isBlockedFromDeposits');
  }

  function test_tryValidateAccess_ZeroTtlPullProviderRefreshesInSameBlock() external {
    address account = address(0xb0b);
    mockProvider1.setIsPullProvider(true);
    mockProvider1.setCredential(account, uint32(block.timestamp));
    baseHooks.addRoleProvider(address(mockProvider1), 0);

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, '');
    assertTrue(hasValidCredential, 'initial credential');
    assertTrue(wasUpdated, 'initial update');

    mockProvider1.setCredential(account, 0);
    (hasValidCredential, wasUpdated) = baseHooks.tryValidateAccess(account, '');
    assertFalse(hasValidCredential, 'removed credential');
    assertTrue(wasUpdated, 'removal update');
  }

  function test_tryValidateAccess_ZeroTtlPushProviderUsesSameBlockCredential() external {
    address account = address(0xb0b);
    mockProvider1.setIsPullProvider(false);
    baseHooks.addRoleProvider(address(mockProvider1), 0);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    (bool hasValidCredential, bool wasUpdated) = baseHooks.tryValidateAccess(account, '');
    assertTrue(hasValidCredential, 'hasValidCredential');
    assertFalse(wasUpdated, 'wasUpdated');
  }

  function test_isMarketTransferRecipientAllowed() external {
    address market = address(0xCAFE);
    address unrestricted = address(0xA11CE);
    address knownLender = address(0xB0B);
    address blockedLender = address(0xBAD);
    address credentialedLender = address(0xC0FFEE);

    baseHooks.setIsKnownLender(knownLender, market, true);
    baseHooks.blockFromDeposits(blockedLender);
    mockProvider1.setIsPullProvider(true);
    mockProvider1.setCredential(credentialedLender, uint32(block.timestamp));
    baseHooks.addRoleProvider(address(mockProvider1), type(uint32).max);

    assertTrue(
      baseHooks.isMarketTransferRecipientAllowed(market, unrestricted, false),
      'open transfer'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(market, blockedLender, false),
      'blocked open transfer'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(market, unrestricted, true),
      'unknown lender'
    );
    assertTrue(
      baseHooks.isMarketTransferRecipientAllowed(market, knownLender, true),
      'known lender'
    );
    baseHooks.blockFromDeposits(knownLender);
    assertTrue(
      baseHooks.isMarketTransferRecipientAllowed(market, knownLender, true),
      'blocked known lender'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(market, blockedLender, true),
      'blocked lender'
    );
    assertTrue(
      baseHooks.isMarketTransferRecipientAllowed(market, credentialedLender, true),
      'credentialed lender'
    );
  }

  function test_isMarketTransferRecipientAllowed_OnlyExemptsExactNonzeroRegisteredWrapper()
    external
  {
    address market = address(0xCAFE);
    address otherMarket = address(0xBEEF);
    address zeroWrapperMarket = address(0xCAFF);
    address dirtyWrapperMarket = address(0xBAD0);
    address shortReturnMarket = address(0xBAD1);
    address wrapper = address(0x4626);
    address arbitraryWrapper = address(0x4627);
    bytes memory getterCall = abi.encodeWithSignature('registeredWrapper()');

    baseHooks.blockFromDeposits(wrapper);
    baseHooks.blockFromDeposits(arbitraryWrapper);
    baseHooks.blockFromDeposits(address(0));
    vm.mockCall(market, getterCall, abi.encode(wrapper));
    vm.mockCall(zeroWrapperMarket, getterCall, abi.encode(address(0)));
    vm.mockCall(
      dirtyWrapperMarket,
      getterCall,
      abi.encode(bytes32(uint256(uint160(wrapper)) | (uint256(1) << 160)))
    );
    vm.mockCall(shortReturnMarket, getterCall, hex'0001');

    assertTrue(
      baseHooks.isMarketTransferRecipientAllowed(market, wrapper, true),
      'registered wrapper'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(market, arbitraryWrapper, true),
      'arbitrary wrapper'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(otherMarket, wrapper, true),
      'cross-market wrapper'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(zeroWrapperMarket, address(0), true),
      'zero wrapper'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(dirtyWrapperMarket, wrapper, true),
      'dirty wrapper response'
    );
    assertFalse(
      baseHooks.isMarketTransferRecipientAllowed(shortReturnMarket, wrapper, true),
      'short wrapper response'
    );
  }

  // ========================================================================== //
  //                                 grantRoles                                 //
  // ========================================================================== //

  function test_grantRoles() external {
    address[] memory accounts = new address[](4);
    for (uint160 i; i < accounts.length; i++) {
      accounts[i] = address(i);
    }
    uint32 timestamp = uint32(block.timestamp);
    baseHooks.addRoleProvider(address(mockProvider1), 1);

    uint32[] memory timestamps = new uint32[](accounts.length);
    for (uint i; i < accounts.length; i++) {
      timestamps[i] = timestamp;
    }
    vm.prank(address(mockProvider1));
    baseHooks.grantRoles(accounts, timestamps);
    vm.prank(address(mockProvider1));
    baseHooks.grantRoles(accounts, timestamps);
  }

  function test_grantRoles_InvalidCredentialTimestamp() external {
    address[] memory accounts = new address[](2);
    accounts[0] = address(1);
    accounts[1] = address(2);
    uint32[] memory timestamps = new uint32[](2);
    timestamps[0] = uint32(block.timestamp);
    timestamps[1] = uint32(block.timestamp + 1);
    baseHooks.addRoleProvider(address(mockProvider1), 1);

    vm.prank(address(mockProvider1));
    vm.expectRevert(BaseAccessControls.InvalidCredentialTimestamp.selector);
    baseHooks.grantRoles(accounts, timestamps);
  }

  function test_grantRoles_InvalidArrayLength() external {
    address[] memory accounts = new address[](4);
    uint32[] memory timestamps = new uint32[](3);
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    vm.expectRevert(BaseAccessControls.InvalidArrayLength.selector);
    baseHooks.grantRoles(accounts, timestamps);
  }

  /// @dev `grantRole` reverts if the provider is not found.
  function test_grantRoles_ProviderNotFound() external {
    address[] memory accounts = new address[](1);
    uint32[] memory timestamps = new uint32[](1);
    vm.prank(address(1));
    vm.expectRevert(BaseAccessControls.ProviderNotFound.selector);
    baseHooks.grantRoles(accounts, timestamps);
  }

  // ========================================================================== //
  //                                 revokeRole                                 //
  // ========================================================================== //

  function test_revokeRole() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.startPrank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(
      address(mockProvider1),
      address(1),
      address(mockProvider1)
    );
    baseHooks.revokeRole(address(1));
  }

  function test_revokeRole_ProviderCanNotRevokeCredential() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.prank(address(mockProvider2));
    vm.expectRevert(BaseAccessControls.ProviderCanNotRevokeCredential.selector);
    baseHooks.revokeRole(address(1));
  }

  // ========================================================================== //
  //                                 revokeRoles                                //
  // ========================================================================== //

  function test_revokeRoles() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    address[] memory lenders = new address[](1);
    lenders[0] = address(1);
    vm.startPrank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(
      address(mockProvider1),
      address(1),
      address(mockProvider1)
    );
    baseHooks.revokeRoles(lenders);
  }

  function test_revokeRoles_ProviderCanNotRevokeCredential() external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    address[] memory lenders = new address[](1);
    lenders[0] = address(1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(address(1), uint32(block.timestamp));
    vm.prank(address(mockProvider2));
    vm.expectRevert(BaseAccessControls.ProviderCanNotRevokeCredential.selector);
    baseHooks.revokeRoles(lenders);
  }

  // ========================================================================== //
  //                              blockFromDeposits                             //
  // ========================================================================== //

  function test_blockFromDeposits_CallerNotAdministrator() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.blockFromDeposits(address(1));
  }

  function test_blockFromDeposits(address account) external {
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(address(this), account);
    baseHooks.blockFromDeposits(account);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  function test_blockFromDeposits_UnsetsCredential(address account) external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(address(mockProvider1), account, address(this));
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(address(this), account);

    baseHooks.blockFromDeposits(account);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  function test_blockFromDeposits_multiple_CallerNotAdministrator() external asAccount(address(1)) {
    address[] memory accounts = new address[](1);
    accounts[0] = address(0);
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.blockFromDeposits(accounts);
  }

  function test_blockFromDeposits_multiple(address account) external {
    address[] memory accounts = new address[](1);
    accounts[0] = account;
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(address(this), account);
    baseHooks.blockFromDeposits(accounts);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  function test_blockFromDeposits_multiple_UnsetsCredential(address account) external {
    baseHooks.addRoleProvider(address(mockProvider1), 1);
    vm.prank(address(mockProvider1));
    baseHooks.grantRole(account, uint32(block.timestamp));

    address[] memory accounts = new address[](1);
    accounts[0] = account;

    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountAccessRevoked(address(mockProvider1), account, address(this));
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountBlockedFromDeposits(address(this), account);

    baseHooks.blockFromDeposits(accounts);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, true, 'isBlockedFromDeposits');
  }

  // ========================================================================== //
  //                             unblockFromDeposits                            //
  // ========================================================================== //

  function test_unblockFromDeposits_CallerNotAdministrator() external asAccount(address(1)) {
    vm.expectRevert(BaseAccessControls.CallerNotAdministrator.selector);
    baseHooks.unblockFromDeposits(address(1));
  }

  function test_unblockFromDeposits(address account) external {
    baseHooks.blockFromDeposits(account);
    vm.expectEmit(address(baseHooks));
    emit BaseAccessControls.AccountUnblockedFromDeposits(address(this), account);
    baseHooks.unblockFromDeposits(account);
    LenderStatus memory status = baseHooks.getLenderStatus(account);
    assertEq(status.isBlockedFromDeposits, false, 'isBlockedFromDeposits');
  }
}
