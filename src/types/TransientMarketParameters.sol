// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.25;

import './HooksConfig.sol';

struct TmpMarketParameters {
  address borrower;
  address asset;
  address feeRecipient;
  uint128 maxTotalSupply;
  uint16 protocolFeeBips;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  bytes32 packedNameWord0;
  bytes32 packedNameWord1;
  bytes32 packedSymbolWord0;
  bytes32 packedSymbolWord1;
  uint8 decimals;
  HooksConfig hooks;
  address borrowerPrincipal;
  uint16 commitmentFeeBips;
}

library LibTransientMarketParameters {
  uint256 internal constant ParametersSlot =
    uint256(keccak256('Transient:MarketParameters')) - 1;

  function write(TmpMarketParameters memory parameters) internal {
    uint256 slot = ParametersSlot;
    assembly ('memory-safe') {
      let addressMask := 0xffffffffffffffffffffffffffffffffffffffff
      let packedAsset := or(
        and(mload(add(parameters, 0x20)), addressMask),
        shl(160, and(mload(add(parameters, 0x1c0)), 0xff))
      )
      let packedScalars := or(
        and(mload(add(parameters, 0x60)), 0xffffffffffffffffffffffffffffffff),
        shl(128, and(mload(add(parameters, 0x80)), 0xffff))
      )
      packedScalars := or(
        packedScalars,
        shl(144, and(mload(add(parameters, 0xa0)), 0xffff))
      )
      packedScalars := or(
        packedScalars,
        shl(160, and(mload(add(parameters, 0xc0)), 0xffff))
      )
      packedScalars := or(
        packedScalars,
        shl(176, and(mload(add(parameters, 0xe0)), 0xffffffff))
      )
      packedScalars := or(
        packedScalars,
        shl(208, and(mload(add(parameters, 0x100)), 0xffff))
      )
      packedScalars := or(
        packedScalars,
        shl(224, and(mload(add(parameters, 0x120)), 0xffffffff))
      )
      let packedPrincipal := or(
        and(mload(add(parameters, 0x200)), addressMask),
        shl(160, and(mload(add(parameters, 0x220)), 0xffff))
      )

      tstore(add(slot, 1), packedAsset)
      tstore(add(slot, 2), and(mload(add(parameters, 0x40)), addressMask))
      tstore(add(slot, 3), packedScalars)
      tstore(add(slot, 4), mload(add(parameters, 0x140)))
      tstore(add(slot, 5), mload(add(parameters, 0x160)))
      tstore(add(slot, 6), mload(add(parameters, 0x180)))
      tstore(add(slot, 7), mload(add(parameters, 0x1a0)))
      tstore(add(slot, 8), mload(add(parameters, 0x1e0)))
      tstore(add(slot, 9), packedPrincipal)
      // The borrower word doubles as the active-deployment marker, so write it last.
      tstore(slot, and(mload(parameters), addressMask))
    }
  }

  function read() internal view returns (TmpMarketParameters memory parameters) {
    uint256 slot = ParametersSlot;
    assembly ('memory-safe') {
      parameters := mload(0x40)
      mstore(0x40, add(parameters, 0x240))

      let borrower := tload(slot)
      if iszero(borrower) {
        revert(0, 0)
      }
      let addressMask := 0xffffffffffffffffffffffffffffffffffffffff
      let packedAsset := tload(add(slot, 1))
      let packedScalars := tload(add(slot, 3))
      let packedPrincipal := tload(add(slot, 9))

      mstore(parameters, and(borrower, addressMask))
      mstore(add(parameters, 0x20), and(packedAsset, addressMask))
      mstore(add(parameters, 0x40), and(tload(add(slot, 2)), addressMask))
      mstore(add(parameters, 0x60), and(packedScalars, 0xffffffffffffffffffffffffffffffff))
      mstore(add(parameters, 0x80), and(shr(128, packedScalars), 0xffff))
      mstore(add(parameters, 0xa0), and(shr(144, packedScalars), 0xffff))
      mstore(add(parameters, 0xc0), and(shr(160, packedScalars), 0xffff))
      mstore(add(parameters, 0xe0), and(shr(176, packedScalars), 0xffffffff))
      mstore(add(parameters, 0x100), and(shr(208, packedScalars), 0xffff))
      mstore(add(parameters, 0x120), shr(224, packedScalars))
      mstore(add(parameters, 0x140), tload(add(slot, 4)))
      mstore(add(parameters, 0x160), tload(add(slot, 5)))
      mstore(add(parameters, 0x180), tload(add(slot, 6)))
      mstore(add(parameters, 0x1a0), tload(add(slot, 7)))
      mstore(add(parameters, 0x1c0), and(shr(160, packedAsset), 0xff))
      mstore(add(parameters, 0x1e0), tload(add(slot, 8)))
      mstore(add(parameters, 0x200), and(packedPrincipal, addressMask))
      mstore(add(parameters, 0x220), and(shr(160, packedPrincipal), 0xffff))
    }
  }

  function commitmentFeeBips() internal view returns (uint16 commitmentFee) {
    uint256 slot = ParametersSlot;
    assembly ('memory-safe') {
      if iszero(tload(slot)) {
        revert(0, 0)
      }
      commitmentFee := and(shr(160, tload(add(slot, 9))), 0xffff)
    }
  }

  function clear() internal {
    uint256 slot = ParametersSlot;
    assembly ('memory-safe') {
      // Every deployment overwrites the other words before this marker is restored.
      tstore(slot, 0)
    }
  }
}
