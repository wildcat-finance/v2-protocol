// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity 0.8.25;

import './WildcatMarketBase.sol';

/// @notice ERC-20-compatible normalized balance surface backed by scaled market shares.
contract WildcatMarketToken is WildcatMarketBase {
  using SafeCastLib for uint256;
  using FunctionTypeCasts for *;

  // ========================================================================== //
  //                                ERC20 Queries                               //
  // ========================================================================== //

  /// @notice normalized market-token allowance from owner to spender.
  mapping(address => mapping(address => uint256)) public allowance;

  /// @notice returns `account`'s normalized balance with interest accrued through this block.
  /// @param account lender whose direct market-token balance is queried.
  function balanceOf(address account) public view virtual nonReentrantView returns (uint256) {
    return
      _calculateCurrentStatePointers.asReturnsMarketState()().normalizeAmount(
        _accounts[account].scaledBalance
      );
  }

  /// @notice returns normalized supply with interest accrued through this block.
  function totalSupply() external view virtual nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().totalSupply();
  }

  // ========================================================================== //
  //                                ERC20 Actions                               //
  // ========================================================================== //

  /// @notice sets `spender`'s normalized allowance over the caller's market tokens.
  /// @param spender account allowed to spend the caller's tokens.
  /// @param amount new normalized allowance.
  /// @return always true when the approval succeeds.
  function approve(
    address spender,
    uint256 amount
  ) external virtual nonReentrant sphereXGuardExternal returns (bool) {
    _approve(msg.sender, spender, amount);
    return true;
  }

  /// @notice transfers up to `amount` normalized market tokens from the caller to `to`.
  /// @dev the moved scaled amount is rounded down. reverts if it is zero, balances are
  ///      insufficient, or the transfer hook rejects the transfer.
  /// @param to recipient of the scaled shares.
  /// @param amount normalized amount used to derive the scaled transfer.
  /// @return always true when the transfer succeeds.
  function transfer(
    address to,
    uint256 amount
  ) external virtual nonReentrant sphereXGuardExternal returns (bool) {
    _transfer(msg.sender, to, amount, 0x44);
    return true;
  }

  /// @notice transfers up to `amount` normalized market tokens using the caller's allowance.
  /// @dev the moved scaled amount is rounded down. infinite allowances aren't decremented.
  /// @param from owner of the scaled shares and allowance.
  /// @param to recipient of the scaled shares.
  /// @param amount normalized amount charged to allowance and used to derive the scaled transfer.
  /// @return always true when the transfer succeeds.
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external virtual nonReentrant sphereXGuardExternal returns (bool) {
    uint256 allowed = allowance[from][msg.sender];

    // Saves gas for unlimited approvals.
    if (allowed != type(uint256).max) {
      uint256 newAllowance = allowed - amount;
      _approve(from, msg.sender, newAllowance);
    }

    _transfer(from, to, amount, 0x64);

    return true;
  }

  function _approve(address approver, address spender, uint256 amount) internal virtual {
    allowance[approver][spender] = amount;
    emit_Approval(approver, spender, amount);
  }

  function _transfer(
    address from,
    address to,
    uint256 amount,
    uint baseCalldataSize
  ) internal virtual {
    MarketState memory state = _getUpdatedState();
    uint104 scaledAmount = state.scaleAmountDown(amount).toUint104();

    if (scaledAmount == 0) revert_NullTransferAmount();

    hooks.onTransfer(from, to, scaledAmount, state, baseCalldataSize);

    Account memory fromAccount = _getAccount(from);
    fromAccount.scaledBalance -= scaledAmount;
    _accounts[from] = fromAccount;

    Account memory toAccount = _getAccount(to);
    toAccount.scaledBalance += scaledAmount;
    _accounts[to] = toAccount;

    _writeState(state);
    emit_Transfer(from, to, amount);
  }
}
