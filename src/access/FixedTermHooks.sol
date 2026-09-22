// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './BaseHooks.sol';
import '../libraries/SafeCastLib.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/// @dev per-market maturity and access settings owned by one reusable hooks instance.
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
}

/// @title FixedTermHooks
/// @notice credential policy with one maturity timestamp before which queueing is blocked.
/// @dev maturity may move earlier when configured, but never later. entry with a valid credential
///      marks a lender permanently known on that market, so losing the credential can't trap an
///      existing position after maturity. the hooks administrator can still block deposits wherever
///      `onDeposit` is enabled.
contract FixedTermHooks is BaseHooks {
  // ========================================================================== //
  //                                   Events                                   //
  // ========================================================================== //

  /// @notice emitted when an allowed term reduction moves a market's maturity earlier.
  event FixedTermUpdated(
    address indexed market,
    address indexed caller,
    uint32 previousFixedTermEndTime,
    uint32 newFixedTermEndTime
  );

  // ========================================================================== //
  //                                   Errors                                   //
  // ========================================================================== //

  /// @dev market-creation hook data omitted the fixed-term timestamp.
  error FixedTermNotProvided();
  /// @dev maturity is earlier than now or more than 365 days away.
  error InvalidFixedTerm();
  /// @dev a term update tried to move maturity later.
  error IncreaseFixedTerm();
  /// @dev the lender tried to queue a withdrawal before maturity.
  error WithdrawBeforeTermEnd();
  /// @dev the borrower tried to reduce APR before maturity.
  error NoReducingAprBeforeTermEnd();
  /// @dev the borrower tried to close before maturity without permission.
  error ClosureDisabledBeforeTerm();
  /// @dev this market was not configured to allow term reductions.
  error TermReductionDisabled();

  // ========================================================================== //
  //                                    State                                   //
  // ========================================================================== //

  /// @notice longest fixed term accepted when a market is attached.
  uint32 public constant MaximumLoanTerm = 365 days;

  mapping(address => HookedMarket) internal _hookedMarkets;
  // keep immutable dispatch separate; adding it to HookedMarket would change the public tuple.
  mapping(address => bool) internal _depositHookEnabled;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  /// @param _administrator initial hooks administrator. this does not grant provider authority.
  /// @param args optional ABI-encoded `NameAndProviderInputs` for the name and initial providers.
  constructor(
    address _administrator,
    bytes memory args
  )
    BaseHooks(
      _administrator,
      args,
      encodeHooksDeploymentConfig(
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer),
        EmptyHooksConfig
          .setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
          .setFlag(Bit_Enabled_CloseMarket)
          .setFlag(Bit_Enabled_QueueWithdrawal)
      )
    )
  {}

  function version() external pure override returns (string memory) {
    return 'FixedTermHooks';
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

  /// @dev binds the market after BaseHooks checks `administrator_` against the current
  ///      administrator. `hooksData` is `(uint32 fixedTermEndTime, uint128 minimumDeposit?,
  ///      bool transfersDisabled?, bool allowClosureBeforeTerm?, bool allowTermReduction?)`.
  ///      maturity is required, can't be in the past, and can't be more than 365 days away.
  ///      gated withdrawals need gated deposits and gated or disabled transfers. otherwise a
  ///      lender can enter without credentials and get stuck on exit.
  function _initializeMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual override returns (HooksConfig marketHooksConfig) {
    if (hooksData.length < 32) revert FixedTermNotProvided();
    uint32 fixedTermEndTime = _readUint32Cd(hooksData);
    if (
      fixedTermEndTime < block.timestamp || (fixedTermEndTime - block.timestamp) > MaximumLoanTerm
    ) {
      revert InvalidFixedTerm();
    }
    emit FixedTermUpdated(marketAddress, administrator_, 0, fixedTermEndTime);

    (
      AccessConfig memory access,
      bool depositHookEnabled,
      HooksConfig effective
    ) = _configureMarketAccess(
        administrator_,
        marketAddress,
        parameters.hooks,
        _readUint128Cd(hooksData, 0x20),
        _readBoolCd(hooksData, 0x40)
      );
    _depositHookEnabled[marketAddress] = depositHookEnabled;
    _hookedMarkets[marketAddress] = HookedMarket({
      isHooked: access.isHooked,
      transferRequiresAccess: access.transferRequiresAccess,
      depositRequiresAccess: access.depositRequiresAccess,
      withdrawalRequiresAccess: access.withdrawalRequiresAccess,
      fixedTermEndTime: fixedTermEndTime,
      allowClosureBeforeTerm: _readBoolCd(hooksData, 0x60),
      allowTermReduction: _readBoolCd(hooksData, 0x80),
      minimumDeposit: access.minimumDeposit,
      transfersDisabled: access.transfersDisabled
    });
    return effective;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  function _readAccessConfig(
    address market
  ) internal view virtual override returns (AccessConfig memory) {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    return
      AccessConfig({
        isHooked: hookedMarket.isHooked,
        transferRequiresAccess: hookedMarket.transferRequiresAccess,
        depositRequiresAccess: hookedMarket.depositRequiresAccess,
        withdrawalRequiresAccess: hookedMarket.withdrawalRequiresAccess,
        minimumDeposit: hookedMarket.minimumDeposit,
        transfersDisabled: hookedMarket.transfersDisabled
      });
  }

  function _isDepositHookEnabled(address market) internal view virtual override returns (bool) {
    return _depositHookEnabled[market];
  }

  function _writeMinimumDeposit(address market, uint128 value) internal virtual override {
    _hookedMarkets[market].minimumDeposit = value;
  }

  /// @notice moves a hooked market's maturity earlier when term reduction was enabled at creation.
  /// @dev the new time may be now or in the past. maturity can never be extended.
  function setFixedTermEndTime(
    address market,
    uint32 newFixedTermEndTime
  ) external onlyAdministrator {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (!hookedMarket.allowTermReduction && newFixedTermEndTime <= hookedMarket.fixedTermEndTime)
      revert TermReductionDisabled();
    if (newFixedTermEndTime > hookedMarket.fixedTermEndTime) revert IncreaseFixedTerm();
    uint32 previousFixedTermEndTime = hookedMarket.fixedTermEndTime;
    hookedMarket.fixedTermEndTime = newFixedTermEndTime;
    emit FixedTermUpdated(market, msg.sender, previousFixedTermEndTime, newFixedTermEndTime);
  }

  // ========================================================================== //
  //                               Market Queries                               //
  // ========================================================================== //

  /// @notice returns the fixed-term configuration stored for `marketAddress`.
  /// @dev an unattached market returns the zero-value struct.
  function getHookedMarket(address marketAddress) external view returns (HookedMarket memory) {
    return _hookedMarkets[marketAddress];
  }

  /// @notice batch version of `getHookedMarket`, preserving input order.
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

  /// @notice blocks withdrawal queueing before maturity, then applies any withdrawal access policy.
  /// @dev at and after maturity, a gated withdrawal needs either market-specific known-lender
  ///      status or a current credential. execution of an existing request is never term-gated.
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

  /// @dev execution stays permissionless once the lender has queued the withdrawal.
  function onExecuteWithdrawal(
    address lender,
    uint32 /* expiry */,
    uint128 /* normalizedAmountWithdrawn */,
    MarketState calldata /* state */,
    bytes calldata hooksData
  ) external override {}

  /// @dev fixed-term policy does not constrain borrower draws.
  function onBorrow(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}

  /// @dev fixed-term policy does not constrain repayments.
  function onRepay(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {}

  /// @notice enforces the deployment-time early-closure policy.
  /// @dev before maturity, closure needs either `allowClosureBeforeTerm` or `allowTermReduction`.
  ///      an allowed early close moves maturity to the closure timestamp. closure at or after
  ///      maturity needs no term-policy permission.
  function onCloseMarket(
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {
    HookedMarket storage market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    if (block.timestamp < market.fixedTermEndTime) {
      if (!(market.allowTermReduction || market.allowClosureBeforeTerm)) {
        revert ClosureDisabledBeforeTerm();
      }
      uint32 previousFixedTermEndTime = market.fixedTermEndTime;
      market.fixedTermEndTime = uint32(block.timestamp);
      emit FixedTermUpdated(
        msg.sender,
        msg.sender,
        previousFixedTermEndTime,
        market.fixedTermEndTime
      );
    }
  }

  /// @dev quarantine reaches the maturity check in the ordinary queue callback that follows.
  function onNukeFromOrbit(
    address /* lender */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /// @dev this template adds no supply-cap policy.
  function onSetMaxTotalSupply(
    uint256 /* maxTotalSupply */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /// @notice rejects APR reductions before maturity, then applies the shared reserve policy.
  /// @dev equal or higher APRs are allowed during the term, subject to the shared bounds.
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

  /// @dev this template adds no protocol-fee policy.
  function onSetProtocolFeeBips(
    uint16 /* protocolFeeBips */,
    MarketState memory /* intermediateState */,
    bytes calldata /* extraData */
  ) external override {}
}
