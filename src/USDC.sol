// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20 {

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {

    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

}