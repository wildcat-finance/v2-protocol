// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import '../ReentrancyGuard.sol';
import '../spherex/SphereXProtectedRegisteredBase.sol';
import '../interfaces/IMarketEventsAndErrors.sol';
import '../interfaces/IWildcatArchController.sol';
import '../IHooksFactory.sol';
import '../libraries/FeeMath.sol';
import '../libraries/MarketLifecycle.sol';
import '../libraries/MarketErrors.sol';
import '../libraries/MarketEvents.sol';
import '../libraries/Withdrawal.sol';
import '../libraries/FunctionTypeCasts.sol';
import '../libraries/LibERC20.sol';
import '../types/HooksConfig.sol';

/// @notice shared market storage, accounting, identity, sanctions, and state-update machinery.
contract WildcatMarketBase is
  SphereXProtectedRegisteredBase,
  ReentrancyGuard,
  IMarketEventsAndErrors
{
  using SafeCastLib for uint256;
  using MathUtils for uint256;
  using FunctionTypeCasts for *;
  using LibERC20 for address;
  using MarketLifecycleLib for MarketLifecycle;
  using MarketLifecycleLib for MarketState;

  // ==================================================================== //
  //                            Market Config                             //
  // ==================================================================== //

  /**
   * @notice returns the market implementation version, `2.5`.
   * @dev bumped from "2" for the v2.5 release: transfer and deposit scaling
   *      changed from half-up to floor rounding, so v2.5 markets must be
   *      distinguishable from earlier deployments. Consumers that only check
   *      the major version read the first byte, which remains '2'.
   */
  function version() external pure returns (string memory) {
    assembly {
      mstore(0x40, 0)
      // Length byte (3) at 0x5f followed by '2.5' at 0x60-0x62.
      mstore(0x43, 0x03322e35)
      mstore(0x20, 0x20)
      return(0x20, 0x60)
    }
  }

  /**
   * @notice identifies floor rounding for normalized-to-scaled transfers and deposits.
   * @dev Rounding convention for scaled amounts in transfers and deposits
   *      (`MarketState.scaleAmountDown`). Rounding-sensitive integrations,
   *      e.g. the 4626 wrapper factory, key on this rather than on version
   *      strings. Markets predating v2.5 lack this function and round
   *      half-up.
   */
  function scaledTransferRounding() external pure returns (bytes32) {
    return keccak256('scaleAmountDown');
  }

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

  /// @dev Reserved slots for borrower transfer and wrapper state. These are
  ///      the final five slots in the EVM storage range, from 2^256 - 1 through
  ///      2^256 - 5. Solidity assigns ordinary market storage from zero upward,
  ///      so ordinary state and future market types can keep extending that layout
  ///      without reaching this range.
  ///
  ///      Mappings and dynamic arrays derive their element slots with keccak256.
  ///      Their chance of landing on one of these slots is the same negligible
  ///      256-bit collision risk as an ordinary namespaced storage slot. Other
  ///      manual storage must not use this five-slot range.
  bytes32 internal constant BORROWER_STORAGE_SLOT = bytes32(type(uint256).max);
  bytes32 internal constant BORROWER_PRINCIPAL_STORAGE_SLOT = bytes32(type(uint256).max - 1);
  bytes32 internal constant PENDING_BORROWER_STORAGE_SLOT = bytes32(type(uint256).max - 2);
  bytes32 internal constant PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT =
    bytes32(type(uint256).max - 3);
  bytes32 internal constant REGISTERED_WRAPPER_STORAGE_SLOT = bytes32(type(uint256).max - 4);

  /// @dev ABI-encoded size of `MarketParameters`, which has 24 static fields.
  uint256 internal constant _MARKET_PARAMETERS_SIZE = 0x300;

  /// @notice annual penalty rate added to lender interest during penalized delinquency, in bips.
  uint public immutable delinquencyFeeBips;

  /// @notice delinquent time before the penalty rate applies, in seconds.
  uint public immutable delinquencyGracePeriod;

  /// @notice duration of each withdrawal batch, in seconds.
  uint public immutable withdrawalBatchDuration;

  /// @notice market-token decimals copied from the underlying asset.
  uint8 public immutable decimals;

  /// @notice underlying ERC-20 asset.
  address public immutable asset;

  bytes32 internal immutable PACKED_NAME_WORD_0;
  bytes32 internal immutable PACKED_NAME_WORD_1;
  bytes32 internal immutable PACKED_SYMBOL_WORD_0;
  bytes32 internal immutable PACKED_SYMBOL_WORD_1;

  /// @notice returns the market-token symbol set at deployment.
  function symbol() external view returns (string memory) {
    bytes32 symbolWord0 = PACKED_SYMBOL_WORD_0;
    bytes32 symbolWord1 = PACKED_SYMBOL_WORD_1;

    assembly {
      // The layout here is:
      // 0x00: Offset to the string
      // 0x20: Length of the string
      // 0x40: First word of the string
      // 0x60: Second word of the string
      // The first word of the string that is kept in immutable storage also contains the
      // length byte, meaning the total size limit of the string is 63 bytes.
      mstore(0, 0x20)
      mstore(0x20, 0)
      mstore(0x3f, symbolWord0)
      mstore(0x5f, symbolWord1)
      return(0, 0x80)
    }
  }

  /// @notice returns the market-token name set at deployment.
  function name() external view returns (string memory) {
    bytes32 nameWord0 = PACKED_NAME_WORD_0;
    bytes32 nameWord1 = PACKED_NAME_WORD_1;

    assembly {
      // The layout here is:
      // 0x00: Offset to the string
      // 0x20: Length of the string
      // 0x40: First word of the string
      // 0x60: Second word of the string
      // The first word of the string that is kept in immutable storage also contains the
      // length byte, meaning the total size limit of the string is 63 bytes.
      mstore(0, 0x20)
      mstore(0x20, 0)
      mstore(0x3f, nameWord0)
      mstore(0x5f, nameWord1)
      return(0, 0x80)
    }
  }

  /// @notice returns the protocol registry that authorized this market.
  function archController() external view returns (address) {
    return _archController;
  }

  // ===================================================================== //
  //                             Market State                               //
  // ===================================================================== //

  MarketState internal _state;

  mapping(address => Account) internal _accounts;

  /// @notice Current operational borrower.
  function borrower() public view returns (address) {
    return _getAddress(BORROWER_STORAGE_SLOT);
  }

  /// @notice Current registered principal for the market.
  function borrowerPrincipal() public view returns (address) {
    return _getAddress(BORROWER_PRINCIPAL_STORAGE_SLOT);
  }

  /// @notice Address that can accept the pending borrower transfer.
  function pendingBorrower() public view returns (address) {
    return _getAddress(PENDING_BORROWER_STORAGE_SLOT);
  }

  /// @notice Principal resolved for the pending borrower when the transfer was requested.
  function pendingBorrowerPrincipal() public view returns (address) {
    return _getAddress(PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT);
  }

  /// @notice Canonical ERC-4626 wrapper for this market, or zero if none has been deployed.
  function registeredWrapper() public view returns (address) {
    return _getAddress(REGISTERED_WRAPPER_STORAGE_SLOT);
  }

  WithdrawalData internal _withdrawalData;
  MarketLifecycle internal _lifecycle;

  uint64 internal immutable _repaymentTerms;

  error InvalidRepaymentTerms();
  error UnsupportedExecuteWithdrawalHook();
  error MarketInRepayment();
  error RepaymentReserveRequired();

  event RepaymentDateReached(uint256 effectiveTimestamp);
  event DefaultRecorded(uint256 effectiveTimestamp);

  /// @notice scheduled start of full repayment, or zero when disabled. safe in hook callbacks.
  function repaymentDate() public view returns (uint256) {
    return uint32(_repaymentTerms);
  }

  /// @notice seconds from repayment date through the inclusive deadline; zero is valid.
  function repaymentPeriod() public view returns (uint256) {
    return _repaymentTerms >> 32;
  }

  function repaymentDeadline() public view returns (uint256) {
    return repaymentDate() + repaymentPeriod();
  }

  /// @notice committed default cutoff. zero means no default has been recorded yet.
  function defaultedAt() external view returns (uint256) {
    return _lifecycle.defaultedAt;
  }

  function _isInRepayment() internal view returns (bool) {
    uint256 date = repaymentDate();
    return date != 0 && block.timestamp >= date;
  }

  // ===================================================================== //
  //                             Constructor                               //
  // ===================================================================== //

  /// @dev allocates and fills the static `MarketParameters` block from the deploying factory.
  function _getMarketParameters() internal view returns (uint256 marketParametersPointer) {
    assembly {
      marketParametersPointer := mload(0x40)
      mstore(0x40, add(marketParametersPointer, _MARKET_PARAMETERS_SIZE))
      // Write the selector for IHooksFactory.getMarketParameters
      mstore(0x00, 0x04032dbb)
      // Call `getMarketParameters` and copy the returned struct to the allocated memory
      // buffer, reverting if the call fails or does not return the correct amount of bytes.
      // This overrides all the ABI decoding safety checks, as the call is always made to
      // the factory contract which will only ever return the prepared market parameters.
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

  constructor() {
    factory = msg.sender;
    // Cast the function signature of `_getMarketParameters` to get a valid reference to
    // a `MarketParameters` object without creating a duplicate allocation or unnecessarily
    // zeroing out the memory buffer.
    MarketParameters memory parameters = _getMarketParameters.asReturnsMarketParameters()();
    if (parameters.borrower == address(0)) revert InvalidBorrower();
    uint256 date = parameters.repaymentDate;
    uint256 period = parameters.repaymentPeriod;
    if (
      (date == 0 && period != 0) ||
      (date != 0 && (date <= block.timestamp || date + period > type(uint32).max))
    ) {
      revert InvalidRepaymentTerms();
    }
    if (parameters.hooks.useOnExecuteWithdrawal()) revert UnsupportedExecuteWithdrawalHook();
    _repaymentTerms = uint64(date | (period << 32));

    // Set asset metadata
    asset = parameters.asset;
    decimals = parameters.decimals;

    PACKED_NAME_WORD_0 = parameters.packedNameWord0;
    PACKED_NAME_WORD_1 = parameters.packedNameWord1;
    PACKED_SYMBOL_WORD_0 = parameters.packedSymbolWord0;
    PACKED_SYMBOL_WORD_1 = parameters.packedSymbolWord1;

    {
      // Initialize the market state - all values in slots 1 and 2 of the struct are
      // initialized to zero, so they are skipped.

      uint maxTotalSupply = parameters.maxTotalSupply;
      uint reserveRatioBips = parameters.reserveRatioBips;
      uint annualInterestBips = parameters.annualInterestBips;
      uint protocolFeeBips = parameters.protocolFeeBips;

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

        let slot3 := or(
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
      // `staticcall` takes raw memory offsets, not Solidity arguments. This
      // four-byte selector literal has 28 leading zero bytes in the word written
      // at 0x00. Starting the calldata at 0x1c skips that padding, leaving exactly
      // `archController()` as the four-byte input.
      mstore(0, 0x54635570) // archController()

      // The last two arguments tell the EVM to copy up to one return word into
      // memory at 0x00. `staticcall` itself returns 1 on success and 0 on failure.
      let validRegistry := staticcall(gas(), identityRegistry, 0x1c, 0x04, 0, 0x20)

      // A valid address return is exactly one ABI word. Both operands below are
      // already 0 or 1, so this bitwise `and` is also a logical AND.
      validRegistry := and(validRegistry, eq(returndatasize(), 0x20))
      if validRegistry {
        // The call copied its return word over the selector at 0x00. An address
        // occupies the low 160 bits of that word. If any of the upper 96 bits are
        // set, the registry returned malformed ABI data and we must not truncate it.
        let registryArchController := mload(0)
        if shr(160, registryArchController) {
          revert(0, 0)
        }

        // At this point the word is a clean address. The registry is only valid
        // for this market if it points at the same ArchController the factory supplied.
        validRegistry := eq(registryArchController, archController_)
      }
      if iszero(validRegistry) {
        // This uses the same compact custom-error layout as MarketErrors.sol:
        // selector in the last four bytes of a word, then return only those bytes.
        mstore(0, 0x41d9e607) // InvalidBorrowerIdentityRegistry()
        revert(0x1c, 0x04)
      }
    }
    if (
      parameters.borrowerPrincipal == address(0) ||
      !IWildcatArchController(archController_).isRegisteredBorrower(parameters.borrowerPrincipal)
    ) {
      revert BorrowerPrincipalNotRegistered();
    }
    __SphereXProtectedRegisteredBase_init(parameters.sphereXEngine);
  }

  // ===================================================================== //
  //                              Modifiers                                //
  // ===================================================================== //

  modifier onlyBorrower() {
    address _borrower = borrower();
    assembly {
      // Equivalent to
      // if (msg.sender != borrower) revert NotApprovedBorrower();
      if xor(caller(), _borrower) {
        mstore(0, 0x02171e6a)
        revert(0x1c, 0x04)
      }
    }
    _;
  }

  // ===================================================================== //
  //                         Borrower Transfer                             //
  // ===================================================================== //

  /// @dev returns the first raw Chainalysis-flagged identity, ignoring sentinel overrides.
  function _flaggedBorrowerIdentity(
    address operationalBorrower,
    address principal
  ) internal view returns (address flaggedIdentity) {
    if (_isFlaggedByChainalysis(operationalBorrower)) return operationalBorrower;
    if (principal != operationalBorrower && _isFlaggedByChainalysis(principal)) return principal;
  }

  /// @dev reverts if either borrower identity is raw-flagged by Chainalysis.
  function _checkBorrowerNotSanctioned(
    address operationalBorrower,
    address principal
  ) internal view {
    address flaggedIdentity = _flaggedBorrowerIdentity(operationalBorrower, principal);
    if (flaggedIdentity != address(0)) {
      revert_BorrowerTransferWhileSanctioned(flaggedIdentity);
    }
  }

  /// @dev resolves a transfer target, binds an expected principal on acceptance, rejects an exact
  ///      identity no-op, and checks raw sanctions on both sides of the transfer.
  function _validateBorrowerTransferTarget(
    address newBorrower,
    address expectedPrincipal
  ) internal view returns (address newBorrowerPrincipal) {
    address currentBorrower;
    address currentBorrowerPrincipal;
    bytes32 borrowerSlot = BORROWER_STORAGE_SLOT;
    bytes32 borrowerPrincipalSlot = BORROWER_PRINCIPAL_STORAGE_SLOT;
    address identityRegistry = borrowerIdentityRegistry;
    assembly {
      // The borrower fields use reserved storage slots rather than ordinary
      // Solidity state variables. `sload` reads the whole 32-byte slot; the
      // stored address is the low 160 bits and is assigned cleanly to the
      // Solidity address variable.
      currentBorrower := sload(borrowerSlot)
      if iszero(newBorrower) {
        // InvalidBorrowerTransferTarget() has no arguments, so its revert data
        // is just the four-byte selector at the end of this scratch word.
        mstore(0, 0x5176bd60)
        revert(0x1c, 0x04)
      }

      // Build `resolveBorrower(newBorrower)` directly in scratch memory. The
      // selector occupies the last four bytes of the word at 0x00 and the address
      // occupies the word at 0x20. Reading from 0x1c for 0x24 bytes gives the call
      // its four-byte selector followed by one complete ABI argument.
      mstore(0, 0xa111a9e8)
      mstore(0x20, newBorrower)

      // Ask the registry to resolve the operational address without allowing it
      // to change state. The first 32 bytes of a successful return are copied
      // back to 0x00, replacing the selector because we no longer need it.
      if iszero(staticcall(gas(), identityRegistry, 0x1c, 0x24, 0, 0x20)) {
        // If the registry explains why it failed, preserve that exact error.
        // `returndatacopy` moves every returned byte into scratch memory and the
        // following revert sends the same bytes back to our caller.
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }

      // Solidity needs at least one full word to decode an address. It also
      // rejects dirty upper bits instead of silently truncating them, so perform
      // both checks before treating the return word as a principal.
      if lt(returndatasize(), 0x20) {
        revert(0, 0)
      }
      newBorrowerPrincipal := mload(0)
      if shr(160, newBorrowerPrincipal) {
        revert(0, 0)
      }

      currentBorrowerPrincipal := sload(borrowerPrincipalSlot)

      // Requests pass zero here because there is no earlier resolution to bind.
      // Acceptance passes the principal stored with the pending transfer. Yul
      // treats any nonzero word as true, so this outer check is the readable way
      // to distinguish those paths without confusing bitwise AND with boolean AND.
      if expectedPrincipal {
        // `xor(a, b)` is zero only when every bit is identical. Any nonzero
        // result means the account changed principals while acceptance was pending.
        if xor(newBorrowerPrincipal, expectedPrincipal) {
          // PendingBorrowerPrincipalChanged(address,address) is the four-byte
          // selector followed by the expected and current principal words.
          mstore(0, 0xe1357b3c)
          mstore(0x20, expectedPrincipal)
          mstore(0x40, newBorrowerPrincipal)
          revert(0x1c, 0x44)
        }
      }

      // Re-requesting the same operational borrower is valid when its principal
      // changed, but an exact borrower/principal no-op is not. Unlike raw
      // addresses, each `eq` returns exactly 0 or 1, so `and` is safe here as a
      // logical AND.
      if and(eq(newBorrower, currentBorrower), eq(newBorrowerPrincipal, currentBorrowerPrincipal)) {
        mstore(0, 0x5176bd60)
        revert(0x1c, 0x04)
      }
    }
    _checkBorrowerNotSanctioned(currentBorrower, currentBorrowerPrincipal);
    _checkBorrowerNotSanctioned(newBorrower, newBorrowerPrincipal);
  }

  /// @notice requests transfer of borrower authority to `newBorrower`.
  /// @dev only the current borrower can call. a new request replaces any pending target. the
  ///      identity registry pins the target's principal, and raw sanctions block either side.
  /// @param newBorrower operational address that may later accept the transfer.
  function requestBorrowerTransfer(
    address newBorrower
  ) external onlyBorrower nonReentrant sphereXGuardExternal {
    address newBorrowerPrincipal = _validateBorrowerTransferTarget(
      newBorrower,
      _runtimeConstant(address(0))
    );
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

  /// @notice clears the pending borrower transfer without changing current authority.
  function cancelBorrowerTransfer() external onlyBorrower nonReentrant sphereXGuardExternal {
    address cancelledPendingBorrower = pendingBorrower();
    if (cancelledPendingBorrower == address(0)) revert_NoPendingBorrowerTransfer();
    address cancelledPendingBorrowerPrincipal = pendingBorrowerPrincipal();
    _setAddress(PENDING_BORROWER_STORAGE_SLOT, address(0));
    _setAddress(PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT, address(0));
    emit_BorrowerTransferCancelled(
      msg.sender,
      cancelledPendingBorrower,
      borrowerPrincipal(),
      cancelledPendingBorrowerPrincipal
    );
  }

  /// @notice accepts borrower authority for the pending operational address and pinned principal.
  /// @dev only the pending borrower can call. the target is resolved and sanctions are checked
  ///      again; a principal change since request makes the caller request a fresh transfer.
  function acceptBorrowerTransfer() external nonReentrant sphereXGuardExternal {
    address newBorrower = pendingBorrower();
    if (msg.sender != newBorrower) revert_NotPendingBorrower();

    address expectedPrincipal = pendingBorrowerPrincipal();
    address newBorrowerPrincipal = _validateBorrowerTransferTarget(newBorrower, expectedPrincipal);
    address previousBorrower = borrower();
    address previousBorrowerPrincipal = borrowerPrincipal();

    _setAddress(PENDING_BORROWER_STORAGE_SLOT, address(0));
    _setAddress(PENDING_BORROWER_PRINCIPAL_STORAGE_SLOT, address(0));
    _setAddress(BORROWER_STORAGE_SLOT, newBorrower);
    _setAddress(BORROWER_PRINCIPAL_STORAGE_SLOT, newBorrowerPrincipal);

    emit_BorrowerTransferred(
      previousBorrower,
      newBorrower,
      previousBorrowerPrincipal,
      newBorrowerPrincipal
    );
  }

  // ===================================================================== //
  //                       Internal State Getters                          //
  // ===================================================================== //

  /// @dev loads an account and reverts if it is currently sanctioned for this borrower principal.
  function _getAccount(address accountAddress) internal view returns (Account memory account) {
    account = _accounts[accountAddress];
    if (_isSanctioned(accountAddress)) revert_AccountBlocked();
  }

  /**
   * @dev checks whether `account` is sanctioned in this market's current principal namespace.
   *      If an account is flagged mistakenly, the principal can override their
   *      status on the sentinel and allow them to interact with the market.
   */
  function _isSanctioned(address account) internal view returns (bool result) {
    address _borrowerPrincipal = borrowerPrincipal();
    address _sentinel = address(sentinel);
    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(0, 0x06e74444)
      mstore(0x20, _borrowerPrincipal)
      mstore(0x40, account)
      // Call `sentinel.isSanctioned(principal, account)` and revert if the call fails
      // or does not return 32 bytes.
      if iszero(
        and(eq(returndatasize(), 0x20), staticcall(gas(), _sentinel, 0x1c, 0x44, 0, 0x20))
      ) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      result := mload(0)
      mstore(0x40, freeMemoryPointer)
    }
  }

  // ===================================================================== //
  //                       External State Getters                          //
  // ===================================================================== //

  /// @notice returns the current collateral obligation in underlying-asset units.
  function coverageLiquidity() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().liquidityRequired();
  }

  /// @notice returns the current ray-scaled ratio from scaled shares to normalized tokens.
  function scaleFactor() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().scaleFactor;
  }

  /// @notice returns the market contract's raw underlying-asset balance.
  /// @dev this includes reserves, protocol fees, and paid-but-unclaimed withdrawals.
  function totalAssets() public view returns (uint256) {
    return asset.balanceOf(address(this));
  }

  /// @notice returns underlying assets left after the market's full collateral obligation.
  function borrowableAssets() external view nonReentrantView returns (uint256) {
    if (_state.isClosed || _isInRepayment()) return 0;
    return _calculateCurrentStatePointers.asReturnsMarketState()().borrowableAssets(totalAssets());
  }

  /// @notice returns all accrued protocol fees, including any not currently withdrawable.
  function accruedProtocolFees() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().accruedProtocolFees;
  }

  /// @notice returns normalized lender supply, unclaimed withdrawals, and protocol fees.
  function totalDebts() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().totalDebts();
  }

  /// @notice returns stored state without applying time or withdrawal-batch changes.
  function previousState() external view returns (MarketState memory) {
    MarketState memory state = _state;

    assembly {
      return(state, 0x1c0)
    }
  }

  /// @notice returns the state calculable through this block without writing storage.
  /// @dev includes accrued interest and fees plus any current-batch expiry and payment.
  function currentState() external view nonReentrantView returns (MarketState memory state) {
    state = _calculateCurrentStatePointers.asReturnsMarketState()();
    assembly {
      return(state, 0x1c0)
    }
  }

  /**
   * @dev Call `_calculateCurrentState()` and return only the `state` parameter.
   *
   *      Casting the function type prevents a duplicate declaration of the MarketState
   *      return parameter, which would cause unnecessary zeroing and allocation of memory.
   *      With `viaIR` enabled, the cast is a noop.
   */
  function _calculateCurrentStatePointers() internal view returns (uint256 state) {
    (state, , ) = _calculateCurrentState.asReturnsPointers()();
  }

  /// @notice returns current scaled supply after any calculable withdrawal-batch payment.
  function scaledTotalSupply() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().scaledTotalSupply;
  }

  /// @notice returns `account`'s direct share-like balance without applying the scale factor.
  function scaledBalanceOf(address account) external view nonReentrantView returns (uint256) {
    return _accounts[account].scaledBalance;
  }

  /// @notice returns protocol fees withdrawable after reserving paid lender claims.
  function withdrawableProtocolFees() external view nonReentrantView returns (uint128) {
    return
      _calculateCurrentStatePointers.asReturnsMarketState()().withdrawableProtocolFees(
        totalAssets()
      );
  }

  // /*//////////////////////////////////////////////////////////////
  //                     Internal State Handlers
  // //////////////////////////////////////////////////////////////*/

  /// @dev derived market hook for quarantining a sanctioned lender's balance.
  function _blockAccount(MarketState memory state, address accountAddress) internal virtual {}

  /// @dev revolving markets override only the base rate; fees and penalty timing stay shared.
  function _calculateBaseInterest(
    MarketState memory state,
    uint256 timestamp
  ) internal view virtual returns (uint256) {
    return state.calculateBaseInterest(timestamp);
  }

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
    uint256 penaltyTime = state.updateTimeDelinquentAndGetPenaltyTime(
      delinquencyGracePeriod,
      timeDelta
    );
    uint256 date = repaymentDate();
    if (date != 0 && state.lastInterestAccruedTimestamp >= date && state.isDelinquent) {
      penaltyTime = timeDelta;
    }
    if (penaltyTime > 0 && delinquencyFeeBips > 0) {
      delinquencyFeeRay = MathUtils.calculateLinearInterestFromBips(
        delinquencyFeeBips,
        penaltyTime
      );
    }
    uint256 scale = state.scaleFactor;
    state.scaleFactor = (scale + scale.rayMul(baseInterestRay + delinquencyFeeRay)).toUint112();
    state.lastInterestAccruedTimestamp = timestamp.toUint32();
  }

  /// @dev derived-market accounting hook called before borrowed assets leave the market.
  function _onBorrow(MarketState memory state, uint256 amount) internal virtual {
    state;
    amount;
  }

  /// @dev derived-market accounting hook called after repaid assets reach the market.
  function _onRepay(MarketState memory state, uint256 amount) internal virtual {
    state;
    amount;
  }

  /// @dev runs derived repayment accounting and returns the post-transfer underlying balance.
  function _onRepayAndGetTotalAssets(
    MarketState memory state,
    uint256 amount
  ) internal virtual returns (uint256 currentTotalAssets) {
    _onRepay(state, amount);
    currentTotalAssets = totalAssets();
  }

  /**
   * @dev Returns the last asset balance observed by a state write while a current withdrawal
   *      batch existed or repayment terms were enabled. The uint152 value occupies otherwise unused high bits in state slots
   *      zero and three, preserving the MarketState storage layout and hook ABI.
   */
  function _checkpointedTotalAssets() internal view returns (uint256 value) {
    assembly {
      value := or(shr(0x88, sload(_state.slot)), shl(0x78, shr(0xe0, sload(add(_state.slot, 3)))))
    }
  }

  /// @dev derived-market accounting hook after closure fully funds debt and queued withdrawals.
  function _onCloseMarket() internal virtual {}

  /**
   * @dev Returns cached MarketState after accruing interest and delinquency / protocol fees
   *      and processing expired withdrawal batch, if any.
   *
   *      Used by functions that make additional changes to `state`.
   *
   *      NOTE: Returned `state` does not match `_state` if interest is accrued
   *            Calling function must update `_state` or revert.
   *
   * @return state Market state after interest is accrued.
   */
  function _getUpdatedState() internal returns (MarketState memory state) {
    // keep the view/write/repay callers on one transition body. constant flags clone it in viaIR.
    return _getUpdatedState(_runtimeConstant(1) != 0);
  }

  /// @dev repayment transfers arrive before this call. defer today's closure until the explicit
  ///      repayment accounting finishes; historical closure still applies at its own boundary.
  function _getUpdatedState(
    bool closeAtCurrentTimestamp
  ) internal returns (MarketState memory state) {
    uint256 currentAssets = totalAssets();
    LifecycleTransition memory next = _calculateTransition(currentAssets, closeAtCurrentTimestamp);
    state = next.state;
    for (uint256 i; i <= next.accrualCount; ++i) {
      if (next.batchExpired && next.expiryAfterAccrual == i)
        _commitTransitionBatch(next, _runtimeConstant(1) != 0);
      if (i < next.accrualCount) {
        LifecycleAccrual memory a = next.accruals[i];
        emit_InterestAndFeesAccrued(
          a.from,
          a.to,
          a.scaleFactor,
          a.baseInterestRay,
          a.delinquencyFeeRay,
          a.protocolFee
        );
      }
    }
    if (!next.batchExpired && next.batchExpiry != 0)
      _commitTransitionBatch(next, _runtimeConstant(0) != 0);
    if (next.repaymentActivated) emit RepaymentDateReached(repaymentDate());
    if (_lifecycle.defaultedAt == 0 && next.lifecycle.defaultedAt != 0) {
      emit DefaultRecorded(next.lifecycle.defaultedAt);
    }
    _lifecycle = next.lifecycle;
    if (next.closedAt != 0) _commitAutomaticClosure(state, currentAssets, next.closedAt);
  }

  function _commitTransitionBatch(LifecycleTransition memory next, bool expired) internal {
    uint32 expiry = next.batchExpiry;
    WithdrawalBatch memory previous = _withdrawalData.batches[expiry];
    WithdrawalBatch memory batch = next.batch;
    if (batch.scaledAmountBurned != previous.scaledAmountBurned) {
      uint128 paid = batch.normalizedAmountPaid - previous.normalizedAmountPaid;
      emit_Transfer(address(this), _runtimeConstant(address(0)), paid);
      emit_WithdrawalBatchPayment(
        expiry,
        batch.scaledAmountBurned - previous.scaledAmountBurned,
        paid
      );
    }
    _withdrawalData.batches[expiry] = batch;
    if (expired) {
      emit_WithdrawalBatchExpired(
        expiry,
        batch.scaledTotalAmount,
        batch.scaledAmountBurned,
        batch.normalizedAmountPaid
      );
      if (batch.scaledAmountBurned < batch.scaledTotalAmount) {
        _withdrawalData.unpaidBatches.push(expiry);
      } else {
        emit_WithdrawalBatchClosed(expiry);
      }
    }
  }

  function _calculateCurrentState()
    internal
    view
    returns (
      MarketState memory state,
      uint32 pendingBatchExpiry,
      WithdrawalBatch memory pendingBatch
    )
  {
    LifecycleTransition memory next = _calculateTransition(totalAssets(), _runtimeConstant(1) != 0);
    return (next.state, next.batchExpiry, next.batch);
  }

  /// @dev replay only the finite boundaries that change accounting. no daily loop, and no
  ///      accrual split merely to record the separate 90-day default marker.
  function _calculateTransition(
    uint256 currentAssets,
    bool closeNow
  ) internal view returns (LifecycleTransition memory next) {
    next.state = _state;
    next.lifecycle = _lifecycle;
    MarketState memory state = next.state;
    uint256 historicalAssets = _checkpointedTotalAssets();
    uint256 date = repaymentDate();
    uint256 deadline = repaymentDeadline();
    bool datePending = date != 0 &&
      date > state.lastInterestAccruedTimestamp &&
      date <= block.timestamp;
    bool deadlinePending = date != 0 &&
      deadline >= state.lastInterestAccruedTimestamp &&
      block.timestamp > deadline;
    bool expiryPending = state.hasPendingExpiredBatch();
    if (state.pendingWithdrawalExpiry != 0) {
      next.batchExpiry = state.pendingWithdrawalExpiry;
      next.batch = _withdrawalData.batches[next.batchExpiry];
    }
    while (true) {
      uint256 target = block.timestamp;
      if (datePending && date < target) target = date;
      if (deadlinePending && deadline < target) target = deadline;
      if (expiryPending && next.batchExpiry < target) target = next.batchExpiry;
      _accrueTransition(next, target, date);
      if (datePending && target == date) {
        datePending = false;
        if (!state.isClosed) {
          next.repaymentActivated = true;
          next.lifecycle.activateRepayment(state, historicalAssets, date);
          if (historicalAssets >= state.totalDebts())
            _previewAutomaticClosure(next, historicalAssets, target);
        }
      }
      // An expiry exactly at the inclusive deadline is processed after judging that deadline.
      if (deadlinePending && target == deadline) {
        deadlinePending = false;
        if (
          !state.isClosed &&
          historicalAssets < state.totalDebts() &&
          next.lifecycle.defaultedAt == 0
        ) {
          next.lifecycle.defaultedAt = uint32(deadline);
        }
      }
      if (expiryPending && target == next.batchExpiry) {
        expiryPending = false;
        if (state.pendingWithdrawalExpiry != 0) {
          _payTransitionBatch(next, historicalAssets);
          state.pendingWithdrawalExpiry = 0;
          next.batchExpired = true;
          next.expiryAfterAccrual = next.accrualCount;
          state.isDelinquent = state.liquidityRequired() > historicalAssets;
        }
      }
      if (next.closedAt != 0 || target == block.timestamp) break;
    }
    if (next.closedAt != 0) state.lastInterestAccruedTimestamp = uint32(block.timestamp);
    if (state.pendingWithdrawalExpiry != 0) _payTransitionBatch(next, currentAssets);
    if (
      closeNow &&
      date != 0 &&
      block.timestamp >= date &&
      !state.isClosed &&
      currentAssets >= state.totalDebts()
    ) {
      _previewAutomaticClosure(next, currentAssets, block.timestamp);
    }
  }

  function _accrueTransition(
    LifecycleTransition memory next,
    uint256 timestamp,
    uint256 date
  ) internal view {
    MarketState memory state = next.state;
    uint256 grace = date != 0 && state.lastInterestAccruedTimestamp >= date
      ? 0
      : delinquencyGracePeriod;
    next.lifecycle.accrueDefaultRun(state, timestamp, grace);
    if (timestamp == state.lastInterestAccruedTimestamp) return;
    // LifecycleTransition already allocated four records. fill the next slot in place.
    LifecycleAccrual memory a = next.accruals[next.accrualCount++];
    a.from = state.lastInterestAccruedTimestamp;
    a.to = timestamp.toUint32();
    (a.baseInterestRay, a.delinquencyFeeRay, a.protocolFee) = _updateScaleFactorAndFees(
      state,
      timestamp
    );
    a.scaleFactor = state.scaleFactor;
  }

  function _payTransitionBatch(LifecycleTransition memory next, uint256 assets) internal pure {
    uint256 available = next.batch.availableLiquidityForPendingBatch(next.state, assets);
    if (available != 0) _applyWithdrawalBatchPaymentView(next.batch, next.state, available);
  }

  function _previewAutomaticClosure(
    LifecycleTransition memory next,
    uint256 assets,
    uint256 timestamp
  ) internal pure {
    MarketState memory state = next.state;
    if (state.pendingWithdrawalExpiry != 0) {
      _payTransitionBatch(next, assets);
      state.pendingWithdrawalExpiry = 0;
      next.batchExpired = true;
      next.expiryAfterAccrual = next.accrualCount;
    }
    state.closeFundedState();
    next.lifecycle.penaltyCutoff = 0;
    next.closedAt = uint32(timestamp);
  }

  /// @dev closure freezes all fully backed claims. older batches can then finish in bounded FIFO
  ///      calls. never give an arbitrary hook a veto over the scheduled obligation.
  function _commitAutomaticClosure(
    MarketState memory state,
    uint256 assets,
    uint256 timestamp
  ) internal returns (uint256 remainingAssets) {
    remainingAssets = state.totalDebts();
    if (assets > remainingAssets) asset.safeTransfer(borrower(), assets - remainingAssets);
    _onCloseMarket();
    emit_AnnualInterestAndReserveRatioBipsUpdated(
      borrower(),
      _state.annualInterestBips,
      0,
      _state.reserveRatioBips,
      10_000
    );
    emit_MarketClosed(borrower(), timestamp);
  }

  function _closeAfterCurrentAction(
    MarketState memory state,
    uint256 assets
  ) internal returns (uint256) {
    if (state.isClosed || !_isInRepayment() || assets < state.totalDebts()) return assets;
    if (state.pendingWithdrawalExpiry != 0) {
      uint32 expiry = state.pendingWithdrawalExpiry;
      WithdrawalBatch memory batch = _withdrawalData.batches[expiry];
      uint256 available = batch.availableLiquidityForPendingBatch(state, assets);
      _applyWithdrawalBatchPayment(batch, state, expiry, available);
      _withdrawalData.batches[expiry] = batch;
      state.pendingWithdrawalExpiry = 0;
      emit_WithdrawalBatchExpired(
        expiry,
        batch.scaledTotalAmount,
        batch.scaledAmountBurned,
        batch.normalizedAmountPaid
      );
      emit_WithdrawalBatchClosed(expiry);
    }
    state.closeFundedState();
    return _commitAutomaticClosure(state, assets, block.timestamp);
  }

  /**
   * @dev Writes the cached MarketState to storage and emits an event.
   *      Used at the end of all functions which modify `state`.
   */
  function _writeState(MarketState memory state) internal {
    _writeState(state, totalAssets());
  }

  /**
   * @dev Writes state using a current asset balance already loaded after the last
   *      external state-changing call.
   */
  function _writeState(MarketState memory state, uint256 currentTotalAssets) internal {
    currentTotalAssets = _closeAfterCurrentAction(state, currentTotalAssets);
    bool isDelinquent = state.liquidityRequired() > currentTotalAssets;
    state.isDelinquent = isDelinquent;
    if (!isDelinquent || state.isClosed) _lifecycle.penaltyCutoff = 0;

    // An arbitrary direct transfer can exceed uint152, so saturate rather than making every
    // state write revert. The uint104/uint112/uint128 accounting fields bound every payable
    // market liability below uint152, making the saturated value economically equivalent.
    uint256 checkpointedTotalAssets;
    if (state.pendingWithdrawalExpiry != 0 || repaymentDate() != 0) {
      checkpointedTotalAssets = MathUtils.min(currentTotalAssets, type(uint152).max);
    }

    {
      bool isClosed = state.isClosed;
      uint maxTotalSupply = state.maxTotalSupply;
      assembly {
        // Slot 0 Storage Layout:
        // [0:15]  | low 120 bits of checkpointedTotalAssets
        // [15:31] | state.maxTotalSupply
        // [31:32] | state.isClosed
        let checkpointMask := sub(shl(0x78, 1), 1)
        let slot0 := or(
          or(isClosed, shl(0x08, maxTotalSupply)),
          shl(0x88, and(checkpointedTotalAssets, checkpointMask))
        )
        sstore(_state.slot, slot0)
      }
    }
    {
      uint accruedProtocolFees = state.accruedProtocolFees;
      uint normalizedUnclaimedWithdrawals = state.normalizedUnclaimedWithdrawals;
      assembly {
        // Slot 1 Storage Layout:
        // [0:16] | state.normalizedUnclaimedWithdrawals
        // [16:32] | state.accruedProtocolFees
        let slot1 := or(accruedProtocolFees, shl(0x80, normalizedUnclaimedWithdrawals))
        sstore(add(_state.slot, 1), slot1)
      }
    }
    {
      uint scaledTotalSupply = state.scaledTotalSupply;
      uint scaledPendingWithdrawals = state.scaledPendingWithdrawals;
      uint pendingWithdrawalExpiry = state.pendingWithdrawalExpiry;
      assembly {
        // Slot 2 Storage Layout:
        // [1:2] | state.isDelinquent
        // [2:6] | state.pendingWithdrawalExpiry
        // [6:19] | state.scaledPendingWithdrawals
        // [19:32] | state.scaledTotalSupply
        let slot2 := or(
          or(
            or(shl(0xf0, isDelinquent), shl(0xd0, pendingWithdrawalExpiry)),
            shl(0x68, scaledPendingWithdrawals)
          ),
          scaledTotalSupply
        )
        sstore(add(_state.slot, 2), slot2)
      }
    }
    {
      uint timeDelinquent = state.timeDelinquent;
      uint protocolFeeBips = state.protocolFeeBips;
      uint annualInterestBips = state.annualInterestBips;
      uint reserveRatioBips = state.reserveRatioBips;
      uint scaleFactor = state.scaleFactor;
      uint lastInterestAccruedTimestamp = state.lastInterestAccruedTimestamp;
      assembly {
        // Slot 3 Storage Layout:
        // [0:4] | high 32 bits of checkpointedTotalAssets
        // [4:8] | state.lastInterestAccruedTimestamp
        // [8:22] | state.scaleFactor
        // [22:24] | state.reserveRatioBips
        // [24:26] | state.annualInterestBips
        // [26:28] | protocolFeeBips
        // [28:32] | state.timeDelinquent
        let slot3 := or(
          shl(0xe0, shr(0x78, checkpointedTotalAssets)),
          or(
            or(
              or(
                or(shl(0xc0, lastInterestAccruedTimestamp), shl(0x50, scaleFactor)),
                shl(0x40, reserveRatioBips)
              ),
              or(shl(0x30, annualInterestBips), shl(0x20, protocolFeeBips))
            ),
            timeDelinquent
          )
        )
        sstore(add(_state.slot, 3), slot3)
      }
    }
    emit_StateUpdated(state.scaleFactor, isDelinquent);
  }

  /**
   * @dev Handles an expired withdrawal batch:
   *      - Retrieves the amount of underlying assets that can be used to pay for the batch.
   *      - If the amount is sufficient to pay the full amount owed to the batch, the batch
   *        is closed and the total withdrawal amount is reserved.
   *      - If the amount is insufficient to pay the full amount owed to the batch, the batch
   *        is recorded as an unpaid batch and the available assets are reserved.
   *      - The assets reserved for the batch are scaled by the current scale factor and that
   *        amount of scaled tokens is burned, ensuring borrowers do not continue paying interest
   *        on withdrawn assets.
   */
  function _processExpiredWithdrawalBatch(
    MarketState memory state,
    uint256 currentTotalAssets
  ) internal {
    uint32 expiry = state.pendingWithdrawalExpiry;
    WithdrawalBatch memory batch = _withdrawalData.batches[expiry];

    if (batch.scaledAmountBurned < batch.scaledTotalAmount) {
      // Burn as much of the withdrawal batch as possible with available liquidity.
      uint256 availableLiquidity = batch.availableLiquidityForPendingBatch(
        state,
        currentTotalAssets
      );
      if (availableLiquidity > 0) {
        _applyWithdrawalBatchPayment(batch, state, expiry, availableLiquidity);
      }
    }

    emit_WithdrawalBatchExpired(
      expiry,
      batch.scaledTotalAmount,
      batch.scaledAmountBurned,
      batch.normalizedAmountPaid
    );

    if (batch.scaledAmountBurned < batch.scaledTotalAmount) {
      _withdrawalData.unpaidBatches.push(expiry);
    } else {
      emit_WithdrawalBatchClosed(expiry);
    }

    state.pendingWithdrawalExpiry = 0;

    _withdrawalData.batches[expiry] = batch;
  }

  /**
   * @dev Process withdrawal payment, burning market tokens and reserving
   *      underlying assets so they are only available for withdrawals.
   */
  function _applyWithdrawalBatchPayment(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint32 expiry,
    uint256 availableLiquidity
  ) internal returns (uint104 scaledAmountBurned, uint128 normalizedAmountPaid) {
    uint104 scaledAmountOwed = batch.scaledTotalAmount - batch.scaledAmountBurned;

    // Do nothing if batch is already paid
    if (scaledAmountOwed == 0) return (0, 0);

    uint256 scaledAvailableLiquidity = state.maxScaledSettleableAmount(availableLiquidity);
    scaledAmountBurned = MathUtils.min(scaledAvailableLiquidity, scaledAmountOwed).toUint104();
    if (scaledAmountBurned == 0) return (0, 0);
    // Use mulDiv instead of normalizeAmount to round `normalizedAmountPaid` down, ensuring
    // it is always possible to finish withdrawal batches on closed markets.
    normalizedAmountPaid = MathUtils.mulDiv(scaledAmountBurned, state.scaleFactor, RAY).toUint128();

    batch.scaledAmountBurned += scaledAmountBurned;
    batch.normalizedAmountPaid += normalizedAmountPaid;
    state.scaledPendingWithdrawals -= scaledAmountBurned;

    // Update normalizedUnclaimedWithdrawals so the tokens are only accessible for withdrawals.
    state.normalizedUnclaimedWithdrawals += normalizedAmountPaid;

    // Burn market tokens to stop interest accrual upon withdrawal payment.
    state.scaledTotalSupply -= scaledAmountBurned;

    // Emit transfer for external trackers to indicate burn.
    emit_Transfer(address(this), _runtimeConstant(address(0)), normalizedAmountPaid);
    emit_WithdrawalBatchPayment(expiry, scaledAmountBurned, normalizedAmountPaid);
  }

  function _applyWithdrawalBatchPaymentView(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint256 availableLiquidity
  ) internal pure {
    uint104 scaledAmountOwed = batch.scaledTotalAmount - batch.scaledAmountBurned;
    // Do nothing if batch is already paid
    if (scaledAmountOwed == 0) return;

    uint256 scaledAvailableLiquidity = state.maxScaledSettleableAmount(availableLiquidity);
    uint104 scaledAmountBurned = MathUtils
      .min(scaledAvailableLiquidity, scaledAmountOwed)
      .toUint104();
    if (scaledAmountBurned == 0) return;
    // Use mulDiv instead of normalizeAmount to round `normalizedAmountPaid` down, ensuring
    // it is always possible to finish withdrawal batches on closed markets.
    uint128 normalizedAmountPaid = MathUtils
      .mulDiv(scaledAmountBurned, state.scaleFactor, RAY)
      .toUint128();

    batch.scaledAmountBurned += scaledAmountBurned;
    batch.normalizedAmountPaid += normalizedAmountPaid;
    state.scaledPendingWithdrawals -= scaledAmountBurned;

    // Update normalizedUnclaimedWithdrawals so the tokens are only accessible for withdrawals.
    state.normalizedUnclaimedWithdrawals += normalizedAmountPaid;

    // Burn market tokens to stop interest accrual upon withdrawal payment.
    state.scaledTotalSupply -= scaledAmountBurned;
  }

  /**
   * @dev Function to obfuscate the fact that a value is constant from solc's optimizer.
   *      This prevents function specialization for calls with a constant input parameter,
   *      which usually has very little benefit in terms of gas savings but can
   *      drastically increase contract size.
   *
   *      The value returned will always match the input value outside of the constructor,
   *      fallback and receive functions.
   */
  function _runtimeConstant(
    uint256 actualConstant
  ) internal pure returns (uint256 runtimeConstant) {
    assembly {
      mstore(0, actualConstant)
      runtimeConstant := mload(iszero(calldatasize()))
    }
  }

  function _runtimeConstant(
    address actualConstant
  ) internal pure returns (address runtimeConstant) {
    assembly {
      mstore(0, actualConstant)
      runtimeConstant := mload(iszero(calldatasize()))
    }
  }

  /// @dev checks the raw Chainalysis list directly and ignores borrower overrides.
  function _isFlaggedByChainalysis(address account) internal view returns (bool isFlagged) {
    address sentinelAddress = address(sentinel);
    assembly {
      mstore(0, 0x95c09839)
      mstore(0x20, account)
      if iszero(
        and(eq(returndatasize(), 0x20), staticcall(gas(), sentinelAddress, 0x1c, 0x24, 0, 0x20))
      ) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      isFlagged := mload(0)
    }
  }

  /// @dev gets or deploys the lender's escrow for the current principal and underlying asset.
  function _createEscrowForUnderlyingAsset(
    address accountAddress
  ) internal returns (address escrow) {
    address tokenAddress = address(asset);
    address principalAddress = borrowerPrincipal();
    address sentinelAddress = address(sentinel);

    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(0, 0xa1054f6b)
      mstore(0x20, principalAddress)
      mstore(0x40, accountAddress)
      mstore(0x60, tokenAddress)
      if iszero(
        and(eq(returndatasize(), 0x20), call(gas(), sentinelAddress, 0, 0x1c, 0x64, 0, 0x20))
      ) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      escrow := mload(0)
      mstore(0x40, freeMemoryPointer)
      mstore(0x60, 0)
    }
  }
}
