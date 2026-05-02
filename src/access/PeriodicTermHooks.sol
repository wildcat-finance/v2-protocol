// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import './MarketConstraintHooks.sol';
import '../libraries/SafeCastLib.sol';
import './BaseAccessControls.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

struct HookedMarket {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  bool withdrawalRequiresAccess;
  bool depositHookEnabled;
  uint128 minimumDeposit;
  uint32 periodStart;
  uint32 periodDuration;
  uint32 withdrawalWindowDuration;
  bool transfersDisabled;
  bool isClosed;
}

/**
 * @title PeriodicTermHooks
 * @dev Hooks contract for markets where withdrawals may only be queued during
 *      a recurring end-of-period window. Withdrawal batches still expire using
 *      the market's immutable `withdrawalBatchDuration`.
 */
contract PeriodicTermHooks is BaseAccessControls, MarketConstraintHooks {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  event MinimumDepositUpdated(address market, uint128 newMinimumDeposit);
  event PeriodicTermUpdated(
    address market,
    uint32 periodStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration
  );
  event PeriodicTermClosed(address market);

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  error NotHookedMarket();
  error DepositBelowMinimum();
  error TransfersDisabled();
  error PeriodicWindowNotProvided();
  error InitialWithdrawalWindowTooFarInFuture();
  error PeriodDurationOutOfBounds();
  error WithdrawalWindowDurationOutOfBounds();
  error DepositHookNotEnabled();
  error WithdrawOutsideWindow();
  error NoReducingAprOutsideWithdrawalWindow();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  HooksDeploymentConfig public immutable override config;

  uint32 public constant MinimumPeriodDuration = 1 days;
  uint32 public constant MaximumPeriodDuration = 365 days;
  uint32 public constant MinimumWithdrawalWindowDuration = 1 hours;
  uint32 public constant MaximumInitialWithdrawalWindowDelay = MaximumPeriodDuration;

  mapping(address => HookedMarket) internal _hookedMarkets;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  /**
   * @param _deployer Address of the account that called the factory.
   * @param args Optional abi-encoded `NameAndProviderInputs` struct to initialize
   *             the providers and name for the hooks instance.
   */
  constructor(address _deployer, bytes memory args) BaseAccessControls(_deployer) IHooks() {
    HooksConfig optionalFlags = encodeHooksConfig({
      hooksAddress: address(0),
      useOnDeposit: true,
      useOnQueueWithdrawal: false,
      useOnExecuteWithdrawal: false,
      useOnTransfer: true,
      useOnBorrow: false,
      useOnRepay: false,
      useOnCloseMarket: false,
      useOnNukeFromOrbit: false,
      useOnSetMaxTotalSupply: false,
      useOnSetAnnualInterestAndReserveRatioBips: false,
      useOnSetProtocolFeeBips: false
    });
    HooksConfig requiredFlags = EmptyHooksConfig
      .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
      .setFlag(Bit_Enabled_QueueWithdrawal)
      .setFlag(Bit_Enabled_CloseMarket);
    config = encodeHooksDeploymentConfig(optionalFlags, requiredFlags);

    if (args.length > 0) {
      NameAndProviderInputs memory inputs = abi.decode(args, (NameAndProviderInputs));
      _initialize(inputs);
    }
  }

  function version() external pure override returns (string memory) {
    return 'PeriodicTermHooks';
  }

  function _readBoolCd(bytes calldata data, uint256 offset) internal pure returns (bool value) {
    assembly {
      value := and(calldataload(add(data.offset, offset)), 1)
    }
  }

  function _readUint32Cd(bytes calldata data, uint256 offset) internal pure returns (uint32 value) {
    uint256 _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint32();
  }

  function _readUint128Cd(
    bytes calldata data,
    uint256 offset
  ) internal pure returns (uint128 value) {
    uint256 _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint128();
  }

  /**
   * @dev Called when market is deployed using this contract as its `hooks`.
   *
   *     `hooksData` is a tuple of (
   *        uint32 periodStart,
   *        uint32 periodDuration,
   *        uint32 withdrawalWindowDuration,
   *        uint128? minimumDeposit,
   *        bool? transfersDisabled
   *     )
   *
   *      The withdrawal window is always the final `withdrawalWindowDuration`
   *      seconds of each `periodDuration`.
   *
   *      Note: Called inside the root `onCreateMarket` in the base contract,
   *      so no need to verify the caller is the factory.
   */
  function _onCreateMarket(
    address deployer,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal override returns (HooksConfig marketHooksConfig) {
    super._onCreateMarket(deployer, marketAddress, parameters, hooksData);
    if (deployer != borrower) revert CallerNotBorrower();
    if (hooksData.length < 0x60) revert PeriodicWindowNotProvided();

    marketHooksConfig = parameters.hooks;

    uint32 periodStart = _readUint32Cd(hooksData, 0);
    uint32 periodDuration = _readUint32Cd(hooksData, 0x20);
    uint32 withdrawalWindowDuration = _readUint32Cd(hooksData, 0x40);

    _validatePeriodicTerm(periodStart, periodDuration, withdrawalWindowDuration, block.timestamp);

    HookedMarket memory hookedMarket = HookedMarket({
      isHooked: true,
      transferRequiresAccess: marketHooksConfig.useOnTransfer(),
      depositRequiresAccess: marketHooksConfig.useOnDeposit(),
      withdrawalRequiresAccess: marketHooksConfig.useOnQueueWithdrawal(),
      depositHookEnabled: false,
      periodStart: periodStart,
      periodDuration: periodDuration,
      withdrawalWindowDuration: withdrawalWindowDuration,
      minimumDeposit: _readUint128Cd(hooksData, 0x60),
      transfersDisabled: _readBoolCd(hooksData, 0x80),
      isClosed: false
    });

    emit PeriodicTermUpdated(marketAddress, periodStart, periodDuration, withdrawalWindowDuration);

    if (hookedMarket.minimumDeposit > 0) {
      marketHooksConfig = marketHooksConfig.setFlag(Bit_Enabled_Deposit);
      emit MinimumDepositUpdated(marketAddress, hookedMarket.minimumDeposit);
    }
    if (hookedMarket.transfersDisabled) {
      marketHooksConfig = marketHooksConfig.setFlag(Bit_Enabled_Transfer);
    }

    if (marketHooksConfig.useOnQueueWithdrawal()) {
      marketHooksConfig = marketHooksConfig.setFlag(Bit_Enabled_Transfer).setFlag(
        Bit_Enabled_Deposit
      );
    }
    hookedMarket.depositHookEnabled = marketHooksConfig.useOnDeposit();
    marketHooksConfig = marketHooksConfig.mergeFlags(config);
    _hookedMarkets[address(marketAddress)] = hookedMarket;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyBorrower {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (newMinimumDeposit > 0 && !hookedMarket.depositHookEnabled) revert DepositHookNotEnabled();
    hookedMarket.minimumDeposit = newMinimumDeposit;
    emit MinimumDepositUpdated(market, newMinimumDeposit);
  }

  // ========================================================================== //
  //                               Market Queries                               //
  // ========================================================================== //

  function getHookedMarket(address marketAddress) external view returns (HookedMarket memory) {
    return _hookedMarkets[marketAddress];
  }

  function getHookedMarkets(
    address[] calldata marketAddresses
  ) external view returns (HookedMarket[] memory hookedMarkets) {
    hookedMarkets = new HookedMarket[](marketAddresses.length);
    for (uint256 i = 0; i < marketAddresses.length; i++) {
      hookedMarkets[i] = _hookedMarkets[marketAddresses[i]];
    }
  }

  function isWithdrawalWindowOpen(address marketAddress) external view returns (bool) {
    HookedMarket memory market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return _isWithdrawalWindowOpen(market, block.timestamp);
  }

  function _isWithdrawalWindowOpen(
    HookedMarket memory market,
    uint256 timestamp
  ) internal pure returns (bool) {
    if (market.isClosed) return true;
    if (timestamp < market.periodStart) return false;

    uint256 timeInPeriod = (timestamp - market.periodStart) % market.periodDuration;
    return timeInPeriod >= market.periodDuration - market.withdrawalWindowDuration;
  }

  function _validatePeriodicTerm(
    uint32 periodStart,
    uint32 periodDuration,
    uint32 withdrawalWindowDuration,
    uint256 currentTimestamp
  ) internal pure {
    if (periodDuration < MinimumPeriodDuration || periodDuration > MaximumPeriodDuration) {
      revert PeriodDurationOutOfBounds();
    }
    if (
      withdrawalWindowDuration < MinimumWithdrawalWindowDuration ||
      withdrawalWindowDuration >= periodDuration
    ) {
      revert WithdrawalWindowDurationOutOfBounds();
    }

    uint256 firstWindowStart = uint256(periodStart) + periodDuration - withdrawalWindowDuration;
    if (firstWindowStart > currentTimestamp + MaximumInitialWithdrawalWindowDelay) {
      revert InitialWithdrawalWindowTooFarInFuture();
    }
  }

  // ========================================================================== //
  //                                    Hooks                                   //
  // ========================================================================== //

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();

    LenderStatus memory status = _lenderStatus[lender];

    if (status.isBlockedFromDeposits) revert NotApprovedLender();

    uint256 normalizedAmount = scaledAmount.rayMul(state.scaleFactor);
    if (market.minimumDeposit > normalizedAmount) {
      revert DepositBelowMinimum();
    }

    (bool hasValidCredential, bool roleUpdated) = _tryValidateAccessInner(
      status,
      lender,
      hooksData
    );

    if (market.depositRequiresAccess.and(!hasValidCredential)) {
      revert NotApprovedLender();
    }

    _writeLenderStatus(status, lender, hasValidCredential, roleUpdated, true);
  }

  function onQueueWithdrawal(
    address lender,
    uint32,
    /* expiry */
    uint256,
    /* scaledAmount */
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (!state.isClosed && !_isWithdrawalWindowOpen(market, block.timestamp))
      revert WithdrawOutsideWindow();

    if (market.withdrawalRequiresAccess) {
      LenderStatus memory status = _lenderStatus[lender];
      if (
        !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, hooksData)
      ) {
        revert NotApprovedLender();
      }
    }
  }

  function onExecuteWithdrawal(
    address,
    /* lender */
    uint128,
    /* normalizedAmountWithdrawn */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

  function onTransfer(
    address,
    /* caller */
    address,
    /* from */
    address to,
    uint256,
    /* scaledAmount */
    MarketState calldata,
    /* state */
    bytes calldata extraData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];

    if (!market.isHooked) revert NotHookedMarket();

    if (market.transfersDisabled) {
      revert TransfersDisabled();
    }

    if (!isKnownLenderOnMarket[to][msg.sender]) {
      LenderStatus memory toStatus = _lenderStatus[to];
      if (toStatus.isBlockedFromDeposits) revert NotApprovedLender();

      (bool hasValidCredential, bool wasUpdated) = _tryValidateAccessInner(toStatus, to, extraData);

      if (market.transferRequiresAccess.and(!hasValidCredential)) {
        revert NotApprovedLender();
      }

      _writeLenderStatus(toStatus, to, hasValidCredential, wasUpdated, true);
    }
  }

  function onBorrow(
    uint256,
    /* normalizedAmount */
    MarketState calldata,
    /* state */
    bytes calldata /* extraData */
  ) external override {}

  function onRepay(
    uint256,
    /* normalizedAmount */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

  function onCloseMarket(
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    market.isClosed = true;
    emit PeriodicTermClosed(msg.sender);
  }

  function onNukeFromOrbit(
    address,
    /* lender */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

  function onSetMaxTotalSupply(
    uint256,
    /* maxTotalSupply */
    MarketState calldata,
    /* state */
    bytes calldata /* hooksData */
  ) external override {}

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata hooksData
  )
    public
    virtual
    override
    returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips)
  {
    HookedMarket memory hookedMarket = _hookedMarkets[msg.sender];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (
      annualInterestBips < intermediateState.annualInterestBips &&
      !intermediateState.isClosed &&
      !_isWithdrawalWindowOpen(hookedMarket, block.timestamp)
    ) {
      revert NoReducingAprOutsideWithdrawalWindow();
    }

    return
      super.onSetAnnualInterestAndReserveRatioBips(
        annualInterestBips,
        reserveRatioBips,
        intermediateState,
        hooksData
      );
  }

  function onSetProtocolFeeBips(
    uint16,
    /* protocolFeeBips */
    MarketState memory,
    /* intermediateState */
    bytes calldata /* extraData */
  ) external override {}
}
