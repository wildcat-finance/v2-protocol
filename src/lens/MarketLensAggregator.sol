// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ╔════════════════════════════════════════════════════════════════════════════
// ║  █▄         ▄█
// ║  ███▄     ▄███   WILDCAT v2.5 // MarketLensAggregator
// ║  ██▀▀     ▀▀██   Factory discovery and cross-generation hooks and market reads.
// ║  ▀▀███▄ ▄███▀▀
// ║      ▀▀▄▀▀
// ║
// ║  SETUP
// ║  constructor(...)
// ║
// ║  FACTORY DISCOVERY
// ║  getActiveHooksFactories()
// ║  _isHooksFactory(...)
// ║  _asFactory(...)
// ║  _containsAddress(...)
// ║  _shrinkAddressArray(...)
// ║
// ║  BORROWER HOOKS DATA
// ║  getHooksDataForBorrower(...)
// ║  getHooksDataForBorrower(...)
// ║  getAggregatedHooksDataForBorrower(...)
// ║
// ║  HOOKS INSTANCES
// ║  getHooksInstancesForBorrower(...)
// ║  getHooksInstancesForBorrower(...)
// ║  getAggregatedHooksInstancesForBorrower(...)
// ║  getAggregatedHooksInstancesForBorrowerWithFactories(...)
// ║  _containsHooksInstanceAddress(...)
// ║  _shrinkHooksInstanceArray(...)
// ║
// ║  HOOKS TEMPLATES
// ║  getHooksTemplateForBorrower(...)
// ║  getHooksTemplateForBorrower(...)
// ║  getHooksTemplatesForBorrower(...)
// ║  getHooksTemplatesForBorrower(...)
// ║  getAllHooksTemplatesForBorrower(...)
// ║  getAllHooksTemplatesForBorrower(...)
// ║  getAggregatedAllHooksTemplatesForBorrower(...)
// ║  getAggregatedHooksTemplatesForBorrowerWithFactory(...)
// ║  getAggregatedAllHooksTemplatesForBorrowerWithFactories(...)
// ║  _collectHooksTemplatesByFactory(...)
// ║  _containsHooksTemplateAddress(...)
// ║  _shrinkHooksTemplateArray(...)
// ║  _shrinkFactoryScopedHooksTemplateArray(...)
// ║
// ║  TEMPLATE MARKETS
// ║  getMarketsForHooksTemplateCount(...)
// ║  getMarketsForHooksTemplateCount(...)
// ║  getAggregatedMarketsForHooksTemplateCount(...)
// ║  getPaginatedMarketsDataForHooksTemplate(...)
// ║  getPaginatedMarketsDataForHooksTemplate(...)
// ║  getPaginatedMarketsDataV2ForHooksTemplate(...)
// ║  getPaginatedMarketsDataV2ForHooksTemplate(...)
// ║  getAllMarketsDataForHooksTemplate(...)
// ║  getAllMarketsDataForHooksTemplate(...)
// ║  getAllMarketsDataV2ForHooksTemplate(...)
// ║  getAllMarketsDataV2ForHooksTemplate(...)
// ║  getAggregatedAllMarketsDataForHooksTemplate(...)
// ║  getAggregatedAllMarketsDataV2ForHooksTemplate(...)
// ║  _getAggregatedMarketsForHooksTemplate(...)
// ╚═════

import '../IHooksFactory.sol';
import './FactoryScopedHooksTemplateData.sol';
import './HooksDataForBorrower.sol';
import './HooksInstanceData.sol';
import './HooksTemplateData.sol';
import './MarketData.sol';
import './interfaces/IMarketLensAggregator.sol';

// ┌─ MarketLensAggregator ─────────────────────────────────────────────────────
/// @title hooks-factory aggregation lens helper
///
/// @notice gathers hooks and market data across the default factory or active factory generations.
///
/// @dev active factories are registered controllers that answer the hooks-factory probe, plus the
///      configured default when needed. discovery is interface-based, not provenance.
contract MarketLensAggregator is IMarketLensAggregator {
  /// @notice ArchController used to discover active controller factories.
  WildcatArchController public immutable archController;

  /// @notice default hooks factory included in aggregation results.
  IHooksFactory public immutable hooksFactory;

  // ░░▒▒▓▓██ [ SETUP ] ────────────────────────────────────────────────────────

  // ┌─ constructor ─────
  constructor(address _archController, address _hooksFactory) {
    archController = WildcatArchController(_archController);
    hooksFactory = IHooksFactory(_hooksFactory);
  }

  // ░░▒▒▓▓██ [ FACTORY DISCOVERY ] ────────────────────────────────────────────

  // ┌─ getActiveHooksFactories ─────
  /// @notice returns discoverable hooks factories in ArchController order.
  ///
  /// @dev appends the configured default if it is valid and not already registered.
  function getActiveHooksFactories() public view returns (address[] memory factories) {
    address[] memory controllers = archController.getRegisteredControllers();
    address[] memory tmp = new address[](controllers.length + 1);
    uint256 count;

    for (uint256 i; i < controllers.length; i++) {
      address controller = controllers[i];
      if (_isHooksFactory(controller)) {
        tmp[count++] = controller;
      }
    }

    address defaultFactory = address(hooksFactory);
    if (!_containsAddress(tmp, count, defaultFactory) && _isHooksFactory(defaultFactory)) {
      tmp[count++] = defaultFactory;
    }

    return _shrinkAddressArray(tmp, count);
  }

  // ┌─ _isHooksFactory ─────
  /// @dev treats any contract that answers `getHooksTemplatesCount()` as a factory candidate.
  function _isHooksFactory(address candidate) internal view returns (bool isFactory) {
    try IHooksFactory(candidate).getHooksTemplatesCount() returns (uint256) {
      return true;
    } catch {
      return false;
    }
  }

  // ┌─ _asFactory ─────
  function _asFactory(address hooksFactoryAddress) internal pure returns (IHooksFactory) {
    return IHooksFactory(hooksFactoryAddress);
  }

  // ┌─ _containsAddress ─────
  function _containsAddress(address[] memory arr, uint256 length, address value) internal pure returns (bool) {
    for (uint256 i; i < length; i++) {
      if (arr[i] == value) return true;
    }
    return false;
  }

  // ┌─ _shrinkAddressArray ─────
  function _shrinkAddressArray(address[] memory arr, uint256 newLength) internal pure returns (address[] memory) {
    assembly {
      mstore(arr, newLength)
    }
    return arr;
  }

  // ░░▒▒▓▓██ [ BORROWER HOOKS DATA ] ──────────────────────────────────────────

  // ┌─ getHooksDataForBorrower ─────
  function getHooksDataForBorrower(address borrower) public view returns (HooksDataForBorrower memory data) {
    return getHooksDataForBorrower(address(hooksFactory), borrower);
  }

  // ┌─ getHooksDataForBorrower ─────
  function getHooksDataForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    public
    view
    returns (HooksDataForBorrower memory data)
  {
    data.fill(archController, _asFactory(hooksFactoryAddress), borrower);
  }

  // ┌─ getAggregatedHooksDataForBorrower ─────
  function getAggregatedHooksDataForBorrower(address borrower)
    external
    view
    returns (HooksDataForBorrower memory data)
  {
    address[] memory factories = getActiveHooksFactories();
    data.borrower = borrower;
    data.isRegisteredBorrower = archController.isRegisteredBorrower(borrower);
    data.hooksInstances = getAggregatedHooksInstancesForBorrowerWithFactories(borrower, factories);
    data.hooksTemplates = getAggregatedAllHooksTemplatesForBorrowerWithFactories(borrower, factories);
  }

  // ░░▒▒▓▓██ [ HOOKS INSTANCES ] ──────────────────────────────────────────────

  // ┌─ getHooksInstancesForBorrower ─────
  function getHooksInstancesForBorrower(address borrower) public view returns (HooksInstanceData[] memory arr) {
    return getHooksInstancesForBorrower(address(hooksFactory), borrower);
  }

  // ┌─ getHooksInstancesForBorrower ─────
  function getHooksInstancesForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    public
    view
    returns (HooksInstanceData[] memory arr)
  {
    IHooksFactory factory = _asFactory(hooksFactoryAddress);
    address[] memory hooksInstances = factory.getHooksInstancesForBorrower(borrower);
    arr = new HooksInstanceData[](hooksInstances.length);
    for (uint256 i; i < hooksInstances.length; i++) {
      address hooksInstance = hooksInstances[i];
      HooksInstanceKind kind = HooksConfigDataLib.kindForHooks(hooksInstance);
      arr[i].fill(hooksInstance, factory, borrower, kind);
    }
  }

  // ┌─ getAggregatedHooksInstancesForBorrower ─────
  function getAggregatedHooksInstancesForBorrower(address borrower)
    external
    view
    returns (HooksInstanceData[] memory arr)
  {
    return getAggregatedHooksInstancesForBorrowerWithFactories(borrower, getActiveHooksFactories());
  }

  // ┌─ getAggregatedHooksInstancesForBorrowerWithFactories ─────
  /// @notice combines borrower-indexed instances from a supplied factory list.
  ///
  /// @dev factory enumeration failures are skipped. duplicate instances use the first factory that
  ///      reported them, and malformed instance metadata can still revert the complete call.
  function getAggregatedHooksInstancesForBorrowerWithFactories(
    address borrower,
    address[] memory factories
  )
    public
    view
    returns (HooksInstanceData[] memory arr)
  {
    uint256 numFactories = factories.length;
    if (numFactories == 0) {
      return new HooksInstanceData[](0);
    }
    if (numFactories == 1) {
      IHooksFactory factory = IHooksFactory(factories[0]);
      try factory.getHooksInstancesForBorrower(borrower) returns (address[] memory hooksInstances) {
        arr = new HooksInstanceData[](hooksInstances.length);
        for (uint256 i; i < hooksInstances.length; i++) {
          address hooksInstance = hooksInstances[i];
          HooksInstanceKind kind = HooksConfigDataLib.kindForHooks(hooksInstance);
          arr[i].fill(hooksInstance, factory, borrower, kind);
        }
        return arr;
      } catch {
        return new HooksInstanceData[](0);
      }
    }

    address[][] memory hooksInstancesByFactory = new address[][](numFactories);
    uint256 totalInstances = 0;

    for (uint256 i; i < numFactories; i++) {
      try IHooksFactory(factories[i]).getHooksInstancesForBorrower(borrower) returns (address[] memory hooksInstances) {
        hooksInstancesByFactory[i] = hooksInstances;
        totalInstances += hooksInstances.length;
      } catch { }
    }

    arr = new HooksInstanceData[](totalInstances);
    uint256 uniqueCount = 0;
    for (uint256 i; i < numFactories; i++) {
      IHooksFactory factory = IHooksFactory(factories[i]);
      address[] memory hooksInstances = hooksInstancesByFactory[i];
      for (uint256 j; j < hooksInstances.length; j++) {
        address hooksAddress = hooksInstances[j];
        if (!_containsHooksInstanceAddress(arr, uniqueCount, hooksAddress)) {
          HooksInstanceKind kind = HooksConfigDataLib.kindForHooks(hooksAddress);
          arr[uniqueCount].fill(hooksAddress, factory, borrower, kind);
          uniqueCount++;
        }
      }
    }

    return _shrinkHooksInstanceArray(arr, uniqueCount);
  }

  // ┌─ _containsHooksInstanceAddress ─────
  function _containsHooksInstanceAddress(
    HooksInstanceData[] memory arr,
    uint256 length,
    address hooksAddress
  )
    internal
    pure
    returns (bool)
  {
    for (uint256 i; i < length; i++) {
      if (arr[i].hooksAddress == hooksAddress) return true;
    }
    return false;
  }

  // ┌─ _shrinkHooksInstanceArray ─────
  function _shrinkHooksInstanceArray(
    HooksInstanceData[] memory arr,
    uint256 newLength
  )
    internal
    pure
    returns (HooksInstanceData[] memory)
  {
    assembly {
      mstore(arr, newLength)
    }
    return arr;
  }

  // ░░▒▒▓▓██ [ HOOKS TEMPLATES ] ──────────────────────────────────────────────

  // ┌─ getHooksTemplateForBorrower ─────
  function getHooksTemplateForBorrower(
    address borrower,
    address hooksTemplate
  )
    public
    view
    returns (HooksTemplateData memory data)
  {
    return getHooksTemplateForBorrower(address(hooksFactory), borrower, hooksTemplate);
  }

  // ┌─ getHooksTemplateForBorrower ─────
  function getHooksTemplateForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address hooksTemplate
  )
    public
    view
    returns (HooksTemplateData memory data)
  {
    data.fill(_asFactory(hooksFactoryAddress), hooksTemplate, borrower);
  }

  // ┌─ getHooksTemplatesForBorrower ─────
  function getHooksTemplatesForBorrower(
    address borrower,
    address[] memory hooksTemplates
  )
    public
    view
    returns (HooksTemplateData[] memory data)
  {
    return getHooksTemplatesForBorrower(address(hooksFactory), borrower, hooksTemplates);
  }

  // ┌─ getHooksTemplatesForBorrower ─────
  function getHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower,
    address[] memory hooksTemplates
  )
    public
    view
    returns (HooksTemplateData[] memory data)
  {
    IHooksFactory factory = _asFactory(hooksFactoryAddress);
    data = new HooksTemplateData[](hooksTemplates.length);
    for (uint256 i; i < hooksTemplates.length; i++) {
      data[i].fill(factory, hooksTemplates[i], borrower);
    }
  }

  // ┌─ getAllHooksTemplatesForBorrower ─────
  function getAllHooksTemplatesForBorrower(address borrower) public view returns (HooksTemplateData[] memory data) {
    return getAllHooksTemplatesForBorrower(address(hooksFactory), borrower);
  }

  // ┌─ getAllHooksTemplatesForBorrower ─────
  function getAllHooksTemplatesForBorrower(
    address hooksFactoryAddress,
    address borrower
  )
    public
    view
    returns (HooksTemplateData[] memory data)
  {
    IHooksFactory factory = _asFactory(hooksFactoryAddress);
    address[] memory hooksTemplates = factory.getHooksTemplates();
    return getHooksTemplatesForBorrower(hooksFactoryAddress, borrower, hooksTemplates);
  }

  // ┌─ getAggregatedAllHooksTemplatesForBorrower ─────
  function getAggregatedAllHooksTemplatesForBorrower(address borrower)
    external
    view
    returns (HooksTemplateData[] memory data)
  {
    return getAggregatedAllHooksTemplatesForBorrowerWithFactories(borrower, getActiveHooksFactories());
  }

  // ┌─ getAggregatedHooksTemplatesForBorrowerWithFactory ─────
  function getAggregatedHooksTemplatesForBorrowerWithFactory(address borrower)
    external
    view
    returns (FactoryScopedHooksTemplateData[] memory data)
  {
    address[] memory factories = getActiveHooksFactories();
    uint256 numFactories = factories.length;
    if (numFactories == 0) {
      return new FactoryScopedHooksTemplateData[](0);
    }

    (address[][] memory templatesByFactory, uint256 totalTemplates) = _collectHooksTemplatesByFactory(factories);

    data = new FactoryScopedHooksTemplateData[](totalTemplates);
    uint256 count = 0;
    for (uint256 i; i < numFactories; i++) {
      IHooksFactory factory = IHooksFactory(factories[i]);
      address[] memory hooksTemplates = templatesByFactory[i];
      for (uint256 j; j < hooksTemplates.length; j++) {
        data[count].hooksFactory = factories[i];
        data[count].hooksTemplateData.fill(factory, hooksTemplates[j], borrower);
        count++;
      }
    }

    return _shrinkFactoryScopedHooksTemplateArray(data, count);
  }

  // ┌─ getAggregatedAllHooksTemplatesForBorrowerWithFactories ─────
  /// @notice combines templates from a supplied factory list, deduplicated by template address.
  ///
  /// @dev the first factory reporting a duplicate supplies its metadata and fee readiness.
  function getAggregatedAllHooksTemplatesForBorrowerWithFactories(
    address borrower,
    address[] memory factories
  )
    public
    view
    returns (HooksTemplateData[] memory data)
  {
    uint256 numFactories = factories.length;
    if (numFactories == 0) {
      return new HooksTemplateData[](0);
    }
    if (numFactories == 1) {
      IHooksFactory factory = IHooksFactory(factories[0]);
      try factory.getHooksTemplates() returns (address[] memory hooksTemplates) {
        data = new HooksTemplateData[](hooksTemplates.length);
        for (uint256 i; i < hooksTemplates.length; i++) {
          data[i].fill(factory, hooksTemplates[i], borrower);
        }
        return data;
      } catch {
        return new HooksTemplateData[](0);
      }
    }

    (address[][] memory templatesByFactory, uint256 totalTemplates) = _collectHooksTemplatesByFactory(factories);

    data = new HooksTemplateData[](totalTemplates);
    uint256 uniqueCount = 0;
    for (uint256 i; i < numFactories; i++) {
      IHooksFactory factory = IHooksFactory(factories[i]);
      address[] memory hooksTemplates = templatesByFactory[i];
      for (uint256 j; j < hooksTemplates.length; j++) {
        address hooksTemplate = hooksTemplates[j];
        if (!_containsHooksTemplateAddress(data, uniqueCount, hooksTemplate)) {
          data[uniqueCount].fill(factory, hooksTemplate, borrower);
          uniqueCount++;
        }
      }
    }

    return _shrinkHooksTemplateArray(data, uniqueCount);
  }

  // ┌─ _collectHooksTemplatesByFactory ─────
  /// @dev collects template addresses best-effort; a factory that reverts contributes no rows.
  function _collectHooksTemplatesByFactory(address[] memory factories)
    internal
    view
    returns (address[][] memory templatesByFactory, uint256 totalTemplates)
  {
    uint256 numFactories = factories.length;
    templatesByFactory = new address[][](numFactories);

    for (uint256 i; i < numFactories; i++) {
      try IHooksFactory(factories[i]).getHooksTemplates() returns (address[] memory hooksTemplates) {
        templatesByFactory[i] = hooksTemplates;
        totalTemplates += hooksTemplates.length;
      } catch { }
    }
  }

  // ┌─ _containsHooksTemplateAddress ─────
  function _containsHooksTemplateAddress(
    HooksTemplateData[] memory arr,
    uint256 length,
    address hooksTemplate
  )
    internal
    pure
    returns (bool)
  {
    for (uint256 i; i < length; i++) {
      if (arr[i].hooksTemplate == hooksTemplate) return true;
    }
    return false;
  }

  // ┌─ _shrinkHooksTemplateArray ─────
  function _shrinkHooksTemplateArray(
    HooksTemplateData[] memory arr,
    uint256 newLength
  )
    internal
    pure
    returns (HooksTemplateData[] memory)
  {
    assembly {
      mstore(arr, newLength)
    }
    return arr;
  }

  // ┌─ _shrinkFactoryScopedHooksTemplateArray ─────
  function _shrinkFactoryScopedHooksTemplateArray(
    FactoryScopedHooksTemplateData[] memory arr,
    uint256 newLength
  )
    internal
    pure
    returns (FactoryScopedHooksTemplateData[] memory)
  {
    assembly {
      mstore(arr, newLength)
    }
    return arr;
  }

  // ░░▒▒▓▓██ [ TEMPLATE MARKETS ] ─────────────────────────────────────────────

  // ┌─ getMarketsForHooksTemplateCount ─────
  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
    return getMarketsForHooksTemplateCount(address(hooksFactory), hooksTemplate);
  }

  // ┌─ getMarketsForHooksTemplateCount ─────
  function getMarketsForHooksTemplateCount(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    public
    view
    returns (uint256)
  {
    return _asFactory(hooksFactoryAddress).getMarketsForHooksTemplateCount(hooksTemplate);
  }

  // ┌─ getAggregatedMarketsForHooksTemplateCount ─────
  function getAggregatedMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256 count) {
    return _getAggregatedMarketsForHooksTemplate(hooksTemplate).length;
  }

  // ┌─ getPaginatedMarketsDataForHooksTemplate ─────
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    public
    view
    returns (MarketData[] memory data)
  {
    return getPaginatedMarketsDataForHooksTemplate(address(hooksFactory), hooksTemplate, start, end);
  }

  // ┌─ getPaginatedMarketsDataForHooksTemplate ─────
  function getPaginatedMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    public
    view
    returns (MarketData[] memory data)
  {
    address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate, start, end);
    return MarketDataLib.fillMarketsData(markets);
  }

  // ┌─ getPaginatedMarketsDataV2ForHooksTemplate ─────
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    public
    view
    returns (MarketDataV2_5[] memory data)
  {
    return getPaginatedMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate, start, end);
  }

  // ┌─ getPaginatedMarketsDataV2ForHooksTemplate ─────
  function getPaginatedMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate,
    uint256 start,
    uint256 end
  )
    public
    view
    returns (MarketDataV2_5[] memory data)
  {
    address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate, start, end);
    return MarketDataLib.fillMarketsDataV2(markets);
  }

  // ┌─ getAllMarketsDataForHooksTemplate ─────
  function getAllMarketsDataForHooksTemplate(address hooksTemplate) external view returns (MarketData[] memory data) {
    return getAllMarketsDataForHooksTemplate(address(hooksFactory), hooksTemplate);
  }

  // ┌─ getAllMarketsDataForHooksTemplate ─────
  function getAllMarketsDataForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    public
    view
    returns (MarketData[] memory data)
  {
    address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate);
    return MarketDataLib.fillMarketsData(markets);
  }

  // ┌─ getAllMarketsDataV2ForHooksTemplate ─────
  function getAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketDataV2_5[] memory data)
  {
    return getAllMarketsDataV2ForHooksTemplate(address(hooksFactory), hooksTemplate);
  }

  // ┌─ getAllMarketsDataV2ForHooksTemplate ─────
  function getAllMarketsDataV2ForHooksTemplate(
    address hooksFactoryAddress,
    address hooksTemplate
  )
    public
    view
    returns (MarketDataV2_5[] memory data)
  {
    address[] memory markets = _asFactory(hooksFactoryAddress).getMarketsForHooksTemplate(hooksTemplate);
    return MarketDataLib.fillMarketsDataV2(markets);
  }

  // ┌─ getAggregatedAllMarketsDataForHooksTemplate ─────
  function getAggregatedAllMarketsDataForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketData[] memory data)
  {
    return MarketDataLib.fillMarketsData(_getAggregatedMarketsForHooksTemplate(hooksTemplate));
  }

  // ┌─ getAggregatedAllMarketsDataV2ForHooksTemplate ─────
  function getAggregatedAllMarketsDataV2ForHooksTemplate(address hooksTemplate)
    external
    view
    returns (MarketDataV2_5[] memory data)
  {
    return MarketDataLib.fillMarketsDataV2(_getAggregatedMarketsForHooksTemplate(hooksTemplate));
  }

  // ┌─ _getAggregatedMarketsForHooksTemplate ─────
  /// @dev collects markets best-effort and deduplicates them by address in first-seen order.
  function _getAggregatedMarketsForHooksTemplate(address hooksTemplate)
    internal
    view
    returns (address[] memory markets)
  {
    address[] memory factories = getActiveHooksFactories();
    uint256 numFactories = factories.length;
    if (numFactories == 0) {
      return new address[](0);
    }
    if (numFactories == 1) {
      try IHooksFactory(factories[0]).getMarketsForHooksTemplate(hooksTemplate) returns (
        address[] memory singleFactoryMarkets
      ) {
        return singleFactoryMarkets;
      } catch {
        return new address[](0);
      }
    }

    address[][] memory marketsByFactory = new address[][](numFactories);
    uint256 totalMarkets = 0;

    for (uint256 i; i < numFactories; i++) {
      try IHooksFactory(factories[i]).getMarketsForHooksTemplate(hooksTemplate) returns (
        address[] memory factoryMarkets
      ) {
        marketsByFactory[i] = factoryMarkets;
        totalMarkets += factoryMarkets.length;
      } catch { }
    }

    markets = new address[](totalMarkets);
    uint256 uniqueCount = 0;
    for (uint256 i; i < numFactories; i++) {
      address[] memory factoryMarkets = marketsByFactory[i];
      for (uint256 j; j < factoryMarkets.length; j++) {
        address marketAddress = factoryMarkets[j];
        if (!_containsAddress(markets, uniqueCount, marketAddress)) {
          markets[uniqueCount++] = marketAddress;
        }
      }
    }

    return _shrinkAddressArray(markets, uniqueCount);
  }
}
