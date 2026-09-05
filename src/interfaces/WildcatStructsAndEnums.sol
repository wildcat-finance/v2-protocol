// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { MarketState } from '../libraries/MarketState.sol';

import { HooksConfig } from '../types/HooksConfig.sol';

/// @notice complete constructor payload read by a market from its deploying factory.
/// @dev every field is static so the market can copy the returned ABI block directly.
/// @param asset underlying ERC-20 asset.
/// @param decimals decimals copied from `asset` for the market token.
/// @param packedNameWord0 first packed word of the market-token name, including its length byte.
/// @param packedNameWord1 second packed word of the market-token name.
/// @param packedSymbolWord0 first market-token symbol word, including its length byte.
/// @param packedSymbolWord1 second packed word of the market-token symbol.
/// @param borrower operational address allowed to use borrower-only market functions.
/// @param feeRecipient immutable recipient of accrued protocol fees.
/// @param sentinel sanctions sentinel used for borrower and lender checks.
/// @param wrapperFactory only address allowed to register the canonical ERC-4626 wrapper.
/// @param maxTotalSupply normalized supply cap for new deposits.
/// @param protocolFeeBips protocol share of base interest, charged on top, in bips.
/// @param annualInterestBips base annual lender rate, in bips.
/// @param delinquencyFeeBips additional annual lender rate during penalized delinquency, in bips.
/// @param withdrawalBatchDuration duration of each withdrawal batch, in seconds.
/// @param reserveRatioBips share of outstanding supply kept as liquid reserves, in bips.
/// @param delinquencyGracePeriod delinquent time before the penalty rate applies, in seconds.
/// @param archController protocol registry used for borrower and market authorization.
/// @param sphereXEngine transaction-checking engine used by the market.
/// @param hooks hook address and enabled callback flags installed on the market.
/// @param borrowerPrincipal registered legal principal used as the sanctions namespace.
/// @param borrowerIdentityRegistry registry that resolves operational borrowers to principals.
struct MarketParameters {
  address asset;
  uint8 decimals;
  bytes32 packedNameWord0;
  bytes32 packedNameWord1;
  bytes32 packedSymbolWord0;
  bytes32 packedSymbolWord1;
  address borrower;
  address feeRecipient;
  address sentinel;
  address wrapperFactory;
  uint128 maxTotalSupply;
  uint16 protocolFeeBips;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  address archController;
  address sphereXEngine;
  HooksConfig hooks;
  // appended so the existing 20 parameter offsets remain unchanged.
  address borrowerPrincipal;
  address borrowerIdentityRegistry;
}

/// @notice borrower-selected terms passed to hooks before market deployment.
/// @param asset underlying ERC-20 asset.
/// @param namePrefix prefix added to the underlying token name.
/// @param symbolPrefix prefix added to the underlying token symbol.
/// @param maxTotalSupply normalized supply cap for new deposits.
/// @param annualInterestBips base annual lender rate, in bips.
/// @param delinquencyFeeBips additional annual lender rate during penalized delinquency, in bips.
/// @param withdrawalBatchDuration duration of each withdrawal batch, in seconds.
/// @param reserveRatioBips share of outstanding supply kept as liquid reserves, in bips.
/// @param delinquencyGracePeriod delinquent time before the penalty rate applies, in seconds.
/// @param hooks requested hook instance and callback flags; hooks may return a modified config.
struct DeployMarketInputs {
  address asset;
  string namePrefix;
  string symbolPrefix;
  uint128 maxTotalSupply;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  HooksConfig hooks;
}

/// @notice controller configuration and market-term bounds for controller-based deployment.
/// @param archController protocol registry that authorizes the controller and its markets.
/// @param borrower operational borrower assigned to deployed markets.
/// @param sentinel sanctions sentinel assigned to deployed markets.
/// @param marketInitCodeStorage contract holding the market creation bytecode.
/// @param marketInitCodeHash keccak256 hash of the market creation bytecode.
/// @param minimumDelinquencyGracePeriod lower grace-period bound, in seconds.
/// @param maximumDelinquencyGracePeriod upper grace-period bound, in seconds.
/// @param minimumReserveRatioBips lower reserve-ratio bound, in bips.
/// @param maximumReserveRatioBips upper reserve-ratio bound, in bips.
/// @param minimumDelinquencyFeeBips lower delinquency-fee bound, in bips.
/// @param maximumDelinquencyFeeBips upper delinquency-fee bound, in bips.
/// @param minimumWithdrawalBatchDuration lower withdrawal-batch duration, in seconds.
/// @param maximumWithdrawalBatchDuration upper withdrawal-batch duration, in seconds.
/// @param minimumAnnualInterestBips lower base-APR bound, in bips.
/// @param maximumAnnualInterestBips upper base-APR bound, in bips.
/// @param sphereXEngine transaction-checking engine assigned to deployed markets.
struct MarketControllerParameters {
  address archController;
  address borrower;
  address sentinel;
  address marketInitCodeStorage;
  uint256 marketInitCodeHash;
  uint32 minimumDelinquencyGracePeriod;
  uint32 maximumDelinquencyGracePeriod;
  uint16 minimumReserveRatioBips;
  uint16 maximumReserveRatioBips;
  uint16 minimumDelinquencyFeeBips;
  uint16 maximumDelinquencyFeeBips;
  uint32 minimumWithdrawalBatchDuration;
  uint32 maximumWithdrawalBatchDuration;
  uint16 minimumAnnualInterestBips;
  uint16 maximumAnnualInterestBips;
  address sphereXEngine;
}

/// @notice protocol charges applied to markets deployed from a hooks template.
/// @param feeRecipient recipient of origination fees and accrued protocol fees.
/// @param originationFeeAsset token charged once at market deployment.
/// @param originationFeeAmount amount of `originationFeeAsset` charged at deployment.
/// @param protocolFeeBips protocol share of base interest, charged on top, in bips.
struct ProtocolFeeConfiguration {
  address feeRecipient;
  address originationFeeAsset;
  uint80 originationFeeAmount;
  uint16 protocolFeeBips;
}

/// @notice inclusive term bounds enforced by market-constraint hooks.
/// @param minimumDelinquencyGracePeriod lower grace-period bound, in seconds.
/// @param maximumDelinquencyGracePeriod upper grace-period bound, in seconds.
/// @param minimumReserveRatioBips lower reserve-ratio bound, in bips.
/// @param maximumReserveRatioBips upper reserve-ratio bound, in bips.
/// @param minimumDelinquencyFeeBips lower delinquency-fee bound, in bips.
/// @param maximumDelinquencyFeeBips upper delinquency-fee bound, in bips.
/// @param minimumWithdrawalBatchDuration lower withdrawal-batch duration, in seconds.
/// @param maximumWithdrawalBatchDuration upper withdrawal-batch duration, in seconds.
/// @param minimumAnnualInterestBips lower base-APR bound, in bips.
/// @param maximumAnnualInterestBips upper base-APR bound, in bips.
struct MarketParameterConstraints {
  uint32 minimumDelinquencyGracePeriod;
  uint32 maximumDelinquencyGracePeriod;
  uint16 minimumReserveRatioBips;
  uint16 maximumReserveRatioBips;
  uint16 minimumDelinquencyFeeBips;
  uint16 maximumDelinquencyFeeBips;
  uint32 minimumWithdrawalBatchDuration;
  uint32 maximumWithdrawalBatchDuration;
  uint16 minimumAnnualInterestBips;
  uint16 maximumAnnualInterestBips;
}
