// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "./TransferHelper.sol";

contract Airdrop is Ownable, ReentrancyGuard {
    IERC20 public token;
    uint256 public preset_amount;

    constructor(IERC20 _token) {
        token = _token;
    }

    function airdrop(address[] calldata _recipients, uint256[] calldata _amounts) external onlyOwner nonReentrant {
        require(_recipients.length == _amounts.length, "Airdrop: Invalid input");
        for (uint256 i = 0; i < _recipients.length; i++) {
            TransferHelper.safeTransfer(address(token), _recipients[i], _amounts[i]);
        }
    }

    function airdropPreset(address[] calldata _recipients) external onlyOwner nonReentrant {
        for (uint256 i = 0; i < _recipients.length; i++) {
            TransferHelper.safeTransfer(address(token), _recipients[i], preset_amount);
        }
    }

    function setPresetAmount(uint256 _amount) external onlyOwner {
        preset_amount = _amount;
    }

    function withdraw(address _token, address _to, uint256 _amount) external onlyOwner nonReentrant {
        TransferHelper.safeTransfer(_token, _to, _amount);
    }
}