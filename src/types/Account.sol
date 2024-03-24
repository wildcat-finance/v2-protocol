// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

struct Account {
  bool hasEverDeposited;
  bool isAuthorized;
  uint32 expiry;
  uint104 scaledBalance;
}
