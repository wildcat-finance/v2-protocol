# The Wildcat Protocol

Here's the code. Enjoy it.

For other bits and pieces:

### The Whitepaper

[https://tinyurl.com/wildcat-whitepaper](https://github.com/wildcat-finance/wildcat-whitepaper/blob/main/whitepaper_v1.0.pdf)

### The Manifesto

[https://tinyurl.com/wildcat-manifesto](https://medium.com/@wildcatprotocol/the-wildcat-manifesto-db23d4b9484d)

### The Documentation

[https://wildcat-protocol.gitbook.io](https://wildcat-protocol.gitbook.io/wildcat/)

### Notes on memory layout

When modifying any type definition, look for any place where the type is directly accessed in yul.

Most events and errors in this contract are emitted using custom emitter functions which rely on the specific order of parameters in the definition.

## Hooks

Wildcat Markets in v2 support hooks which can add additional behavior to the markets, such as handling access control or adding new features.

```solidity=
interface IHooks {
  function onDeposit(
    address lender,
    uint256 scaledAmount,
    uint256 scaleFactor,
    uint256 scaledTotalSupply,
    bytes calldata extraData
  ) external virtual;

  function onQueueWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external virtual;

  function onExecuteWithdrawal(
    address lender,
    uint32 withdrawalBatchExpiry,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external virtual;

  function onTransfer(
    address from,
    address to,
    uint scaledAmount,
    uint256 scaleFactor,
    bytes calldata extraData
  ) external virtual;

  function onBorrow(
    uint normalizedAmount,
    bytes calldata extraData
  ) external virtual;

  function onRepay(
    uint normalizedAmount,
    bytes calldata extraData
  ) external virtual;

  function onCloseMarket(bytes calldata extraData) external virtual;

  function onAssetsSentToEscrow(
    address lender,
    address escrow,
    uint scaledAmount,
    bytes calldata extraData
  ) external virtual;

  function onSetMaxTotalSupply(bytes calldata extraData) external virtual;

  function onSetAnnualInterestBips(bytes calldata extraData) external virtual;
}
```

### Example: Access Control

Restrict deposits to users manually approved or registered on Violet.
