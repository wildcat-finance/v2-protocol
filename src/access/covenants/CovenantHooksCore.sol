// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

import '../MarketConstraintHooks.sol';
import '../IMarketTransferPolicy.sol';
import '../BaseAccessControls.sol';
import '../../libraries/SafeCastLib.sol';
import '../../IHooksFactoryRevolving.sol';
import './CovenantBase.sol';

using BoolUtils for bool;
using MathUtils for uint256;
using SafeCastLib for uint256;

struct HookedMarket {
  bool isHooked;
  bool transferRequiresAccess;
  bool depositRequiresAccess;
  uint128 minimumDeposit;
  bool transfersDisabled;
}

/**
 * @title CovenantHooksCore
 * @dev Access-control and hook scaffolding shared by every covenant template.
 *      Behaviour for deposits, withdrawals, transfers, minimum deposits and
 *      APR/reserve constraints is identical to `OpenTermHooks`.
 *
 *      Concrete templates supply only their covenant wiring:
 *      - `_initCovenants` — parse covenant words from `hooksData` and
 *        initialise each inherited covenant for the market being deployed.
 *      - `_requiredCovenantFlags` — the hook dispatch flags the covenants
 *        need. Flags are immutable per market, so a covenant that must
 *        observe every draw has to make `onBorrow` mandatory rather than
 *        optional. A template that needs no repay observation should not
 *        require `onRepay`, and pays nothing for it.
 *      - `onBorrow` / `onRepay` — call the inherited covenant entry points.
 *
 *      All covenant templates are revolving-only: the covenants read
 *      `drawnAmount()`, which standard markets do not implement. The
 *      constructor enforces this by checking the deploying factory's name, so
 *      an instance cannot be created through the standard hooks factory.
 */
abstract contract CovenantHooksCore is
  BaseAccessControls,
  MarketConstraintHooks,
  IMarketTransferPolicy,
  CovenantBase
{
  event MinimumDepositUpdated(address market, uint128 newMinimumDeposit);

  error NotHookedMarket();
  error DepositBelowMinimum();
  error DepositHookNotEnabled();
  error InvalidAccessConfiguration();
  error TransfersDisabled();
  error UnknownHooksFactory();

  HooksDeploymentConfig public immutable override config;

  address public immutable archControllerAddress;

  mapping(address => HookedMarket) internal _hookedMarkets;
  // Tracks immutable deposit-hook dispatch without changing the public HookedMarket ABI.
  mapping(address => bool) internal _depositHookEnabled;

  constructor(address _deployer, bytes memory args) BaseAccessControls(_deployer) IHooks() {
    bytes32 factoryName = keccak256(bytes(IHooksFactoryRevolving(msg.sender).name()));
    if (
      factoryName != keccak256('WildcatHooksFactoryRevolving') &&
      factoryName != keccak256('WildcatHooksFactory')
    ) {
      revert UnknownHooksFactory();
    }
    archControllerAddress = IHooksFactoryRevolving(msg.sender).archController();

    HooksConfig optionalFlags = encodeHooksConfig({
      hooksAddress: address(0),
      useOnDeposit: true,
      useOnQueueWithdrawal: true,
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
      .mergeAllFlags(_requiredCovenantFlags());
    config = encodeHooksDeploymentConfig(optionalFlags, requiredFlags);

    if (args.length > 0) {
      NameAndProviderInputs memory inputs = abi.decode(args, (NameAndProviderInputs));
      _initialize(inputs);
    }
  }

  // ========================================================================== //
  //                          Concrete template surface                         //
  // ========================================================================== //

  /// @dev Hook dispatch flags the inherited covenants require. Must be a
  ///      constant expression: it is read during construction.
  function _requiredCovenantFlags() internal pure virtual returns (HooksConfig);

  /// @dev Initialise inherited covenants for a market being deployed.
  ///      Covenant configuration words begin at offset `0x40` of `hooksData`;
  ///      the first two words are `minimumDeposit` and `transfersDisabled`.
  function _initCovenants(
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual;

  // ========================================================================== //
  //                              Calldata readers                              //
  // ========================================================================== //

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

  function _readUint128Cd(
    bytes calldata data,
    uint offset
  ) internal pure returns (uint128 value) {
    if (data.length >= offset + 0x20) {
      assembly {
        value := calldataload(add(data.offset, offset))
      }
    }
  }

  function _readUint32Cd(bytes calldata data, uint offset) internal pure returns (uint32 value) {
    uint _value;
    assembly {
      _value := calldataload(add(data.offset, offset))
    }
    return _value.toUint32();
  }

  // ========================================================================== //
  //                               Market Creation                              //
  // ========================================================================== //

  /**
   * @dev `hooksData` is a tuple of (
   *        uint128? minimumDeposit,
   *        bool?    transfersDisabled,
   *        ...      covenant words, per concrete template
   *      )
   *      Calldata beyond the supplied length reads as zero, so trailing
   *      parameters may be omitted.
   */
  function _onCreateMarket(
    address deployer,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData
  ) internal virtual override returns (HooksConfig marketHooksConfig) {
    super._onCreateMarket(deployer, marketAddress, parameters, hooksData);
    if (deployer != borrower) revert CallerNotBorrower();
    marketHooksConfig = parameters.hooks;

    HookedMarket memory hookedMarket = HookedMarket({
      isHooked: true,
      transferRequiresAccess: marketHooksConfig.useOnTransfer(),
      depositRequiresAccess: marketHooksConfig.useOnDeposit(),
      minimumDeposit: _readUint128Cd(hooksData),
      transfersDisabled: _readBoolCd(hooksData, 0x20)
    });

    if (marketHooksConfig.useOnQueueWithdrawal()) {
      if (!hookedMarket.depositRequiresAccess) revert InvalidAccessConfiguration();
      if (!hookedMarket.transfersDisabled && !hookedMarket.transferRequiresAccess) {
        revert InvalidAccessConfiguration();
      }
    }

    _initCovenants(marketAddress, parameters, hooksData);

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
    _depositHookEnabled[marketAddress] = marketHooksConfig.useOnDeposit();
    _hookedMarkets[address(marketAddress)] = hookedMarket;
  }

  // ========================================================================== //
  //                              Market Management                             //
  // ========================================================================== //

  /**
   * @notice Sets the minimum deposit for a market created by this instance.
   * @dev Hook dispatch flags are immutable after deployment: a positive
   *      minimum is enforceable only if `onDeposit` was enabled at creation.
   */
  function setMinimumDeposit(address market, uint128 newMinimumDeposit) external onlyBorrower {
    HookedMarket storage hookedMarket = _hookedMarkets[market];
    if (!hookedMarket.isHooked) revert NotHookedMarket();
    if (newMinimumDeposit > 0 && !_depositHookEnabled[market]) revert DepositHookNotEnabled();
    hookedMarket.minimumDeposit = newMinimumDeposit;
    emit MinimumDepositUpdated(market, newMinimumDeposit);
  }

  function isMarketTransferDisabled(address marketAddress) external view override returns (bool) {
    HookedMarket storage market = _hookedMarkets[marketAddress];
    if (!market.isHooked) revert NotHookedMarket();
    return market.transfersDisabled;
  }

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
  //                            Access-control Hooks                            //
  // ========================================================================== //

  /// @dev Identical to `OpenTermHooks.onDeposit`.
  function onDeposit(
    address lender,
    uint scaledAmount,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();

    LenderStatus memory status = _lenderStatus[lender];
    if (status.isBlockedFromDeposits) revert NotApprovedLender();

    // Compare in scaled units, flooring both sides identically (see
    // `OpenTermHooks.onDeposit` for the rounding rationale).
    if (market.minimumDeposit > 0) {
      if (MathUtils.mulDiv(market.minimumDeposit, RAY, state.scaleFactor) > scaledAmount) {
        revert DepositBelowMinimum();
      }
    }

    (bool hasValidCredential, bool roleUpdated) = _tryValidateAccessInner(
      status,
      lender,
      hooksData
    );
    if (market.depositRequiresAccess.and(!hasValidCredential)) revert NotApprovedLender();

    _writeLenderStatus(status, lender, hasValidCredential, roleUpdated, true);
  }

  /// @dev Identical to `OpenTermHooks.onQueueWithdrawal`.
  /// @dev Term-behaviour seam. Host mixins (fixed-term, periodic) override
  ///      this to gate withdrawal queueing; the open-term default is a no-op.
  function _beforeQueueWithdrawal(
    address market,
    MarketState calldata state
  ) internal view virtual {}

  function onQueueWithdrawal(
    address lender,
    uint32 /* expiry */,
    uint /* scaledAmount */,
    MarketState calldata state,
    bytes calldata hooksData
  ) external override {
    HookedMarket memory market = _hookedMarkets[msg.sender];
    if (!market.isHooked) revert NotHookedMarket();
    _beforeQueueWithdrawal(msg.sender, state);
    LenderStatus memory status = _lenderStatus[lender];
    if (
      !isKnownLenderOnMarket[lender][msg.sender] && !_tryValidateAccess(status, lender, hooksData)
    ) {
      revert NotApprovedLender();
    }
  }

  /// @dev Identical to `OpenTermHooks.onTransfer`.
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
    if (market.transfersDisabled) revert TransfersDisabled();

    if (!isKnownLenderOnMarket[to][msg.sender]) {
      LenderStatus memory toStatus = _lenderStatus[to];
      if (toStatus.isBlockedFromDeposits) revert NotApprovedLender();
      (bool hasValidCredential, bool wasUpdated) = _tryValidateAccessInner(toStatus, to, extraData);
      if (market.transferRequiresAccess.and(!hasValidCredential)) revert NotApprovedLender();
      _writeLenderStatus(toStatus, to, hasValidCredential, wasUpdated, true);
    }
  }

  // ========================================================================== //
  //                             Unimplemented Hooks                            //
  // ========================================================================== //

  function onExecuteWithdrawal(
    address /* lender */,
    uint128 /* normalizedAmountWithdrawn */,
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

  function onCloseMarket(
    MarketState calldata /* state */,
    bytes calldata /* hooksData */
  ) external override {}

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

  function onSetProtocolFeeBips(
    uint16 /* protocolFeeBips */,
    MarketState memory /* intermediateState */,
    bytes calldata /* extraData */
  ) external override {}

  /// @dev Defers APR changes to the parent market constraint hook.
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
}
