// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract AToken is ERC20 {

    address private owner;
    address[] private _userList;
    mapping(address => bool) private _added;
    mapping(address => bool) private _state;
    mapping(address => bool) private liquidated;

    address private _original;

    constructor(string memory name, string memory symbol, address original_) ERC20(name, symbol) {
        owner = msg.sender;
        _original = original_;
    }

    function original() public view returns (address) {
        return _original;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function mint(address account, uint256 amount) public onlyOwner {
        if (!_added[account]) {
            _added[account] = true;
            _userList.push(account);
        }

        _state[account] = true;
        _mint(account, amount);
    }

    function updateInterest(uint256 interest) public onlyOwner {
        for (uint256 i = 0; i < _userList.length; ++i) {
            address account = _userList[i];
            if (!_state[account])
                continue;

            uint256 amount = interest * balanceOf(account) / totalSupply();
            _mint(account, amount);
        }
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
        if (balanceOf(account) == 0)
            _state[account] = false;
    }

    function setLiquidate(address account, bool state) public onlyOwner {
        liquidated[account] = state;
    }

    function liquidate(address account) public view returns (bool) {
        return liquidated[account];
    }

}