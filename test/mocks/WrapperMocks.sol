// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // WrapperMocks
// ║  ██▀▀     ▀▀██   Wrapper market, transfer-policy, and adversarial test doubles.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SANCTIONS STATUS
// ║  setSanctioned(...)
// ║  isSanctioned(...)
// ║
// ║  ESCROW CREATION
// ║  createEscrow(...)
// ║  getEscrowAddress(...)
// ║
// ║  MARKET REGISTRATION
// ║  setRegisteredMarket(...)
// ║
// ║  V1 WRAPPER CREATION
// ║  seedWrapper(...)
// ║  createWrapper(...)
// ║
// ║  FACTORY MARKET SETUP
// ║  constructor(...)
// ║  registerWrapper(...)
// ║
// ║  FACTORY MARKET POLICY
// ║  setHooksAddress(...)
// ║  hooks()
// ║  setTransferPolicy(...)
// ║  isMarketTransferDisabled(...)
// ║  isMarketTransferRecipientAllowed(...)
// ║  scaledTransferRounding()
// ║
// ║  FACTORY MARKET TOKEN
// ║  approve(...)
// ║  transfer(...)
// ║  transferFrom(...)
// ║  totalSupply()
// ║  scaledBalanceOf(...)
// ║
// ║  WRAPPER MARKET SETUP
// ║  constructor(...)
// ║  registerWrapper(...)
// ║  setScaleFactor(...)
// ║  setMaxTotalSupply(...)
// ║  setBorrower(...)
// ║
// ║  WRAPPER MARKET POLICY
// ║  hooks()
// ║  setTransferPolicy(...)
// ║  isMarketTransferDisabled(...)
// ║  isMarketTransferRecipientAllowed(...)
// ║  scaledTransferRounding()
// ║
// ║  WRAPPER MARKET TRANSFERS
// ║  mint(...)
// ║  approve(...)
// ║  setTransferSkew(...)
// ║  transfer(...)
// ║  transferFrom(...)
// ║  _transfer(...)
// ║  balanceOf(...)
// ║  scaledBalanceOf(...)
// ║  totalSupply()
// ║
// ║  WRAPPER MARKET SANCTIONS
// ║  setNukeReverts(...)
// ║  nukeFromOrbit(...)
// ║
// ║  PLAIN TOKEN TRANSFERS
// ║  mint(...)
// ║  transfer(...)
// ║
// ║  SPOOFED ESCROW
// ║  constructor(...)
// ║  transferShares(...)
// ║
// ║  INCOMPLETE POLICY
// ║  isMarketTransferDisabled(...)
// ║
// ║  SHORT RETURNS
// ║  fallback()
// ║
// ║  WRONG ROUNDING
// ║  scaledTransferRounding()
// ║
// ║  RETURN DATA BOMB
// ║  fallback()
// ╚═════

import { IMarketTransferPolicy } from 'src/access/IMarketTransferPolicy.sol';
import { MathUtils, RAY } from 'src/libraries/MathUtils.sol';
import { IWildcatMarketToken, Wildcat4626Wrapper } from 'src/vault/Wildcat4626Wrapper.sol';
import { EmptyHooksConfig, HooksConfig } from 'src/types/HooksConfig.sol';

// ┌─ WrapperSentinelMock ──────────────────────────────────────────────────────
contract WrapperSentinelMock {
  address public constant Escrow = address(0xE5C0);

  mapping(address account => bool) public sanctioned;
  uint256 public createEscrowCalls;

  // ░░▒▒▓▓██ [ SANCTIONS STATUS ] ─────────────────────────────────────────────

  // ┌─ setSanctioned ─────
  function setSanctioned(address account, bool value) external {
    sanctioned[account] = value;
  }

  // ┌─ isSanctioned ─────
  function isSanctioned(address, address account) external view returns (bool) {
    return sanctioned[account];
  }

  // ░░▒▒▓▓██ [ ESCROW CREATION ] ──────────────────────────────────────────────

  // ┌─ createEscrow ─────
  function createEscrow(address, address, address) external returns (address) {
    createEscrowCalls++;
    return Escrow;
  }

  // ┌─ getEscrowAddress ─────
  function getEscrowAddress(address, address, address) external pure returns (address) {
    return Escrow;
  }
}

// ┌─ WrapperArchControllerMock ────────────────────────────────────────────────
contract WrapperArchControllerMock {
  mapping(address market => bool) public isRegisteredMarket;

  // ░░▒▒▓▓██ [ MARKET REGISTRATION ] ──────────────────────────────────────────

  // ┌─ setRegisteredMarket ─────
  function setRegisteredMarket(address market, bool registered) external {
    isRegisteredMarket[market] = registered;
  }
}

// ┌─ WrapperV1FactoryMock ─────────────────────────────────────────────────────
contract WrapperV1FactoryMock {
  error WrapperAlreadyExists(address market);

  mapping(address market => address wrapper) public wrapperForMarket;
  uint256 public createCalls;

  // ░░▒▒▓▓██ [ V1 WRAPPER CREATION ] ──────────────────────────────────────────

  // ┌─ seedWrapper ─────
  function seedWrapper(address market, address wrapper) external {
    wrapperForMarket[market] = wrapper;
  }

  // ┌─ createWrapper ─────
  function createWrapper(address market) external returns (address wrapper) {
    if (wrapperForMarket[market] != address(0)) revert WrapperAlreadyExists(market);
    createCalls++;
    wrapper = address(uint160(uint256(keccak256(abi.encode('v1-wrapper', market)))));
    wrapperForMarket[market] = wrapper;
  }
}

// ┌─ WrapperFactoryMarketMock ─────────────────────────────────────────────────
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

  // ░░▒▒▓▓██ [ FACTORY MARKET SETUP ] ─────────────────────────────────────────

  // ┌─ constructor ─────
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

  // ┌─ registerWrapper ─────
  function registerWrapper(address wrapper) external {
    require(msg.sender == wrapperFactory, 'NOT_WRAPPER_FACTORY');
    require(registeredWrapper == address(0), 'WRAPPER_ALREADY_REGISTERED');
    registeredWrapper = wrapper;
  }

  // ░░▒▒▓▓██ [ FACTORY MARKET POLICY ] ────────────────────────────────────────

  // ┌─ setHooksAddress ─────
  function setHooksAddress(address hooksAddress_) external {
    hooksAddress = hooksAddress_;
  }

  // ┌─ hooks ─────
  function hooks() external view returns (HooksConfig) {
    return EmptyHooksConfig.setHooksAddress(hooksAddress);
  }

  // ┌─ setTransferPolicy ─────
  function setTransferPolicy(bool transfersDisabled_, bool recipientAllowed_, bool recipientCheckReverts_) external {
    transfersDisabled = transfersDisabled_;
    recipientAllowed = recipientAllowed_;
    recipientCheckReverts = recipientCheckReverts_;
  }

  // ┌─ isMarketTransferDisabled ─────
  function isMarketTransferDisabled(address market) external view returns (bool) {
    require(market == address(this), 'UNKNOWN_MARKET');
    return transfersDisabled;
  }

  // ┌─ isMarketTransferRecipientAllowed ─────
  function isMarketTransferRecipientAllowed(address market, address) external view returns (bool) {
    if (recipientCheckReverts) revert('RECIPIENT_CHECK_FAILED');
    return market == address(this) && recipientAllowed;
  }

  // ┌─ scaledTransferRounding ─────
  function scaledTransferRounding() external view returns (bytes32) {
    if (!roundingDeclared) revert('NO_ROUNDING_DECLARATION');
    return rounding;
  }

  // ░░▒▒▓▓██ [ FACTORY MARKET TOKEN ] ─────────────────────────────────────────

  // ┌─ approve ─────
  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  // ┌─ transfer ─────
  function transfer(address, uint256) external pure returns (bool) {
    revert('UNSUPPORTED');
  }

  // ┌─ transferFrom ─────
  function transferFrom(address, address, uint256) external pure returns (bool) {
    revert('UNSUPPORTED');
  }

  // ┌─ totalSupply ─────
  function totalSupply() external pure returns (uint256) {
    return 0;
  }

  // ┌─ scaledBalanceOf ─────
  function scaledBalanceOf(address account) external view returns (uint256) {
    return balanceOf[account];
  }
}

// ┌─ WrapperMarketMock ────────────────────────────────────────────────────────
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

  // ░░▒▒▓▓██ [ WRAPPER MARKET SETUP ] ─────────────────────────────────────────

  // ┌─ constructor ─────
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

  // ┌─ registerWrapper ─────
  function registerWrapper(address wrapper) external {
    require(msg.sender == wrapperFactory, 'NOT_WRAPPER_FACTORY');
    require(registeredWrapper == address(0), 'WRAPPER_ALREADY_REGISTERED');
    registeredWrapper = wrapper;
  }

  // ┌─ setScaleFactor ─────
  function setScaleFactor(uint256 scaleFactor_) external {
    require(scaleFactor_ >= RAY, 'INVALID_SCALE_FACTOR');
    scaleFactor = scaleFactor_;
  }

  // ┌─ setMaxTotalSupply ─────
  function setMaxTotalSupply(uint256 maxTotalSupply_) external {
    maxTotalSupply = maxTotalSupply_;
  }

  // ┌─ setBorrower ─────
  function setBorrower(address borrower_, address borrowerPrincipal_) external {
    borrower = borrower_;
    borrowerPrincipal = borrowerPrincipal_;
  }

  // ░░▒▒▓▓██ [ WRAPPER MARKET POLICY ] ────────────────────────────────────────

  // ┌─ hooks ─────
  function hooks() external view returns (HooksConfig) {
    return EmptyHooksConfig.setHooksAddress(address(this));
  }

  // ┌─ setTransferPolicy ─────
  function setTransferPolicy(bool transfersDisabled_, bool recipientAllowed_) external {
    transfersDisabled = transfersDisabled_;
    recipientAllowed = recipientAllowed_;
  }

  // ┌─ isMarketTransferDisabled ─────
  function isMarketTransferDisabled(address market) external view returns (bool) {
    require(market == address(this), 'UNKNOWN_MARKET');
    return transfersDisabled;
  }

  // ┌─ isMarketTransferRecipientAllowed ─────
  function isMarketTransferRecipientAllowed(address market, address) external view returns (bool) {
    return market == address(this) && recipientAllowed && !transfersDisabled;
  }

  // ┌─ scaledTransferRounding ─────
  function scaledTransferRounding() external pure returns (bytes32) {
    return keccak256('scaleAmountDown');
  }

  // ░░▒▒▓▓██ [ WRAPPER MARKET TRANSFERS ] ─────────────────────────────────────

  // ┌─ mint ─────
  function mint(address account, uint256 assets) external returns (uint256 scaledAmount) {
    scaledAmount = MathUtils.mulDiv(assets, RAY, scaleFactor);
    require(scaledAmount != 0, 'SCALED_ZERO');
    require(scaledAmount <= type(uint104).max, 'UINT104');
    _scaledBalances[account] += scaledAmount;
    _scaledTotalSupply += scaledAmount;
  }

  // ┌─ approve ─────
  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  // ┌─ setTransferSkew ─────
  function setTransferSkew(int256 transferSkew_) external {
    transferSkew = transferSkew_;
  }

  // ┌─ transfer ─────
  function transfer(address to, uint256 amount) external returns (bool) {
    _transfer(msg.sender, to, amount);
    return true;
  }

  // ┌─ transferFrom ─────
  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    uint256 allowed = allowance[from][msg.sender];
    if (allowed != type(uint256).max) {
      require(allowed >= amount, 'ALLOWANCE');
      allowance[from][msg.sender] = allowed - amount;
    }
    _transfer(from, to, amount);
    return true;
  }

  // ┌─ _transfer ─────
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

  // ┌─ balanceOf ─────
  function balanceOf(address account) public view override returns (uint256) {
    return _scaledBalances[account].rayMul(scaleFactor);
  }

  // ┌─ scaledBalanceOf ─────
  function scaledBalanceOf(address account) external view returns (uint256) {
    return _scaledBalances[account];
  }

  // ┌─ totalSupply ─────
  function totalSupply() external view returns (uint256) {
    return _scaledTotalSupply.rayMul(scaleFactor);
  }

  // ░░▒▒▓▓██ [ WRAPPER MARKET SANCTIONS ] ─────────────────────────────────────

  // ┌─ setNukeReverts ─────
  function setNukeReverts(bool nukeReverts_) external {
    nukeReverts = nukeReverts_;
  }

  // ┌─ nukeFromOrbit ─────
  function nukeFromOrbit(address) external {
    if (nukeReverts) revert NukeFailed();
    lastNukeCalldataHash = keccak256(msg.data);
  }
}

// ┌─ WrapperPlainERC20Mock ────────────────────────────────────────────────────
contract WrapperPlainERC20Mock {
  mapping(address account => uint256) public balanceOf;

  // ░░▒▒▓▓██ [ PLAIN TOKEN TRANSFERS ] ────────────────────────────────────────

  // ┌─ mint ─────
  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  // ┌─ transfer ─────
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

// ┌─ WrapperSpoofEscrowMock ───────────────────────────────────────────────────
contract WrapperSpoofEscrowMock {
  address public immutable borrower;

  // ░░▒▒▓▓██ [ SPOOFED ESCROW ] ───────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address borrower_) {
    borrower = borrower_;
  }

  // ┌─ transferShares ─────
  function transferShares(Wildcat4626Wrapper wrapper, address to, uint256 amount) external {
    wrapper.transfer(to, amount);
  }
}

// ┌─ IncompleteWrapperTransferPolicyMock ──────────────────────────────────────
contract IncompleteWrapperTransferPolicyMock {
  // ░░▒▒▓▓██ [ INCOMPLETE POLICY ] ────────────────────────────────────────────

  // ┌─ isMarketTransferDisabled ─────
  function isMarketTransferDisabled(address) external pure returns (bool) {
    return false;
  }
}

// ┌─ WrapperShortReturnMock ───────────────────────────────────────────────────
contract WrapperShortReturnMock {
  // ░░▒▒▓▓██ [ SHORT RETURNS ] ────────────────────────────────────────────────

  // ┌─ fallback ─────
  fallback() external {
    assembly {
      return(0, 0x10)
    }
  }
}

// ┌─ WrapperWrongRoundingMock ─────────────────────────────────────────────────
contract WrapperWrongRoundingMock {
  // ░░▒▒▓▓██ [ WRONG ROUNDING ] ───────────────────────────────────────────────

  // ┌─ scaledTransferRounding ─────
  function scaledTransferRounding() external pure returns (bytes32) {
    return keccak256('somethingElse');
  }
}

// ┌─ WrapperReturnBombMock ────────────────────────────────────────────────────
contract WrapperReturnBombMock {
  // ░░▒▒▓▓██ [ RETURN DATA BOMB ] ─────────────────────────────────────────────

  // ┌─ fallback ─────
  fallback() external {
    assembly {
      return(0, 0x1000000)
    }
  }
}
