// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice source of timestamped lender credentials for access-control hooks.
/// @dev providers only answer credential questions. each hooks instance decides whether to trust a
///      provider and how long to cache its answer.
interface IRoleProvider {
  /// @notice says whether hooks may refresh credentials with `getCredential`.
  /// @dev hooks classify a provider when it is attached. returning false does not prevent explicit
  ///      validation or credentials pushed through the hook's grant functions.
  function isPullProvider() external view returns (bool);

  /// @notice returns when `account`'s current credential was granted, or zero if none is available.
  /// @dev hooks reject future timestamps and apply their own provider TTL to the result.
  function getCredential(address account) external view returns (uint32 timestamp);

  /// @notice validates caller-supplied provider data for `account`.
  /// @dev this may change provider state. return zero for an invalid credential; hooks reject
  ///      future timestamps and apply their own provider TTL to nonzero results.
  /// @param data provider-specific bytes following the packed provider address in hook data.
  /// @return timestamp time the credential was granted, or zero when validation fails.
  function validateCredential(
    address account,
    bytes calldata data
  ) external returns (uint32 timestamp);
}
