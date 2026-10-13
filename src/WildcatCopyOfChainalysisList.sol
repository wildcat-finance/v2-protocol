// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import 'solady/auth/Ownable.sol';
import './libraries/MathUtils.sol';

/**
 * @title WildcatCopyOfChainalysisList
 * @author d1ll0n
 * @notice This contract is a registry tracking sanctioned addresses according to Chainalysis.
 *         This is NOT maintained by Chainalysis. It is maintained by Wildcat Finance using
 *         a monitoring process which reads from the mainnet Chainalysis list and pushes
 *         updates to this contract. We make no guarantees about the liveness of the monitoring
 *         process or the speed at which updates are pushed to this contract.
 */
contract WildcatCopyOfChainalysisList is Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  event SanctionedAddressesAdded(address[] addresses);
  event SanctionedAddressesRemoved(address[] addresses);

  constructor() {
    _initializeOwner(msg.sender);
  }

  EnumerableSet.AddressSet internal sanctionedAddresses;

  function addToSanctionsList(address[] memory newSanctions) public onlyOwner {
    for (uint256 i = 0; i < newSanctions.length; i++) {
      sanctionedAddresses.add(newSanctions[i]);
    }
    emit SanctionedAddressesAdded(newSanctions);
  }

  function removeFromSanctionsList(address[] memory removeSanctions) public onlyOwner {
    for (uint256 i = 0; i < removeSanctions.length; i++) {
      sanctionedAddresses.remove(removeSanctions[i]);
    }
    emit SanctionedAddressesRemoved(removeSanctions);
  }

  function updateSanctionsList(
    address[] memory newSanctions,
    address[] memory removeSanctions
  ) public onlyOwner {
    for (uint256 i = 0; i < newSanctions.length; i++) {
      sanctionedAddresses.add(newSanctions[i]);
    }
    if (newSanctions.length > 0) {
      emit SanctionedAddressesAdded(newSanctions);
    }
    for (uint256 i = 0; i < removeSanctions.length; i++) {
      sanctionedAddresses.remove(removeSanctions[i]);
    }
    if (removeSanctions.length > 0) {
      emit SanctionedAddressesRemoved(removeSanctions);
    }
  }

  function isSanctioned(address addr) external view returns (bool) {
    return sanctionedAddresses.contains(addr);
  }

  function checkSanctionsList(
    address[] memory addresses
  ) external view returns (bool[] memory isSanctionedArray) {
    isSanctionedArray = new bool[](addresses.length);
    for (uint256 i = 0; i < addresses.length; i++) {
      isSanctionedArray[i] = sanctionedAddresses.contains(addresses[i]);
    }
  }

  function getSanctionedAddresses() external view returns (address[] memory) {
    return sanctionedAddresses.values();
  }

  function getSanctionedAddresses(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    uint256 len = sanctionedAddresses.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = sanctionedAddresses.at(start + i);
    }
  }

  function getSanctionedAddressesCount() external view returns (uint256) {
    return sanctionedAddresses.length();
  }
}
