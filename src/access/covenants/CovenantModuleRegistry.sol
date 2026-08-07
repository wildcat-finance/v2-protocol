// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity ^0.8.20;

interface IArchControllerOwner {
  function owner() external view returns (address);
}

/**
 * @title CovenantModuleRegistry
 * @dev Append-only registry of reviewed covenant modules, governed by the
 *      archcontroller's owner: the same gate that already curates hooks
 *      templates at the protocol's front door.
 *
 *      Append-only is the whole design. There is no removal, no replacement
 *      and no disable switch, so nothing a live market relies on can ever be
 *      reached from here, and the registry cannot be compelled to do what it
 *      has no code to do. Governance curates what may be *adopted*; it never
 *      touches what is already *running*. Review mistakes are handled the
 *      only place they can be: before registration, and by the waiver every
 *      borrower acknowledges at append time.
 *
 *      Each entry pins the module's codehash at registration, and dispatchers
 *      re-check it on every call, so what was reviewed is what runs, forever.
 */
contract CovenantModuleRegistry {
  event ModuleRegistered(address indexed module, bytes32 codehash, string name);

  error CallerNotArchControllerOwner();
  error ModuleAlreadyRegistered();
  error ModuleHasNoCode();

  /// @notice Acknowledged by the borrower on every append. The hash of this
  ///         exact string is the required acknowledgement value.
  string public constant WAIVER =
    'Covenant modules are third-party code. Appending one to a market is '
    'irrevocable, may block draws on that market permanently, and is done at '
    'the appending borrower\'s sole risk. Neither the registry owner nor '
    'Wildcat Labs warrants any module\'s behaviour.';

  bytes32 public immutable WAIVER_HASH = keccak256(bytes(WAIVER));

  address public immutable archController;

  mapping(address => bytes32) public moduleCodehash;
  address[] internal _modules;

  constructor(address archController_) {
    archController = archController_;
  }

  /// @notice Register a reviewed module. Archcontroller owner only,
  ///         append-only: an address can be registered exactly once and its
  ///         codehash is pinned as it stands in this block.
  function registerModule(address module, string calldata name) external {
    if (msg.sender != IArchControllerOwner(archController).owner()) {
      revert CallerNotArchControllerOwner();
    }
    if (moduleCodehash[module] != bytes32(0)) revert ModuleAlreadyRegistered();
    bytes32 codehash = module.codehash;
    if (codehash == bytes32(0) || module.code.length == 0) revert ModuleHasNoCode();
    moduleCodehash[module] = codehash;
    _modules.push(module);
    emit ModuleRegistered(module, codehash, name);
  }

  function isRegisteredModule(address module) external view returns (bool) {
    return moduleCodehash[module] != bytes32(0);
  }

  function getRegisteredModules() external view returns (address[] memory) {
    return _modules;
  }
}
