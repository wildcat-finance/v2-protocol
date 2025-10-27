// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {IERC20Metadata} from "openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

import {ReentrancyGuard} from "../ReentrancyGuard.sol";
import {MathUtils, RAY} from "../libraries/MathUtils.sol";
import {LibERC20} from "../libraries/LibERC20.sol";

interface IWildcatMarketToken is IERC20Metadata {
    function scaleFactor() external view returns (uint256);

    function scaledBalanceOf(address account) external view returns (uint256);
}

contract Wildcat4626Wrapper is ERC20, ReentrancyGuard {
    using MathUtils for uint256;
    using LibERC20 for address;

    error ZeroAddress();
    error ZeroAssets();
    error ZeroShares();
    error CapExceeded();
    error NotOwner();
    error SharesMismatch(uint256 expected, uint256 actual);

    IWildcatMarketToken public immutable wrappedMarket;
    address public owner;
    uint256 public wrapperCap;

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    event OwnerUpdated(address indexed newOwner);
    event WrapperCapUpdated(uint256 newCap);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    constructor(address marketAddress, string memory name_, string memory symbol_, address owner_) {
        if (marketAddress == address(0) || owner_ == address(0)) revert ZeroAddress();

        wrappedMarket = IWildcatMarketToken(marketAddress);
        owner = owner_;
        wrapperCap = type(uint256).max;

        _name = name_;
        _symbol = symbol_;
        _decimals = wrappedMarket.decimals();
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // -------------------------------------------------------------------------
    // ERC20 metadata
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
    // Admin
    // -------------------------------------------------------------------------

    function setOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    function setWrapperCap(uint256 newCap) external onlyOwner {
        wrapperCap = newCap;
        emit WrapperCapUpdated(newCap);
    }

    // -------------------------------------------------------------------------
    // ERC4626 view interface
    // -------------------------------------------------------------------------

    function asset() public view returns (address) {
        return address(wrappedMarket);
    }

    function totalAssets() public view returns (uint256) {
        return wrappedMarket.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        if (assets == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor(); // do i need to call a market update function to proc scaleFactor?
        return _convertToShares(assets, scaleFactor);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        if (shares == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToAssets(shares, scaleFactor);
    }

    function maxDeposit(address) public view returns (uint256) {
        uint256 cap = wrapperCap;
        if (cap == type(uint256).max) return cap;
        uint256 held = totalAssets();
        if (held >= cap) return 0;
        return cap - held;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function maxMint(address) public view returns (uint256) {
        uint256 capAssets = maxDeposit(address(0));
        if (capAssets == type(uint256).max) return capAssets;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToShares(capAssets, scaleFactor);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        if (shares == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _assetsForShares(shares, scaleFactor);
    }

    function maxWithdraw(address owner_) public view returns (uint256) {
        uint256 shares = balanceOf(owner_);
        if (shares == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToAssets(shares, scaleFactor);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        if (assets == 0) return 0;
        uint256 scaleFactor = wrappedMarket.scaleFactor();
        return _convertToShares(assets, scaleFactor);
    }

    function maxRedeem(address owner_) public view returns (uint256) {
        return balanceOf(owner_);
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    // -------------------------------------------------------------------------
    // Mutating interface
    // -------------------------------------------------------------------------

    function deposit(uint256 assets, address receiver) external nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAssets();

        uint256 limit = maxDeposit(receiver);
        if (assets > limit) revert CapExceeded();

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        uint256 expectedShares = _convertToShares(assets, scaleFactor);
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

    function mint(uint256 shares, address receiver) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();

        uint256 limit = maxMint(receiver);
        if (shares > limit) revert CapExceeded();

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        assets = _assetsForShares(shares, scaleFactor);
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

    function withdraw(uint256 assets, address receiver, address owner_)
        external
        nonReentrant
        returns (uint256 shares)
    {
        if (assets == 0) revert ZeroAssets();

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        shares = _convertToShares(assets, scaleFactor);
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

    function redeem(uint256 shares, address receiver, address owner_) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroShares();

        if (msg.sender != owner_) {
            _spendAllowance(owner_, msg.sender, shares);
        }

        uint256 scaleFactor = wrappedMarket.scaleFactor();
        assets = _convertToAssets(shares, scaleFactor);
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

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _convertToShares(uint256 assets, uint256 scaleFactor) internal pure returns (uint256) {
        return assets.rayDiv(scaleFactor);
    }

    function _convertToAssets(uint256 shares, uint256 scaleFactor) internal pure returns (uint256) {
        return shares.rayMul(scaleFactor);
    }

    function _assetsForShares(uint256 shares, uint256 scaleFactor) internal pure returns (uint256) {
        if (shares == 0) return 0;

        uint256 assets = MathUtils.mulDiv(shares, scaleFactor, RAY);
        if (assets.rayDiv(scaleFactor) < shares) {
            assets += 1;
        }

        return assets;
    }
}
