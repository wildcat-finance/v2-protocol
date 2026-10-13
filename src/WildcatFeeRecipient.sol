// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "./libraries/LibERC20.sol";

contract WildcatFeeRecipient {
    using LibERC20 for address;

    address public owner;
    address public recipient;

    error NotOwner();
    error NotOwnerOrRecipient();
    error NoETHInContract();
    error ETHTransferFailed();
    error NoERC20InContract();
    error InsufficientERC2OInContract();
    error CallFailed();

    event OwnerChanged(address, address);
    event RecipientChanged(address, address);
    event ETHTransferred(address, uint);
    event ERC20Transferred(address, address, uint);

    modifier isOwner() {
        if (msg.sender != owner) {
            revert NotOwner();
        }
        _;
    }

    modifier isRecipientOrOwner() {
        if (msg.sender != owner && msg.sender != recipient) {
            revert NotOwnerOrRecipient();
        }
        _;
    }

    constructor(address _owner, address _recipient) {
        owner = _owner;
        recipient = _recipient;
    }

    function changeOwner(address _newOwner) public isOwner {
        owner = _newOwner;
        emit OwnerChanged(msg.sender, _newOwner);
    }

    function changeRecipient(address _newRecipient) public isOwner {
        address oldRecipient = recipient;
        recipient = _newRecipient;
        emit RecipientChanged(oldRecipient, _newRecipient);
    }

    function releaseETH() public isRecipientOrOwner returns (bool) {
        uint toSend = address(this).balance;
        if (toSend == 0) {
            revert NoETHInContract();
        }
        address payable _recipient = payable(recipient);
        (bool success, ) = _recipient.call{value: toSend}("");
        if (!success) {
            revert ETHTransferFailed();
        }
        emit ETHTransferred(recipient, toSend);
        return true;
    }

    // Variant parameterised by amount
    function releaseETH(uint toSend) public isRecipientOrOwner returns (bool) {
        address payable _recipient = payable(recipient);
        (bool success, ) = _recipient.call{value: toSend}("");
        if (!success) {
            revert ETHTransferFailed();
        }
        emit ETHTransferred(recipient, toSend);
        return true;
    }

    function releaseERC20Fees(
        address asset
    ) public isRecipientOrOwner returns (bool) {
        uint toSend = asset.balanceOf(address(this));
        if (toSend == 0) {
            revert NoERC20InContract();
        }
        asset.safeTransfer(recipient, toSend);
        emit ERC20Transferred(address(this), recipient, toSend);
        return true;
    }

    // Variant parameterised by amount
    function releaseERC20Fees(
        address asset,
        uint toSend
    ) public isRecipientOrOwner returns (bool) {
        uint available = asset.balanceOf(address(this));
        if (toSend > available) {
            revert InsufficientERC2OInContract();
        }
        asset.safeTransfer(recipient, toSend);
        emit ERC20Transferred(address(this), recipient, toSend);
        return true;
    }

    // Execute an arbitrary call to handle any ERC20s with odd behavior
    function execute(
        address payable target,
        bytes memory data
    ) public payable isOwner {
        (bool success, ) = target.call{value: msg.value}(data);
        if (!success) {
            revert CallFailed();
        }
    }
}
