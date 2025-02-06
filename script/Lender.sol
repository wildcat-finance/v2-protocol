// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { Vm as ForgeVM } from 'forge-std/Vm.sol';
import { console } from 'forge-std/console.sol';
import 'solady/utils/LibString.sol';
import './LibDeployment.sol';
import './mock/MockERC20Factory.sol';
import 'src/market/WildcatMarket.sol';

using LibString for string;
using LibString for address;
using LibString for bytes;
using LibString for uint256;

struct Lender {
  address account;
  string label;
  string pvtKeyVarName;
  WildcatMarket market;
  MockERC20 underlying;
}
using LibLender for Lender global;

function buildLender(string memory label, address market) returns (Lender memory lender) {
  lender.label = label;
  address account = forgeVm.envOr(label, address(0));
  if (account == address(0)) {
    revert(string.concat('Account not found in environment variable ', label));
  }
  lender.account = account;
  lender.pvtKeyVarName = string.concat(label, '_PVT_KEY');
  lender.market = WildcatMarket(market);
  lender.underlying = MockERC20(lender.market.asset());
}

library LibLender {
  function broadcast(Lender memory self) internal {
    uint256 key = forgeVm.envOr(self.pvtKeyVarName, uint256(0));
    if (key == 0) {
      revert(string.concat('Private key not found in environment variable ', self.pvtKeyVarName));
    }
    forgeVm.broadcast(key);
  }

  function deposit(Lender memory self, uint256 amount) internal {
    self.broadcast();
    self.underlying.mint(self.account, amount);
    console.log(string.concat('Minted ', amount.toString(), ' to ', self.account.toHexString()));
    self.broadcast();
    self.underlying.approve(address(self.market), amount);
    console.log(
      string.concat(
        'Lender ',
        self.account.toHexString(),
        ' approved market for ',
        amount.toString()
      )
    );
    self.broadcast();
    self.market.deposit(amount);
    console.log(
      string.concat(
        'Lender ',
        self.account.toHexString(),
        ' deposited ',
        amount.toString(),
        ' into market'
      )
    );
  }

  function withdraw(Lender memory self, uint256 amount) internal {
    self.broadcast();
    self.market.queueWithdrawal(amount);
  }
}
