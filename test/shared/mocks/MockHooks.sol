// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'src/access/IHooks.sol';

event OnDepositCalled(
  address lender,
  uint256 scaledAmount,
  MarketState intermediateState,
  bytes extraData
);
event OnQueueWithdrawalCalled(
  address lender,
  uint scaledAmount,
  MarketState intermediateState,
  bytes extraData
);
event OnExecuteWithdrawalCalled(
  address lender,
  uint128 normalizedAmountWithdrawn,
  MarketState intermediateState,
  bytes extraData
);
event OnTransferCalled(
  address caller,
  address from,
  address to,
  uint scaledAmount,
  MarketState intermediateState,
  bytes extraData
);
event OnBorrowCalled(uint normalizedAmount, MarketState intermediateState, bytes extraData);
event OnRepayCalled(uint normalizedAmount, MarketState intermediateState, bytes extraData);
event OnCloseMarketCalled(MarketState intermediateState, bytes extraData);
event OnAssetsSentToEscrowCalled(
  address lender,
  address asset,
  address escrow,
  uint scaledAmount,
  MarketState intermediateState,
  bytes extraData
);
event OnSetMaxTotalSupplyCalled(
  uint256 maxTotalSupply,
  MarketState intermediateState,
  bytes extraData
);
event OnSetAnnualInterestAndReserveRatioBipsCalled(
  uint16 annualInterestBips,
  uint16 reserveRatioBips,
  MarketState intermediateState,
  bytes extraData
);

contract MockHooks is IHooks {
  bytes32 public lastCalldataHash;
  address public deployer;
  bytes public constructorArgs;
  bytes32 public immutable constructorArgsHash;
  HooksConfig public override config;
  address public lastDeployer;
  DeployMarketInputs internal _lastDeployMarketInputs;
  bytes public lastCreateMarketHooksData;

  function lastDeployMarketInputs() external view returns (DeployMarketInputs memory) {
    return _lastDeployMarketInputs;
  }

  constructor(address _caller, bytes memory _constructorArgs) {
    deployer = _caller;
    constructorArgs = _constructorArgs;
    constructorArgsHash = keccak256(_constructorArgs);
  }

  /// @dev Returns the version string of the hooks contract.
  ///      Used to determine what the contract does and how `extraData` is interpreted.
  function version() external view override returns (string memory) {
    return 'mock-hooks';
  }

  function setConfig(HooksConfig _config) external {
    config = _config;
  }

  function _onCreateMarket(
    address deployer,
    DeployMarketInputs calldata parameters,
    bytes calldata extraData
  ) internal virtual override {
    lastDeployer = deployer;
    _lastDeployMarketInputs = parameters;
    lastCreateMarketHooksData = extraData;
  }

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnDepositCalled(lender, scaledAmount, intermediateState, extraData);
  }

  function onQueueWithdrawal(
    address lender,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnQueueWithdrawalCalled(lender, scaledAmount, intermediateState, extraData);
  }

  function onExecuteWithdrawal(
    address lender,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnExecuteWithdrawalCalled(lender, normalizedAmountWithdrawn, intermediateState, extraData);
  }

  function onTransfer(
    address caller,
    address from,
    address to,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnTransferCalled(caller, from, to, scaledAmount, intermediateState, extraData);
  }

  function onBorrow(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnBorrowCalled(normalizedAmount, intermediateState, extraData);
  }

  function onRepay(
    uint normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnRepayCalled(normalizedAmount, intermediateState, extraData);
  }

  function onCloseMarket(
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnCloseMarketCalled(intermediateState, extraData);
  }

  function onAssetsSentToEscrow(
    address lender,
    address asset,
    address escrow,
    uint scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnAssetsSentToEscrowCalled(
      lender,
      asset,
      escrow,
      scaledAmount,
      intermediateState,
      extraData
    );
  }

  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external virtual override {
    lastCalldataHash = keccak256(msg.data);
    emit OnSetMaxTotalSupplyCalled(maxTotalSupply, intermediateState, extraData);
  }

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  )
    external
    virtual
    override
    returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips)
  {
    lastCalldataHash = keccak256(msg.data);
    emit OnSetAnnualInterestAndReserveRatioBipsCalled(annualInterestBips, reserveRatioBips, intermediateState, extraData);
  }
}
