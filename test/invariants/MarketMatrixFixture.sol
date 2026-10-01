// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketMatrixFixture
// ║  ██▀▀     ▀▀██   Six-cell market matrix deployment and actor configuration.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  MATRIX DEPLOYMENT
// ║  _deployMatrix(...)
// ║  _deployMatrixCell(...)
// ║
// ║  MATRIX CONFIGURATION
// ║  _matrixOptions(...)
// ║  _fixedTermDelay()
// ║  _actors()
// ╚═════

import { MockERC20 } from 'solmate/test/utils/mocks/MockERC20.sol';
import { BaseAccessControls } from 'src/access/BaseAccessControls.sol';
import { FixedTermHooks } from 'src/access/FixedTermHooks.sol';
import { IHooks } from 'src/access/IHooks.sol';
import { OpenTermHooks } from 'src/access/OpenTermHooks.sol';
import { HooksConfig } from 'src/types/HooksConfig.sol';
import { MockRoleProvider } from '../mocks/MockRoleProvider.sol';
import { MarketFixture } from '../shared/MarketFixture.sol';

// shared setup only; concrete suites own their invariant entrypoints.
// ┌─ MarketMatrixFixture ──────────────────────────────────────────────────────
abstract contract MarketMatrixFixture is MarketFixture {
  struct MatrixDeployment {
    address[] markets;
    address[] assets;
    address[] sentinels;
    address[] periodicHooks;
    uint8[] hooksKinds;
    bool[] revolving;
    uint32[] fixedTermEnds;
    uint16[] commitmentFeeBips;
  }

  uint8 internal constant OpenTerm = 0;
  uint8 internal constant FixedTerm = 1;
  uint8 internal constant PeriodicTerm = 2;
  uint256 internal constant MatrixSize = 6;

  address internal constant Alice = address(0xA11CE);
  address internal constant Bob = address(0xB0B);
  address internal constant Carol = address(0xCAFE);
  address internal constant Dave = address(0xD00D);

  // ░░▒▒▓▓██ [ MATRIX DEPLOYMENT ] ────────────────────────────────────────────

  // ┌─ _deployMatrix ─────
  function _deployMatrix(address[] memory actors) internal returns (MatrixDeployment memory matrix) {
    // Keep the arrays in one memory bundle. Besides making the matrix shape
    // explicit, this lets Forge's accurate non-IR coverage compiler lower setup.
    matrix.markets = new address[](MatrixSize);
    matrix.assets = new address[](MatrixSize);
    matrix.sentinels = new address[](MatrixSize);
    matrix.periodicHooks = new address[](MatrixSize);
    matrix.hooksKinds = new uint8[](MatrixSize);
    matrix.revolving = new bool[](MatrixSize);
    matrix.fixedTermEnds = new uint32[](MatrixSize);
    matrix.commitmentFeeBips = new uint16[](MatrixSize);
    MockRoleProvider provider = MockRoleProvider(_deployCode('test/mocks/MockRoleProvider.sol:MockRoleProvider'));

    for (uint256 i; i < MatrixSize; i++) {
      uint8 hooksKind = uint8(i % 3);
      bool isRevolving = i >= 3;
      (Fixture memory fixture, uint32 fixedTermEnd) = _deployMatrixCell(hooksKind, isRevolving, provider, actors);
      _deposit(fixture, Alice, 10_000e18);

      matrix.markets[i] = address(fixture.market);
      matrix.assets[i] = address(fixture.asset);
      matrix.sentinels[i] = address(fixture.sentinel);
      matrix.periodicHooks[i] = hooksKind == PeriodicTerm ? address(fixture.hooks) : address(0);
      matrix.hooksKinds[i] = hooksKind;
      matrix.revolving[i] = isRevolving;
      matrix.fixedTermEnds[i] = fixedTermEnd;
      matrix.commitmentFeeBips[i] = isRevolving ? 200 : 0;
    }
  }

  // ┌─ _deployMatrixCell ─────
  function _deployMatrixCell(
    uint8 hooksKind,
    bool isRevolving,
    MockRoleProvider provider,
    address[] memory actors
  )
    internal
    returns (Fixture memory fixture, uint32 fixedTermEnd)
  {
    string memory artifact = hooksKind == OpenTerm
      ? 'src/access/OpenTermHooks.sol:OpenTermHooks'
      : hooksKind == FixedTerm
        ? 'src/access/FixedTermHooks.sol:FixedTermHooks'
        : 'src/access/PeriodicTermHooks.sol:PeriodicTermHooks';
    IHooks hooks = IHooks(_deployCode(artifact, abi.encode(Borrower, bytes(''))));

    Options memory options = _matrixOptions(hooksKind, isRevolving);
    options.requestedHooks = HooksConfig.wrap(HooksConfig.unwrap(hooks.config().optionalFlags()));

    bytes memory hooksData;
    if (hooksKind == OpenTerm) {
      hooksData = abi.encode(uint128(0), false);
    } else if (hooksKind == FixedTerm) {
      fixedTermEnd = uint32(vm.getBlockTimestamp() + _fixedTermDelay());
      hooksData = abi.encode(fixedTermEnd, uint128(0), false, true, true);
    } else {
      hooksData =
        abi.encode(uint32(vm.getBlockTimestamp() + 30 days), uint32(30 days), uint32(7 days), uint128(0), false);
    }

    fixture = _newMarket(options, hooks, hooksData);
    vm.prank(Borrower);
    BaseAccessControls(address(hooks)).addRoleProvider(address(provider), type(uint32).max);
    for (uint256 i; i < actors.length; i++) {
      vm.prank(address(provider));
      BaseAccessControls(address(hooks)).grantRole(actors[i], uint32(vm.getBlockTimestamp()));
    }
  }

  // ░░▒▒▓▓██ [ MATRIX CONFIGURATION ] ─────────────────────────────────────────

  // ┌─ _matrixOptions ─────
  function _matrixOptions(uint8, bool isRevolving) internal view virtual returns (Options memory options) {
    options = _defaultOptions(HooksKind.OpenTerm);
    options.maxTotalSupply = 1_000_000e18;
    options.protocolFeeBips = 1_000;
    options.delinquencyFeeBips = isRevolving ? 0 : 1_000;
    options.delinquencyGracePeriod = 1 days;
    options.revolving = isRevolving;
    options.commitmentFeeBips = isRevolving ? 200 : 0;
  }

  // ┌─ _fixedTermDelay ─────
  function _fixedTermDelay() internal pure virtual returns (uint256) {
    return 60 days;
  }

  // ┌─ _actors ─────
  function _actors() internal pure returns (address[] memory actors) {
    actors = new address[](4);
    actors[0] = Alice;
    actors[1] = Bob;
    actors[2] = Carol;
    actors[3] = Dave;
  }
}
