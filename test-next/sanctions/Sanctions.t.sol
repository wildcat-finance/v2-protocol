// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { WildcatSanctionsEscrow } from 'src/WildcatSanctionsEscrow.sol';
import { WildcatSanctionsSentinel } from 'src/WildcatSanctionsSentinel.sol';
import { IChainalysisSanctionsList } from 'src/interfaces/IChainalysisSanctionsList.sol';
import { IWildcatSanctionsEscrow } from 'src/interfaces/IWildcatSanctionsEscrow.sol';
import { SanctionsListMock } from '../mocks/SanctionsMocks.sol';
import { TestKernel } from '../shared/TestKernel.sol';

contract SanctionsTest is TestKernel {
  struct Fixture {
    SanctionsListMock sanctionsList;
    WildcatSanctionsSentinel sentinel;
    MockERC20 asset;
  }

  event NewSanctionsEscrow(
    address indexed borrower,
    address indexed account,
    address indexed asset
  );
  event SanctionOverride(address indexed borrower, address indexed account);
  event SanctionOverrideRemoved(address indexed borrower, address indexed account);
  event EscrowReleased(address indexed account, address indexed asset, uint256 amount);

  address internal constant ArchController = address(0xAC);
  address internal constant Borrower = address(0xB0B);
  address internal constant Account = address(0xA11CE);
  address internal constant Caller = address(0xCA11);

  function _deploySentinel(
    address archController,
    address sanctionsList
  ) internal returns (WildcatSanctionsSentinel sentinel) {
    sentinel = WildcatSanctionsSentinel(
      _deployCode(
        'src/WildcatSanctionsSentinel.sol:WildcatSanctionsSentinel',
        abi.encode(archController, sanctionsList)
      )
    );
  }

  function _newFixture() internal returns (Fixture memory fixture) {
    fixture.sanctionsList = SanctionsListMock(
      _deployCode('test-next/mocks/SanctionsMocks.sol:SanctionsListMock')
    );
    fixture.sentinel = _deploySentinel(ArchController, address(fixture.sanctionsList));
    fixture.asset = MockERC20(
      _deployCode(
        'lib/solmate/src/test/utils/mocks/MockERC20.sol:MockERC20',
        abi.encode('Mock ERC20', 'MOCK', uint8(18))
      )
    );
  }

  function _createEscrow(
    Fixture memory fixture,
    address borrower,
    address account
  ) internal returns (WildcatSanctionsEscrow escrow) {
    escrow = WildcatSanctionsEscrow(
      fixture.sentinel.createEscrow(borrower, account, address(fixture.asset))
    );
  }

  function _expectedEscrowAddress(
    WildcatSanctionsSentinel sentinel,
    address borrower,
    address account,
    address asset
  ) internal view returns (address) {
    return
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                bytes1(0xff),
                address(sentinel),
                keccak256(abi.encode(borrower, account, asset)),
                sentinel.WildcatSanctionsEscrowInitcodeHash()
              )
            )
          )
        )
      );
  }

  function test_constructor_StoresDependenciesHashAndResetParameters() external {
    Fixture memory fixture = _newFixture();
    assertEq(fixture.sentinel.archController(), ArchController);
    assertEq(fixture.sentinel.chainalysisSanctionsList(), address(fixture.sanctionsList));
    assertEq(
      fixture.sentinel.WildcatSanctionsEscrowInitcodeHash(),
      keccak256(vm.getCode('src/WildcatSanctionsEscrow.sol:WildcatSanctionsEscrow'))
    );
    (address borrower, address account, address asset) = fixture.sentinel.tmpEscrowParams();
    assertEq(borrower, address(1));
    assertEq(account, address(1));
    assertEq(asset, address(1));
  }

  function test_chainalysisRead_ValidatesAndBubblesResponse() external {
    address sanctionsList = address(0xC4A1);
    WildcatSanctionsSentinel sentinel = _deploySentinel(ArchController, sanctionsList);
    bytes memory callData = abi.encodeCall(IChainalysisSanctionsList.isSanctioned, (Account));

    vm.mockCall(sanctionsList, callData, hex'01');
    vm.expectRevert();
    sentinel.isFlaggedByChainalysis(Account);
    vm.clearMockedCalls();

    vm.mockCall(sanctionsList, callData, abi.encode(uint256(2)));
    vm.expectRevert();
    sentinel.isFlaggedByChainalysis(Account);
    vm.clearMockedCalls();

    vm.mockCall(sanctionsList, callData, bytes.concat(abi.encode(true), hex'deadbeef'));
    assertTrue(sentinel.isFlaggedByChainalysis(Account));
    vm.clearMockedCalls();

    bytes memory revertData = hex'deadbeef';
    vm.mockCallRevert(sanctionsList, callData, revertData);
    vm.expectRevert(revertData);
    sentinel.isFlaggedByChainalysis(Account);
    vm.clearMockedCalls();
  }

  function testFuzz_isSanctioned_CombinesListAndBorrowerOverride(
    address borrower,
    address account,
    bool sanctioned,
    bool overridden
  ) external {
    Fixture memory fixture = _newFixture();
    if (sanctioned) fixture.sanctionsList.sanction(account);
    if (overridden) {
      vm.prank(borrower);
      fixture.sentinel.overrideSanction(account);
    }
    assertEq(fixture.sentinel.isSanctioned(borrower, account), sanctioned && !overridden);
  }

  function test_overrideLifecycle_EmitsAndRestoresSanction() external {
    Fixture memory fixture = _newFixture();
    fixture.sanctionsList.sanction(Account);
    assertTrue(fixture.sentinel.isSanctioned(Borrower, Account));

    vm.expectEmit(address(fixture.sentinel));
    emit SanctionOverride(Borrower, Account);
    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(Account);
    assertTrue(fixture.sentinel.sanctionOverrides(Borrower, Account));
    assertFalse(fixture.sentinel.isSanctioned(Borrower, Account));

    vm.expectEmit(address(fixture.sentinel));
    emit SanctionOverrideRemoved(Borrower, Account);
    vm.prank(Borrower);
    fixture.sentinel.removeSanctionOverride(Account);
    assertFalse(fixture.sentinel.sanctionOverrides(Borrower, Account));
    assertTrue(fixture.sentinel.isSanctioned(Borrower, Account));
  }

  function testFuzz_getEscrowAddress_MatchesCreate2Formula(
    address borrower,
    address account,
    address asset
  ) external {
    Fixture memory fixture = _newFixture();
    assertEq(
      fixture.sentinel.getEscrowAddress(borrower, account, asset),
      _expectedEscrowAddress(fixture.sentinel, borrower, account, asset)
    );
  }

  function test_createEscrow_EmitsInitializesOverridesAndIsIdempotent() external {
    Fixture memory fixture = _newFixture();
    address expected = fixture.sentinel.getEscrowAddress(Borrower, Account, address(fixture.asset));

    vm.expectEmit(address(fixture.sentinel));
    emit NewSanctionsEscrow(Borrower, Account, address(fixture.asset));
    vm.expectEmit(address(fixture.sentinel));
    emit SanctionOverride(Borrower, expected);
    WildcatSanctionsEscrow escrow = _createEscrow(fixture, Borrower, Account);

    assertEq(address(escrow), expected);
    assertEq(fixture.sentinel.createEscrow(Borrower, Account, address(fixture.asset)), expected);
    assertEq(escrow.sentinel(), address(fixture.sentinel));
    assertEq(escrow.borrower(), Borrower);
    assertEq(escrow.account(), Account);
    assertTrue(fixture.sentinel.sanctionOverrides(Borrower, expected));

    (address borrower, address account, address asset) = fixture.sentinel.tmpEscrowParams();
    assertEq(borrower, address(1));
    assertEq(account, address(1));
    assertEq(asset, address(1));
  }

  function testFuzz_escrowTracksAssetAndBalance(
    address borrower,
    address account,
    uint256 amount
  ) external {
    Fixture memory fixture = _newFixture();
    WildcatSanctionsEscrow escrow = _createEscrow(fixture, borrower, account);

    assertEq(escrow.sentinel(), address(fixture.sentinel));
    assertEq(escrow.borrower(), borrower);
    assertEq(escrow.account(), account);
    assertEq(escrow.balance(), 0);
    (address escrowedAsset, uint256 escrowedAmount) = escrow.escrowedAsset();
    assertEq(escrowedAsset, address(fixture.asset));
    assertEq(escrowedAmount, 0);

    fixture.asset.mint(address(escrow), amount);
    assertEq(escrow.balance(), amount);
    (escrowedAsset, escrowedAmount) = escrow.escrowedAsset();
    assertEq(escrowedAsset, address(fixture.asset));
    assertEq(escrowedAmount, amount);
  }

  function test_canReleaseEscrow_TracksSanctionAndOverride() external {
    Fixture memory fixture = _newFixture();
    WildcatSanctionsEscrow escrow = _createEscrow(fixture, Borrower, Account);
    assertTrue(escrow.canReleaseEscrow());

    fixture.sanctionsList.sanction(Account);
    assertFalse(escrow.canReleaseEscrow());

    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(Account);
    assertTrue(escrow.canReleaseEscrow());
  }

  function testFuzz_releaseEscrow_IsPermissionlessAndTransfersFullBalance(
    address caller,
    address borrower,
    address account,
    uint256 amount
  ) external {
    Fixture memory fixture = _newFixture();
    address predictedEscrow = fixture.sentinel.getEscrowAddress(
      borrower,
      account,
      address(fixture.asset)
    );
    vm.assume(caller != VmAddress);
    vm.assume(account != predictedEscrow);
    WildcatSanctionsEscrow escrow = _createEscrow(fixture, borrower, account);
    fixture.asset.mint(address(escrow), amount);

    vm.expectEmit(address(escrow));
    emit EscrowReleased(account, address(fixture.asset), amount);
    vm.prank(caller);
    escrow.releaseEscrow();

    assertEq(escrow.balance(), 0);
    assertEq(fixture.asset.balanceOf(account), amount);
  }

  function test_releaseEscrow_UsesBorrowerOverride() external {
    Fixture memory fixture = _newFixture();
    WildcatSanctionsEscrow escrow = _createEscrow(fixture, Borrower, Account);
    fixture.sanctionsList.sanction(Account);
    fixture.asset.mint(address(escrow), 1);

    vm.prank(Borrower);
    fixture.sentinel.overrideSanction(Account);
    escrow.releaseEscrow();
    assertEq(escrow.balance(), 0);
    assertEq(fixture.asset.balanceOf(Account), 1);
  }

  function test_releaseEscrow_RejectsActiveSanction() external {
    Fixture memory fixture = _newFixture();
    WildcatSanctionsEscrow escrow = _createEscrow(fixture, Borrower, Account);
    fixture.sanctionsList.sanction(Account);
    fixture.asset.mint(address(escrow), 1);

    vm.expectRevert(IWildcatSanctionsEscrow.CanNotReleaseEscrow.selector);
    escrow.releaseEscrow();
    assertEq(escrow.balance(), 1);
  }
}
