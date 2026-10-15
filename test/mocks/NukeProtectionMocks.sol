// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ═════════════════════════════════════════════════════════════════════════════
//  |\ /|   WILDCAT v2.5 // NukeProtectionMocks
//  \ ^ /   Feature provenance and deposit callback probes.
//    V
//
//  OPERATIONS
//  constructor(...)
//  createFeature(...)
//  createUnregisteredFeature(...)
//  registerInstance(...)
//  setProbe(...)
//  _probe(...)
//  constructor(...)
//  isMarketTransferDisabled(...)
//  constructor(...)
//  isMarketTransferRecipientAllowed(...)
//  constructor(...)
//  _checkDeposit(...)
//  constructor()
//  transferFrom(...)
// ═════

import { IHooksFactoryBase } from 'src/IHooksFactory.sol';
import { INukeProtectionMarket } from 'src/interfaces/INukeProtectionMarket.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { CredentialedBorrowHooksMock } from './BorrowerAccountMocks.sol';

// ┌─ ProtectedFeatureMock ─────────────────────────────────────────────────────
contract ProtectedFeatureMock {
  address public immutable market;

  // ┌─ constructor ─────
  constructor(address market_) {
    market = market_;
  }
}

// ┌─ NukeProtectionFactoryMock ────────────────────────────────────────────────
/// @dev example of the provenance rule every approved feature factory must enforce.
contract NukeProtectionFactoryMock {
  error InvalidFeatureInstance();

  mapping(address instance => address market) public marketForInstance;

  // ┌─ createFeature ─────
  function createFeature(address market) external returns (address instance) {
    instance = createUnregisteredFeature(market);
    registerInstance(market, instance);
  }

  // ┌─ createUnregisteredFeature ─────
  function createUnregisteredFeature(address market) public returns (address instance) {
    instance = address(new ProtectedFeatureMock(market));
    marketForInstance[instance] = market;
  }

  // ┌─ registerInstance ─────
  function registerInstance(address market, address instance) public {
    if (marketForInstance[instance] != market || market == address(0)) revert InvalidFeatureInstance();
    IHooksFactoryBase(INukeProtectionMarket(market).factory()).registerNukeProtectedAccount(market, instance);
  }
}

// ┌─ NukeProtectionCallbackProbe ──────────────────────────────────────────────
abstract contract NukeProtectionCallbackProbe {
  NukeProtectionFactoryMock internal _featureFactory;
  address internal _instance;
  bool public registrationSucceeded;
  bytes4 public registrationError;

  // ┌─ setProbe ─────
  function setProbe(NukeProtectionFactoryMock featureFactory, address instance) external {
    _featureFactory = featureFactory;
    _instance = instance;
  }

  // ┌─ _probe ─────
  function _probe(address market) internal {
    if (address(_featureFactory) == address(0)) return;
    (bool success, bytes memory data) =
      address(_featureFactory).call(abi.encodeCall(_featureFactory.registerInstance, (market, _instance)));
    registrationSucceeded = success;
    if (data.length >= 4) registrationError = bytes4(data);
  }
}

// ┌─ PartialWrapperPolicyHooksMock ────────────────────────────────────────────
contract PartialWrapperPolicyHooksMock is CredentialedBorrowHooksMock {
  // ┌─ constructor ─────
  constructor(address administrator, bytes memory args) CredentialedBorrowHooksMock(administrator, args) { }

  // ┌─ isMarketTransferDisabled ─────
  function isMarketTransferDisabled(address) external pure returns (bool) {
    return false;
  }
}

// ┌─ MalformedWrapperPolicyHooksMock ──────────────────────────────────────────
contract MalformedWrapperPolicyHooksMock is PartialWrapperPolicyHooksMock {
  // ┌─ constructor ─────
  constructor(address administrator, bytes memory args) PartialWrapperPolicyHooksMock(administrator, args) { }

  // ┌─ isMarketTransferRecipientAllowed ─────
  function isMarketTransferRecipientAllowed(address, address) external pure returns (bool) {
    assembly {
      mstore(0, 2)
      return(0, 0x20)
    }
  }
}

// ┌─ NukeProtectionCallbackHooks ──────────────────────────────────────────────
contract NukeProtectionCallbackHooks is OpenTermHooks, NukeProtectionCallbackProbe {
  // ┌─ constructor ─────
  constructor(address administrator, bytes memory args) OpenTermHooks(administrator, args) { }

  // ┌─ _checkDeposit ─────
  function _checkDeposit(address, uint256, MarketState calldata, bytes calldata) internal override {
    _probe(msg.sender);
  }
}

// ┌─ NukeProtectionCallbackToken ──────────────────────────────────────────────
contract NukeProtectionCallbackToken is MockERC20, NukeProtectionCallbackProbe {
  // ┌─ constructor ─────
  constructor() MockERC20('Callback Token', 'CBT', 18) { }

  // ┌─ transferFrom ─────
  function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    _probe(to);
    return super.transferFrom(from, to, amount);
  }
}
