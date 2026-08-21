// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.25;

import 'forge-std/Test.sol';
import 'src/types/TransientMarketParameters.sol';

contract TransientMarketParametersTest is Test {
  function readParameters() external view returns (TmpMarketParameters memory) {
    return LibTransientMarketParameters.read();
  }

  function readCommitmentFeeBips() external view returns (uint16) {
    return LibTransientMarketParameters.commitmentFeeBips();
  }

  function _assertEqual(
    TmpMarketParameters memory actual,
    TmpMarketParameters memory expected
  ) internal pure {
    assertEq(keccak256(abi.encode(actual)), keccak256(abi.encode(expected)));
  }

  function testFuzz_roundTrip(TmpMarketParameters memory parameters) external {
    if (parameters.borrower == address(0)) parameters.borrower = address(1);

    LibTransientMarketParameters.write(parameters);

    _assertEqual(LibTransientMarketParameters.read(), parameters);
    assertEq(
      LibTransientMarketParameters.commitmentFeeBips(),
      parameters.commitmentFeeBips
    );
  }

  function test_clearDisablesReads() external {
    TmpMarketParameters memory parameters;
    parameters.borrower = address(1);
    parameters.commitmentFeeBips = 123;
    LibTransientMarketParameters.write(parameters);
    LibTransientMarketParameters.clear();

    vm.expectRevert();
    this.readParameters();
    vm.expectRevert();
    this.readCommitmentFeeBips();
  }

  function test_writeOverwritesDirtyWords() external {
    TmpMarketParameters memory dirty;
    dirty.borrower = address(type(uint160).max);
    dirty.asset = address(type(uint160).max);
    dirty.feeRecipient = address(type(uint160).max);
    dirty.maxTotalSupply = type(uint128).max;
    dirty.protocolFeeBips = type(uint16).max;
    dirty.annualInterestBips = type(uint16).max;
    dirty.delinquencyFeeBips = type(uint16).max;
    dirty.withdrawalBatchDuration = type(uint32).max;
    dirty.reserveRatioBips = type(uint16).max;
    dirty.delinquencyGracePeriod = type(uint32).max;
    dirty.packedNameWord0 = bytes32(type(uint256).max);
    dirty.packedNameWord1 = bytes32(type(uint256).max);
    dirty.packedSymbolWord0 = bytes32(type(uint256).max);
    dirty.packedSymbolWord1 = bytes32(type(uint256).max);
    dirty.decimals = type(uint8).max;
    dirty.hooks = HooksConfig.wrap(type(uint256).max);
    dirty.borrowerPrincipal = address(type(uint160).max);
    dirty.commitmentFeeBips = type(uint16).max;
    LibTransientMarketParameters.write(dirty);
    LibTransientMarketParameters.clear();

    TmpMarketParameters memory clean;
    clean.borrower = address(1);
    LibTransientMarketParameters.write(clean);

    _assertEqual(LibTransientMarketParameters.read(), clean);
  }

  function test_readOutsideDeploymentContextReverts() external {
    vm.expectRevert();
    this.readParameters();
    vm.expectRevert();
    this.readCommitmentFeeBips();
  }
}
