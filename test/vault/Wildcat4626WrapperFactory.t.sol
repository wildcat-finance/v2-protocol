// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';

import { Wildcat4626Wrapper, IWildcatMarketToken } from 'src/vault/Wildcat4626Wrapper.sol';
import { Wildcat4626WrapperFactory } from 'src/vault/Wildcat4626WrapperFactory.sol';
import { RAY } from 'src/libraries/MathUtils.sol';

contract StubSanctionsSentinel {
  function isSanctioned(address, address) external pure returns (bool) {
    return false;
  }
}

contract StubMarketToken is IWildcatMarketToken {
  string public constant name = 'Stub Market';
  string public constant symbol = 'stubUSDC';
  uint8 public constant override decimals = 18;

  uint256 public override scaleFactor = RAY;
  address public immutable override borrower;
  address public immutable override sentinel;
  bool internal immutable _declaresFloorRounding;

  mapping(address => uint256) internal _balances;
  mapping(address => mapping(address => uint256)) public override allowance;

  constructor(address borrower_, address sentinel_, bool declaresFloorRounding_) {
    borrower = borrower_;
    sentinel = sentinel_;
    _declaresFloorRounding = declaresFloorRounding_;
  }

  /// @dev v2.5+ markets declare their transfer rounding; legacy markets lack
  ///      the function entirely, which this stub emulates by reverting.
  function scaledTransferRounding() external view returns (bytes32) {
    if (!_declaresFloorRounding) revert('NO_SUCH_FUNCTION');
    return keccak256('scaleAmountDown');
  }

  function balanceOf(address account) public view override returns (uint256) {
    return _balances[account];
  }

  function totalSupply() external pure override returns (uint256) {
    return 0;
  }

  function scaledBalanceOf(address account) external view override returns (uint256) {
    return _balances[account];
  }

  function maxTotalSupply() external pure override returns (uint256) {
    return uint256(type(uint128).max);
  }

  function transfer(address, uint256) external pure override returns (bool) {
    revert('UNSUPPORTED');
  }

  function approve(address spender, uint256 amount) external override returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function transferFrom(address, address, uint256) external pure override returns (bool) {
    revert('UNSUPPORTED');
  }
}

contract StubArchController {
  mapping(address => bool) public isRegisteredMarket;

  function registerMarket(address market) external returns (bool) {
    isRegisteredMarket[market] = true;
  }
}

/// @dev Mirrors the deployed v1 factory's semantics: duplicate creates revert.
contract StubV1WrapperFactory {
  error WrapperAlreadyExists(address market);

  mapping(address => address) public wrapperForMarket;
  uint256 public createCalls;

  function seedWrapper(address market, address wrapper) external {
    wrapperForMarket[market] = wrapper;
  }

  function createWrapper(address market) external returns (address wrapper) {
    if (wrapperForMarket[market] != address(0)) revert WrapperAlreadyExists(market);
    createCalls++;
    wrapper = address(uint160(uint256(keccak256(abi.encode('v1-wrapper', market)))));
    wrapperForMarket[market] = wrapper;
  }
}

/// @dev Hostile probe targets for isFloorRoundingMarket totality.
contract ShortReturner {
  fallback() external {
    assembly {
      return(0, 0x10)
    }
  }
}

contract WrongValueReturner {
  function scaledTransferRounding() external pure returns (bytes32) {
    return keccak256('somethingElse');
  }
}

contract ReturnBomb {
  fallback() external {
    assembly {
      return(0, 0x1000000)
    }
  }
}

contract Wildcat4626WrapperFactoryTest is Test {
  Wildcat4626WrapperFactory internal factory;
  StubMarketToken internal market;
  StubArchController internal archController;
  StubSanctionsSentinel internal sanctionsSentinel;

  StubV1WrapperFactory internal v1Factory;

  address internal constant BORROWER = address(0xB0123);

  function setUp() external {
    archController = new StubArchController();
    v1Factory = new StubV1WrapperFactory();
    factory = new Wildcat4626WrapperFactory(address(archController), address(v1Factory));
    sanctionsSentinel = new StubSanctionsSentinel();
    market = new StubMarketToken(BORROWER, address(sanctionsSentinel), true);
    archController.registerMarket(address(market));
  }

  /// @dev Legacy (half-up) markets are forwarded to the v1 factory for both
  ///      creation and discovery (the equality against v1's own record proves
  ///      discovery reads through rather than resolving locally).
  function test_legacyMarketForwardsToV1Factory() external {
    StubMarketToken legacy = new StubMarketToken(BORROWER, address(sanctionsSentinel), false);
    archController.registerMarket(address(legacy));

    address wrapper = factory.createWrapper(address(legacy));
    assertEq(v1Factory.createCalls(), 1, 'v1 factory not called');
    assertEq(wrapper, v1Factory.wrapperForMarket(address(legacy)), 'forwarded wrapper mismatch');
    assertEq(
      factory.wrapperForMarket(address(legacy)),
      wrapper,
      'discovery should read through to v1'
    );
  }

  /// @dev Without a legacy factory configured, legacy markets are rejected
  ///      while the floor-rounding path is fully functional (fresh chains).
  function test_freshChainWithoutV1Factory() external {
    Wildcat4626WrapperFactory lonely = new Wildcat4626WrapperFactory(
      address(archController),
      address(0)
    );
    StubMarketToken legacy = new StubMarketToken(BORROWER, address(sanctionsSentinel), false);
    archController.registerMarket(address(legacy));

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.LegacyMarketsNotSupported.selector,
        address(legacy)
      )
    );
    lonely.createWrapper(address(legacy));
    assertEq(lonely.wrapperForMarket(address(legacy)), address(0), 'no wrapper expected');

    address wrapper = lonely.createWrapper(address(market));
    assertEq(lonely.wrapperForMarket(address(market)), wrapper, 'floor path should work');
  }

  /// @dev A future market generation declaring an unknown rounding must be
  ///      rejected, not silently forwarded to the half-up v1 factory.
  function test_unknownRoundingMarketRejected() external {
    WrongValueReturner future = new WrongValueReturner();
    archController.registerMarket(address(future));

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.UnsupportedMarketRounding.selector,
        address(future),
        keccak256('somethingElse')
      )
    );
    factory.createWrapper(address(future));
    assertEq(factory.wrapperForMarket(address(future)), address(0), 'no wrapper expected');
  }

  /// @dev A nonzero v1 address that is not a live wrapper factory must be
  ///      rejected at construction: it is frozen forever.
  function test_constructorRejectsBadV1Factory() external {
    vm.expectRevert(
      abi.encodeWithSelector(Wildcat4626WrapperFactory.InvalidV1Factory.selector, address(0xDEAD))
    );
    new Wildcat4626WrapperFactory(address(archController), address(0xDEAD));
  }

  /// @dev A mispaired wrapper sitting in the v1 registry for a floor-rounding
  ///      market must never resolve through this factory.
  function test_crossedV1WrapperIsQuarantined() external {
    v1Factory.seedWrapper(address(market), address(0xBAD));
    assertEq(
      factory.wrapperForMarket(address(market)),
      address(0),
      'crossed wrapper leaked through discovery'
    );

    address wrapper = factory.createWrapper(address(market));
    assertEq(factory.wrapperForMarket(address(market)), wrapper, 'local wrapper should win');
  }

  function test_isFloorRoundingMarket() external {
    assertTrue(factory.isFloorRoundingMarket(address(market)), 'floor market not detected');
    StubMarketToken legacy = new StubMarketToken(BORROWER, address(sanctionsSentinel), false);
    assertFalse(factory.isFloorRoundingMarket(address(legacy)), 'legacy market misdetected');
    assertFalse(factory.isFloorRoundingMarket(address(0xE0A0)), 'EOA misdetected');
    assertFalse(
      factory.isFloorRoundingMarket(address(new ShortReturner())),
      'short returndata misdetected'
    );
    assertFalse(
      factory.isFloorRoundingMarket(address(new WrongValueReturner())),
      'wrong rounding id misdetected'
    );
    assertFalse(
      factory.isFloorRoundingMarket(address(new ReturnBomb())),
      'returndata bomb misdetected'
    );
  }

  /// @dev Duplicate creates on the legacy path surface v1's own revert.
  function test_legacyDuplicateBubblesV1Revert() external {
    StubMarketToken legacy = new StubMarketToken(BORROWER, address(sanctionsSentinel), false);
    archController.registerMarket(address(legacy));
    factory.createWrapper(address(legacy));

    vm.expectRevert(
      abi.encodeWithSelector(StubV1WrapperFactory.WrapperAlreadyExists.selector, address(legacy))
    );
    factory.createWrapper(address(legacy));
  }

  function test_createWrapperDeploysAndRecords() external {
    address wrapperAddr = factory.createWrapper(address(market));

    assertEq(factory.wrapperForMarket(address(market)), wrapperAddr, 'wrapper recorded');
    assertEq(Wildcat4626Wrapper(wrapperAddr).asset(), address(market), 'wrapper asset');
  }

  function test_createWrapperRevertsIfExists() external {
    factory.createWrapper(address(market));

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.WrapperAlreadyExists.selector,
        address(market)
      )
    );
    factory.createWrapper(address(market));
  }

  function test_createWrapperRevertsIfNotRegisteredMarket() external {
    market = new StubMarketToken(BORROWER, address(sanctionsSentinel), true);

    vm.expectRevert(
      abi.encodeWithSelector(
        Wildcat4626WrapperFactory.NotRegisteredMarket.selector,
        address(market)
      )
    );
    factory.createWrapper(address(market));
  }

  function test_createWrapperRevertsOnZeroMarket() external {
    vm.expectRevert(Wildcat4626WrapperFactory.ZeroAddress.selector);
    factory.createWrapper(address(0));
  }
}
