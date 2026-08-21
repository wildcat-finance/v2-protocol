// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC165SupportsInterface {
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

library ERC165QueryLib {
  bytes4 internal constant ERC165_INTERFACE_ID = 0x01ffc9a7;
  bytes4 internal constant INVALID_INTERFACE_ID = 0xffffffff;

  function supportsERC165(address target) internal view returns (bool) {
    return
      supportsInterface(target, ERC165_INTERFACE_ID) &&
      !supportsInterface(target, INVALID_INTERFACE_ID);
  }

  function supportsInterface(
    address target,
    bytes4 interfaceId
  ) internal view returns (bool value) {
    uint256 selectorWord = uint32(IERC165SupportsInterface.supportsInterface.selector);
    uint256 interfaceIdWord = uint32(interfaceId);
    assembly {
      mstore(0x00, selectorWord)
      mstore(0x20, shl(224, interfaceIdWord))
      let success := staticcall(gas(), target, 0x1c, 0x24, 0x00, 0x20)
      value := and(success, and(iszero(lt(returndatasize(), 0x20)), eq(mload(0x00), 1)))
    }
  }
}

library TokenQueryLib {
  function readWord(
    address target,
    bytes4 selector,
    uint256 argument
  ) internal view returns (bool success, uint256 value) {
    uint256 selectorWord = uint32(selector);
    assembly {
      mstore(0x00, selectorWord)
      mstore(0x20, argument)
      success := staticcall(gas(), target, 0x1c, 0x24, 0x00, 0x20)
      success := and(success, iszero(lt(returndatasize(), 0x20)))
      value := mload(0x00)
    }
  }

  function readWordOrRevert(
    address target,
    bytes4 selector,
    uint256 argument
  ) internal view returns (uint256 value) {
    uint256 selectorWord = uint32(selector);
    assembly {
      mstore(0x00, selectorWord)
      mstore(0x20, argument)
      if iszero(staticcall(gas(), target, 0x1c, 0x24, 0x00, 0x20)) {
        returndatacopy(0x00, 0x00, returndatasize())
        revert(0x00, returndatasize())
      }
      if lt(returndatasize(), 0x20) {
        revert(0x00, 0x00)
      }
      value := mload(0x00)
    }
  }
}

interface IERC20BalanceOf {
  function balanceOf(address account) external view returns (uint256);
}

interface IERC4626Assets {
  function balanceOf(address account) external view returns (uint256);

  function convertToAssets(uint256 shares) external view returns (uint256);
}

interface IERC721BalanceOf {
  function balanceOf(address account) external view returns (uint256);
}

interface IERC721OwnerOf {
  function ownerOf(uint256 tokenId) external view returns (address);
}

interface IERC1155BalanceOf {
  function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IERC5192Locked {
  function locked(uint256 tokenId) external view returns (bool);
}

interface IERC5484BurnAuth {
  function burnAuth(uint256 tokenId) external view returns (uint256);
}
