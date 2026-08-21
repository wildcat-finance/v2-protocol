// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.25;

import { IChainalysisSanctionsList } from './interfaces/IChainalysisSanctionsList.sol';
import { IWildcatSanctionsSentinel } from './interfaces/IWildcatSanctionsSentinel.sol';
import { WildcatSanctionsEscrow } from './WildcatSanctionsEscrow.sol';

contract WildcatSanctionsSentinel is IWildcatSanctionsSentinel {
  // ========================================================================== //
  //                                  Constants                                 //
  // ========================================================================== //

  bytes32 public constant override WildcatSanctionsEscrowInitcodeHash =
    keccak256(type(WildcatSanctionsEscrow).creationCode);

  address public immutable override chainalysisSanctionsList;

  address public immutable override archController;

  uint256 internal constant _TMP_ESCROW_PARAMS_SLOT =
    uint256(keccak256('Transient:EscrowParameters')) - 1;

  // ========================================================================== //
  //                                   Storage                                  //
  // ========================================================================== //

  mapping(address borrower => mapping(address account => bool sanctionOverride))
    public
    override sanctionOverrides;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  constructor(address _archController, address _chainalysisSanctionsList) {
    archController = _archController;
    chainalysisSanctionsList = _chainalysisSanctionsList;
  }

  // ========================================================================== //
  //                              Internal Helpers                              //
  // ========================================================================== //

  function tmpEscrowParams()
    public
    view
    override
    returns (address borrower, address account, address asset)
  {
    uint256 slot = _TMP_ESCROW_PARAMS_SLOT;
    assembly ('memory-safe') {
      let packedBorrower := tload(slot)
      switch iszero(packedBorrower)
      case 1 {
        borrower := 1
        account := 1
        asset := 1
      }
      default {
        borrower := and(packedBorrower, 0xffffffffffffffffffffffffffffffffffffffff)
        account := and(tload(add(slot, 1)), 0xffffffffffffffffffffffffffffffffffffffff)
        asset := and(tload(add(slot, 2)), 0xffffffffffffffffffffffffffffffffffffffff)
      }
    }
  }

  function _setTmpEscrowParams(address borrower, address account, address asset) internal {
    uint256 slot = _TMP_ESCROW_PARAMS_SLOT;
    assembly ('memory-safe') {
      let addressMask := 0xffffffffffffffffffffffffffffffffffffffff
      tstore(add(slot, 1), account)
      tstore(add(slot, 2), asset)
      tstore(slot, or(and(borrower, addressMask), shl(160, 1)))
    }
  }

  function _resetTmpEscrowParams() internal {
    uint256 slot = _TMP_ESCROW_PARAMS_SLOT;
    assembly ('memory-safe') {
      tstore(slot, 0)
    }
  }

  /**
   * @dev Derive create2 salt for an escrow given the borrower, account and asset.
   */
  function _deriveSalt(
    address borrower,
    address account,
    address asset
  ) internal pure returns (bytes32 salt) {
    assembly {
      // Cache free memory pointer
      let freeMemoryPointer := mload(0x40)
      // `keccak256(abi.encode(borrower, account, asset))`
      mstore(0x00, borrower)
      mstore(0x20, account)
      mstore(0x40, asset)
      salt := keccak256(0, 0x60)
      // Restore free memory pointer
      mstore(0x40, freeMemoryPointer)
    }
  }

  // ========================================================================== //
  //                              Sanction Queries                              //
  // ========================================================================== //

  /**
   * @dev Returns boolean indicating whether `account` is sanctioned on Chainalysis.
   */
  function isFlaggedByChainalysis(
    address account
  ) public view override returns (bool) {
    bool isFlagged;
    address sanctionsList = chainalysisSanctionsList;
    assembly ('memory-safe') {
      mstore(0, 0xdf592f7d)
      mstore(0x20, account)
      if iszero(staticcall(gas(), sanctionsList, 0x1c, 0x24, 0, 0x20)) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      isFlagged := mload(0)
      if gt(isFlagged, 1) {
        revert(0, 0)
      }
    }
    return isFlagged;
  }

  /**
   * @dev Returns boolean indicating whether `account` is sanctioned on Chainalysis
   *      and that status has not been overridden by `borrower`.
   */
  function isSanctioned(address borrower, address account) public view override returns (bool) {
    return !sanctionOverrides[borrower][account] && isFlaggedByChainalysis(account);
  }

  // ========================================================================== //
  //                             Sanction Overrides                             //
  // ========================================================================== //

  /**
   * @dev Overrides the sanction status of `account` for `borrower`.
   */
  function overrideSanction(address account) public override {
    sanctionOverrides[msg.sender][account] = true;
    emit SanctionOverride(msg.sender, account);
  }

  /**
   * @dev Removes the sanction override of `account` for `borrower`.
   */
  function removeSanctionOverride(address account) public override {
    sanctionOverrides[msg.sender][account] = false;
    emit SanctionOverrideRemoved(msg.sender, account);
  }

  // ========================================================================== //
  //                              Escrow Deployment                             //
  // ========================================================================== //

  /**
   * @dev Creates a new WildcatSanctionsEscrow contract for `borrower`,
   *      `account`, and `asset` or returns the existing escrow contract
   *      if one already exists.
   *
   *      The escrow contract is added to the set of sanction override
   *      addresses for `borrower` so that it can not be blocked.
   */
  function createEscrow(
    address borrower,
    address account,
    address asset
  ) public override returns (address escrowContract) {
    escrowContract = getEscrowAddress(borrower, account, asset);

    // Skip creation if the address code size is non-zero
    if (escrowContract.code.length != 0) return escrowContract;

    _setTmpEscrowParams(borrower, account, asset);

    new WildcatSanctionsEscrow{ salt: _deriveSalt(borrower, account, asset) }();

    emit NewSanctionsEscrow(borrower, account, asset);

    sanctionOverrides[borrower][escrowContract] = true;

    emit SanctionOverride(borrower, escrowContract);

    _resetTmpEscrowParams();
  }

  /**
   * @dev Calculate the create2 escrow address for the combination
   *      of `borrower`, `account`, and `asset`.
   */
  function getEscrowAddress(
    address borrower,
    address account,
    address asset
  ) public view override returns (address escrowAddress) {
    bytes32 salt = _deriveSalt(borrower, account, asset);
    bytes32 initCodeHash = WildcatSanctionsEscrowInitcodeHash;
    assembly {
      // Cache the free memory pointer so it can be restored at the end
      let freeMemoryPointer := mload(0x40)

      // Write 0xff + address(this) to bytes 11:32
      mstore(0x00, or(0xff0000000000000000000000000000000000000000, address()))

      // Write salt to bytes 32:64
      mstore(0x20, salt)

      // Write initcode hash to bytes 64:96
      mstore(0x40, initCodeHash)

      // Calculate create2 hash
      escrowAddress := and(keccak256(0x0b, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)

      // Restore the free memory pointer
      mstore(0x40, freeMemoryPointer)
    }
  }
}
