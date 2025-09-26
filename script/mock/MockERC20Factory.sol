// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.17;

import 'src/libraries/LibStoredInitCode.sol';
import './MockERC20.sol';

contract MockERC20Factory {
  event NewTokenDeployed(address indexed token, string name, string symbol, uint8 decimals);

  // ========================================================================== //
  //                                  Constants                                 //
  // ========================================================================== //
  address public immutable mockERC20InitCodeStorage;

  uint256 public immutable mockERC20InitCodeHash;

  uint256 internal immutable ownCreate2Prefix = LibStoredInitCode.getCreate2Prefix(address(this));

  // ========================================================================== //
  //                                   Storage                                  //
  // ========================================================================== //

  mapping(address => uint256) public deployerNonce;

  string internal _tmpName;
  string internal _tmpSymbol;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  constructor() {
    (mockERC20InitCodeStorage, mockERC20InitCodeHash) = _storeMockERC20InitCode();
  }

  function _storeMockERC20InitCode()
    internal
    virtual
    returns (address initCodeStorage, uint256 initCodeHash)
  {
    bytes memory mockERC20InitCode = type(MockERC20).creationCode;
    initCodeHash = uint256(keccak256(mockERC20InitCode));
    initCodeStorage = LibStoredInitCode.deployInitCode(mockERC20InitCode);
  }

  // ========================================================================== //
  //                                   Queries                                  //
  // ========================================================================== //

  function getDeployParameters() external view returns (string memory name, string memory symbol) {
    return (_tmpName, _tmpSymbol);
  }

  function getNextTokenAddress(address deployer) public view returns (address tokenAddress) {
    bytes32 salt = keccak256(abi.encodePacked(deployer, deployerNonce[deployer]));
    tokenAddress = LibStoredInitCode.calculateCreate2Address(
      ownCreate2Prefix,
      salt,
      mockERC20InitCodeHash
    );
  }

  // ========================================================================== //
  //                                   Deploy                                   //
  // ========================================================================== //

  function deployMockERC20(string memory name, string memory symbol) external returns (address) {
    _tmpName = name;
    _tmpSymbol = symbol;
    bytes32 salt = keccak256(abi.encodePacked(msg.sender, deployerNonce[msg.sender]++));
    MockERC20 token = MockERC20(
      LibStoredInitCode.create2WithStoredInitCode(mockERC20InitCodeStorage, salt)
    );
    _tmpName = '';
    _tmpSymbol = '';
    token.mint(msg.sender, 100e18);
    emit NewTokenDeployed(address(token), name, symbol, 18);
    return address(token);
  }
}