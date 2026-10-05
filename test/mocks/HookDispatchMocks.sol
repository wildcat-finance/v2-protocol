// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // HookDispatchMocks
//  \ ^ /   Factory, sanctions, and callback-recording test doubles.
//    V
//
//  BORROWER REGISTRATION
//  isRegisteredBorrower(...)
//
//  REGISTRY SETUP
//  constructor(...)
//
//  SANCTIONS STATUS
//  setSanctioned(...)
//  isSanctioned(...)
//  isFlaggedByChainalysis(...)
//
//  ESCROW CREATION
//  createEscrow(...)
//  getEscrowAddress(...)
//
//  MARKET DEPLOYMENT
//  setMarketParameters(...)
//  getMarketParameters()
//  deployMarket(...)
//  callMarket(...)
//
//  REVOLVING CONFIGURATION
//  setRevolvingMarketCommitmentFeeResponse(...)
//  getRevolvingMarketCommitmentFeeBips()
//
//  LENS METADATA
//  setLensHooksTemplate(...)
//  getHooksTemplateForInstance(...)
//  getHooksTemplateDetails(...)
//  getMarketsForHooksTemplateCount(...)
//  getMarketsForHooksInstanceCount(...)
//
//  LENDER CALLBACKS
//  onDeposit(...)
//  onTransfer(...)
//  onQueueWithdrawal(...)
//  onExecuteWithdrawal(...)
//
//  BORROWER CALLBACKS
//  onBorrow(...)
//  onRepay(...)
//  onCloseMarket(...)
//
//  CONFIGURATION CALLBACKS
//  onSetMaxTotalSupply(...)
//  setAnnualInterestAndReserveRatioBips(...)
//  onSetAnnualInterestAndReserveRatioBips(...)
//  onSetProtocolFeeBips(...)
//  onNukeFromOrbit(...)
//
//  CALL RECORDS
//  callCount()
//  callAt(...)
// ═════

import { IHooks } from 'src/access/IHooks.sol';
import { HooksTemplate } from 'src/IHooksFactory.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';

// ┌─ HookDispatchArchControllerMock ───────────────────────────────────────────
contract HookDispatchArchControllerMock {
  // ░░▒▒▓▓██ [ BORROWER REGISTRATION ] ────────────────────────────────────────

  // ┌─ isRegisteredBorrower ─────
  function isRegisteredBorrower(address) external pure returns (bool) {
    return true;
  }
}

// ┌─ HookDispatchBorrowerRegistryMock ─────────────────────────────────────────
contract HookDispatchBorrowerRegistryMock {
  address public immutable archController;

  // ░░▒▒▓▓██ [ REGISTRY SETUP ] ───────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address archController_) {
    archController = archController_;
  }
}

// ┌─ HookDispatchSentinelMock ─────────────────────────────────────────────────
contract HookDispatchSentinelMock {
  address public constant EscrowAddress = address(0xE5C0);

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

  // ┌─ isFlaggedByChainalysis ─────
  function isFlaggedByChainalysis(address account) external view returns (bool) {
    return sanctioned[account];
  }

  // ░░▒▒▓▓██ [ ESCROW CREATION ] ──────────────────────────────────────────────

  // ┌─ createEscrow ─────
  function createEscrow(address, address, address) external returns (address) {
    createEscrowCalls++;
    return EscrowAddress;
  }

  // ┌─ getEscrowAddress ─────
  function getEscrowAddress(address, address, address) external pure returns (address) {
    return EscrowAddress;
  }
}

// ┌─ HookDispatchFactoryMock ──────────────────────────────────────────────────
contract HookDispatchFactoryMock {
  MarketParameters internal _parameters;
  address internal _lensHooksTemplate = address(0x7E4);
  uint256 internal _revolvingCommitmentFeeResponse = 500;
  uint256 internal _revolvingCommitmentFeeResponseSize = 32;
  bool internal _revolvingCommitmentFeeReverts;

  // ░░▒▒▓▓██ [ MARKET DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ setMarketParameters ─────
  function setMarketParameters(MarketParameters calldata parameters) external {
    _parameters = parameters;
  }

  // ┌─ getMarketParameters ─────
  function getMarketParameters() external view returns (MarketParameters memory) {
    return _parameters;
  }

  // ┌─ deployMarket ─────
  function deployMarket(bytes memory creationCode) external returns (address market) {
    assembly {
      market := create(0, add(creationCode, 0x20), mload(creationCode))
      if iszero(market) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }

  // ┌─ callMarket ─────
  function callMarket(address market, bytes calldata data) external returns (bytes memory result) {
    bool success;
    (success, result) = market.call(data);
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
  }

  // ░░▒▒▓▓██ [ REVOLVING CONFIGURATION ] ──────────────────────────────────────

  // ┌─ setRevolvingMarketCommitmentFeeResponse ─────
  function setRevolvingMarketCommitmentFeeResponse(uint256 response, uint256 responseSize, bool shouldRevert) external {
    _revolvingCommitmentFeeResponse = response;
    _revolvingCommitmentFeeResponseSize = responseSize;
    _revolvingCommitmentFeeReverts = shouldRevert;
  }

  // ┌─ getRevolvingMarketCommitmentFeeBips ─────
  function getRevolvingMarketCommitmentFeeBips() external view returns (uint16) {
    uint256 response = _revolvingCommitmentFeeResponse;
    uint256 responseSize = _revolvingCommitmentFeeResponseSize;
    bool shouldRevert = _revolvingCommitmentFeeReverts;
    assembly ('memory-safe') {
      mstore(0, response)
      if shouldRevert {
        revert(0, responseSize)
      }
      return(0, responseSize)
    }
  }

  // ░░▒▒▓▓██ [ LENS METADATA ] ────────────────────────────────────────────────

  // ┌─ setLensHooksTemplate ─────
  function setLensHooksTemplate(address hooksTemplate) external {
    _lensHooksTemplate = hooksTemplate;
  }

  // ┌─ getHooksTemplateForInstance ─────
  function getHooksTemplateForInstance(address) external view returns (address) {
    return _lensHooksTemplate;
  }

  // ┌─ getHooksTemplateDetails ─────
  function getHooksTemplateDetails(address hooksTemplate) external view returns (HooksTemplate memory data) {
    data.exists = hooksTemplate == _lensHooksTemplate;
    data.enabled = data.exists;
    data.name = data.exists ? 'Fixture Hooks' : '';
  }

  // ┌─ getMarketsForHooksTemplateCount ─────
  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
    return hooksTemplate == _lensHooksTemplate ? 1 : 0;
  }

  // ┌─ getMarketsForHooksInstanceCount ─────
  function getMarketsForHooksInstanceCount(address) external pure returns (uint256) {
    return 1;
  }
}

// ┌─ HookDispatchMock ─────────────────────────────────────────────────────────
contract HookDispatchMock {
  bytes[] internal _calls;
  bool internal _replaceAprAndReserveRatio;
  uint16 internal _annualInterestBips;
  uint16 internal _reserveRatioBips;

  // ░░▒▒▓▓██ [ LENDER CALLBACKS ] ─────────────────────────────────────────────

  // ┌─ onDeposit ─────
  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(abi.encodeWithSelector(IHooks.onDeposit.selector, lender, scaledAmount, intermediateState, extraData));
  }

  // ┌─ onTransfer ─────
  function onTransfer(
    address caller,
    address from,
    address to,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(
      abi.encodeWithSelector(IHooks.onTransfer.selector, caller, from, to, scaledAmount, intermediateState, extraData)
    );
  }

  // ┌─ onQueueWithdrawal ─────
  function onQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onQueueWithdrawal.selector, lender, expiry, scaledAmount, intermediateState, extraData
      )
    );
  }

  // ┌─ onExecuteWithdrawal ─────
  function onExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onExecuteWithdrawal.selector, lender, expiry, normalizedAmountWithdrawn, intermediateState, extraData
      )
    );
  }

  // ░░▒▒▓▓██ [ BORROWER CALLBACKS ] ───────────────────────────────────────────

  // ┌─ onBorrow ─────
  function onBorrow(
    uint256 normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(abi.encodeWithSelector(IHooks.onBorrow.selector, normalizedAmount, intermediateState, extraData));
  }

  // ┌─ onRepay ─────
  function onRepay(
    uint256 normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(abi.encodeWithSelector(IHooks.onRepay.selector, normalizedAmount, intermediateState, extraData));
  }

  // ┌─ onCloseMarket ─────
  function onCloseMarket(MarketState calldata intermediateState, bytes calldata extraData) external {
    _calls.push(abi.encodeWithSelector(IHooks.onCloseMarket.selector, intermediateState, extraData));
  }

  // ░░▒▒▓▓██ [ CONFIGURATION CALLBACKS ] ──────────────────────────────────────

  // ┌─ onSetMaxTotalSupply ─────
  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(
      abi.encodeWithSelector(IHooks.onSetMaxTotalSupply.selector, maxTotalSupply, intermediateState, extraData)
    );
  }

  // ┌─ setAnnualInterestAndReserveRatioBips ─────
  function setAnnualInterestAndReserveRatioBips(uint16 annualInterestBips, uint16 reserveRatioBips) external {
    _replaceAprAndReserveRatio = true;
    _annualInterestBips = annualInterestBips;
    _reserveRatioBips = reserveRatioBips;
  }

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips)
  {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onSetAnnualInterestAndReserveRatioBips.selector,
        annualInterestBips,
        reserveRatioBips,
        intermediateState,
        extraData
      )
    );
    if (_replaceAprAndReserveRatio) return (_annualInterestBips, _reserveRatioBips);
    return (annualInterestBips, reserveRatioBips);
  }

  // ┌─ onSetProtocolFeeBips ─────
  function onSetProtocolFeeBips(
    uint16 protocolFeeBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
  {
    _calls.push(
      abi.encodeWithSelector(IHooks.onSetProtocolFeeBips.selector, protocolFeeBips, intermediateState, extraData)
    );
  }

  // ┌─ onNukeFromOrbit ─────
  function onNukeFromOrbit(address lender, MarketState calldata intermediateState, bytes calldata extraData) external {
    _calls.push(abi.encodeWithSelector(IHooks.onNukeFromOrbit.selector, lender, intermediateState, extraData));
  }

  // ░░▒▒▓▓██ [ CALL RECORDS ] ─────────────────────────────────────────────────

  // ┌─ callCount ─────
  function callCount() external view returns (uint256) {
    return _calls.length;
  }

  // ┌─ callAt ─────
  function callAt(uint256 index) external view returns (bytes memory) {
    return _calls[index];
  }
}
