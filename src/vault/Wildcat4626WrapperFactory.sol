// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import { Wildcat4626Wrapper } from './Wildcat4626Wrapper.sol';
import { IMarketTransferPolicy } from '../access/IMarketTransferPolicy.sol';
import { IWildcatArchController } from '../interfaces/IWildcatArchController.sol';
import { HooksConfig } from '../types/HooksConfig.sol';

/// @notice compatibility marker for a market's scaled-transfer rounding rule.
interface IMarketRounding {
  /// @notice identifier for the market's scaled-transfer rounding rule.
  function scaledTransferRounding() external view returns (bytes32);
}

/// @notice market callbacks and hook configuration needed during wrapper registration.
interface IWrapperAwareMarket {
  /// @notice records this market's canonical wrapper.
  function registerWrapper(address wrapper) external;

  /// @notice packed hook address and enabled callbacks installed on the market.
  function hooks() external view returns (HooksConfig);
}

/// @notice legacy wrapper factory used for pre-V2.5 half-up markets.
interface IWildcat4626WrapperFactoryV1 {
  /// @notice deploys the legacy wrapper for `market`.
  function createWrapper(address market) external returns (address wrapper);

  /// @notice returns the legacy wrapper for `market`, or zero if none exists.
  function wrapperForMarket(address market) external view returns (address wrapper);
}

/// @title Wildcat ERC-4626 wrapper factory
/// @notice permissionless creation and discovery for one canonical wrapper per market generation.
/// @dev wrapper arithmetic has to match market transfer rounding. this factory handles markets that
///      declare floor rounding (`scaleAmountDown`) and forwards undeclared pre-V2.5 markets to V1.
///      a declared but unknown rule is a future generation, not a legacy market, so it is
///      rejected instead of being handed the wrong wrapper. discovery follows the same split.
contract Wildcat4626WrapperFactory {
  /// @dev the matching factory generation already has a wrapper for `market`.
  error WrapperAlreadyExists(address market);
  /// @dev a required constructor or market address is zero.
  error ZeroAddress();
  /// @dev the V2.5 market is not registered with this factory's ArchController.
  error NotRegisteredMarket(address market);
  /// @dev the market uses legacy rounding but no V1 factory is configured.
  error LegacyMarketsNotSupported(address market);
  /// @dev the market declares a scaled-transfer rounding rule this generation does not support.
  error UnsupportedMarketRounding(address market, bytes32 rounding);
  /// @dev the market hook does not expose both transfer-policy queries required by the wrapper.
  error UnsupportedMarketTransferPolicy(address market, address hooks);
  /// @dev the market hook reports that all market-token transfers are disabled.
  error MarketTransfersDisabled(address market);
  /// @dev the nonzero V1 factory does not answer the required discovery query.
  error InvalidV1Factory(address v1Factory);

  /// @notice emitted when this factory deploys and registers a V2.5 wrapper.
  event WrapperDeployed(address indexed market, address indexed wrapper);

  /// @dev rounding id declared by markets this factory's wrapper supports.
  bytes32 internal constant FloorRounding = keccak256('scaleAmountDown');

  /// @notice registry used to require local V2.5 markets to be registered.
  IWildcatArchController public immutable archController;

  /// @notice previous half-up wrapper factory, or zero when legacy routing is unavailable.
  IWildcat4626WrapperFactoryV1 public immutable v1Factory;

  mapping(address => address) internal _wrapperForMarket;

  /// @param archController_ registry used to validate locally wrapped markets.
  /// @param v1Factory_ legacy factory for undeclared half-up markets, or zero to reject them.
  constructor(address archController_, address v1Factory_) {
    archController = IWildcatArchController(archController_);
    // A wrong-but-nonzero v1 address would permanently brick legacy routing
    // (and make discovery revert on codeless addresses), so prove at deploy
    // time that it answers `wrapperForMarket`.
    if (v1Factory_ != address(0)) {
      (bool success, bytes memory data) = v1Factory_.staticcall(
        abi.encodeWithSelector(IWildcat4626WrapperFactoryV1.wrapperForMarket.selector, address(0))
      );
      if (!success || data.length < 0x20) revert InvalidV1Factory(v1Factory_);
    }
    v1Factory = IWildcat4626WrapperFactoryV1(v1Factory_);
  }

  /// @dev probes `market` with a fixed return buffer so hostile returndata cannot force unbounded
  ///      copying. a revert, codeless target, or response shorter than one word is undeclared;
  ///      a successful unknown declaration is still declared and must not be routed as legacy.
  function _probeRounding(address market) internal view returns (bool declared, bytes32 rounding) {
    assembly {
      mstore(0, 0x4623a7e7) // scaledTransferRounding()
      mstore(0x20, 0)
      let success := staticcall(gas(), market, 0x1c, 0x04, 0x20, 0x20)
      declared := and(success, gt(returndatasize(), 0x1f))
      rounding := mload(0x20)
    }
  }

  /// @notice returns whether `market` declares the floor rounding used by this wrapper generation.
  function isFloorRoundingMarket(address market) public view returns (bool) {
    (bool declared, bytes32 rounding) = _probeRounding(market);
    return declared && rounding == FloorRounding;
  }

  function _validateTransferPolicy(address market) internal view returns (bool) {
    HooksConfig marketHooks = IWrapperAwareMarket(market).hooks();
    address hooksAddress = marketHooks.hooksAddress();
    IMarketTransferPolicy transferPolicy = IMarketTransferPolicy(hooksAddress);
    try transferPolicy.isMarketTransferDisabled(market) returns (bool transfersDisabled) {
      // ask for both methods the wrapper needs. supporting half the policy interface would
      // just move this failure into maxDeposit later.
      try transferPolicy.isMarketTransferRecipientAllowed(market, address(this)) returns (bool) {
        return transfersDisabled;
      } catch {
        revert UnsupportedMarketTransferPolicy(market, hooksAddress);
      }
    } catch {
      revert UnsupportedMarketTransferPolicy(market, hooksAddress);
    }
  }

  /// @notice returns the wrapper for `market` from the matching factory generation.
  /// @dev local records win even if a later rounding probe changes. any declared rounding stays in
  ///      this registry; only undeclared markets fall through to V1, so a mispaired legacy wrapper
  ///      is never surfaced here.
  function wrapperForMarket(address market) public view returns (address wrapper) {
    wrapper = _wrapperForMarket[market];
    if (wrapper != address(0)) return wrapper;
    (bool declared, ) = _probeRounding(market);
    if (declared) return address(0);
    if (address(v1Factory) == address(0)) return address(0);
    return v1Factory.wrapperForMarket(market);
  }

  /// @notice deploys and registers the generation-appropriate wrapper for `market`.
  /// @dev callable by anyone. local floor-rounding markets must be registered, globally
  ///      transferable, expose the full transfer-policy interface, and name this contract as their
  ///      wrapper factory.
  ///      undeclared markets are forwarded to V1; unknown declared rounding is rejected.
  /// @return wrapper generation-appropriate newly deployed wrapper.
  function createWrapper(address market) external returns (address wrapper) {
    if (market == address(0)) revert ZeroAddress();

    if (_wrapperForMarket[market] != address(0)) revert WrapperAlreadyExists(market);

    (bool declared, bytes32 rounding) = _probeRounding(market);
    if (!declared) {
      // The v1 factory performs its own registration and duplicate checks.
      if (address(v1Factory) == address(0)) revert LegacyMarketsNotSupported(market);
      return v1Factory.createWrapper(market);
    }
    // A future market generation with different rounding needs a matching
    // future wrapper factory; forwarding it to v1 would mispair it silently.
    if (rounding != FloorRounding) revert UnsupportedMarketRounding(market, rounding);

    if (!archController.isRegisteredMarket(market)) revert NotRegisteredMarket(market);
    if (_validateTransferPolicy(market)) revert MarketTransfersDisabled(market);

    wrapper = address(new Wildcat4626Wrapper(market));
    _wrapperForMarket[market] = wrapper;
    IWrapperAwareMarket(market).registerWrapper(wrapper);

    emit WrapperDeployed(market, wrapper);
  }
}
