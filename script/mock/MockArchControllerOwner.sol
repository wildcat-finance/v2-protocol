// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import 'src/WildcatArchController.sol';

interface IArchControllerBound {
  function archController() external view returns (address);
}

interface ILegacyWildcatMarketControllerFactory is IArchControllerBound {
  function setProtocolFeeConfiguration(
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external;
}

/**
 * @dev testnet helper for the one ArchController and the protocol contracts
 *      that use `ArchController.owner()` for admin calls.
 */
contract MockArchControllerOwner {
  error AccountAlreadyAuthorized();
  error AccountNotAuthorized();
  error CannotRemoveFinalAuthorizedAccount();
  error InvalidInitialExecutors();
  error InvalidProtocolAction();
  error InvalidProtocolTarget();
  error NotAuthorized();
  error ZeroAddress();

  event AccountAuthorized(address indexed authorizer, address indexed account);
  event AccountDeauthorized(address indexed authorizer, address indexed account);
  event ProtocolActionExecuted(
    address indexed executor,
    address indexed target,
    bytes4 indexed selector
  );

  string public constant version = '2';

  WildcatArchController public immutable archController;

  mapping(address account => bool isAuthorized) public authorizedAccounts;
  mapping(address account => uint256 indexPlusOne) internal _authorizedAccountIndexPlusOne;
  address[] internal _authorizedAccountList;

  constructor(address archController_, address[] memory initialExecutors) {
    if (archController_ == address(0) || archController_.code.length == 0) {
      revert ZeroAddress();
    }
    if (initialExecutors.length == 0) revert InvalidInitialExecutors();

    archController = WildcatArchController(archController_);
    for (uint256 i; i < initialExecutors.length; i++) {
      address account = initialExecutors[i];
      if (account == address(0)) revert ZeroAddress();
      if (authorizedAccounts[account]) revert AccountAlreadyAuthorized();
      _authorizeAccount(msg.sender, account);
    }
  }

  modifier onlyAuthorized() {
    if (!authorizedAccounts[msg.sender]) revert NotAuthorized();
    _;
  }

  function getAuthorizedAccounts() external view returns (address[] memory) {
    return _authorizedAccountList;
  }

  function getAuthorizedAccountsCount() external view returns (uint256) {
    return _authorizedAccountList.length;
  }

  function authorizeAccount(address account) external onlyAuthorized {
    if (account == address(0)) revert ZeroAddress();
    if (authorizedAccounts[account]) revert AccountAlreadyAuthorized();
    _authorizeAccount(msg.sender, account);
  }

  function _authorizeAccount(address authorizer, address account) internal {
    authorizedAccounts[account] = true;
    _authorizedAccountIndexPlusOne[account] = _authorizedAccountList.length + 1;
    _authorizedAccountList.push(account);
    emit AccountAuthorized(authorizer, account);
  }

  function deauthorizeAccount(address account) external onlyAuthorized {
    if (!authorizedAccounts[account]) revert AccountNotAuthorized();
    uint256 length = _authorizedAccountList.length;
    if (length == 1) revert CannotRemoveFinalAuthorizedAccount();

    uint256 index = _authorizedAccountIndexPlusOne[account] - 1;
    uint256 lastIndex = length - 1;
    if (index != lastIndex) {
      address lastAccount = _authorizedAccountList[lastIndex];
      _authorizedAccountList[index] = lastAccount;
      _authorizedAccountIndexPlusOne[lastAccount] = index + 1;
    }
    _authorizedAccountList.pop();
    delete _authorizedAccountIndexPlusOne[account];
    delete authorizedAccounts[account];
    emit AccountDeauthorized(msg.sender, account);
  }

  /**
   * @dev lets an authorized executor take ownership back directly. mostly a
   *      recovery path, but the old scripts still use it too.
   */
  function returnOwnership() external onlyAuthorized {
    archController.transferOwnership(msg.sender);
  }

  /**
   * @dev borrower registration is intentionally permissionless on testnet; the
   *      SDK/frontend onboarding path still uses it. the helper needs to own
   *      the ArchController for this to work.
   */
  function registerBorrower(address borrower) external {
    archController.registerBorrower(borrower);
  }

  function registerBorrowers(address[] calldata borrowers) external {
    for (uint256 i; i < borrowers.length; i++) {
      archController.registerBorrower(borrowers[i]);
    }
  }

  /**
   * @dev keep the old V2 fee call working; the legacy controller factory still
   *      needs it.
   */
  function setProtocolFeeConfiguration(
    ILegacyWildcatMarketControllerFactory factory,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external onlyAuthorized {
    _executeProtocolAction(
      address(factory),
      abi.encodeCall(
        ILegacyWildcatMarketControllerFactory.setProtocolFeeConfiguration,
        (feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips)
      ),
      msg.sender
    );
  }

  /**
   * @dev runs one reviewed owner action through the helper so we don't have to
   *      hand the ArchController to an EOA.
   */
  function executeProtocolAction(
    address target,
    bytes calldata data
  ) external onlyAuthorized returns (bytes memory result) {
    result = _executeProtocolAction(target, data, msg.sender);
  }

  function _executeProtocolAction(
    address target,
    bytes memory data,
    address executor
  ) internal returns (bytes memory result) {
    if (data.length < 4) revert InvalidProtocolAction();
    _requireProtocolTarget(target);

    bytes4 selector;
    assembly {
      selector := mload(add(data, 0x20))
    }

    bool success;
    (success, result) = target.call(data);
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
    emit ProtocolActionExecuted(executor, target, selector);
  }

  function _requireProtocolTarget(address target) internal view {
    if (target == address(this) || target.code.length == 0) revert InvalidProtocolTarget();
    if (target == address(archController)) return;

    address engine = archController.sphereXEngine();
    if (engine != address(0) && target == engine) return;

    (bool success, bytes memory data) = target.staticcall(
      abi.encodeCall(IArchControllerBound.archController, ())
    );
    if (!success || data.length != 0x20) revert InvalidProtocolTarget();

    uint256 encodedArchController;
    assembly {
      encodedArchController := mload(add(data, 0x20))
    }
    if (encodedArchController != uint256(uint160(address(archController)))) {
      revert InvalidProtocolTarget();
    }
  }
}
