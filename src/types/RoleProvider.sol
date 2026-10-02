// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // RoleProvider
// ║  ██▀▀     ▀▀██   Packed provider identity, credential lifetime, and indexes.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ENCODING
// ║  encodeRoleProvider(...)
// ║
// ║  DECODING
// ║  decodeRoleProvider(...)
// ║
// ║  PROVIDER ADDRESS
// ║  setProviderAddress(...)
// ║  providerAddress(...)
// ║
// ║  CREDENTIAL LIFETIME
// ║  setTimeToLive(...)
// ║  timeToLive(...)
// ║  calculateExpiry(...)
// ║
// ║  PULL PROVIDERS
// ║  setPullProviderIndex(...)
// ║  setNotPullProvider(...)
// ║  pullProviderIndex(...)
// ║  isPullProvider(...)
// ║
// ║  PUSH PROVIDERS
// ║  setPushProviderIndex(...)
// ║  pushProviderIndex(...)
// ║
// ║  COMPARISON
// ║  eq(...)
// ║  isNull(...)
// ╚═════

import '../libraries/MathUtils.sol';

/// @notice packed provider address, credential TTL, and positions in the pull/push arrays.
/// @dev layout from most to least significant: 32-bit TTL, 160-bit address, two 24-bit indexes,
///      then 16 unused bits. `NullProviderIndex` marks absence from either provider array.
type RoleProvider is uint256;

// index sentinel for a provider that isn't present in the corresponding array.
uint24 constant NullProviderIndex = type(uint24).max;

// zero-value provider used where no provider is configured.
RoleProvider constant EmptyRoleProvider = RoleProvider.wrap(0);

using LibRoleProvider for RoleProvider global;

// ░░▒▒▓▓██ [ ENCODING ] ───────────────────────────────────────────────────────

// ┌─ encodeRoleProvider ─────
/// @notice pack provider metadata into a `RoleProvider` word.
///
/// @param timeToLive        credential lifetime in seconds; expiry saturates at `type(uint32).max`.
/// @param providerAddress   contract that grants or verifies the credential.
/// @param pullProviderIndex position in the pull-provider array, or `NullProviderIndex`.
/// @param pushProviderIndex position in the push-provider array, or `NullProviderIndex`.
///
/// @return provider packed provider word.
function encodeRoleProvider(
  uint32 timeToLive,
  address providerAddress,
  uint24 pullProviderIndex,
  uint24 pushProviderIndex
)
  pure
  returns (RoleProvider provider)
{
  assembly {
    provider := or(
      or(shl(0xe0, timeToLive), shl(0x40, providerAddress)),
      or(shl(0x28, pullProviderIndex), shl(0x10, pushProviderIndex))
    )
  }
}

// ┌─ LibRoleProvider ──────────────────────────────────────────────────────────
library LibRoleProvider {
  using MathUtils for uint256;

  // ░░▒▒▓▓██ [ DECODING ] ─────────────────────────────────────────────────────

  // ┌─ decodeRoleProvider ─────
  /// @dev unpack `timeToLive, providerAddress, pullProviderIndex, pushProviderIndex`.
  function decodeRoleProvider(RoleProvider provider)
    internal
    pure
    returns (uint32 _timeToLive, address _providerAddress, uint24 _pullProviderIndex, uint24 _pushProviderIndex)
  {
    assembly {
      _timeToLive := shr(0xe0, provider)
      _providerAddress := shr(0x60, shl(0x20, provider))
      _pullProviderIndex := shr(0xe8, shl(0xc0, provider))
      _pushProviderIndex := shr(0xe8, shl(0xd8, provider))
    }
  }

  // ░░▒▒▓▓██ [ PROVIDER ADDRESS ] ─────────────────────────────────────────────

  // ┌─ setProviderAddress ─────
  /// @dev return a copy with `providerAddress` set to `_providerAddress`. the input stays unchanged.
  function setProviderAddress(
    RoleProvider provider,
    address _providerAddress
  )
    internal
    pure
    returns (RoleProvider newProvider)
  {
    assembly {
      newProvider := or(
        and(provider, 0xffffffff0000000000000000000000000000000000000000ffffffffffffffff),
        shl(0x40, _providerAddress)
      )
    }
  }

  // ┌─ providerAddress ─────
  /// @dev read `providerAddress` from `provider`.
  function providerAddress(RoleProvider provider) internal pure returns (address _providerAddress) {
    assembly {
      _providerAddress := shr(0x60, shl(0x20, provider))
    }
  }

  // ░░▒▒▓▓██ [ CREDENTIAL LIFETIME ] ──────────────────────────────────────────

  // ┌─ setTimeToLive ─────
  /// @dev return a copy with `timeToLive` set to `_timeToLive`. the input stays unchanged.
  function setTimeToLive(RoleProvider provider, uint32 _timeToLive) internal pure returns (RoleProvider newProvider) {
    assembly {
      newProvider := or(shr(0x20, shl(0x20, provider)), shl(0xe0, _timeToLive))
    }
  }

  // ┌─ timeToLive ─────
  /// @dev read `timeToLive` from `provider`.
  function timeToLive(RoleProvider provider) internal pure returns (uint32 _timeToLive) {
    assembly {
      _timeToLive := shr(0xe0, provider)
    }
  }

  // ┌─ calculateExpiry ─────
  /// @dev add the provider's TTL to the grant timestamp. saturate at uint32.max,
  ///      the indefinite-access limit.
  function calculateExpiry(RoleProvider provider, uint256 timestamp) internal pure returns (uint256) {
    return timestamp.satAdd(provider.timeToLive(), type(uint32).max);
  }

  // ░░▒▒▓▓██ [ PULL PROVIDERS ] ───────────────────────────────────────────────

  // ┌─ setPullProviderIndex ─────
  /// @dev return a copy with `pullProviderIndex` set to `_pullProviderIndex`. the input stays unchanged.
  function setPullProviderIndex(
    RoleProvider provider,
    uint24 _pullProviderIndex
  )
    internal
    pure
    returns (RoleProvider newProvider)
  {
    assembly {
      newProvider := or(
        and(provider, 0xffffffffffffffffffffffffffffffffffffffffffffffff000000ffffffffff),
        shl(0x28, _pullProviderIndex)
      )
    }
  }

  // ┌─ setNotPullProvider ─────
  /// @dev return a copy with pullProviderIndex set to NullProviderIndex: not a pull provider.
  function setNotPullProvider(RoleProvider provider) internal pure returns (RoleProvider newProvider) {
    assembly {
      newProvider := or(provider, 0xffffff0000000000)
    }
  }

  // ┌─ pullProviderIndex ─────
  /// @dev read `pullProviderIndex` from `provider`.
  function pullProviderIndex(RoleProvider provider) internal pure returns (uint24 _pullProviderIndex) {
    assembly {
      _pullProviderIndex := shr(0xe8, shl(0xc0, provider))
    }
  }

  // ┌─ isPullProvider ─────
  /// @dev a pull provider has a pullProviderIndex other than NullProviderIndex.
  function isPullProvider(RoleProvider provider) internal pure returns (bool) {
    return provider.pullProviderIndex() != NullProviderIndex;
  }

  // ░░▒▒▓▓██ [ PUSH PROVIDERS ] ───────────────────────────────────────────────

  // ┌─ setPushProviderIndex ─────
  /// @dev return a copy with `pushProviderIndex` set to `_pushProviderIndex`. the input stays unchanged.
  function setPushProviderIndex(
    RoleProvider provider,
    uint24 _pushProviderIndex
  )
    internal
    pure
    returns (RoleProvider newProvider)
  {
    assembly {
      newProvider := or(
        and(provider, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffff000000ffff),
        shl(0x10, _pushProviderIndex)
      )
    }
  }

  // ┌─ pushProviderIndex ─────
  /// @dev read `pushProviderIndex` from `provider`.
  function pushProviderIndex(RoleProvider provider) internal pure returns (uint24 _pushProviderIndex) {
    assembly {
      _pushProviderIndex := shr(0xe8, shl(0xd8, provider))
    }
  }

  // ░░▒▒▓▓██ [ COMPARISON ] ───────────────────────────────────────────────────

  // ┌─ eq ─────
  /// @dev compare the full packed provider words.
  function eq(RoleProvider provider, RoleProvider otherRoleProvider) internal pure returns (bool _eq) {
    assembly {
      _eq := eq(provider, otherRoleProvider)
    }
  }

  // ┌─ isNull ─────
  /// @dev check whether `provider` is null.
  function isNull(RoleProvider provider) internal pure returns (bool _null) {
    assembly {
      _null := iszero(provider)
    }
  }
}
