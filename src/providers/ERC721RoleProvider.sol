// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../libraries/SafeCastLib.sol';
import './IERC721RoleProvider.sol';
import { ERC165QueryLib, IERC721BalanceOf, TokenQueryLib } from './TokenInterfaces.sol';

using SafeCastLib for uint256;

/// @notice Grants credentials while an account holds a token from an ERC721 collection.
/// @dev Deploy with `skipInterfaceCheck` for collections that do not implement ERC165.
contract ERC721RoleProvider is IERC721RoleProvider {
  bool public constant override isPullProvider = true;

  bytes4 private constant ERC721_INTERFACE_ID = 0x80ac58cd;

  address public immutable override token;

  constructor(address token_, bool skipInterfaceCheck) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (
      !skipInterfaceCheck &&
      (!ERC165QueryLib.supportsERC165(token_) ||
        !ERC165QueryLib.supportsInterface(token_, ERC721_INTERFACE_ID))
    ) {
      revert InvalidERC721();
    }
    token = token_;
  }

  function getCredential(address account) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function validateCredential(
    address account,
    bytes calldata
  ) external view override returns (uint32 timestamp) {
    return _credentialTimestamp(account);
  }

  function _credentialTimestamp(address account) internal view returns (uint32) {
    uint256 balance = TokenQueryLib.readWordOrRevert(
      token,
      IERC721BalanceOf.balanceOf.selector,
      uint160(account)
    );
    if (balance > 0) {
      return block.timestamp.toUint32();
    }
    return 0;
  }

}
