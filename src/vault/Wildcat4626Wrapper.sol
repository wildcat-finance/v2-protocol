// SPDX-License-Identifier: Apache-2.0 WITH LicenseRef-Commons-Clause-1.0
pragma solidity >=0.8.20;

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {IERC20Metadata} from "openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "../ReentrancyGuard.sol";
import {MathUtils, RAY} from "../libraries/MathUtils.sol";
import {LibERC20} from "../libraries/LibERC20.sol";

interface IWildcatMarketToken is IERC20Metadata {
    function scaleFactor() external view returns (uint256);

    function scaledBalanceOf(address account) external view returns (uint256);

    function borrower() external view returns (address);

    function maxTotalSupply() external view returns (uint256);
}

/**
 * @title Wildcat4626Wrapper
 * @notice Wraps a debt token with an erc-4626 non-rebasing share token.
 *  Shares mirror the market's scaled balance. 
 */
contract Wildcat4626Wrapper is ERC4626, ReentrancyGuard {
    using MathUtils for uint256;
    using LibERC20 for address;

    error ZeroAddress();
    error ZeroAssets();
    error ZeroShares();
    error CapExceeded();
    error SharesMismatch(uint256 expected, uint256 actual);
    error NotMarketOwner();
    error CannotSweepMarketAsset();

    IWildcatMarketToken public immutable wrappedMarket;
    address public immutable marketOwner;

    uint8 private immutable _decimals;
    string private _name;
    string private _symbol;

    /**
     * @param marketAddress the wildcat market (debt token) address to wrap
     */
    constructor(address marketAddress) {
        if (marketAddress == address(0)) revert ZeroAddress();

        wrappedMarket = IWildcatMarketToken(marketAddress);
        address owner = wrappedMarket.borrower();
        if (owner == address(0)) revert ZeroAddress();
        marketOwner = owner;
        _decimals = wrappedMarket.decimals();

        string memory marketSymbol = IERC20Metadata(marketAddress).symbol();
        _name = string.concat(marketSymbol, " [4626 Vault Shares]");
        _symbol = string.concat("v-", marketSymbol);
    }

    // -------------------------------------------------------------------------
    // ERC20 Metadata
    // -------------------------------------------------------------------------

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // -------------------------------------------------------------------------
    // ERC4626 Configuration Overrides
    // -------------------------------------------------------------------------

    /// @dev disabled virtual shares since we use the market's scale factor for conversions
    function _useVirtualShares() internal pure override returns (bool) {
        return false;
    }

    function _underlyingDecimals() internal view override returns (uint8) {
        return _decimals;
    }

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event TokensSwept(address indexed token, address indexed to, uint256 amount);

    // -------------------------------------------------------------------------
    // ERC4626 View Interface
    // -------------------------------------------------------------------------

    /// @notice Address of the wrapped Wildcat market token.
    function market() public view returns (address) {
        return address(wrappedMarket);
    }

    /// @notice Alias for the wrapped market so integrators can treat it as the ERC-4626 asset.
    function asset() public view override returns (address) {
        return address(wrappedMarket);
    }

    /// @notice Total normalized market tokens the wrapper currently custodies.
    function totalAssets() public view override returns (uint256) {
        return wrappedMarket.balanceOf(address(this));
    }

    /// @notice Preview how many shares a deposit of `assets` would mint, rounded down.
    function convertToShares(uint256 assets) public view override returns (uint256) {
        if (assets == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToSharesDown(assets, scaleFactor);
    }

    /// @notice Preview how many assets burning `shares` yields, rounded down.
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        if (shares == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToAssetsDown(shares, scaleFactor);
    }

    /// @notice Remaining normalized assets the wrapper can accept before hitting the market's maxTotalSupply.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 marketCap = wrappedMarket.maxTotalSupply();
        uint256 held = totalAssets();
        if (held >= marketCap) return 0;
        return marketCap - held;
    }

    /// @notice Shares minted for depositing `assets`, rounded down.
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    /// @notice Remaining shares that could be minted without violating the market's maxTotalSupply.
    function maxMint(address) public view override returns (uint256) {
        uint256 capAssets = maxDeposit(address(0));
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToSharesDown(capAssets, scaleFactor);
    }

    /// @notice Assets required to mint `shares`, rounded up so callers see worst-case cost.
    function previewMint(uint256 shares) public view override returns (uint256) {
        if (shares == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToAssetsUp(shares, scaleFactor);
    }

    /// @notice Maximum assets `owner_` can pull via `withdraw`, rounded down.
    function maxWithdraw(address owner_) public view override returns (uint256) {
        uint256 shares = balanceOf(owner_);
        if (shares == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToAssetsDown(shares, scaleFactor);
    }

    /// @notice Shares that would be burned to withdraw `assets`, rounded up.
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        if (assets == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToSharesUp(assets, scaleFactor);
    }

    /// @notice All shares `owner_` currently holds.
    function maxRedeem(address owner_) public view override returns (uint256) {
        return balanceOf(owner_);
    }

    /// @notice Assets returned when redeeming `shares`, rounded down.
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Returns the current exchange rate of assets per share, scaled by RAY (1e27).
    /// @dev This is equivalent to the market's scale factor. Useful for integrators to see
    ///      the exchange rate without needing to pick a sample share size.
    function assetsPerShareRay() external view returns (uint256) {
        return wrappedMarket.scaleFactor();
    }

    /// @notice Returns the current exchange rate of shares per asset, scaled by RAY (1e27).
    /// @dev This is the inverse of the scale factor to see
    ///      how many shares a given asset amount would yield.
    function sharesPerAssetRay() external view returns (uint256) {
        return MathUtils.mulDiv(RAY, RAY, wrappedMarket.scaleFactor());
    }

    // -------------------------------------------------------------------------
    // Mutating Interface
    // -------------------------------------------------------------------------

    /// @notice Pull `assets` from the caller and mint the resulting shares to `receiver`.
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();

        uint256 limit = maxDeposit(receiver);
        if (assets > limit) revert CapExceeded();

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        uint256 expectedShares = _convertToSharesHalfUp(assets, scaleFactor);
        if (expectedShares == 0) revert ZeroShares();

        address assetAddress = address(wrappedMarket);
        uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));
        assetAddress.safeTransferFrom(msg.sender, address(this), assets);
        uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

        shares = scaledAfter - scaledBefore;
        if (shares != expectedShares) revert SharesMismatch(expectedShares, shares);

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Mint exactly `shares` to `receiver`, charging the caller the required assets (rounded up).
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();

        uint256 limit = maxMint(receiver);
        if (shares > limit) revert CapExceeded();

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        assets = _convertToAssetsUp(shares, scaleFactor);
        if (assets == 0) revert ZeroAssets();

        address assetAddress = address(wrappedMarket);
        uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));
        assetAddress.safeTransferFrom(msg.sender, address(this), assets);
        uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

        uint256 mintedShares = scaledAfter - scaledBefore;
        if (mintedShares != shares) revert SharesMismatch(shares, mintedShares);

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Withdraw `assets` to `receiver`, burning shares from `owner_` (shares rounded up).
    function withdraw(uint256 assets, address receiver, address owner_)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAssets();

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        shares = _convertToSharesHalfUp(assets, scaleFactor);
        if (shares == 0) revert ZeroShares();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));

        _burn(owner_, shares);
        address assetAddress = address(wrappedMarket);
        assetAddress.safeTransfer(receiver, assets);
        uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

        uint256 burnedShares = scaledBefore - scaledAfter;
        if (burnedShares != shares) revert SharesMismatch(shares, burnedShares);
        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /// @notice Redeem `shares` from `owner_` and send the corresponding assets to `receiver` (assets rounded down).
    function redeem(uint256 shares, address receiver, address owner_)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (shares == 0) revert ZeroShares();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        assets = _convertToAssetsDown(shares, scaleFactor);
        if (assets == 0) revert ZeroAssets();

        uint256 scaledBefore = wrappedMarket.scaledBalanceOf(address(this));

        _burn(owner_, shares);
        address assetAddress = address(wrappedMarket);
        assetAddress.safeTransfer(receiver, assets);
        uint256 scaledAfter = wrappedMarket.scaledBalanceOf(address(this));

        uint256 burnedShares = scaledBefore - scaledAfter;
        if (burnedShares != shares) revert SharesMismatch(shares, burnedShares);

        emit Withdraw(msg.sender, receiver, owner_, assets, shares);
    }

    /// @notice sweep arbitrary erc20 balances (excluding the wrapped market's debt token)
    /// @dev only the underlying market's borrower may call this. util for any case where
    ///      non-market tokens somehow accrue to the wrapper.
    function sweep(address token, address to)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (msg.sender != marketOwner) revert NotMarketOwner();
        if (token == address(0) || to == address(0)) revert ZeroAddress();
        if (token == address(wrappedMarket)) revert CannotSweepMarketAsset();

        amount = LibERC20.balanceOf(token, address(this));
        if (amount == 0) revert ZeroAssets();

        token.safeTransfer(to, amount);
        emit TokensSwept(token, to, amount);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _convertToSharesDown(uint256 assets, uint256 scaleFactor) internal pure returns (uint256) {
        return MathUtils.mulDiv(assets, RAY, scaleFactor);
    }

    function _convertToSharesUp(uint256 assets, uint256 scaleFactor) internal pure returns (uint256) {
        return MathUtils.mulDivUp(assets, RAY, scaleFactor);
    }

    /// @dev half-up rounding to match the market's rayDiv behavior in transfers
    function _convertToSharesHalfUp(uint256 assets, uint256 scaleFactor) internal pure returns (uint256) {
        return (assets * RAY + scaleFactor / 2) / scaleFactor;
    }

    function _convertToAssetsDown(uint256 shares, uint256 scaleFactor) internal pure returns (uint256) {
        return MathUtils.mulDiv(shares, scaleFactor, RAY);
    }

    function _convertToAssetsUp(uint256 shares, uint256 scaleFactor) internal pure returns (uint256) {
        return MathUtils.mulDivUp(shares, scaleFactor, RAY);
    }
}
