// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import './MockHooks.sol';

contract RevertingHooks is MockHooks {
  error OnDepositReverted();
  error OnQueueWithdrawalReverted();
  error OnExecuteWithdrawalReverted();
  error OnTransferReverted();
  error OnBorrowReverted();
  error OnRepayReverted();
  error OnCloseMarketReverted();
  error OnNukeFromOrbitReverted();
  error OnSetMaxTotalSupplyReverted();
  error OnSetAnnualInterestAndReserveRatioBipsReverted();
  error OnSetProtocolFeeBipsReverted();

  bool public shouldRevert;

  constructor(
    address _caller,
    bytes memory _constructorArgs
  ) MockHooks(_caller, _constructorArgs) {}

  function setShouldRevert(bool value) external {
    shouldRevert = value;
  }

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnDepositReverted();
    lastExtraData = extraData;
    lastCalldataHash = keccak256(msg.data);
    emit OnDepositCalled(lender, scaledAmount, intermediateState, extraData);
  }

  function onQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnQueueWithdrawalReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnQueueWithdrawalCalled(lender, expiry, scaledAmount, intermediateState, extraData);
  }

  function onExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnExecuteWithdrawalReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnExecuteWithdrawalCalled(
      lender,
      expiry,
      normalizedAmountWithdrawn,
      intermediateState,
      extraData
    );
  }

  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnTransferReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnTransferCalled(caller, from, to, scaledAmount, intermediateState, extraData);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnBorrowReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnBorrowCalled(normalizedAmount, intermediateState, extraData);
  }

  function onRepay(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnRepayReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnRepayCalled(normalizedAmount, intermediateState, extraData);
  }

  function onCloseMarket(
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnCloseMarketReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnCloseMarketCalled(intermediateState, extraData);
  }

  function onNukeFromOrbit(
    address lender,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnNukeFromOrbitReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnNukeFromOrbitCalled(lender, intermediateState, extraData);
  }

  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnSetMaxTotalSupplyReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnSetMaxTotalSupplyCalled(maxTotalSupply, intermediateState, extraData);
  }

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips) {
    if (shouldRevert) revert OnSetAnnualInterestAndReserveRatioBipsReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnSetAnnualInterestAndReserveRatioBipsCalled(
      annualInterestBips,
      reserveRatioBips,
      intermediateState,
      extraData
    );
    return (annualInterestBips, reserveRatioBips);
  }

  function onSetProtocolFeeBips(
    uint16 protocolFeeBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external override {
    if (shouldRevert) revert OnSetProtocolFeeBipsReverted();
    lastCalldataHash = keccak256(msg.data);
    emit OnSetProtocolFeeBipsCalled(protocolFeeBips, intermediateState, extraData);
  }
}
