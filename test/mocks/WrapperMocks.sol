// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import { IMarketTransferPolicy } from 'src/access/IMarketTransferPolicy.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { IWildcatMarketToken, Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';

contract WrapperSentinelMock {
  address public constant Escrow = address(0xE5C0);

  mapping(address account => bool) public sanctioned;
  uint256 public createEscrowCalls;

  function setSanctioned(address account, bool value) external {
    sanctioned[account] = value;
  }

  function isSanctioned(address, address account) external view returns (bool) {
    return sanctioned[account];
  }

  function getEscrowAddress(address, address, address) external pure returns (address) {
    return Escrow;
  }

  function createEscrow(address, address, address) external returns (address) {
    createEscrowCalls++;
    return Escrow;
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

contract WrapperMarketMock is IWildcatMarketToken, IMarketTransferPolicy {
  using MathUtils for uint256;

  error NukeFailed();

  string public constant name = 'Mock fries USDC';
  string public constant symbol = 'friesUSDC';
  uint8 public immutable override decimals;

  uint256 public override scaleFactor = RAY;
  uint256 public override maxTotalSupply = type(uint128).max;
  address public override borrower;
  address public override borrowerPrincipal;
  address public immutable override sentinel;
  address public immutable override wrapperFactory;

  bool public transfersDisabled;
  bool public recipientAllowed = true;
  bool public nukeReverts;
  int256 public transferSkew;
  bytes32 public lastNukeCalldataHash;
  address public registeredWrapper;

  mapping(address account => uint256) internal _scaledBalances;
  mapping(address owner => mapping(address spender => uint256)) public override allowance;
  uint256 internal _scaledTotalSupply;

  constructor(
    uint8 decimals_,
    address borrower_,
    address borrowerPrincipal_,
    address sentinel_,
    address wrapperFactory_
  ) {
    decimals = decimals_;
    borrower = borrower_;
    borrowerPrincipal = borrowerPrincipal_;
    sentinel = sentinel_;
    wrapperFactory = wrapperFactory_;
  }

  function hooks() external view returns (HooksConfig) {
    return EmptyHooksConfig.setHooksAddress(address(this));
  }

  function scaledTransferRounding() external pure returns (bytes32) {
    return keccak256('scaleAmountDown');
  }

  function isMarketTransferDisabled(address market) external view returns (bool) {
    require(market == address(this), 'UNKNOWN_MARKET');
    return transfersDisabled;
  }

  function isMarketTransferRecipientAllowed(address market, address) external view returns (bool) {
    return market == address(this) && recipientAllowed && !transfersDisabled;
  }

  function setScaleFactor(uint256 scaleFactor_) external {
    require(scaleFactor_ >= RAY, 'INVALID_SCALE_FACTOR');
    scaleFactor = scaleFactor_;
  }

  function setMaxTotalSupply(uint256 maxTotalSupply_) external {
    maxTotalSupply = maxTotalSupply_;
  }

  function setBorrower(address borrower_, address borrowerPrincipal_) external {
    borrower = borrower_;
    borrowerPrincipal = borrowerPrincipal_;
  }

  function setTransferPolicy(bool transfersDisabled_, bool recipientAllowed_) external {
    transfersDisabled = transfersDisabled_;
    recipientAllowed = recipientAllowed_;
  }

  function setTransferSkew(int256 transferSkew_) external {
    transferSkew = transferSkew_;
  }

  function setNukeReverts(bool nukeReverts_) external {
    nukeReverts = nukeReverts_;
  }

  function registerWrapper(address wrapper) external {
    require(msg.sender == wrapperFactory, 'NOT_WRAPPER_FACTORY');
    require(registeredWrapper == address(0), 'WRAPPER_ALREADY_REGISTERED');
    registeredWrapper = wrapper;
  }

  function nukeFromOrbit(address) external {
    if (nukeReverts) revert NukeFailed();
    lastNukeCalldataHash = keccak256(msg.data);
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _scaledBalances[account].rayMul(scaleFactor);
  }

  function totalSupply() external view returns (uint256) {
    return _scaledTotalSupply.rayMul(scaleFactor);
  }

  function scaledBalanceOf(address account) external view returns (uint256) {
    return _scaledBalances[account];
  }

  function mint(address account, uint256 assets) external returns (uint256 scaledAmount) {
    scaledAmount = MathUtils.mulDiv(assets, RAY, scaleFactor);
    require(scaledAmount != 0, 'SCALED_ZERO');
    require(scaledAmount <= type(uint104).max, 'UINT104');
    _scaledBalances[account] += scaledAmount;
    _scaledTotalSupply += scaledAmount;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    uint256 allowed = allowance[from][msg.sender];
    if (allowed != type(uint256).max) {
      require(allowed >= amount, 'ALLOWANCE');
      allowance[from][msg.sender] = allowed - amount;
    }
    _transfer(from, to, amount);
    return true;
  }

  function _transfer(address from, address to, uint256 assets) private {
    uint256 expectedScaled = MathUtils.mulDiv(assets, RAY, scaleFactor);
    require(expectedScaled != 0, 'SCALED_ZERO');
    require(expectedScaled <= type(uint104).max, 'UINT104');

    int256 adjustedScaled = int256(expectedScaled) + transferSkew;
    require(adjustedScaled > 0, 'SCALED_ZERO');
    uint256 actualScaled = uint256(adjustedScaled);
    require(actualScaled <= type(uint104).max, 'UINT104');

    uint256 fromBalance = _scaledBalances[from];
    require(fromBalance >= actualScaled, 'BALANCE');
    unchecked {
      _scaledBalances[from] = fromBalance - actualScaled;
      _scaledBalances[to] += actualScaled;
    }
  }
}

contract WrapperPlainERC20Mock {
  mapping(address account => uint256) public balanceOf;

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address to, uint256 amount) external returns (bool) {
    uint256 balance = balanceOf[msg.sender];
    require(balance >= amount, 'BALANCE');
    unchecked {
      balanceOf[msg.sender] = balance - amount;
      balanceOf[to] += amount;
    }
    return true;
  }
}

contract WrapperSpoofEscrowMock {
  address public immutable borrower;

  constructor(address borrower_) {
    borrower = borrower_;
  }

  function transferShares(Wildcat4626Wrapper wrapper, address to, uint256 amount) external {
    wrapper.transfer(to, amount);
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
