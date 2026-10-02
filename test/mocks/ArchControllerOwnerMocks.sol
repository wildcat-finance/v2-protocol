// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // ArchControllerOwnerMocks
// ║  ██▀▀     ▀▀██   Protocol authority, legacy factory, and engine owner mocks.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  PROTOCOL TARGET
// ║  constructor(...)
// ║  setValue(...)
// ║  fail(...)
// ║
// ║  LEGACY FACTORY
// ║  constructor(...)
// ║  setProtocolFeeConfiguration(...)
// ║
// ║  ENGINE AUTHORITY
// ║  constructor(...)
// ║  addAllowedSenderOnChain(...)
// ║  supportsInterface(...)
// ║
// ║  ENGINE VALIDATION
// ║  sphereXValidatePre(...)
// ║  sphereXValidatePost(...)
// ║  sphereXValidateInternalPre(...)
// ║  sphereXValidateInternalPost(...)
// ╚═════

import 'openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol';
import { WildcatArchController } from 'src/WildcatArchController.sol';
import { ISphereXEngine } from 'src/spherex/ISphereXEngine.sol';

// ┌─ ArchControllerOwnerProtocolTargetMock ────────────────────────────────────
contract ArchControllerOwnerProtocolTargetMock {
  error ExpectedFailure(uint256 value);

  address public immutable archController;
  address public lastCaller;
  uint256 public value;

  // ░░▒▒▓▓██ [ PROTOCOL TARGET ] ──────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address archController_) {
    archController = archController_;
  }

  // ┌─ setValue ─────
  function setValue(uint256 value_) external returns (uint256 result) {
    lastCaller = msg.sender;
    value = value_;
    result = value_ + 1;
  }

  // ┌─ fail ─────
  function fail(uint256 value_) external pure {
    revert ExpectedFailure(value_);
  }
}

// ┌─ ArchControllerOwnerLegacyFactoryMock ─────────────────────────────────────
contract ArchControllerOwnerLegacyFactoryMock {
  error CallerNotArchControllerOwner();

  address public immutable archController;
  address public feeRecipient;
  address public originationFeeAsset;
  uint80 public originationFeeAmount;
  uint16 public protocolFeeBips;

  // ░░▒▒▓▓██ [ LEGACY FACTORY ] ───────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address archController_) {
    archController = archController_;
  }

  // ┌─ setProtocolFeeConfiguration ─────
  function setProtocolFeeConfiguration(
    address feeRecipient_,
    address originationFeeAsset_,
    uint80 originationFeeAmount_,
    uint16 protocolFeeBips_
  )
    external
  {
    if (msg.sender != WildcatArchController(archController).owner()) {
      revert CallerNotArchControllerOwner();
    }
    feeRecipient = feeRecipient_;
    originationFeeAsset = originationFeeAsset_;
    originationFeeAmount = originationFeeAmount_;
    protocolFeeBips = protocolFeeBips_;
  }
}

// ┌─ ArchControllerOwnerSphereXEngineMock ─────────────────────────────────────
contract ArchControllerOwnerSphereXEngineMock is AccessControlDefaultAdminRules, ISphereXEngine {
  bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
  bytes32 public constant SENDER_ADDER_ROLE = keccak256('SENDER_ADDER_ROLE');

  // ░░▒▒▓▓██ [ ENGINE AUTHORITY ] ─────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(
    uint48 initialDelay,
    address initialDefaultAdmin
  )
    AccessControlDefaultAdminRules(initialDelay, initialDefaultAdmin)
  {
    _grantRole(OPERATOR_ROLE, initialDefaultAdmin);
  }

  // ┌─ addAllowedSenderOnChain ─────
  function addAllowedSenderOnChain(address) external onlyRole(SENDER_ADDER_ROLE) { }

  // ┌─ supportsInterface ─────
  function supportsInterface(bytes4 interfaceId)
    public
    view
    override(AccessControlDefaultAdminRules, ISphereXEngine)
    returns (bool)
  {
    return interfaceId == type(ISphereXEngine).interfaceId || super.supportsInterface(interfaceId);
  }

  // ░░▒▒▓▓██ [ ENGINE VALIDATION ] ────────────────────────────────────────────

  // ┌─ sphereXValidatePre ─────
  function sphereXValidatePre(int256, address, bytes calldata) external pure returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  // ┌─ sphereXValidatePost ─────
  function sphereXValidatePost(int256, uint256, bytes32[] calldata, bytes32[] calldata) external pure { }

  // ┌─ sphereXValidateInternalPre ─────
  function sphereXValidateInternalPre(int256) external pure returns (bytes32[] memory values) {
    values = new bytes32[](0);
  }

  // ┌─ sphereXValidateInternalPost ─────
  function sphereXValidateInternalPost(int256, uint256, bytes32[] calldata, bytes32[] calldata) external pure { }
}
