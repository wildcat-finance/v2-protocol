import './access/IHooks.sol';
import './interfaces/WildcatStructsAndEnums.sol';

interface IHooksFactory {
  /// @dev Add a hooks template contract that stores the initcode for an approved hooks template
  ///      Only callable by the owner
  function addHooksConstructorTemplate(address hooksInitCodeStorage) external;

  /// @dev Deploy a hooks instance for an approved template with constructor args.
  ///      Callable by approved borrowers on the arch-controller.
  function deployHooks(
    address hooksConstructor,
    bytes calldata constructorArgs
  ) external returns (address hooksDeployment);

  /// @dev Deploy a market with an existing hooks deployment (in `parameters.hooks`)
  ///      Will call `onCreateMarket` on `parameters.hooks`.
  function deployMarket(MarketParameters memory parameters) external returns (address market);

  /// @dev Deploy a hooks instance for an approved template with constructor args,
  ///      then deploy a new market with that deployment as its hooks contract.
  ///      Will call `onCreateMarket` on `parameters.hooks`.
  function deployMarketAndHooks(
    MarketParameters memory parameters,
    address hooksConstructor,
    bytes calldata constructorArgs
  ) external returns (address market, address hooks);
}
