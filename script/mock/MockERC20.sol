// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 as SoladyERC20 } from 'solady/tokens/ERC20.sol';

interface IParentFactory {
  function getDeployParameters() external view returns (string memory name, string memory symbol);
}

/// @dev WARNING! This mock is strictly intended for testing purposes only.
/// Do NOT copy anything here into production code unless you really know what you are doing.
contract MockERC20 is SoladyERC20 {
  string internal _name;
  string internal _symbol;
  bytes32 internal immutable _nameHash;

  bool public constant isMock = true;

  constructor() {
    (string memory name_, string memory symbol_) = IParentFactory(msg.sender)
      .getDeployParameters();
    _name = name_;
    _symbol = symbol_;
    _nameHash = keccak256(bytes(name_));
  }

  function _constantNameHash() internal view virtual override returns (bytes32) {
    return _nameHash;
  }

  function name() public view virtual override returns (string memory) {
    return _name;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  function decimals() public view virtual override returns (uint8) {
    return 18;
  }

  function mint(address to, uint256 value) public virtual {
    _mint(to, value);
  }

  function burn(address from, uint256 value) public virtual {
    _burn(from, value);
  }

  function faucet() external {
    _mint(msg.sender, 100e18);
  }
}
