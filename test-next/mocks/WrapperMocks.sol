// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IMarketTransferPolicy } from 'src/access/IMarketTransferPolicy.sol';
import { IWildcatMarketToken } from 'src/vault/Wildcat4626Wrapper.sol';
import { EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';

contract WrapperSentinelMock {
  mapping(address account => bool) public sanctioned;

  function setSanctioned(address account, bool value) external {
    sanctioned[account] = value;
  }

  function isSanctioned(address, address account) external view returns (bool) {
    return sanctioned[account];
  }

  function getEscrowAddress(address, address, address) external pure returns (address) {
    return address(0xE5C0);
  }
}

contract WrapperArchControllerMock {
  mapping(address market => bool) public isRegisteredMarket;

  function setRegisteredMarket(address market, bool registered) external {
    isRegisteredMarket[market] = registered;
  }
}

contract WrapperV1FactoryMock {
  error WrapperAlreadyExists(address market);

  mapping(address market => address wrapper) public wrapperForMarket;
  uint256 public createCalls;

  function seedWrapper(address market, address wrapper) external {
    wrapperForMarket[market] = wrapper;
  }

  function createWrapper(address market) external returns (address wrapper) {
    if (wrapperForMarket[market] != address(0)) revert WrapperAlreadyExists(market);
    createCalls++;
    wrapper = address(uint160(uint256(keccak256(abi.encode('v1-wrapper', market)))));
    wrapperForMarket[market] = wrapper;
  }
}

contract WrapperFactoryMarketMock is IWildcatMarketToken, IMarketTransferPolicy {
  string public constant name = 'Factory Market';
  string public constant symbol = 'factoryUSDC';
  uint8 public constant override decimals = 18;

  uint256 public constant override scaleFactor = 1e27;
  uint256 public constant override maxTotalSupply = type(uint128).max;
  address public immutable override borrower;
  address public immutable override borrowerPrincipal;
  address public immutable override sentinel;
  address public immutable override wrapperFactory;

  address public hooksAddress;
  address public registeredWrapper;
  bool public roundingDeclared;
  bytes32 public rounding;
  bool public transfersDisabled;
  bool public recipientAllowed = true;
  bool public recipientCheckReverts;

  mapping(address account => uint256) public override balanceOf;
  mapping(address owner => mapping(address spender => uint256)) public override allowance;

  constructor(
    address borrower_,
    address sentinel_,
    address wrapperFactory_,
    bool roundingDeclared_,
    bytes32 rounding_
  ) {
    borrower = borrower_;
    borrowerPrincipal = borrower_;
    sentinel = sentinel_;
    wrapperFactory = wrapperFactory_;
    hooksAddress = address(this);
    roundingDeclared = roundingDeclared_;
    rounding = rounding_;
  }

  function hooks() external view returns (HooksConfig) {
    return EmptyHooksConfig.setHooksAddress(hooksAddress);
  }

  function setHooksAddress(address hooksAddress_) external {
    hooksAddress = hooksAddress_;
  }

  function setTransferPolicy(
    bool transfersDisabled_,
    bool recipientAllowed_,
    bool recipientCheckReverts_
  ) external {
    transfersDisabled = transfersDisabled_;
    recipientAllowed = recipientAllowed_;
    recipientCheckReverts = recipientCheckReverts_;
  }

  function scaledTransferRounding() external view returns (bytes32) {
    if (!roundingDeclared) revert('NO_ROUNDING_DECLARATION');
    return rounding;
  }

  function isMarketTransferDisabled(address market) external view returns (bool) {
    require(market == address(this), 'UNKNOWN_MARKET');
    return transfersDisabled;
  }

  function isMarketTransferRecipientAllowed(address market, address) external view returns (bool) {
    if (recipientCheckReverts) revert('RECIPIENT_CHECK_FAILED');
    return market == address(this) && recipientAllowed;
  }

  function registerWrapper(address wrapper) external {
    require(msg.sender == wrapperFactory, 'NOT_WRAPPER_FACTORY');
    require(registeredWrapper == address(0), 'WRAPPER_ALREADY_REGISTERED');
    registeredWrapper = wrapper;
  }

  function totalSupply() external pure returns (uint256) {
    return 0;
  }

  function scaledBalanceOf(address account) external view returns (uint256) {
    return balanceOf[account];
  }

  function transfer(address, uint256) external pure returns (bool) {
    revert('UNSUPPORTED');
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transferFrom(address, address, uint256) external pure returns (bool) {
    revert('UNSUPPORTED');
  }
}

contract IncompleteWrapperTransferPolicyMock {
  function isMarketTransferDisabled(address) external pure returns (bool) {
    return false;
  }
}

contract WrapperShortReturnMock {
  fallback() external {
    assembly {
      return(0, 0x10)
    }
  }
}

contract WrapperWrongRoundingMock {
  function scaledTransferRounding() external pure returns (bytes32) {
    return keccak256('somethingElse');
  }
}

contract WrapperReturnBombMock {
  fallback() external {
    assembly {
      return(0, 0x1000000)
    }
  }
}
