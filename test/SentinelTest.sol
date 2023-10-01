// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { WildcatSanctionsSentinel, WildcatSanctionsEscrow, IChainalysisSanctionsList, IWildcatArchController } from '../src/WildcatSanctionsSentinel.sol';
import { SanctionsList } from '../src/libraries/Chainalysis.sol';

import { MockChainalysis, deployMockChainalysis } from './helpers/MockChainalysis.sol';
import { MockERC20 } from './helpers/MockERC20.sol';
import { Test } from 'forge-std/Test.sol';

// -- TEMP START --
contract MockWildcatArchController is IWildcatArchController {
  mapping(address vault => bool) public isRegisteredVault;

  function setIsRegsiteredVault(address vault, bool isRegistered) external {
    isRegisteredVault[vault] = isRegistered;
  }
}

// -- TEMP END --

contract SentinelTest is Test {
  event NewSanctionsEscrow(
    address indexed borrower,
    address indexed account,
    address indexed asset
  );

  MockWildcatArchController internal archController;
  WildcatSanctionsSentinel internal sentinel;

  function setUp() public {
    deployMockChainalysis();
    archController = new MockWildcatArchController();
    sentinel = new WildcatSanctionsSentinel(archController);
  }

  function testWildcatSanctionsEscrowInitcodeHash() public {
    assertEq(
      sentinel.WildcatSanctionsEscrowInitcodeHash(),
      keccak256(type(WildcatSanctionsEscrow).creationCode)
    );
  }

  function testChainalysisSanctionsList() public {
    assertEq(address(sentinel.chainalysisSanctionsList()), address(SanctionsList));
  }

  function testArchController() public {
    assertEq(address(sentinel.archController()), address(archController));
  }

  function testIsSanctioned() public {
    assertEq(sentinel.isSanctioned(address(1)), false);
    MockChainalysis(address(SanctionsList)).sanction(address(1));
    assertEq(sentinel.isSanctioned(address(1)), true);
  }

  function testFuzzIsSanctioned(address forWhomTheBellTolls, bool sanctioned) public {
    assertEq(sentinel.isSanctioned(forWhomTheBellTolls), false);
    if (sanctioned) MockChainalysis(address(SanctionsList)).sanction(forWhomTheBellTolls);
    assertEq(sentinel.isSanctioned(forWhomTheBellTolls), sanctioned);
  }

  function testGetEscrowAddress() public {
    address borrower = address(1);
    address account = address(2);
    address asset = address(3);

    assertEq(
      sentinel.getEscrowAddress(borrower, account, asset),
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
      )
    );
  }

  function testFuzzGetEscrowAddress(address borrower, address account, address asset) public {
    assertEq(
      sentinel.getEscrowAddress(borrower, account, asset),
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
      )
    );
  }

  function testCreateEscrow() public {
    address borrower = address(1);
    address account = address(2);
    address asset = address(new MockERC20());
    uint256 amount = 1;

    archController.setIsRegsiteredVault(address(this), true);

    vm.expectEmit(true, true, true, true, address(sentinel));
    emit NewSanctionsEscrow(borrower, account, asset);

    address escrow = sentinel.createEscrow(borrower, account, asset);
    MockERC20(asset).mint(escrow, amount);
    (address escrowedAsset, uint256 escrowedAmount) = WildcatSanctionsEscrow(escrow)
      .escrowedAsset();

    assertEq(escrow, sentinel.getEscrowAddress(borrower, account, asset));
    assertEq(escrow, sentinel.createEscrow(borrower, account, asset));
    assertEq(WildcatSanctionsEscrow(escrow).borrower(), borrower);
    assertEq(WildcatSanctionsEscrow(escrow).account(), account);
    assertEq(WildcatSanctionsEscrow(escrow).balance(), amount);
    assertEq(
      WildcatSanctionsEscrow(escrow).canReleaseEscrow(),
      !SanctionsList.isSanctioned(account)
    );
    assertEq(escrowedAsset, asset);
    assertEq(escrowedAmount, amount);
  }

  function testFuzzCreateEscrow(
    address borrower,
    address account,
    bytes32 assetSalt,
    uint256 amount,
    bool sanctioned
  ) public {
    address asset = address(new MockERC20{ salt: assetSalt }());

    archController.setIsRegsiteredVault(address(this), true);
    if (sanctioned) MockChainalysis(address(SanctionsList)).sanction(account);

    vm.expectEmit(true, true, true, true, address(sentinel));
    emit NewSanctionsEscrow(borrower, account, asset);

    address escrow = sentinel.createEscrow(borrower, account, asset);
    MockERC20(asset).mint(escrow, amount);
    (address escrowedAsset, uint256 escrowedAmount) = WildcatSanctionsEscrow(escrow)
      .escrowedAsset();

    assertEq(escrow, sentinel.getEscrowAddress(borrower, account, asset));
    assertEq(escrow, sentinel.createEscrow(borrower, account, asset));
    assertEq(WildcatSanctionsEscrow(escrow).borrower(), borrower);
    assertEq(WildcatSanctionsEscrow(escrow).account(), account);
    assertEq(WildcatSanctionsEscrow(escrow).balance(), amount);
    assertEq(
      WildcatSanctionsEscrow(escrow).canReleaseEscrow(),
      !SanctionsList.isSanctioned(account)
    );
    assertEq(escrowedAsset, asset);
    assertEq(escrowedAmount, amount);
  }

  function testCreateEscrowNotRegisteredVault() public {
    address borrower = address(1);
    address account = address(2);
    address asset = address(3);

    vm.expectRevert(WildcatSanctionsSentinel.NotRegisteredVault.selector);
    sentinel.createEscrow(borrower, account, asset);
  }

  function testFuzzCreateEscrowNotRegisteredVault(
    address borrower,
    address account,
    address asset
  ) public {
    vm.expectRevert(WildcatSanctionsSentinel.NotRegisteredVault.selector);
    sentinel.createEscrow(borrower, account, asset);
  }
}
