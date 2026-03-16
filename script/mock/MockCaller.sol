// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import { WildcatMarket } from '../../src/market/WildcatMarket.sol';

// contract MockCaller {
//   address internal immutable _caller;

//   constructor(address caller) {
//     _caller = caller;
//   }

//   modifier onlyCaller() {
//     if (msg.sender != _caller) revert();
//     _;
//   }

//   // function execute(address target, uint value, bytes memory data) public onlyCaller {
//   //
//   // }
//   function rescueTokens(address market, address token) external {
//     WildcatMarket(market).rescueTokens(token);
//   }

//   function borrow(address market, uint256 amount) external onlyCaller {
//     WildcatMarket(market).borrow(amount);
//   }

//   function forceBuyBack(
//     address market,
//     address lender,
//     uint256 normalizedAmount
//   ) external onlyCaller {
//     WildcatMarket(market).forceBuyBack(lender, normalizedAmount);
//   }

//   function _exec(bytes calldata callInfo) internal {
//     assembly {
//       let size := callInfo.length
//       if lt(size, 20) {
//         revert(0, 0)
//       }
//       let target := shr(96, calldataload(callInfo.offset))
//       let ptr := mload(64)
//       size := sub(size, 20)
//       calldatacopy(ptr, add(callInfo.offset, 20), size)

//       if iszero(call(gas(), target, 0, ptr, size, 0, 0)) {
//         returndatacopy(0, 0, returndatasize())
//         revert(0, returndatasize())
//       }
//     }
//   }
// }

// forceBuyBack
// closeMarket
// borrow
// rescueTokens
// setMaxTotalSupply
// setAnnualInterestAndReserveRatioBips
// nukeFromOrbit
