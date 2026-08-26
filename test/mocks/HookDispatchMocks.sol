// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IHooks } from 'src/access/IHooks.sol';
import { HooksTemplate } from 'src/IHooksFactory.sol';
import { MarketState } from 'src/libraries/MarketState.sol';
import { MarketParameters } from 'src/interfaces/WildcatStructsAndEnums.sol';

contract HookDispatchArchControllerMock {
  function isRegisteredBorrower(address) external pure returns (bool) {
    return true;
  }
}

contract HookDispatchBorrowerRegistryMock {
  address public immutable archController;

  constructor(address archController_) {
    archController = archController_;
  }
}

contract HookDispatchSentinelMock {
  address public constant EscrowAddress = address(0xE5C0);

  mapping(address account => bool) public sanctioned;
  uint256 public createEscrowCalls;

  function setSanctioned(address account, bool value) external {
    sanctioned[account] = value;
  }

  function isSanctioned(address, address account) external view returns (bool) {
    return sanctioned[account];
  }

  function isFlaggedByChainalysis(address account) external view returns (bool) {
    return sanctioned[account];
  }

  function getEscrowAddress(address, address, address) external pure returns (address) {
    return EscrowAddress;
  }

  function createEscrow(address, address, address) external returns (address) {
    createEscrowCalls++;
    return EscrowAddress;
  }
}

contract HookDispatchFactoryMock {
  MarketParameters internal _parameters;
  address internal _lensHooksTemplate = address(0x7E4);
  uint256 internal _revolvingCommitmentFeeResponse = 500;
  uint256 internal _revolvingCommitmentFeeResponseSize = 32;
  bool internal _revolvingCommitmentFeeReverts;

  function setMarketParameters(MarketParameters calldata parameters) external {
    _parameters = parameters;
  }

  function getMarketParameters() external view returns (MarketParameters memory) {
    return _parameters;
  }

  function setLensHooksTemplate(address hooksTemplate) external {
    _lensHooksTemplate = hooksTemplate;
  }

  function getHooksTemplateForInstance(address) external view returns (address) {
    return _lensHooksTemplate;
  }

  function getHooksTemplateDetails(
    address hooksTemplate
  ) external view returns (HooksTemplate memory data) {
    data.exists = hooksTemplate == _lensHooksTemplate;
    data.enabled = data.exists;
    data.name = data.exists ? 'Fixture Hooks' : '';
  }

  function getMarketsForHooksTemplateCount(address hooksTemplate) external view returns (uint256) {
    return hooksTemplate == _lensHooksTemplate ? 1 : 0;
  }

  function getMarketsForHooksInstanceCount(address) external pure returns (uint256) {
    return 1;
  }

  function setRevolvingMarketCommitmentFeeResponse(
    uint256 response,
    uint256 responseSize,
    bool shouldRevert
  ) external {
    _revolvingCommitmentFeeResponse = response;
    _revolvingCommitmentFeeResponseSize = responseSize;
    _revolvingCommitmentFeeReverts = shouldRevert;
  }

  function getRevolvingMarketCommitmentFeeBips() external view returns (uint16) {
    uint256 response = _revolvingCommitmentFeeResponse;
    uint256 responseSize = _revolvingCommitmentFeeResponseSize;
    bool shouldRevert = _revolvingCommitmentFeeReverts;
    assembly ('memory-safe') {
      mstore(0, response)
      if shouldRevert {
        revert(0, responseSize)
      }
      return(0, responseSize)
    }
  }

  function deployMarket(bytes memory creationCode) external returns (address market) {
    assembly {
      market := create(0, add(creationCode, 0x20), mload(creationCode))
      if iszero(market) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
  }

  function callMarket(address market, bytes calldata data) external returns (bytes memory result) {
    bool success;
    (success, result) = market.call(data);
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
  }
}

contract HookDispatchMock {
  bytes[] internal _calls;
  bool internal _replaceAprAndReserveRatio;
  uint16 internal _annualInterestBips;
  uint16 internal _reserveRatioBips;

  function callCount() external view returns (uint256) {
    return _calls.length;
  }

  function callAt(uint256 index) external view returns (bytes memory) {
    return _calls[index];
  }

  function setAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips
  ) external {
    _replaceAprAndReserveRatio = true;
    _annualInterestBips = annualInterestBips;
    _reserveRatioBips = reserveRatioBips;
  }

  function onDeposit(
    address lender,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onDeposit.selector,
        lender,
        scaledAmount,
        intermediateState,
        extraData
      )
    );
  }

  function onQueueWithdrawal(
    address lender,
    uint32 expiry,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onQueueWithdrawal.selector,
        lender,
        expiry,
        scaledAmount,
        intermediateState,
        extraData
      )
    );
  }

  function onExecuteWithdrawal(
    address lender,
    uint32 expiry,
    uint128 normalizedAmountWithdrawn,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onExecuteWithdrawal.selector,
        lender,
        expiry,
        normalizedAmountWithdrawn,
        intermediateState,
        extraData
      )
    );
  }

  function onTransfer(
    address caller,
    address from,
    address to,
    uint256 scaledAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onTransfer.selector,
        caller,
        from,
        to,
        scaledAmount,
        intermediateState,
        extraData
      )
    );
  }

  function onBorrow(
    uint256 normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onBorrow.selector,
        normalizedAmount,
        intermediateState,
        extraData
      )
    );
  }

  function onRepay(
    uint256 normalizedAmount,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onRepay.selector,
        normalizedAmount,
        intermediateState,
        extraData
      )
    );
  }

  function onCloseMarket(
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(IHooks.onCloseMarket.selector, intermediateState, extraData)
    );
  }

  function onNukeFromOrbit(
    address lender,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(IHooks.onNukeFromOrbit.selector, lender, intermediateState, extraData)
    );
  }

  function onSetMaxTotalSupply(
    uint256 maxTotalSupply,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onSetMaxTotalSupply.selector,
        maxTotalSupply,
        intermediateState,
        extraData
      )
    );
  }

  function onSetAnnualInterestAndReserveRatioBips(
    uint16 annualInterestBips,
    uint16 reserveRatioBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external returns (uint16 updatedAnnualInterestBips, uint16 updatedReserveRatioBips) {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onSetAnnualInterestAndReserveRatioBips.selector,
        annualInterestBips,
        reserveRatioBips,
        intermediateState,
        extraData
      )
    );
    if (_replaceAprAndReserveRatio) return (_annualInterestBips, _reserveRatioBips);
    return (annualInterestBips, reserveRatioBips);
  }

  function onSetProtocolFeeBips(
    uint16 protocolFeeBips,
    MarketState calldata intermediateState,
    bytes calldata extraData
  ) external {
    _calls.push(
      abi.encodeWithSelector(
        IHooks.onSetProtocolFeeBips.selector,
        protocolFeeBips,
        intermediateState,
        extraData
      )
    );
  }
}
