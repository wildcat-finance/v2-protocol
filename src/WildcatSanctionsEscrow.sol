// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import './interfaces/IERC20.sol';
import './interfaces/IWildcatSanctionsEscrow.sol';
import './interfaces/IWildcatSanctionsSentinel.sol';
import './libraries/LibERC20.sol';

contract WildcatSanctionsEscrow is IWildcatSanctionsEscrow {
  using LibERC20 for address;

  address public immutable override sentinel;
  address public immutable override borrower;
  address public immutable override account;
  address internal immutable asset;

  constructor() {
    sentinel = msg.sender;
    (borrower, account, asset) = IWildcatSanctionsSentinel(sentinel).tmpEscrowParams();
  }

  function balance() public view override returns (uint256) {
    address token = asset;
    uint256 amount;
    assembly ('memory-safe') {
      mstore(0, 0x70a08231)
      mstore(0x20, address())
      if iszero(staticcall(gas(), token, 0x1c, 0x24, 0, 0x20)) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      amount := mload(0)
    }
    return amount;
  }

  function canReleaseEscrow() public view override returns (bool) {
    address sentinelAddress = sentinel;
    address borrowerAddress = borrower;
    address accountAddress = account;
    bool canRelease;
    assembly ('memory-safe') {
      let pointer := mload(0x40)
      mstore(pointer, 0x06e74444)
      mstore(add(pointer, 0x20), borrowerAddress)
      mstore(add(pointer, 0x40), accountAddress)
      if iszero(staticcall(gas(), sentinelAddress, add(pointer, 0x1c), 0x44, pointer, 0x20)) {
        returndatacopy(pointer, 0, returndatasize())
        revert(pointer, returndatasize())
      }
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      canRelease := mload(pointer)
      if gt(canRelease, 1) {
        revert(0, 0)
      }
      canRelease := iszero(canRelease)
    }
    return canRelease;
  }

  function escrowedAsset() public view override returns (address, uint256) {
    return (asset, balance());
  }

  function releaseEscrow() public override {
    if (!canReleaseEscrow()) revert CanNotReleaseEscrow();

    uint256 amount = balance();
    address _account = account;
    address _asset = asset;

    _asset.safeTransfer(_account, amount);

    emit EscrowReleased(_account, _asset, amount);
  }
}
