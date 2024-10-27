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
  uint128 minimumDeposit;
  uint32 fixedTermEndTime;
  bool transfersDisabled;
  bool allowClosureBeforeTerm;
  bool allowTermReduction;
  bool allowForceBuyBacks;
}

/**
 * @title FixedTermLoanHooks
 * @dev Hooks contract for wildcat markets. Restricts access to deposits
 *      to accounts that have credentials from approved role providers, or
 *      which are manually approved by the borrower. Restricts withdrawals
 *      until a fixed loan term has elapsed, which can be reduced but not
 *      increased by the borrower.
 *
 *      Withdrawals are restricted in the same way for users that have not
 *      made a deposit, while users who have made a deposit at any point (or
 *      received market tokens while having deposit access) will always remain
 *      approved, even if their access is later revoked.
 *
 *      Deposit access may be canceled by the borrower.
 */
contract FixedTermLoanHooks is BaseAccessControls, MarketConstraintHooks {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  event MinimumDepositUpdated(address market, uint128 newMinimumDeposit);
  event FixedTermUpdated(address market, uint32 fixedTermEndTime);
  event DisabledForceBuyBacks(address market);

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  error NotHookedMarket();
  error DepositBelowMinimum();
  error FixedTermNotProvided();
  error InvalidFixedTerm();
  error IncreaseFixedTerm();
  error WithdrawBeforeTermEnd();
  error NoReducingAprBeforeTermEnd();
  error TransfersDisabled();
  error ForceBuyBacksDisabled();
  error ForceBuyBackDisabledBeforeTerm();
  error ClosureDisabledBeforeTerm();
  error TermReductionDisabled();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  uint32 public constant MaximumLoanTerm = 365 days;

  HooksDeploymentConfig public immutable override config;

  mapping(address => HookedMarket) internal _hookedMarkets;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  /**
   * @param _deployer Address of the account that called the factory.
   * @param {} unused extra bytes to match the constructor signature
   *  restrictedFunctions Configuration specifying which functions to apply
   *                            access controls to.
   */
  constructor(address _deployer, bytes memory /* args */) BaseAccessControls(_deployer) IHooks() {
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
      .setFlag(Bit_Enabled_CloseMarket)
      .setFlag(Bit_Enabled_QueueWithdrawal);
    config = encodeHooksDeploymentConfig(optionalFlags, requiredFlags);
  }

  function version() external pure override returns (string memory) {
    return 'FixedTermLoanHooks';
  }

  function _readBoolCd(bytes calldata data, uint offset) internal pure returns (bool value) {
    assembly {
      value := and(calldataload(add(data.offset, offset)), 1)
    }
  }

  function _readUint32Cd(bytes calldata data) internal pure returns (uint32 value) {
    uint _value;
    assembly {
      _value := calldataload(data.offset)
    }
    return _value.toUint32();
  }

  function _readUint128Cd(bytes calldata data, uint offset) internal pure returns (uint128 value) {
    uint _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint128();
  }

  /**
   * @dev Called when market is deployed using this contract as its `hooks`.
   *
   *     @param deployer      Address of the account that called the factory - must
   *                          match the borrower address.
   *     @param marketAddress Address of the market being deployed.
   *     @param parameters    Parameters used to deploy the market.
   *     @param hooksData     Extra data passed to the market deployment function containing
   *                          the parameters for the hooks.
   *
   *     `hooksData` is a tuple of (
   *        uint32 fixedTermEndTime,
   *        uint128? minimumDeposit,
   *        bool? transfersDisabled,
   *        bool? allowForceBuyBacks,
   *        bool? allowClosureBeforeTerm,
   *        bool? allowTermReduction
   *     )
   *     Where none of the parameters are mandatory except `fixedTermEndTime`.
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
    // Validate the deploy parameters
    super._onCreateMarket(deployer, marketAddress, parameters, hooksData);
    if (deployer != borrower) revert CallerNotBorrower();
    if (hooksData.length < 32) revert FixedTermNotProvided();

    marketHooksConfig = parameters.hooks;

    uint32 fixedTermEndTime = _readUint32Cd(hooksData);

    if (
      fixedTermEndTime < block.timestamp || (fixedTermEndTime - block.timestamp) > MaximumLoanTerm
    ) {
      revert InvalidFixedTerm();
    }
    emit FixedTermUpdated(marketAddress, fixedTermEndTime);

    // Use the deposit and transfer flags to determine whether those require
    // access control. These are tracked separately because if the market
    // enables `onQueueWithdrawal`, deposit and transfer hooks will also be
    // enabled, but may not require access control.
    // Initialisations to zero here (and subsequent updates) are just because
    // of stack-too-deep errors otherwise.

    // Read `minimumDeposit`, `transfersDisabled`, `allowClosureBeforeTerm` and `allowTermReduction`
    // from `hooksData`.
    // If the calldata does not contain sufficient bytes for a parameter, it will be read as zero.
    HookedMarket memory hookedMarket = HookedMarket({
      isHooked: true,
      transferRequiresAccess: marketHooksConfig.useOnTransfer(),
      depositRequiresAccess: marketHooksConfig.useOnDeposit(),
      withdrawalRequiresAccess: marketHooksConfig.useOnQueueWithdrawal(),
      fixedTermEndTime: fixedTermEndTime,
      minimumDeposit: _readUint128Cd(hooksData, 0x20),
      transfersDisabled: _readBoolCd(hooksData, 0x40),
      allowForceBuyBacks: _readBoolCd(hooksData, 0x60),
      allowClosureBeforeTerm: _readBoolCd(hooksData, 0x80),
      allowTermReduction: _readBoolCd(hooksData, 0xa0)
    });
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
    marketHooksConfig = marketHooksConfig.mergeFlags(config);
    _hookedMarkets[address(marketAddress)] = hookedMarket;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyBorrower {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    hookedMarket.minimumDeposit = newMinimumDeposit;
    emit MinimumDepositUpdated(market, newMinimumDeposit);
  }

  function setFixedTermEndTime(address market, uint32 newFixedTermEndTime) external onlyBorrower {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (!hookedMarket.allowTermReduction && newFixedTermEndTime <= hookedMarket.fixedTermEndTime)
      revert TermReductionDisabled();
    if (newFixedTermEndTime > hookedMarket.fixedTermEndTime) revert IncreaseFixedTerm();
    hookedMarket.fixedTermEndTime = newFixedTermEndTime;
    emit FixedTermUpdated(market, newFixedTermEndTime);
  }

  function disableForceBuyBacks(address market) external onlyBorrower {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (hookedMarket.allowForceBuyBacks) {
      hookedMarket.allowForceBuyBacks = false;
      emit DisabledForceBuyBacks(market);
    }
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

  // ========================================================================== //
  //                                    Hooks                                   //
  // ========================================================================== //

  /**
   * @dev Called when a lender attempts to deposit.
   *      Passes the check if the lender is not blocked from deposits
   *      and has a valid credential from an approved role provider.
   */
  function onDeposit(
    address lender,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();

    // Retrieve the lender's status from storage
    LenderStatus memory status = _lenderStatus[lender];

    // Check that the lender is not blocked
    if (status.isBlockedFromDeposits) revert NotApprovedLender();

    // Check that the deposit amount is at or above the market's minimum
    uint normalizedAmount = scaledAmount.rayMul(state.scaleFactor);
    if (market.minimumDeposit > normalizedAmount) {
      revert DepositBelowMinimum();
    }

    // Attempt to validate the lender's access
    // Uses the inner method here as storage may need to be updated if this
    // is their first deposit
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

  /**
   * @dev Called when a lender attempts to queue a withdrawal.
   *      Passes the check if the lender has previously deposited or received
   *      market tokens while having the ability to deposit, or currently has a
   *      valid credential from an approved role provider.
   */
  function onQueueWithdrawal(
    address lender,
    uint32 /* expiry */,
    uint /* scaledAmount */,
    MarketState calldata /* state */,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (market.fixedTermEndTime > block.timestamp) {
      revert WithdrawBeforeTermEnd();
    }
    LenderStatus memory status = _lenderStatus[lender];
    if (market.withdrawalRequiresAccess) {
      if (
        !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, hooksData)
      ) {
        revert NotApprovedLender();
      }
    }
  }

  /**
   * @dev Hook not implemented for this contract.
   */
  function onExecuteWithdrawal(
    address lender,
    uint128 /* normalizedAmountWithdrawn */,
    MarketState calldata /* state */,
    bytes calldata hooksData
  ) external override {}

  /**
   * @dev Called when a lender attempts to transfer market tokens on a market
   *      that requires credentials for either transfers or withdrawals.
   *
   *      Allows the transfer if the recipient:
   *      - is a known lender OR
   *      - is not blocked AND
   *        - has a valid credential OR
   *        - market does not require a credential for transfers
   *
   *    If the recipient is not a known lender but does have a valid
   *    credential, they will be marked as a known lender.
   */
  function onTransfer(
    address /* caller */,
    address /* from */,
    address to,
    uint /* scaledAmount */,
    MarketState calldata /* state */,
    bytes calldata extraData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];

    if (!market.isHooked) revert NotHookedMarket();

    if (market.transfersDisabled) {
      revert TransfersDisabled();
    }

    // If the recipient is a known lender, skip access control checks.
    if (!isKnownLenderOnMarket[to][msg.sender]) {
      LenderStatus memory toStatus = _lenderStatus[to];
      // Respect `isBlockedFromDeposits` only if the recipient is not a known lender
      if (toStatus.isBlockedFromDeposits) revert NotApprovedLender();

      // Attempt to validate the lender's access even if the market does not require
      // a credential for transfers, as the recipient may need to be updated to reflect
      // their new status as a known lender.
      (bool hasValidCredential, bool wasUpdated) = _tryValidateAccessInner(toStatus, to, extraData);

      // Revert if the recipient does not have a valid credential and the market requires one
      if (market.transferRequiresAccess.and(!hasValidCredential)) {
        revert NotApprovedLender();
      }

      _writeLenderStatus(toStatus, to, hasValidCredential, wasUpdated, true);
    }
  }

  /**
   * @dev Hook not implemented for this contract.
   */
  function onBorrow(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}

  /**
   * @dev Hook not implemented for this contract.
   */
  function onRepay(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {}

  function onCloseMarket(
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (!market.allowClosureBeforeTerm && block.timestamp < market.fixedTermEndTime)
      revert ClosureDisabledBeforeTerm();
    if (market.fixedTermEndTime > block.timestamp) {
      market.fixedTermEndTime = uint32(block.timestamp);
      emit FixedTermUpdated(msg.sender, market.fixedTermEndTime);
    }
  }

  function onNukeFromOrbit(
    address /* lender */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  function onSetMaxTotalSupply(
    uint256 /* maxTotalSupply */,
    MarketState calldata /* state */,
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
    HookedMarket storage hookedMarket = _hookedMarkets[msg.sender];

    /* Revert if market is still in fixed term and new APR is lower than it was */
    if (
      (hookedMarket.fixedTermEndTime > block.timestamp) &&
      (annualInterestBips < intermediateState.annualInterestBips)
    ) {
      revert NoReducingAprBeforeTermEnd();
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
    uint16 /* protocolFeeBips */,
    MarketState memory /* intermediateState */,
    bytes calldata /* extraData */
  ) external override {}

  function onForceBuyBack(
    address /* lender */,
    uint /* scaledAmount */,
    MarketState calldata /* intermediateState */,
    bytes calldata /* extraData */
  ) external virtual override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (!market.allowForceBuyBacks) revert ForceBuyBacksDisabled();
    if (market.fixedTermEndTime > block.timestamp) {
      revert ForceBuyBackDisabledBeforeTerm();
    }
    // If the borrower does not already have a credential, grant them one
    LenderStatus storage status = _lenderStatus[borrower];
    if (!status.hasCredential()) {
      // Give the borrower a self-granted credential with no expiry so they are
      // able to withdraw the purchased market tokens.
      _setCredentialAndEmitAccessGranted(
        status,
        _roleProviders[borrower],
        borrower,
        uint32(block.timestamp)
      );
    }
  }
}
