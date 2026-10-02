// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // BorrowerAccountMocks
// ║  ██▀▀     ▀▀██   Executing borrower accounts and credentialed borrowing hooks.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  ACCOUNT SETUP
// ║  constructor(...)
// ║  receive()
// ║
// ║  ACCOUNT EXECUTION
// ║  execute(...)
// ║  principal()
// ║
// ║  ACCOUNT DEPLOYMENT
// ║  constructor(...)
// ║  deployAccount(...)
// ║
// ║  BORROWER IDENTITY
// ║  borrower()
// ║  borrowerPrincipal()
// ║
// ║  HOOK SETUP
// ║  constructor(...)
// ║  _onCreateMarket(...)
// ║
// ║  CREDENTIALED BORROWING
// ║  onBorrow(...)
// ║
// ║  PASSIVE CALLBACKS
// ║  onDeposit(...)
// ║  onQueueWithdrawal(...)
// ║  onExecuteWithdrawal(...)
// ║  onTransfer(...)
// ║  onRepay(...)
// ║  onCloseMarket(...)
// ║  onNukeFromOrbit(...)
// ║  onSetMaxTotalSupply(...)
// ║  onSetAnnualInterestAndReserveRatioBips(...)
// ║  onSetProtocolFeeBips(...)
// ║
// ║  HOOK IDENTITY
// ║  version()
// ╚═════

import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { NameAndProviderInputs } from 'src/access/ProviderStructs.sol';
import { IBorrowerIdentityRegistry } from 'src/interfaces/IBorrowerIdentityRegistry.sol';
import { DeployMarketInputs } from 'src/interfaces/WildcatStructsAndEnums.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import {
  Bit_Enabled_Borrow,
  EmptyHooksConfig,
  HooksConfig,
  HooksDeploymentConfig,
  encodeHooksDeploymentConfig
} from 'src/types/HooksConfig.sol';
import { LenderStatus } from 'src/types/LenderStatus.sol';

// ┌─ ExecutingBorrowerAccountMock ─────────────────────────────────────────────
contract ExecutingBorrowerAccountMock {
  error CallerNotPrincipal();

  IBorrowerIdentityRegistry public immutable registry;

  // ░░▒▒▓▓██ [ ACCOUNT SETUP ] ────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  // ┌─ receive ─────
  receive() external payable { }

  // ░░▒▒▓▓██ [ ACCOUNT EXECUTION ] ────────────────────────────────────────────

  // ┌─ execute ─────
  function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory result) {
    if (msg.sender != principal()) revert CallerNotPrincipal();

    bool success;
    (success, result) = target.call{ value: value }(data);
    if (!success) {
      assembly ('memory-safe') {
        revert(add(result, 0x20), mload(result))
      }
    }
  }

  // ┌─ principal ─────
  function principal() public view returns (address) {
    return registry.principalOf(address(this));
  }
}

// ┌─ ExecutingBorrowerAccountFactoryMock ──────────────────────────────────────
contract ExecutingBorrowerAccountFactoryMock {
  IBorrowerIdentityRegistry public immutable registry;

  // ░░▒▒▓▓██ [ ACCOUNT DEPLOYMENT ] ───────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address registry_) {
    registry = IBorrowerIdentityRegistry(registry_);
  }

  // ┌─ deployAccount ─────
  function deployAccount(address principal) external returns (address account) {
    account = address(new ExecutingBorrowerAccountMock(address(registry)));
    registry.registerBorrowerAccount(account, principal);
  }
}

// ┌─ ICredentialedBorrowMarket ────────────────────────────────────────────────
interface ICredentialedBorrowMarket {
  // ░░▒▒▓▓██ [ BORROWER IDENTITY ] ────────────────────────────────────────────

  // ┌─ borrower ─────
  function borrower() external view returns (address);

  // ┌─ borrowerPrincipal ─────
  function borrowerPrincipal() external view returns (address);
}

// ┌─ CredentialedBorrowHooksMock ──────────────────────────────────────────────
contract CredentialedBorrowHooksMock is IHooks, BaseAccessControls {
  error BorrowCredentialRequired();
  error NotHookedMarket();

  HooksDeploymentConfig public immutable override config;
  mapping(address market => bool) public isHookedMarket;
  mapping(address market => address) public lastBorrower;
  mapping(address market => address) public lastBorrowerPrincipal;

  // ░░▒▒▓▓██ [ HOOK SETUP ] ───────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address administrator_, bytes memory constructorArgs) IHooks() BaseAccessControls(administrator_) {
    config = encodeHooksDeploymentConfig(EmptyHooksConfig, EmptyHooksConfig.setFlag(Bit_Enabled_Borrow));
    if (constructorArgs.length != 0) {
      _initialize(abi.decode(constructorArgs, (NameAndProviderInputs)));
    }
  }

  // ┌─ _onCreateMarket ─────
  function _onCreateMarket(
    address marketAdministrator,
    address marketAddress,
    DeployMarketInputs calldata parameters,
    bytes calldata
  )
    internal
    override
    returns (HooksConfig)
  {
    if (marketAdministrator != administrator) revert CallerNotAdministrator();
    isHookedMarket[marketAddress] = true;
    return parameters.hooks.mergeFlags(config);
  }

  // ░░▒▒▓▓██ [ CREDENTIALED BORROWING ] ───────────────────────────────────────

  // ┌─ onBorrow ─────
  function onBorrow(uint256, MarketState calldata, bytes calldata extraData) external override {
    if (!isHookedMarket[msg.sender]) revert NotHookedMarket();

    ICredentialedBorrowMarket market = ICredentialedBorrowMarket(msg.sender);
    address account = market.borrower();
    address principal = market.borrowerPrincipal();
    LenderStatus memory status = _lenderStatus[principal];
    if (!_tryValidateAccess(status, principal, extraData)) revert BorrowCredentialRequired();

    lastBorrower[msg.sender] = account;
    lastBorrowerPrincipal[msg.sender] = principal;
  }

  // ░░▒▒▓▓██ [ PASSIVE CALLBACKS ] ────────────────────────────────────────────

  // ┌─ onDeposit ─────
  function onDeposit(address, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onQueueWithdrawal ─────
  function onQueueWithdrawal(address, uint32, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onExecuteWithdrawal ─────
  function onExecuteWithdrawal(address, uint32, uint128, MarketState calldata, bytes calldata) external override { }

  // ┌─ onTransfer ─────
  function onTransfer(address, address, address, uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onRepay ─────
  function onRepay(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onCloseMarket ─────
  function onCloseMarket(MarketState calldata, bytes calldata) external override { }

  // ┌─ onNukeFromOrbit ─────
  function onNukeFromOrbit(address, MarketState calldata, bytes calldata) external override { }

  // ┌─ onSetMaxTotalSupply ─────
  function onSetMaxTotalSupply(uint256, MarketState calldata, bytes calldata) external override { }

  // ┌─ onSetAnnualInterestAndReserveRatioBips ─────
  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata,
    bytes calldata
  )
    external
    pure
    override
    returns (uint16, uint16)
  {
    return (annualInterestBips, reserveRatioBips);
  }

  // ┌─ onSetProtocolFeeBips ─────
  function onSetProtocolFeeBips(uint16, MarketState memory, bytes calldata) external override { }

  // ░░▒▒▓▓██ [ HOOK IDENTITY ] ────────────────────────────────────────────────

  // ┌─ version ─────
  function version() external pure override returns (string memory) {
    return 'credentialed-borrow-test-hook';
  }
}
