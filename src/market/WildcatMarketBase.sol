// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // WildcatMarketBase
//  \ ^ /   Shared identity, accounting, and market lifecycle machinery.
//    V
//
//  SETUP
//  constructor()
//  _getMarketParameters()
//
//  METADATA
//  version()
//  scaledTransferRounding()
//  name()
//  symbol()
//  _returnPackedString(...)
//  archController()
//  registeredWrapper()
//
//  BORROWER AUTHORITY
//  onlyBorrower()
//  borrower()
//  borrowerPrincipal()
//  requestBorrowerTransfer(...)
//  acceptBorrowerTransfer()
//  cancelBorrowerTransfer()
//  _validateBorrowerTransferTarget(...)
//  _checkBorrowerNotSanctioned(...)
//  _flaggedBorrowerIdentity(...)
//  pendingBorrower()
//  pendingBorrowerPrincipal()
//
//  REPAYMENT TERMS
//  repaymentDate()
//  repaymentPeriod()
//  repaymentDeadline()
//  _isInRepayment()
//  defaultedAt()
//
//  STATE TRANSITIONS
//  currentState()
//  previousState()
//  _calculateCurrentState()
//  _calculateCurrentStatePointers()
//  _getUpdatedState()
//  _getUpdatedState(...)
//  _allocateTransition()
//  _calculateTransition(...)
//  _accrueTransition(...)
//  _updateScaleFactorAndFees(...)
//  _calculateBaseInterest(...)
//
//  BATCH FUNDING
//  _commitTransitionBatch(...)
//  _closeOrQueueWithdrawalBatch(...)
//  _payTransitionBatch(...)
//  _applyWithdrawalBatchPayment(...)
//  _applyWithdrawalBatchPaymentView(...)
//
//  CLOSURE
//  _previewAutomaticClosure(...)
//  _closeAfterCurrentAction(...)
//  _commitAutomaticClosure(...)
//  _onCloseMarket()
//
//  STATE PERSISTENCE
//  _writeState(...)
//  _writeState(...)
//  _checkpointedTotalAssets()
//
//  BORROWING AND REPAYMENT
//  _onBorrow(...)
//  _onRepay(...)
//  _onRepayAndGetTotalAssets(...)
//
//  ACCOUNTING QUERIES
//  totalAssets()
//  totalDebts()
//  coverageLiquidity()
//  borrowableAssets()
//  scaleFactor()
//  scaledTotalSupply()
//  scaledBalanceOf(...)
//  accruedProtocolFees()
//  withdrawableProtocolFees()
//
//  SANCTIONS
//  _getAccount(...)
//  _isSanctioned(...)
//  _blockAccount(...)
//  _isFlaggedByChainalysis(...)
//  _createEscrowForUnderlyingAsset(...)
//
//  RUNTIME CONSTANTS
//  _runtimeConstant(...)
//  _runtimeConstant(...)
// ═════

import '../ReentrancyGuard.sol';
import '../spherex/SphereXProtectedRegisteredBase.sol';
import '../interfaces/IMarketEventsAndErrors.sol';
import '../interfaces/IWildcatArchController.sol';
import '../IHooksFactory.sol';
import '../libraries/FeeMath.sol';
import '../libraries/MarketLifecycle.sol';
import '../libraries/BoolUtils.sol';
import '../libraries/MarketErrors.sol';
import '../libraries/MarketEvents.sol';
import '../libraries/Withdrawal.sol';
import '../libraries/FunctionTypeCasts.sol';
import '../libraries/LibERC20.sol';
import '../libraries/LibFixedCall.sol';
import '../types/HooksConfig.sol';

// ┌─ WildcatMarketBase ────────────────────────────────────────────────────────
/// @notice shared market storage, accounting, identity, sanctions, and state-update machinery.
contract WildcatMarketBase is SphereXProtectedRegisteredBase, ReentrancyGuard, IMarketEventsAndErrors {
  using BoolUtils for bool;
  using SafeCastLib for uint256;
  using MathUtils for uint256;
  using FunctionTypeCasts for *;
  using LibERC20 for address;
  using MarketLifecycleLib for MarketLifecycle;
  using MarketLifecycleLib for MarketState;

  // ░░▒▒▓▓██ [ MARKET CONFIG ] ────────────────────────────────────────────────

  /// @notice installed hook address and enabled callback flags.
  HooksConfig public immutable hooks;

  /// @notice sanctions sentinel used for borrower/lender checks and escrow deployment.
  address public immutable sentinel;

  /// @notice factory that deployed the market and can update its protocol fee.
  address public immutable factory;

  /// @notice immutable account that receives protocol fees.
  address public immutable feeRecipient;

  /// @notice canonical factory allowed to register this market's optional ERC-4626 wrapper.
  address public immutable wrapperFactory;

  /// @notice registry that resolves borrower accounts to registered principals.
  address public immutable borrowerIdentityRegistry;

  /// @dev borrower transfer and wrapper state use the final five EVM slots, 2^256 - 1 through
  ///      2^256 - 5. ordinary Solidity storage grows from zero, leaving room for future market types.
  ///
  ///      mapping and dynamic-array elements use keccak256-derived slots. collisions carry the
  ///      same negligible 256-bit risk as other namespaced storage. don't reuse this range for
  ///      other manual storage.
  bytes32 internal constant BORROWER_STORAGE_SLOT = bytes32(type(uint256).max);
  bytes32 internal constant BORROWER_PRINCIPAL_STORAGE_SLOT = bytes32(type(uint256).max - 1);
  bytes32 internal constant PENDING_BORROWER_STORAGE_SLOT = bytes32(type(uint256).max - 2);
  bytes32 internal constant PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT = bytes32(type(uint256).max - 3);
  bytes32 internal constant REGISTERED_WRAPPER_STORAGE_SLOT = bytes32(type(uint256).max - 4);

  /// @dev ABI-encoded size of `MarketParameters`, which has 24 static fields.
  uint256 internal constant _MARKET_PARAMETERS_SIZE = 0x300;

  /// @notice annual penalty rate added to lender interest during penalized delinquency, in bips.
  uint256 public immutable delinquencyFeeBips;

  /// @notice delinquent time before the penalty rate applies, in seconds.
  uint256 public immutable delinquencyGracePeriod;

  /// @notice duration of each withdrawal batch, in seconds.
  uint256 public immutable withdrawalBatchDuration;

  /// @notice market-token decimals copied from the underlying asset.
  uint8 public immutable decimals;

  /// @notice underlying ERC-20 asset.
  address public immutable asset;

  bytes32 internal immutable PACKED_NAME_WORD_0;
  bytes32 internal immutable PACKED_NAME_WORD_1;
  bytes32 internal immutable PACKED_SYMBOL_WORD_0;
  bytes32 internal immutable PACKED_SYMBOL_WORD_1;

  // ░░▒▒▓▓██ [ MARKET STATE ] ─────────────────────────────────────────────────

  MarketState internal _state;

  mapping(address => Account) internal _accounts;

  WithdrawalData internal _withdrawalData;
  MarketLifecycle internal _lifecycle;

  uint64 internal immutable _repaymentTerms;

  // ░░▒▒▓▓██ [ ERRORS ] ───────────────────────────────────────────────────────

  error InvalidRepaymentTerms();
  error UnsupportedExecuteWithdrawalHook();
  error MarketInRepayment();
  error RepaymentReserveRequired();

  // ░░▒▒▓▓██ [ EVENTS ] ───────────────────────────────────────────────────────

  event RepaymentDateReached(uint256 effectiveTimestamp);
  event DefaultRecorded(uint256 effectiveTimestamp);

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor() {
    factory = msg.sender;

    // reuse `_getMarketParameters`' buffer as a MarketParameters reference. don't allocate
    // and zero a second copy just to change the return type.
    MarketParameters memory parameters = _getMarketParameters.asReturnsMarketParameters()();
    if (parameters.borrower == address(0)) revert InvalidBorrower();
    uint256 date = parameters.repaymentDate;
    uint256 period = parameters.repaymentPeriod;
    // both terms came from uint32 fields, so evaluating date + period eagerly cannot overflow.
    if ((date == 0)
        .and(period != 0)
        .or((date != 0).and((date <= block.timestamp).or(date + period > type(uint32).max)))) {
      revertWithSelector(InvalidRepaymentTerms_ErrorSelector);
    }
    if (parameters.hooks.useOnExecuteWithdrawal()) revertWithSelector(UnsupportedExecuteWithdrawalHook_ErrorSelector);
    _repaymentTerms = uint64(date | (period << 32));

    asset = parameters.asset;
    decimals = parameters.decimals;

    PACKED_NAME_WORD_0 = parameters.packedNameWord0;
    PACKED_NAME_WORD_1 = parameters.packedNameWord1;
    PACKED_SYMBOL_WORD_0 = parameters.packedSymbolWord0;
    PACKED_SYMBOL_WORD_1 = parameters.packedSymbolWord1;

    {
      // slots 1 and 2 start at zero. only initialize the nonzero state slots.
      uint256 maxTotalSupply = parameters.maxTotalSupply;
      uint256 reserveRatioBips = parameters.reserveRatioBips;
      uint256 annualInterestBips = parameters.annualInterestBips;
      uint256 protocolFeeBips = parameters.protocolFeeBips;

      assembly {
        // MarketState Slot 0 Storage Layout:
        // [0:15]  | low 120 bits of checkpointedTotalAssets = 0
        // [15:31] | state.maxTotalSupply
        // [31:32] | state.isClosed = false

        let slot0 := shl(8, maxTotalSupply)
        sstore(_state.slot, slot0)

        // MarketState Slot 3 Storage Layout:
        // [0:4] | high 32 bits of checkpointedTotalAssets = 0
        // [4:8] | lastInterestAccruedTimestamp
        // [8:22] | scaleFactor = 1e27
        // [22:24] | reserveRatioBips
        // [24:26] | annualInterestBips
        // [26:28] | protocolFeeBips
        // [28:32] | timeDelinquent = 0

        let slot3 :=
          or(
            or(or(shl(0xc0, timestamp()), shl(0x50, RAY)), shl(0x40, reserveRatioBips)),
            or(shl(0x30, annualInterestBips), shl(0x20, protocolFeeBips))
          )

        sstore(add(_state.slot, 3), slot3)
      }
    }

    hooks = parameters.hooks;
    sentinel = parameters.sentinel;
    _setAddress(BORROWER_STORAGE_SLOT, parameters.borrower);
    _setAddress(BORROWER_PRINCIPAL_STORAGE_SLOT, parameters.borrowerPrincipal);
    feeRecipient = parameters.feeRecipient;
    wrapperFactory = parameters.wrapperFactory;
    address identityRegistry = parameters.borrowerIdentityRegistry;
    borrowerIdentityRegistry = identityRegistry;
    delinquencyFeeBips = parameters.delinquencyFeeBips;
    delinquencyGracePeriod = parameters.delinquencyGracePeriod;
    withdrawalBatchDuration = parameters.withdrawalBatchDuration;
    address archController_ = parameters.archController;
    _archController = archController_;
    assembly {
      // staticcall reads raw memory. start at 0x1c to skip the selector word's 28 zero bytes;
      // the four-byte input is `archController()` with no arguments.
      mstore(0, 0x54635570) // archController()

      // copy up to one return word to 0x00. staticcall returns 1 on success, 0 on failure.
      let validRegistry := staticcall(gas(), identityRegistry, 0x1c, 0x04, 0, 0x20)

      // require exactly one ABI word. both operands are 0 or 1, so bitwise AND is logical AND here.
      validRegistry := and(validRegistry, eq(returndatasize(), 0x20))
      if validRegistry {
        // the return word replaced the selector at 0x00. an address occupies its low 160 bits;
        // reject dirty upper 96 bits rather than silently truncating malformed ABI data.
        let registryArchController := mload(0)
        if shr(160, registryArchController) {
          revert(0, 0)
        }

        // a clean address isn't enough. the registry must use the factory's ArchController.
        validRegistry := eq(registryArchController, archController_)
      }
      if iszero(validRegistry) {
        // use MarketErrors.sol's compact error layout: return only the word's last four bytes.
        mstore(0, 0x41d9e607) // InvalidBorrowerIdentityRegistry()
        revert(0x1c, 0x04)
      }
    }
    if (
      parameters.borrowerPrincipal == address(0)
        || !LibFixedCall.readBool(
          archController_, IWildcatArchController.isRegisteredBorrower.selector, parameters.borrowerPrincipal
        )
    ) {
      revert BorrowerPrincipalNotRegistered();
    }
    __SphereXProtectedRegisteredBase_init(parameters.sphereXEngine);
  }

  // ┌─ _getMarketParameters ─────
  /// @dev allocates and fills the static `MarketParameters` block from the deploying factory.
  function _getMarketParameters() internal view returns (uint256 marketParametersPointer) {
    assembly {
      marketParametersPointer := mload(0x40)
      mstore(0x40, add(marketParametersPointer, _MARKET_PARAMETERS_SIZE))

      // IHooksFactory.getMarketParameters()
      mstore(0x00, 0x04032dbb)

      // the deploying factory supplies the prepared struct directly into this buffer.
      // require a successful call and the exact byte count. field-level ABI checks are
      // deliberately skipped: this path trusts the factory's prepared parameters.
      if iszero(
        and(
          eq(returndatasize(), _MARKET_PARAMETERS_SIZE),
          staticcall(gas(), caller(), 0x1c, 0x04, marketParametersPointer, _MARKET_PARAMETERS_SIZE)
        )
      ) {
        revert(0, 0)
      }
    }
  }

  // ░░▒▒▓▓██ [ METADATA ] ─────────────────────────────────────────────────────

  // ┌─ version ─────
  /// @notice return the market implementation version, `2.5`.
  ///
  /// @dev bumped from "2" for the v2.5 release: transfer and deposit scaling
  ///      changed from half-up to floor rounding, so v2.5 markets must be
  ///      distinguishable from earlier deployments. consumers that only check
  ///      the major version read the first byte, which remains '2'.
  function version() external pure returns (string memory) {
    assembly {
      mstore(0x40, 0)
      // length byte (3) at 0x5f, then '2.5' at 0x60-0x62.
      mstore(0x43, 0x03322e35)
      mstore(0x20, 0x20)
      return(0x20, 0x60)
    }
  }

  // ┌─ scaledTransferRounding ─────
  /// @notice identify floor rounding for normalized-to-scaled transfers and deposits.
  ///
  /// @dev transfers and deposits use `MarketState.scaleAmountDown`. rounding-sensitive integrations,
  ///      including the ERC-4626 wrapper factory, check this instead of parsing version strings.
  ///      pre-v2.5 markets lack this function and round half-up.
  function scaledTransferRounding() external pure returns (bytes32) {
    return keccak256('scaleAmountDown');
  }

  // ┌─ name ─────
  /// @notice return the market-token name set at deployment.
  function name() external view returns (string memory) {
    _returnPackedString(PACKED_NAME_WORD_0, PACKED_NAME_WORD_1);
  }

  // ┌─ symbol ─────
  /// @notice return the market-token symbol set at deployment.
  function symbol() external view returns (string memory) {
    _returnPackedString(PACKED_SYMBOL_WORD_0, PACKED_SYMBOL_WORD_1);
  }

  // ┌─ _returnPackedString ─────
  /// @dev end the call with the ABI string packed into two immutable words.
  function _returnPackedString(bytes32 word0, bytes32 word1) internal pure {
    assembly {
      // ABI string layout:
      // 0x00: Offset to the string
      // 0x20: Length of the string
      // 0x40: First word of the string
      // 0x60: Second word of the string
      // the first immutable word also holds the length byte. that leaves at most 63 string bytes.
      mstore(0, 0x20)
      mstore(0x20, 0)
      mstore(0x3f, word0)
      mstore(0x5f, word1)
      return(0, 0x80)
    }
  }

  // ┌─ archController ─────
  /// @notice return the protocol registry that authorized this market.
  function archController() external view returns (address) {
    return _archController;
  }

  // ┌─ registeredWrapper ─────
  /// @notice canonical ERC-4626 wrapper for this market, or zero if none has been deployed.
  function registeredWrapper() public view returns (address) {
    return _getAddress(REGISTERED_WRAPPER_STORAGE_SLOT);
  }

  // ░░▒▒▓▓██ [ BORROWER AUTHORITY ] ───────────────────────────────────────────

  // ┌─ onlyBorrower ─────
  modifier onlyBorrower() {
    if (msg.sender != borrower()) revertWithSelector(NotApprovedBorrower_ErrorSelector);
    _;
  }

  // ┌─ borrower ─────
  /// @notice current operational borrower.
  function borrower() public view returns (address) {
    return _getAddress(BORROWER_STORAGE_SLOT);
  }

  // ┌─ borrowerPrincipal ─────
  /// @notice current registered principal for the market.
  function borrowerPrincipal() public view returns (address) {
    return _getAddress(BORROWER_PRINCIPAL_STORAGE_SLOT);
  }

  // ┌─ requestBorrowerTransfer ─────
  /// @notice request transfer of borrower authority to `newBorrower`.
  ///
  /// @dev only the current borrower can call. a new request replaces any pending target. the
  ///      identity registry pins the target's principal, and raw sanctions block either side.
  ///
  /// @param newBorrower operational address that may later accept the transfer.
  function requestBorrowerTransfer(address newBorrower) external onlyBorrower nonReentrant sphereXGuardExternal {
    address newBorrowerPrincipal = _validateBorrowerTransferTarget(newBorrower, _runtimeConstant(address(0)));
    address previousPendingBorrower = pendingBorrower();
    address previousPendingBorrowerPrincipal = pendingBorrowerPrincipal();
    _setAddress(PENDING_BORROWER_STORAGE_SLOT, newBorrower);
    _setAddress(PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT, newBorrowerPrincipal);
    emit_BorrowerTransferRequested(
      msg.sender,
      previousPendingBorrower,
      newBorrower,
      borrowerPrincipal(),
      previousPendingBorrowerPrincipal,
      newBorrowerPrincipal
    );
  }

  // ┌─ acceptBorrowerTransfer ─────
  /// @notice accept borrower authority for the pending operational address and pinned principal.
  ///
  /// @dev only the pending borrower can call. the target is resolved and sanctions are checked
  ///      again; a principal change since request makes the caller request a fresh transfer.
  function acceptBorrowerTransfer() external nonReentrant sphereXGuardExternal {
    address newBorrower = pendingBorrower();
    if (msg.sender != newBorrower) revertWithSelector(NotPendingBorrower_ErrorSelector);

    address expectedPrincipal = pendingBorrowerPrincipal();
    address newBorrowerPrincipal = _validateBorrowerTransferTarget(newBorrower, expectedPrincipal);
    address previousBorrower = borrower();
    address previousBorrowerPrincipal = borrowerPrincipal();

    _setAddress(PENDING_BORROWER_STORAGE_SLOT, address(0));
    _setAddress(PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT, address(0));
    _setAddress(BORROWER_STORAGE_SLOT, newBorrower);
    _setAddress(BORROWER_PRINCIPAL_STORAGE_SLOT, newBorrowerPrincipal);

    emit_BorrowerTransferred(previousBorrower, newBorrower, previousBorrowerPrincipal, newBorrowerPrincipal);
  }

  // ┌─ cancelBorrowerTransfer ─────
  /// @notice clear the pending borrower transfer without changing current authority.
  function cancelBorrowerTransfer() external onlyBorrower nonReentrant sphereXGuardExternal {
    address cancelledPendingBorrower = pendingBorrower();
    if (cancelledPendingBorrower == address(0)) revertWithSelector(NoPendingBorrowerTransfer_ErrorSelector);
    address cancelledPendingBorrowerPrincipal = pendingBorrowerPrincipal();
    _setAddress(PENDING_BORROWER_STORAGE_SLOT, address(0));
    _setAddress(PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT, address(0));
    emit_BorrowerTransferCancelled(
      msg.sender, cancelledPendingBorrower, borrowerPrincipal(), cancelledPendingBorrowerPrincipal
    );
  }

  // ┌─ _validateBorrowerTransferTarget ─────
  /// @dev resolves a transfer target, binds an expected principal on acceptance, rejects an exact
  ///      identity no-op, and checks raw sanctions on both sides of the transfer.
  function _validateBorrowerTransferTarget(
    address newBorrower,
    address expectedPrincipal
  )
    internal
    view
    returns (address newBorrowerPrincipal)
  {
    address currentBorrower;
    address currentBorrowerPrincipal;
    bytes32 borrowerSlot = BORROWER_STORAGE_SLOT;
    bytes32 borrowerPrincipalSlot = BORROWER_PRINCIPAL_STORAGE_SLOT;
    address identityRegistry = borrowerIdentityRegistry;
    assembly {
      // borrower addresses live in reserved slots, not ordinary Solidity state variables.
      // each slot holds a clean address in its low 160 bits.
      currentBorrower := sload(borrowerSlot)
      if iszero(newBorrower) {
        // InvalidBorrowerTransferTarget() needs only the selector, not an argument word.
        mstore(0, 0x5176bd60)
        revert(0x1c, 0x04)
      }

      // resolveBorrower(newBorrower): selector at the end of 0x00, address at 0x20.
      // reading 0x24 bytes from 0x1c gives the selector and one full ABI argument.
      mstore(0, 0xa111a9e8)
      mstore(0x20, newBorrower)

      // resolve without allowing state changes. reuse 0x00 for the first return word;
      // the selector is no longer needed.
      if iszero(staticcall(gas(), identityRegistry, 0x1c, 0x24, 0, 0x20)) {
        // bubble the registry's exact revert data.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }

      // match Solidity's address decoding: at least one full word, with clean upper bits.
      // don't treat a short or silently truncated return as a principal.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      newBorrowerPrincipal := mload(0)
      if shr(160, newBorrowerPrincipal) {
        revert(0, 0)
      }

      currentBorrowerPrincipal := sload(borrowerPrincipalSlot)

      // requests pass zero; acceptance passes the pinned principal. Yul's `if` accepts
      // any nonzero word. don't use bitwise AND as though a raw address were a boolean.
      if expectedPrincipal {
        // nonzero XOR means the principal changed while acceptance was pending.
        if xor(newBorrowerPrincipal, expectedPrincipal) {
          // PendingBorrowerPrincipalChanged(address,address): selector, expected principal, current principal.
          mstore(0, 0xe1357b3c)
          mstore(0x20, expectedPrincipal)
          mstore(0x40, newBorrowerPrincipal)
          revert(0x1c, 0x44)
        }
      }

      // the same borrower can request a changed principal, but not an exact identity no-op.
      // each `eq` returns 0 or 1, so bitwise AND is logical AND here.
      if and(eq(newBorrower, currentBorrower), eq(newBorrowerPrincipal, currentBorrowerPrincipal)) {
        mstore(0, 0x5176bd60)
        revert(0x1c, 0x04)
      }
    }
    _checkBorrowerNotSanctioned(currentBorrower, currentBorrowerPrincipal);
    _checkBorrowerNotSanctioned(newBorrower, newBorrowerPrincipal);
  }

  // ┌─ _checkBorrowerNotSanctioned ─────
  /// @dev reverts if either borrower identity is raw-flagged by Chainalysis.
  function _checkBorrowerNotSanctioned(address operationalBorrower, address principal) internal view {
    address flaggedIdentity = _flaggedBorrowerIdentity(operationalBorrower, principal);
    if (flaggedIdentity != address(0)) {
      revertWithSelectorAndArgument(BorrowerTransferWhileSanctioned_ErrorSelector, uint256(uint160(flaggedIdentity)));
    }
  }

  // ┌─ _flaggedBorrowerIdentity ─────
  /// @dev returns the first raw Chainalysis-flagged identity, ignoring sentinel overrides.
  function _flaggedBorrowerIdentity(
    address operationalBorrower,
    address principal
  )
    internal
    view
    returns (address flaggedIdentity)
  {
    if (_isFlaggedByChainalysis(operationalBorrower)) return operationalBorrower;
    if (principal != operationalBorrower && _isFlaggedByChainalysis(principal)) return principal;
  }

  // ┌─ pendingBorrower ─────
  /// @notice address that can accept the pending borrower transfer.
  function pendingBorrower() public view returns (address) {
    return _getAddress(PENDING_BORROWER_STORAGE_SLOT);
  }

  // ┌─ pendingBorrowerPrincipal ─────
  /// @notice principal resolved for the pending borrower when the transfer was requested.
  function pendingBorrowerPrincipal() public view returns (address) {
    return _getAddress(PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT);
  }

  // ░░▒▒▓▓██ [ REPAYMENT TERMS ] ──────────────────────────────────────────────

  // ┌─ repaymentDate ─────
  /// @notice scheduled start of full repayment, or zero when disabled. safe in hook callbacks.
  function repaymentDate() public view returns (uint256) {
    return uint32(_repaymentTerms);
  }

  // ┌─ repaymentPeriod ─────
  /// @notice seconds from repayment date through the inclusive deadline; zero is valid.
  function repaymentPeriod() public view returns (uint256) {
    return _repaymentTerms >> 32;
  }

  // ┌─ repaymentDeadline ─────
  function repaymentDeadline() public view returns (uint256) {
    return repaymentDate() + repaymentPeriod();
  }

  // ┌─ _isInRepayment ─────
  function _isInRepayment() internal view returns (bool) {
    uint256 date = repaymentDate();
    return (date != 0).and(block.timestamp >= date);
  }

  // ┌─ defaultedAt ─────
  /// @notice committed default cutoff. zero means no default has been recorded yet.
  function defaultedAt() external view returns (uint256) {
    return _lifecycle.defaultedAt;
  }

  // ░░▒▒▓▓██ [ STATE TRANSITIONS ] ────────────────────────────────────────────

  // ┌─ currentState ─────
  /// @notice return the state calculable through this block without writing storage.
  ///
  /// @dev includes accrued interest and fees plus any current-batch expiry and payment.
  function currentState() external view nonReentrantView returns (MarketState memory state) {
    state = _calculateCurrentStatePointers.asReturnsMarketState()();
    assembly {
      return(state, 0x1e0)
    }
  }

  // ┌─ previousState ─────
  /// @notice return stored state without applying time or withdrawal-batch changes.
  function previousState() external view returns (MarketState memory) {
    MarketState memory state = _state;

    assembly {
      return(state, 0x1e0)
    }
  }

  // ┌─ _calculateCurrentState ─────
  function _calculateCurrentState()
    internal
    view
    returns (MarketState memory state, uint32 pendingBatchExpiry, WithdrawalBatch memory pendingBatch)
  {
    LifecycleTransition memory next = _allocateTransition.asTransitionAllocator()();
    _calculateTransition(next, totalAssets(), _runtimeConstant(1) != 0);
    return (next.state, next.batchExpiry, next.batch);
  }

  // ┌─ _calculateCurrentStatePointers ─────
  /// @dev these callers only need MarketState. skip the three-result wrapper and return its
  ///      existing memory pointer without allocating another empty MarketState.
  function _calculateCurrentStatePointers() internal view returns (uint256 state) {
    LifecycleTransition memory next = _allocateTransition.asTransitionAllocator()();
    _calculateTransition(next, totalAssets(), _runtimeConstant(1) != 0);
    assembly ('memory-safe') {
      state := mload(next)
    }
  }

  // ┌─ _getUpdatedState ─────
  /// @dev return memory state after accruing interest, delinquency and protocol fees, and
  ///      processing any expired current batch. callers can make further changes to that state.
  ///      accrued changes aren't committed to `_state`: the caller must write them or revert.
  ///
  /// @return state market state after accrual.
  function _getUpdatedState() internal returns (MarketState memory state) {
    // keep the view/write/repay callers on one transition body. constant flags clone it in viaIR.
    return _getUpdatedState(_runtimeConstant(1) != 0);
  }

  // ┌─ _getUpdatedState ─────
  /// @dev repayment transfers arrive before this call. defer today's closure until the explicit
  ///      repayment accounting finishes; historical closure still applies at its own boundary.
  function _getUpdatedState(bool closeAtCurrentTimestamp) internal returns (MarketState memory state) {
    uint256 currentAssets = totalAssets();
    LifecycleTransition memory next = _allocateTransition.asTransitionAllocator()();
    _calculateTransition(next, currentAssets, closeAtCurrentTimestamp);
    state = next.state;
    for (uint256 i; i <= next.accrualCount; ++i) {
      if (next.batchExpired.and(next.expiryAfterAccrual == i)) {
        _commitTransitionBatch(next, _runtimeConstant(1) != 0);
      }
      if (i < next.accrualCount) {
        LifecycleAccrual memory a = next.accruals[i];
        emit_InterestAndFeesAccrued(a);
      }
    }
    if ((!next.batchExpired).and(next.batchExpiry != 0)) {
      _commitTransitionBatch(next, _runtimeConstant(0) != 0);
    }
    if (next.repaymentActivated) emit_RepaymentDateReached(repaymentDate());
    if ((_lifecycle.defaultedAt == 0).and(next.lifecycle.defaultedAt != 0)) {
      emit_DefaultRecorded(next.lifecycle.defaultedAt);
    }
    _lifecycle = next.lifecycle;
    if (next.closedAt != 0) _commitAutomaticClosure(next.closedAt);
  }

  // ┌─ _allocateTransition ─────
  /// @dev one zeroed arena for the ten-word header, four-word batch, four record pointers and
  ///      four six-word accrual records. _calculateTransition loads state/lifecycle separately.
  function _allocateTransition() internal pure returns (uint256 pointer) {
    assembly ('memory-safe') {
      pointer := mload(0x40)
      mstore(0x40, add(pointer, 0x540))
      calldatacopy(pointer, calldatasize(), 0x540)
      mstore(add(pointer, 0x40), add(pointer, 0x140))
      let records := add(pointer, 0x1c0)
      mstore(add(pointer, 0xe0), records)
      for {
        let i := 0
      } lt(i, 4) {
        i := add(i, 1)
      } {
        mstore(add(records, mul(i, 0x20)), add(add(pointer, 0x240), mul(i, 0xc0)))
      }
    }
  }

  // ┌─ _calculateTransition ─────
  /// @dev replay only the finite boundaries that change accounting. no daily loop, and no
  ///      accrual split merely to record the separate 90-day default marker.
  function _calculateTransition(LifecycleTransition memory next, uint256 currentAssets, bool closeNow) internal view {
    next.state = _state;
    next.lifecycle = _lifecycle;
    MarketState memory state = next.state;
    uint256 historicalAssets = _checkpointedTotalAssets();
    uint256 date = repaymentDate();
    uint256 deadline = repaymentDeadline();
    bool datePending = (date != 0).and(date > state.lastInterestAccruedTimestamp).and(date <= block.timestamp);
    bool deadlinePending =
      (date != 0).and(deadline >= state.lastInterestAccruedTimestamp).and(block.timestamp > deadline);
    bool expiryPending = state.hasPendingExpiredBatch();
    if (state.pendingWithdrawalExpiry != 0) {
      next.batchExpiry = state.pendingWithdrawalExpiry;
      next.batch = _withdrawalData.batches[next.batchExpiry];
    }
    while (true) {
      uint256 target = block.timestamp;
      if (datePending.and(date < target)) target = date;
      if (deadlinePending.and(deadline < target)) target = deadline;
      if (expiryPending.and(next.batchExpiry < target)) target = next.batchExpiry;
      _accrueTransition(next, target, date);
      if (datePending.and(target == date)) {
        datePending = false;
        if (!state.isClosed) {
          next.repaymentActivated = true;
          next.lifecycle.activateRepayment(state, historicalAssets, date);
          if (historicalAssets >= state.totalDebts()) {
            _previewAutomaticClosure(next, historicalAssets, target);
          }
        }
      }

      // judge the inclusive deadline before processing an expiry at that same timestamp.
      if (deadlinePending.and(target == deadline)) {
        deadlinePending = false;
        if (!state.isClosed && historicalAssets < state.totalDebts() && next.lifecycle.defaultedAt == 0) {
          next.lifecycle.defaultedAt = uint32(deadline);
        }
      }
      if (expiryPending.and(target == next.batchExpiry)) {
        expiryPending = false;
        if (state.pendingWithdrawalExpiry != 0) {
          _payTransitionBatch(next, historicalAssets);
          next.batch.releaseRemainder(state);
          state.pendingWithdrawalExpiry = 0;
          next.batchExpired = true;
          next.expiryAfterAccrual = next.accrualCount;
          state.isDelinquent = state.liquidityRequired() > historicalAssets;
        }
      }
      if ((next.closedAt != 0).or(target == block.timestamp)) break;
    }
    if (next.closedAt != 0) state.lastInterestAccruedTimestamp = uint32(block.timestamp);
    if (state.pendingWithdrawalExpiry != 0) _payTransitionBatch(next, currentAssets);
    if (
      closeNow.and(date != 0).and(block.timestamp >= date).and(!state.isClosed) && currentAssets >= state.totalDebts()
    ) {
      _previewAutomaticClosure(next, currentAssets, block.timestamp);
    }
  }

  // ┌─ _accrueTransition ─────
  function _accrueTransition(LifecycleTransition memory next, uint256 timestamp, uint256 date) internal view {
    MarketState memory state = next.state;
    uint256 grace = (date != 0).and(state.lastInterestAccruedTimestamp >= date) ? 0 : delinquencyGracePeriod;
    next.lifecycle.accrueDefaultRun(state, timestamp, grace);
    if (timestamp == state.lastInterestAccruedTimestamp) return;

    // LifecycleTransition already allocated four records. fill the next slot in place.
    LifecycleAccrual memory a = next.accruals[next.accrualCount++];
    a.from = state.lastInterestAccruedTimestamp;
    a.to = timestamp.toUint32();
    (a.baseInterestRay, a.delinquencyFeeRay, a.protocolFee) = _updateScaleFactorAndFees(state, timestamp);
    a.scaleFactor = state.scaleFactor;
  }

  // ┌─ _updateScaleFactorAndFees ─────
  function _updateScaleFactorAndFees(
    MarketState memory state,
    uint256 timestamp
  )
    internal
    view
    returns (uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee)
  {
    baseInterestRay = _calculateBaseInterest(state, timestamp);
    if (state.protocolFeeBips > 0) protocolFee = state.applyProtocolFee(baseInterestRay);
    uint256 timeDelta = timestamp - state.lastInterestAccruedTimestamp;
    uint256 penaltyTime = state.updateTimeDelinquentAndGetPenaltyTime(delinquencyGracePeriod, timeDelta);
    uint256 date = repaymentDate();
    if ((date != 0).and(state.lastInterestAccruedTimestamp >= date).and(state.isDelinquent)) {
      penaltyTime = timeDelta;
    }
    if ((penaltyTime > 0).and(delinquencyFeeBips > 0)) {
      delinquencyFeeRay = MathUtils.calculateLinearInterestFromBips(delinquencyFeeBips, penaltyTime);
    }
    uint256 scale = state.scaleFactor;
    state.scaleFactor = (scale + scale.rayMul(baseInterestRay + delinquencyFeeRay)).toUint112();
    state.lastInterestAccruedTimestamp = timestamp.toUint32();
  }

  // ┌─ _calculateBaseInterest ─────
  /// @dev revolving markets override only the base rate; fees and penalty timing stay shared.
  function _calculateBaseInterest(MarketState memory state, uint256 timestamp) internal view virtual returns (uint256) {
    return state.calculateBaseInterest(timestamp);
  }

  // ░░▒▒▓▓██ [ BATCH FUNDING ] ────────────────────────────────────────────────

  // ┌─ _commitTransitionBatch ─────
  function _commitTransitionBatch(LifecycleTransition memory next, bool expired) internal {
    uint32 expiry = next.batchExpiry;
    WithdrawalBatch memory previous = _withdrawalData.batches[expiry];
    WithdrawalBatch memory batch = next.batch;
    if (batch.scaledAmountBurned != previous.scaledAmountBurned) {
      uint128 paid = batch.normalizedAmountPaid - previous.normalizedAmountPaid;
      emit_Transfer(address(this), _runtimeConstant(address(0)), paid);
      emit_WithdrawalBatchPayment(expiry, batch.scaledAmountBurned - previous.scaledAmountBurned, paid);
    }
    _withdrawalData.batches[expiry] = batch;
    if (expired) {
      emit_WithdrawalBatchExpired(expiry, batch.scaledTotalAmount, batch.scaledAmountBurned, batch.normalizedAmountPaid);
      _closeOrQueueWithdrawalBatch(expiry, batch);
    }
  }

  // ┌─ _closeOrQueueWithdrawalBatch ─────
  /// @dev close fully paid batches. keep capped or underfunded batches reachable through FIFO.
  function _closeOrQueueWithdrawalBatch(uint32 expiry, WithdrawalBatch memory batch) internal {
    if (batch.scaledAmountBurned == batch.scaledTotalAmount) {
      emit_WithdrawalBatchClosed(expiry);
    } else {
      _withdrawalData.unpaidBatches.push(expiry);
    }
  }

  // ┌─ _payTransitionBatch ─────
  function _payTransitionBatch(LifecycleTransition memory next, uint256 assets) internal pure {
    uint256 available = next.batch.availableLiquidityForPendingBatch(next.state, assets);
    if (available != 0) _applyWithdrawalBatchPaymentView(next.batch, next.state, available);
  }

  // ┌─ _applyWithdrawalBatchPayment ─────
  /// @dev fund a batch by burning market tokens and reserving the underlying assets for claims.
  function _applyWithdrawalBatchPayment(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint32 expiry,
    uint256 availableLiquidity
  )
    internal
    returns (uint104 scaledAmountBurned, uint128 normalizedAmountPaid)
  {
    (scaledAmountBurned, normalizedAmountPaid) = _applyWithdrawalBatchPaymentView(batch, state, availableLiquidity);
    if (scaledAmountBurned == 0) return (0, 0);

    // expose the burn to external token trackers.
    emit_Transfer(address(this), _runtimeConstant(address(0)), normalizedAmountPaid);
    emit_WithdrawalBatchPayment(expiry, scaledAmountBurned, normalizedAmountPaid);
  }

  // ┌─ _applyWithdrawalBatchPaymentView ─────
  /// @dev shared by preview and execution. mutate only these memory structs; the caller commits
  ///      storage and emits payment events when `scaledAmountBurned` is nonzero.
  function _applyWithdrawalBatchPaymentView(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint256 availableLiquidity
  )
    internal
    pure
    returns (uint104 scaledAmountBurned, uint128 normalizedAmountPaid)
  {
    // all paid-but-unclaimed withdrawals share one uint128 counter. leave excess liquidity
    // unallocated until claims free capacity. the uint128 complement is exactly
    // type(uint128).max minus the stored value.
    uint256 headroom = ~state.normalizedUnclaimedWithdrawals;
    if (availableLiquidity > headroom) availableLiquidity = headroom;

    // cumulative totals and their live difference still fit uint104. the packed ABI fields stay uint128.
    uint256 burned = uint256(batch.scaledTotalAmount - batch.scaledAmountBurned).toUint104();
    uint256 paymentRay;
    unchecked {
      // uint104 owed * uint112 factor plus a sub-RAY remainder fits uint256.
      paymentRay = burned * state.scaleFactor + batch.paymentRemainder;
      if (paymentRay / RAY > availableLiquidity) {
        // solve floor((burned * factor + remainder) / RAY) <= available directly.
        // bound available before multiplying by RAY, including for huge donations.
        burned = ((availableLiquidity + 1) * RAY - 1 - batch.paymentRemainder) / state.scaleFactor;
        paymentRay = burned * state.scaleFactor + batch.paymentRemainder;
      }
    }

    // covers an already paid batch and liquidity too small to fund one share.
    if (burned == 0) return (0, 0);

    // the affordability inverse can only reduce the checked live amount.
    scaledAmountBurned = uint104(burned);
    normalizedAmountPaid = (paymentRay / RAY).toUint128();
    uint128 nextRemainder = uint128(paymentRay % RAY);
    state.withdrawalRemainder = state.withdrawalRemainder - batch.paymentRemainder + nextRemainder;
    batch.paymentRemainder = nextRemainder;

    batch.scaledAmountBurned += scaledAmountBurned;
    batch.normalizedAmountPaid += normalizedAmountPaid;
    state.scaledPendingWithdrawals -= scaledAmountBurned;

    // reserve these assets for claims; they aren't free liquidity anymore.
    state.normalizedUnclaimedWithdrawals += normalizedAmountPaid;

    // funded shares stop earning interest.
    state.scaledTotalSupply -= scaledAmountBurned;
  }

  // ░░▒▒▓▓██ [ CLOSURE ] ──────────────────────────────────────────────────────

  // ┌─ _previewAutomaticClosure ─────
  function _previewAutomaticClosure(LifecycleTransition memory next, uint256 assets, uint256 timestamp) internal pure {
    MarketState memory state = next.state;
    if (state.pendingWithdrawalExpiry != 0) {
      _payTransitionBatch(next, assets);
      next.batch.releaseRemainder(state);
      state.pendingWithdrawalExpiry = 0;
      next.batchExpired = true;
      next.expiryAfterAccrual = next.accrualCount;
    }
    state.closeFundedState();
    next.lifecycle.penaltyCutoff = 0;
    next.closedAt = uint32(timestamp);
  }

  // ┌─ _closeAfterCurrentAction ─────
  function _closeAfterCurrentAction(MarketState memory state, uint256 assets) internal {
    if (state.isClosed.or(!_isInRepayment()) || assets < state.totalDebts()) return;
    if (state.pendingWithdrawalExpiry != 0) {
      uint32 expiry = state.pendingWithdrawalExpiry;
      WithdrawalBatch memory batch = _withdrawalData.batches[expiry];
      uint256 available = batch.availableLiquidityForPendingBatch(state, assets);
      _applyWithdrawalBatchPayment(batch, state, expiry, available);
      batch.releaseRemainder(state);
      _withdrawalData.batches[expiry] = batch;
      state.pendingWithdrawalExpiry = 0;
      emit_WithdrawalBatchExpired(expiry, batch.scaledTotalAmount, batch.scaledAmountBurned, batch.normalizedAmountPaid);
      _closeOrQueueWithdrawalBatch(expiry, batch);
    }
    state.closeFundedState();
    _commitAutomaticClosure(block.timestamp);
  }

  // ┌─ _commitAutomaticClosure ─────
  /// @dev closure freezes all fully backed claims. older batches can then finish in bounded FIFO
  ///      calls. leave surplus for rescueTokens; a failed borrower transfer must not block lenders.
  ///      never give an arbitrary hook a veto over the scheduled obligation.
  function _commitAutomaticClosure(uint256 timestamp) internal {
    _onCloseMarket();
    emit_AnnualInterestAndReserveRatioBipsUpdated(
      borrower(), _state.annualInterestBips, 0, _state.reserveRatioBips, 10_000
    );
    emit_MarketClosed(borrower(), timestamp);
  }

  // ┌─ _onCloseMarket ─────
  /// @dev derived-market accounting hook after closure with all debt backed. automatic closure
  ///      can leave older withdrawal batches to be funded in later bounded calls.
  function _onCloseMarket() internal virtual { }

  // ░░▒▒▓▓██ [ STATE PERSISTENCE ] ────────────────────────────────────────────

  // ┌─ _writeState ─────
  /// @dev commit the caller's modified memory state and emit the state-update event.
  function _writeState(MarketState memory state) internal {
    _writeState(state, totalAssets());
  }

  // ┌─ _writeState ─────
  /// @dev commit state using an asset balance read after the last external state-changing call.
  function _writeState(MarketState memory state, uint256 currentTotalAssets) internal {
    _closeAfterCurrentAction(state, currentTotalAssets);
    bool isDelinquent = state.liquidityRequired() > currentTotalAssets;
    state.isDelinquent = isDelinquent;
    if ((!isDelinquent).or(state.isClosed)) _lifecycle.penaltyCutoff = 0;

    // a direct transfer can exceed uint152. saturate instead of bricking every state write.
    // the uint104/uint112/uint128 accounting fields keep every payable liability below uint152,
    // so saturation preserves the economically relevant balance.
    uint256 checkpointedTotalAssets;
    if ((state.pendingWithdrawalExpiry != 0).or(repaymentDate() != 0)) {
      checkpointedTotalAssets = MathUtils.min(currentTotalAssets, type(uint152).max);
    }

    {
      bool isClosed = state.isClosed;
      uint256 maxTotalSupply = state.maxTotalSupply;
      assembly {
        // Slot 0 Storage Layout:
        // [0:15]  | low 120 bits of checkpointedTotalAssets
        // [15:31] | state.maxTotalSupply
        // [31:32] | state.isClosed
        let checkpointMask := sub(shl(0x78, 1), 1)
        let slot0 :=
          or(or(isClosed, shl(0x08, maxTotalSupply)), shl(0x88, and(checkpointedTotalAssets, checkpointMask)))
        sstore(_state.slot, slot0)
      }
    }
    {
      uint256 accruedProtocolFees = state.accruedProtocolFees;
      uint256 normalizedUnclaimedWithdrawals = state.normalizedUnclaimedWithdrawals;
      assembly {
        // Slot 1 Storage Layout:
        // [0:16] | state.normalizedUnclaimedWithdrawals
        // [16:32] | state.accruedProtocolFees
        let slot1 := or(accruedProtocolFees, shl(0x80, normalizedUnclaimedWithdrawals))
        sstore(add(_state.slot, 1), slot1)
      }
    }
    {
      uint256 scaledTotalSupply = state.scaledTotalSupply;
      uint256 scaledPendingWithdrawals = state.scaledPendingWithdrawals;
      uint256 pendingWithdrawalExpiry = state.pendingWithdrawalExpiry;
      assembly {
        // Slot 2 Storage Layout:
        // [1:2] | state.isDelinquent
        // [2:6] | state.pendingWithdrawalExpiry
        // [6:19] | state.scaledPendingWithdrawals
        // [19:32] | state.scaledTotalSupply
        let slot2 :=
          or(
            or(or(shl(0xf0, isDelinquent), shl(0xd0, pendingWithdrawalExpiry)), shl(0x68, scaledPendingWithdrawals)),
            scaledTotalSupply
          )
        sstore(add(_state.slot, 2), slot2)
      }
    }
    {
      uint256 timeDelinquent = state.timeDelinquent;
      uint256 protocolFeeBips = state.protocolFeeBips;
      uint256 annualInterestBips = state.annualInterestBips;
      uint256 reserveRatioBips = state.reserveRatioBips;
      uint256 scaleFactor = state.scaleFactor;
      uint256 lastInterestAccruedTimestamp = state.lastInterestAccruedTimestamp;
      assembly {
        // Slot 3 Storage Layout:
        // [0:4] | high 32 bits of checkpointedTotalAssets
        // [4:8] | state.lastInterestAccruedTimestamp
        // [8:22] | state.scaleFactor
        // [22:24] | state.reserveRatioBips
        // [24:26] | state.annualInterestBips
        // [26:28] | protocolFeeBips
        // [28:32] | state.timeDelinquent
        let slot3 :=
          or(
            shl(0xe0, shr(0x78, checkpointedTotalAssets)),
            or(
              or(
                or(or(shl(0xc0, lastInterestAccruedTimestamp), shl(0x50, scaleFactor)), shl(0x40, reserveRatioBips)),
                or(shl(0x30, annualInterestBips), shl(0x20, protocolFeeBips))
              ),
              timeDelinquent
            )
          )
        sstore(add(_state.slot, 3), slot3)
      }
    }
    _state.withdrawalRemainder = state.withdrawalRemainder;
    emit_StateUpdated(state.scaleFactor, isDelinquent);
  }

  // ┌─ _checkpointedTotalAssets ─────
  /// @dev last asset balance committed while a current batch existed or repayment terms were enabled.
  ///      the uint152 value uses spare high bits in state slots zero and three; MarketState layout
  ///      and the hook ABI stay unchanged.
  function _checkpointedTotalAssets() internal view returns (uint256 value) {
    assembly {
      value := or(shr(0x88, sload(_state.slot)), shl(0x78, shr(0xe0, sload(add(_state.slot, 3)))))
    }
  }

  // ░░▒▒▓▓██ [ BORROWING AND REPAYMENT ] ──────────────────────────────────────

  // ┌─ _onBorrow ─────
  /// @dev derived-market accounting hook called before borrowed assets leave the market.
  function _onBorrow(MarketState memory state, uint256 amount) internal virtual {
    state;
    amount;
  }

  // ┌─ _onRepay ─────
  /// @dev derived-market accounting hook called after repaid assets reach the market.
  function _onRepay(MarketState memory state, uint256 amount) internal virtual {
    state;
    amount;
  }

  // ┌─ _onRepayAndGetTotalAssets ─────
  /// @dev runs derived repayment accounting and returns the post-transfer underlying balance.
  function _onRepayAndGetTotalAssets(
    MarketState memory state,
    uint256 amount
  )
    internal
    virtual
    returns (uint256 currentTotalAssets)
  {
    _onRepay(state, amount);
    currentTotalAssets = totalAssets();
  }

  // ░░▒▒▓▓██ [ ACCOUNTING QUERIES ] ───────────────────────────────────────────

  // ┌─ totalAssets ─────
  /// @notice return the market contract's raw underlying-asset balance.
  ///
  /// @dev this includes reserves, protocol fees, and paid-but-unclaimed withdrawals.
  function totalAssets() public view returns (uint256) {
    return asset.balanceOf(address(this));
  }

  // ┌─ totalDebts ─────
  /// @notice return normalized lender supply, unclaimed withdrawals, and protocol fees.
  function totalDebts() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().totalDebts();
  }

  // ┌─ coverageLiquidity ─────
  /// @notice return the current collateral obligation in underlying-asset units.
  function coverageLiquidity() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().liquidityRequired();
  }

  // ┌─ borrowableAssets ─────
  /// @notice return underlying assets left after the market's full collateral obligation.
  function borrowableAssets() external view nonReentrantView returns (uint256) {
    if (_state.isClosed.or(_isInRepayment())) return 0;
    return _calculateCurrentStatePointers.asReturnsMarketState()().borrowableAssets(totalAssets());
  }

  // ┌─ scaleFactor ─────
  /// @notice return the current ray-scaled ratio from scaled shares to normalized tokens.
  function scaleFactor() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().scaleFactor;
  }

  // ┌─ scaledTotalSupply ─────
  /// @notice return current scaled supply after any calculable withdrawal-batch payment.
  function scaledTotalSupply() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().scaledTotalSupply;
  }

  // ┌─ scaledBalanceOf ─────
  /// @notice return `account`'s direct share-like balance without applying the scale factor.
  function scaledBalanceOf(address account) external view nonReentrantView returns (uint256) {
    return _accounts[account].scaledBalance;
  }

  // ┌─ accruedProtocolFees ─────
  /// @notice return all accrued protocol fees, including any not currently withdrawable.
  function accruedProtocolFees() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().accruedProtocolFees;
  }

  // ┌─ withdrawableProtocolFees ─────
  /// @notice return protocol fees withdrawable after reserving paid lender claims.
  function withdrawableProtocolFees() external view nonReentrantView returns (uint128) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().withdrawableProtocolFees(totalAssets());
  }

  // ░░▒▒▓▓██ [ SANCTIONS ] ────────────────────────────────────────────────────

  // ┌─ _getAccount ─────
  /// @dev loads an account and reverts if it is currently sanctioned for this borrower principal.
  function _getAccount(address accountAddress) internal view returns (Account memory account) {
    account = _accounts[accountAddress];
    if (_isSanctioned(accountAddress)) revertWithSelector(AccountBlocked_ErrorSelector);
  }

  // ┌─ _isSanctioned ─────
  /// @dev checks whether `account` is sanctioned in this market's current principal namespace.
  ///      if an account is flagged mistakenly, the principal can override their
  ///      status on the sentinel and allow them to interact with the market.
  function _isSanctioned(address account) internal view returns (bool result) {
    address _borrowerPrincipal = borrowerPrincipal();
    address _sentinel = address(sentinel);
    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(0, 0x06e74444)
      mstore(0x20, _borrowerPrincipal)
      mstore(0x40, account)
      // sentinel.isSanctioned(principal, account) must succeed and return exactly 32 bytes.
      if iszero(and(eq(returndatasize(), 0x20), staticcall(gas(), _sentinel, 0x1c, 0x44, 0, 0x20))) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      result := mload(0)
      mstore(0x40, freeMemoryPointer)
    }
  }

  // ┌─ _blockAccount ─────
  /// @dev derived market hook for quarantining a sanctioned lender's balance.
  function _blockAccount(MarketState memory state, address accountAddress) internal virtual { }

  // ┌─ _isFlaggedByChainalysis ─────
  /// @dev checks the raw Chainalysis list directly and ignores borrower overrides.
  function _isFlaggedByChainalysis(address account) internal view returns (bool isFlagged) {
    address sentinelAddress = address(sentinel);
    assembly {
      mstore(0, 0x95c09839)
      mstore(0x20, account)
      if iszero(and(eq(returndatasize(), 0x20), staticcall(gas(), sentinelAddress, 0x1c, 0x24, 0, 0x20))) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      isFlagged := mload(0)
    }
  }

  // ┌─ _createEscrowForUnderlyingAsset ─────
  /// @dev gets or deploys the lender's escrow for the current principal and underlying asset.
  function _createEscrowForUnderlyingAsset(address accountAddress) internal returns (address escrow) {
    address tokenAddress = address(asset);
    address principalAddress = borrowerPrincipal();
    address sentinelAddress = address(sentinel);

    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(0, 0xa1054f6b)
      mstore(0x20, principalAddress)
      mstore(0x40, accountAddress)
      mstore(0x60, tokenAddress)
      if iszero(and(eq(returndatasize(), 0x20), call(gas(), sentinelAddress, 0, 0x1c, 0x64, 0, 0x20))) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      escrow := mload(0)
      mstore(0x40, freeMemoryPointer)
      mstore(0x60, 0)
    }
  }

  // ░░▒▒▓▓██ [ RUNTIME CONSTANTS ] ────────────────────────────────────────────

  // ┌─ _runtimeConstant ─────
  /// @dev hide constant arguments from solc so it doesn't clone specialized function bodies.
  ///      those clones usually save little gas and can add substantial contract size.
  ///
  ///      the result equals the input outside constructors, fallback, and receive functions.
  function _runtimeConstant(uint256 actualConstant) internal pure returns (uint256 runtimeConstant) {
    assembly {
      mstore(0, actualConstant)
      runtimeConstant := mload(iszero(calldatasize()))
    }
  }

  // ┌─ _runtimeConstant ─────
  function _runtimeConstant(address actualConstant) internal pure returns (address runtimeConstant) {
    assembly {
      mstore(0, actualConstant)
      runtimeConstant := mload(iszero(calldatasize()))
    }
  }
}
