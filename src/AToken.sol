// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract AToken is ERC20 {

    address private owner;
    address[] private _userList;
    mapping(address => bool) private _added;
    mapping(address => bool) private _liquidate;
    mapping(address => bool) private _guarantee;

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
        _mint(account, amount);
    }

    function updateInterest(uint256 interest) public onlyOwner {
        for (uint256 i = 0; i < _userList.length; ++i) {
            address account = _userList[i];
            uint256 amount = interest * balanceOf(account) / totalSupply();
            _mint(account, amount);
        }
    }

    function burn(address account, uint256 amount) public onlyOwner {
        _burn(account, amount);
    }

    function setLiquidate(address account, bool state) public onlyOwner {
        _liquidate[account] = state;
    }

    function liquidate(address account) public view returns (bool) {
        return _liquidate[account];
    }

    function setGuarantee(address account, bool state) public onlyOwner {
        _guarantee[account] = state;
    }

    function guarantee(address account) public view returns (bool) {
        return _guarantee[account];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        super._beforeTokenTransfer(from, to, amount);

        if (to != address(0)) {
            require(!(_guarantee[from] || _liquidate[from]), "AToken: Guanteed or Liquidated");

            if (!_added[to]) {
                _added[to] = true;
                _userList.push(to);
            }
        }

    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        super._afterTokenTransfer(from, to, amount);
        
        if (balanceOf(from) == 0) {
            _added[from] = false;
            for (uint i = 0; i < _userList.length; ++i) {
                if (_userList[i] == from) {
                    _userList[i] = _userList[_userList.length - 1];
                    _userList.pop();
                }
            }
        }
    }


}