// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './BaseHooks.sol';
import '../libraries/SafeCastLib.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

/// @dev per-market access settings owned by one reusable hooks instance.
struct HookedMarket {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  uint128 minimumDeposit;
  bool transfersDisabled;
}

/// @title OpenTermHooks
/// @notice credential and transfer policy without maturity or periodic withdrawal windows.
/// @dev each market chooses whether deposits and transfers require credentials and whether
///      withdrawals are credential-gated. a lender that enters a market with a valid credential
///      becomes permanently known there, so losing the credential can't trap an existing position.
///      the hooks administrator can still block deposits wherever `onDeposit` is enabled.
contract OpenTermHooks is BaseHooks {
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
        EmptyHooksConfig.setFlag(Bit_Enabled_Deposit).setFlag(Bit_Enabled_Transfer).setFlag(
          Bit_Enabled_QueueWithdrawal
        ),
        EmptyHooksConfig.setFlag(Bit_Enabled_SetAnnualInterestAndReserveRatioBips)
      )
    )
  {}

  function version() external pure override returns (string memory) {
    return 'OpenTermHooks';
  }

  function _readBoolCd(bytes calldata data, uint offset) internal pure returns (bool value) {
    assembly {
      value := and(calldataload(add(data.offset, offset)), 1)
    }
  }

  function _readUint128Cd(bytes calldata data) internal pure returns (uint128 value) {
    uint _value;
    assembly {
      _value := calldataload(data.offset)
    }
    return _value.toUint128();
  }

  /// @dev binds the market after BaseHooks checks `administrator_` against the current
  ///      administrator. `hooksData` is `(uint128 minimumDeposit?, bool transfersDisabled?)`;
  ///      missing words read as zero. gated withdrawals need gated deposits and gated or disabled
  ///      transfers. otherwise a lender can enter without credentials and get stuck on exit.
  function _initializeMarket(
    address administrator_,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual override returns (HooksConfig marketHooksConfig) {
    (
      AccessConfig memory access,
      bool depositHookEnabled,
      HooksConfig effective
    ) = _configureMarketAccess(
        administrator_,
        marketAddress,
        parameters.hooks,
        _readUint128Cd(hooksData),
        _readBoolCd(hooksData, 0x20)
      );
    _depositHookEnabled[marketAddress] = depositHookEnabled;
    _hookedMarkets[marketAddress] = HookedMarket({
      isHooked: access.isHooked,
      transferRequiresAccess: access.transferRequiresAccess,
      depositRequiresAccess: access.depositRequiresAccess,
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
        // open-term withdrawals always check access when the market calls this hook.
        withdrawalRequiresAccess: true,
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

  // ========================================================================== //
  //                               Market Queries                               //
  // ========================================================================== //

  /// @notice says whether every market-token transfer is disabled for this market.
  /// @dev reverts for a market not bound to this hooks instance. false is permanent because this
  ///      template has no setter for the deployment-time flag.
  function isMarketTransferDisabled(address marketAddress) external view override returns (bool) {
    HookedMarket storage market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return market.transfersDisabled;
  }

  /// @notice says whether `recipient` can receive tokens now without hook data.
  /// @dev returns false for disabled transfers, an unknown blocked recipient, or a required
  ///      credential that cannot be resolved from cache or pull providers. reverts for an unknown
  ///      market.
  function isMarketTransferRecipientAllowed(
    address marketAddress,
    address recipient
  ) external view override returns (bool) {
    HookedMarket storage market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return
      !market.transfersDisabled &&
      _isMarketTransferRecipientAllowed(marketAddress, recipient, market.transferRequiresAccess);
  }

  /// @notice returns the open-term configuration stored for `marketAddress`.
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

  /// @notice enforces the market's minimum deposit and lender entry policy.
  /// @dev the minimum is compared in scaled units using the same floor as the market. a valid
  ///      credential marks the lender permanently known on this market, even when deposit access
  ///      itself is optional.
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

    // Check that the deposit amount is at or above the market's minimum.
    // The market floors the scaled amount (v2.5), so an exact-minimum tender
    // can round-trip below the minimum; compare in scaled units, flooring
    // both sides identically. Tolerance is at most one scaled token. Skips
    // the conversion when no minimum is set.
    if (market.minimumDeposit > 0) {
      if (MathUtils.mulDiv(market.minimumDeposit, RAY, state.scaleFactor) > scaledAmount) {
        revert DepositBelowMinimum();
      }
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

  /// @notice allows a withdrawal request from a known lender or one with a current credential.
  /// @dev known status is market-specific and survives credential expiry, revocation, provider
  ///      removal, and local deposit blocks.
  function onQueueWithdrawal(
    address lender,
    uint32 /* expiry */,
    uint /* scaledAmount */,
    MarketState calldata /* state */,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    LenderStatus memory status = _lenderStatus[lender];
    if (
      !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, hooksData)
    ) {
      revert NotApprovedLender();
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

  /// @notice enforces the recipient side of the market's transfer policy.
  /// @dev known recipients and the market's registered wrapper bypass later credential and
  ///      deposit-block checks. any other unknown recipient must not be blocked and, when transfers
  ///      are gated, must supply or resolve a credential. successful credential validation
  ///      permanently marks the recipient known on this market.
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
      // Wrapper entry is an ordinary market-token transfer without credential data. Only the
      // canonical wrapper registered by this market receives the protocol exemption.
      if (_isRegisteredWrapper(msg.sender, to)) return;

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

  /// @dev open-term access policy does not constrain borrower draws.
  function onBorrow(
    uint /* normalizedAmount */,
    MarketState calldata /* state */,
    bytes calldata /* extraData */
  ) external override {}

  /// @dev open-term access policy does not constrain repayments.
  function onRepay(
    uint normalizedAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {}

  /// @dev open-term markets have no hook-level closure restriction.
  function onCloseMarket(
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  /// @dev the market uses its ordinary queue path after this; there is no separate quarantine
  ///      bypass.
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

  /// @notice applies the shared APR bounds and temporary excess-reserve policy.
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
