// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import { Wildcat4626Wrapper } from './Wildcat4626Wrapper.sol';
import { IMarketTransferPolicy } from '../access/IMarketTransferPolicy.sol';
import { IWildcatArchController } from '../interfaces/IWildcatArchController.sol';
import { HooksConfig } from '../types/HooksConfig.sol';

interface IMarketRounding {
  function scaledTransferRounding() external view returns (bytes32);
}

interface IWrapperAwareMarket {
  function registerWrapper(address wrapper) external;

  function hooks() external view returns (HooksConfig);
}

interface IWildcat4626WrapperFactoryV1 {
  function createWrapper(address market) external returns (address wrapper);

  function wrapperForMarket(address market) external view returns (address wrapper);
}

/**
 * @title Wildcat4626WrapperFactory
 * @notice factory for deploying wilcat erc-4626 wrappers.
 *  ensures at most one wrapper per market.
 * @dev Single entry point for wrappers across market generations. Wrapper
 *      execution arithmetic is coupled to the market's transfer rounding:
 *      v2.5+ markets round scaled amounts down (`scaleAmountDown`) and
 *      declare it via `scaledTransferRounding()`, while earlier markets round
 *      half-up and lack that function. Floor-rounding markets are wrapped
 *      here; anything else is forwarded to the previously deployed v1
 *      factory, whose wrapper matches half-up markets. Discovery routes the
 *      same way, so a wrapper deployed against the wrong generation (only
 *      possible by calling the v1 factory directly) never resolves through
 *      this factory.
 */
contract Wildcat4626WrapperFactory {
  error WrapperAlreadyExists(address market);
  error ZeroAddress();
  error NotRegisteredMarket(address market);
  error LegacyMarketsNotSupported(address market);
  error UnsupportedMarketRounding(address market, bytes32 rounding);
  error UnsupportedMarketTransferPolicy(address market, address hooks);
  error MarketTransfersDisabled(address market);
  error InvalidV1Factory(address v1Factory);

  event WrapperDeployed(address indexed market, address indexed wrapper);

  /// @dev Rounding id declared by markets this factory's wrapper supports.
  bytes32 internal constant FloorRounding = keccak256('scaleAmountDown');

  IWildcatArchController public immutable archController;

  /// @dev Previous wrapper factory generation, for markets that round
  ///      half-up. Zero on chains with no legacy deployment.
  IWildcat4626WrapperFactoryV1 public immutable v1Factory;

  mapping(address => address) internal _wrapperForMarket;

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

  /// @dev Probe `market`'s declared transfer rounding. Markets predating
  ///      v2.5 lack the declaration entirely (`declared` false); later
  ///      generations may declare a different rounding, which callers must
  ///      not conflate with legacy. Fixed-buffer assembly staticcall so the
  ///      probe is total: try/catch reverts on codeless addresses (empty
  ///      returndata fails return decoding), and a high-level staticcall
  ///      copies unbounded returndata, letting a hostile target OOG the
  ///      caller.
  function _probeRounding(address market) internal view returns (bool declared, bytes32 rounding) {
    assembly {
      mstore(0, 0x4623a7e7) // scaledTransferRounding()
      mstore(0x20, 0)
      let success := staticcall(gas(), market, 0x1c, 0x04, 0x20, 0x20)
      declared := and(success, gt(returndatasize(), 0x1f))
      rounding := mload(0x20)
    }
  }

  /// @dev Whether `market` declares the floor transfer rounding this
  ///      factory's wrapper is built for.
  function isFloorRoundingMarket(address market) public view returns (bool) {
    (bool declared, bytes32 rounding) = _probeRounding(market);
    return declared && rounding == FloorRounding;
  }

  function _isMarketTransferDisabled(address market) internal view returns (bool) {
    HooksConfig marketHooks = IWrapperAwareMarket(market).hooks();
    address hooksAddress = marketHooks.hooksAddress();
    try IMarketTransferPolicy(hooksAddress).isMarketTransferDisabled(market) returns (
      bool transfersDisabled
    ) {
      return transfersDisabled;
    } catch {
      revert UnsupportedMarketTransferPolicy(market, hooksAddress);
    }
  }

  /// @notice Wrapper for `market`, whichever factory generation deployed it.
  ///         Locally recorded wrappers always resolve, regardless of what the
  ///         market's rounding probe answers later. Markets declaring any
  ///         rounding resolve only from this factory's registry, so a
  ///         mispaired wrapper in the legacy registry is never surfaced; only
  ///         undeclared (pre-v2.5) markets read through to v1.
  function wrapperForMarket(address market) public view returns (address wrapper) {
    wrapper = _wrapperForMarket[market];
    if (wrapper != address(0)) return wrapper;
    (bool declared, ) = _probeRounding(market);
    if (declared) return address(0);
    if (address(v1Factory) == address(0)) return address(0);
    return v1Factory.wrapperForMarket(market);
  }

  /// @notice callable by anyone, deploys a new wrapper for `market` if one does not already exist.
  ///         Undeclared (pre-v2.5, half-up) markets are forwarded to the v1
  ///         factory; markets declaring a rounding this wrapper does not
  ///         implement are rejected rather than mis-routed.
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
    if (_isMarketTransferDisabled(market)) revert MarketTransfersDisabled(market);

    wrapper = address(new Wildcat4626Wrapper(market));
    _wrapperForMarket[market] = wrapper;
    IWrapperAwareMarket(market).registerWrapper(wrapper);

    emit WrapperDeployed(market, wrapper);
  }
}
