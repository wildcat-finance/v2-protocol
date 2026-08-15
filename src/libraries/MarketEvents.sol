// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

uint256 constant InterestAndFeesAccrued_abi_head_size = 0xc0;
uint256 constant InterestAndFeesAccrued_toTimestamp_offset = 0x20;
uint256 constant InterestAndFeesAccrued_scaleFactor_offset = 0x40;
uint256 constant InterestAndFeesAccrued_baseInterestRay_offset = 0x60;
uint256 constant InterestAndFeesAccrued_delinquencyFeeRay_offset = 0x80;
uint256 constant InterestAndFeesAccrued_protocolFees_offset = 0xa0;

function emit_Transfer(address from, address to, uint256 value) {
  assembly {
    mstore(0, value)
    log3(0, 0x20, 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef, from, to)
  }
}

function emit_Approval(address owner, address spender, uint256 value) {
  assembly {
    mstore(0, value)
    log3(
      0,
      0x20,
      0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925,
      owner,
      spender
    )
  }
}

function emit_MaxTotalSupplyUpdated(
  address eventCaller,
  uint256 previousMaxTotalSupply,
  uint256 newMaxTotalSupply
) {
  assembly {
    mstore(0, previousMaxTotalSupply)
    mstore(0x20, newMaxTotalSupply)
    log2(
      0,
      0x40,
      0xd017ca3aaecec8f5f194aa734b4f62d6a43d6a273268b625de051c3b692a2c6e,
      eventCaller
    )
  }
}

function emit_ProtocolFeeBipsUpdated(
  address eventCaller,
  uint256 previousProtocolFeeBips,
  uint256 newProtocolFeeBips
) {
  assembly {
    mstore(0, previousProtocolFeeBips)
    mstore(0x20, newProtocolFeeBips)
    log2(
      0,
      0x40,
      0x54f104211bc2c1b4b49e83767e54234a36150ee5cbf00a5516a19e7a5026c509,
      eventCaller
    )
  }
}

function emit_AnnualInterestAndReserveRatioBipsUpdated(
  address eventCaller,
  uint256 previousAnnualInterestBips,
  uint256 newAnnualInterestBips,
  uint256 previousReserveRatioBips,
  uint256 newReserveRatioBips
) {
  assembly {
    let dst := mload(0x40)
    mstore(dst, previousAnnualInterestBips)
    mstore(add(dst, 0x20), newAnnualInterestBips)
    mstore(add(dst, 0x40), previousReserveRatioBips)
    mstore(add(dst, 0x60), newReserveRatioBips)
    log2(
      dst,
      0x80,
      0xe829464a47e4f00b1c8c879651d6d9f8238513fdd4721d8f8a0a93531a939e80,
      eventCaller
    )
  }
}

function emit_SanctionedAccountAssetsQueuedForWithdrawal(
  address account,
  uint32 expiry,
  uint256 scaledAmount,
  uint256 normalizedAmount
) {
  assembly {
    let freePointer := mload(0x40)
    mstore(0, expiry)
    mstore(0x20, scaledAmount)
    mstore(0x40, normalizedAmount)
    log2(0, 0x60, 0xe12b220b92469ae28fb0d79de531f94161431be9f073b96b8aad3effb88be6fa, account)
    mstore(0x40, freePointer)
  }
}

function emit_Deposit(address account, uint256 assetAmount, uint256 scaledAmount) {
  assembly {
    mstore(0, assetAmount)
    mstore(0x20, scaledAmount)
    log2(0, 0x40, 0x90890809c654f11d6e72a28fa60149770a0d11ec6c92319d6ceb2bb0a4ea1a15, account)
  }
}

function emit_Borrow(address borrower, uint256 assetAmount) {
  assembly {
    mstore(0, assetAmount)
    log2(0, 0x20, 0xcbc04eca7e9da35cb1393a6135a199ca52e450d5e9251cbd99f7847d33a36750, borrower)
  }
}

function emit_DebtRepaid(address from, uint256 assetAmount) {
  assembly {
    mstore(0, assetAmount)
    log2(0, 0x20, 0xe8b606ac1e5df7657db58d297ca8f41c090fc94c5fd2d6958f043e41736e9fa6, from)
  }
}

function emit_DrawnAmountUpdated(uint256 previousDrawnAmount, uint256 newDrawnAmount) {
  assembly {
    mstore(0, previousDrawnAmount)
    mstore(0x20, newDrawnAmount)
    log1(0, 0x40, 0x2ce2176519c2ba0775d24b5f484690a4c3cf808f45a5a9094bf065d9ad59c0f9)
  }
}

function emit_MarketClosed(address borrower, uint256 _timestamp) {
  assembly {
    mstore(0, _timestamp)
    log2(0, 0x20, 0xcd125386a57ad5c51057dd568605a0a6854d06095d7d414e8ac65bcbf288e4eb, borrower)
  }
}

function emit_FeesCollected(address collector, address feeRecipient, uint256 assets) {
  assembly {
    mstore(0, assets)
    log3(
      0,
      0x20,
      0x9bcb6d1f38f6800906185471a11ede9a8e16200853225aa62558db6076490f2d,
      collector,
      feeRecipient
    )
  }
}

function emit_StateUpdated(uint256 scaleFactor, bool isDelinquent) {
  assembly {
    mstore(0, scaleFactor)
    mstore(0x20, isDelinquent)
    log1(0, 0x40, 0x9385f9ff65bcd2fb81cece54b27d4ec7376795fc4dcff686e370e347b0ed86c0)
  }
}

function emit_InterestAndFeesAccrued(
  uint256 fromTimestamp,
  uint256 toTimestamp,
  uint256 scaleFactor,
  uint256 baseInterestRay,
  uint256 delinquencyFeeRay,
  uint256 protocolFees
) {
  assembly {
    let dst := mload(0x40)
    /// Copy fromTimestamp
    mstore(dst, fromTimestamp)
    /// Copy toTimestamp
    mstore(add(dst, InterestAndFeesAccrued_toTimestamp_offset), toTimestamp)
    /// Copy scaleFactor
    mstore(add(dst, InterestAndFeesAccrued_scaleFactor_offset), scaleFactor)
    /// Copy baseInterestRay
    mstore(add(dst, InterestAndFeesAccrued_baseInterestRay_offset), baseInterestRay)
    /// Copy delinquencyFeeRay
    mstore(add(dst, InterestAndFeesAccrued_delinquencyFeeRay_offset), delinquencyFeeRay)
    /// Copy protocolFees
    mstore(add(dst, InterestAndFeesAccrued_protocolFees_offset), protocolFees)
    log1(
      dst,
      InterestAndFeesAccrued_abi_head_size,
      0x18247a393d0531b65fbd94f5e78bc5639801a4efda62ae7b43533c4442116c3a
    )
  }
}

function emit_BorrowerTransferRequested(
  address borrower,
  address previousPendingBorrower,
  address pendingBorrower,
  address borrowerPrincipal,
  address previousPendingBorrowerPrincipal,
  address pendingBorrowerPrincipal
) {
  assembly {
    // An EVM event is split between topics and ordinary data. Topic zero is the
    // event signature hash. The three indexed borrower addresses fill the other
    // three topics, while the principal addresses are ABI-encoded in memory.
    //
    // Memory from 0x00 through 0x3f is scratch space, but 0x40 normally holds
    // Solidity's free-memory pointer. This event needs three words, so save that
    // pointer before borrowing its slot and put it back when the log is written.
    let freePointer := mload(0x40)
    mstore(0, borrowerPrincipal)
    mstore(0x20, previousPendingBorrowerPrincipal)
    mstore(0x40, pendingBorrowerPrincipal)
    // `log4(offset, size, topic0, topic1, topic2, topic3)` reads the three
    // non-indexed values from memory 0x00 through 0x5f.
    log4(
      0,
      0x60,
      0x52a27a931945087c237eb781de9ec1bd1328a944b2ce031b914ed4ac5ce2ae47,
      borrower,
      previousPendingBorrower,
      pendingBorrower
    )
    mstore(0x40, freePointer)
  }
}

function emit_BorrowerTransferCancelled(
  address borrower,
  address cancelledPendingBorrower,
  address borrowerPrincipal,
  address cancelledPendingBorrowerPrincipal
) {
  assembly {
    // This event has two indexed values, so `log3` carries the signature hash
    // plus those two addresses as topics. The two principal addresses are the
    // ordinary event data, laid out as two 32-byte ABI words in scratch memory.
    mstore(0, borrowerPrincipal)
    mstore(0x20, cancelledPendingBorrowerPrincipal)
    log3(
      0,
      0x40,
      0x845fafbf05c3dba243e654ea4d739f09ec145e9d8c0d24cc8859eedcbd121889,
      borrower,
      cancelledPendingBorrower
    )
  }
}

function emit_BorrowerTransferred(
  address previousBorrower,
  address newBorrower,
  address previousBorrowerPrincipal,
  address newBorrowerPrincipal
) {
  assembly {
    // `newBorrowerPrincipal` is indexed here, so it belongs in a topic rather
    // than the data buffer. That leaves only `previousBorrowerPrincipal` in
    // memory. `log4` then writes the signature hash and all three indexed fields.
    mstore(0, previousBorrowerPrincipal)
    log4(
      0,
      0x20,
      0x933b680a96769adaa385bb12d51347d449bd0e14defe462185eb094f62bc6628,
      previousBorrower,
      newBorrower,
      newBorrowerPrincipal
    )
  }
}

function emit_WithdrawalBatchExpired(
  uint256 expiry,
  uint256 scaledTotalAmount,
  uint256 scaledAmountBurned,
  uint256 normalizedAmountPaid
) {
  assembly {
    let freePointer := mload(0x40)
    mstore(0, scaledTotalAmount)
    mstore(0x20, scaledAmountBurned)
    mstore(0x40, normalizedAmountPaid)
    log2(0, 0x60, 0x9262dc39b47cad3a0512e4c08dda248cb345e7163058f300bc63f56bda288b6e, expiry)
    mstore(0x40, freePointer)
  }
}

function emit_WithdrawalBatchCreated(uint256 expiry) {
  assembly {
    log2(0, 0x00, 0x5c9a946d3041134198ebefcd814de7748def6576efd3d1b48f48193e183e89ef, expiry)
  }
}

function emit_WithdrawalBatchClosed(uint256 expiry) {
  assembly {
    log2(0, 0x00, 0xcbdf25bf6e096dd9030d89bb2ba2e3e7adb82d25a233c3ca3d92e9f098b74e55, expiry)
  }
}

function emit_WithdrawalBatchPayment(
  uint256 expiry,
  uint256 scaledAmountBurned,
  uint256 normalizedAmountPaid
) {
  assembly {
    mstore(0, scaledAmountBurned)
    mstore(0x20, normalizedAmountPaid)
    log2(0, 0x40, 0x5272034725119f19d7236de4129fdb5093f0dcb80282ca5edbd587df91d2bd89, expiry)
  }
}

function emit_WithdrawalQueued(
  uint256 expiry,
  address account,
  uint256 scaledAmount,
  uint256 normalizedAmount
) {
  assembly {
    mstore(0, scaledAmount)
    mstore(0x20, normalizedAmount)
    log3(
      0,
      0x40,
      0xecc966b282a372469fa4d3e497c2ac17983c3eaed03f3f17c9acf4b15591663e,
      expiry,
      account
    )
  }
}

function emit_WithdrawalExecuted(uint256 expiry, address account, uint256 normalizedAmount) {
  assembly {
    mstore(0, normalizedAmount)
    log3(
      0,
      0x20,
      0xd6cddb3d69146e96ebc2c87b1b3dd0b20ee2d3b0eadf134e011afb434a3e56e6,
      expiry,
      account
    )
  }
}

function emit_SanctionedAccountWithdrawalSentToEscrow(
  address account,
  address escrow,
  uint32 expiry,
  uint256 amount
) {
  assembly {
    let freePointer := mload(0x40)
    mstore(0, escrow)
    mstore(0x20, expiry)
    mstore(0x40, amount)
    log2(0, 0x60, 0x0d0843a0fcb8b83f625aafb6e42f234ac48c6728b207d52d97cfa8fbd34d498f, account)
    mstore(0x40, freePointer)
  }
}
