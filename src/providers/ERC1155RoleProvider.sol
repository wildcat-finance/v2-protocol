// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../libraries/SafeCastLib.sol';
import './IERC1155RoleProvider.sol';
import { ERC165QueryLib, IERC1155BalanceOf, TokenQueryLib } from './TokenInterfaces.sol';

using SafeCastLib for uint256;

/// @notice Grants credentials while an account holds the configured ERC1155 token ID.
/// @dev Deploy with `skipInterfaceCheck` for collections that do not implement ERC165.
contract ERC1155RoleProvider is IERC1155RoleProvider {
  bool public constant override isPullProvider = true;

  bytes4 private constant ERC1155_INTERFACE_ID = 0xd9b67a26;

  address public immutable override token;
  uint256 public immutable override tokenId;

  constructor(address token_, uint256 tokenId_, bool skipInterfaceCheck) {
    if (token_.code.length == 0) revert InvalidTokenAddress();
    if (
      !skipInterfaceCheck &&
      (!ERC165QueryLib.supportsERC165(token_) ||
        !ERC165QueryLib.supportsInterface(token_, ERC1155_INTERFACE_ID))
    ) {
      revert InvalidERC1155();
    }
    token = token_;
    tokenId = tokenId_;
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
      IERC1155BalanceOf.balanceOf.selector,
      uint160(account),
      tokenId
    );
    if (balance > 0) {
      return block.timestamp.toUint32();
    }
    return 0;
  }

}
