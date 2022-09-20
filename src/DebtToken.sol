// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DebtToken is ERC20 {

    address private owner;
    mapping(address => uint256) internal _principal;
    mapping(address => uint256) internal _timestamps;
    mapping(address => uint256) internal _updateTimestamps;
    
    address private _original;

    constructor(string memory name, string memory symbol, address original_) ERC20(name, symbol) {
        owner = msg.sender;
        _original = original_;
    }

    function original() public view returns (address) {
        return _original;
    }

    function principal(address account) public view returns (uint256) {
        return _principal[account];
    }

    function balanceOf(address account) public view virtual override returns(uint256) {
        uint256 times = (block.timestamp - _timestamps[account]) / 1 days;
        uint256 checked = (_updateTimestamps[account] - _timestamps[account]) / 1 days;

        uint balance = super.balanceOf(account);
        if (times <= checked)
            return balance;

        uint interest = balance;
        for (uint i = 0; i < times - checked; ++i)
            interest += interest / 1000;

        return interest;
    }

    function getLastInterest(address account) public view returns(uint256 interest) {
        return balanceOf(account) - principal(account);
    }

    function _updateBalance(address account) internal returns (uint256 balance) {
        balance = balanceOf(account);
        _updateTimestamps[account] = block.timestamp;
        _mint(account, balance - super.balanceOf(account));
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function mint(address account, uint256 amount) public onlyOwner {
        if (_timestamps[account] == 0)
            _timestamps[account] = _updateTimestamps[account] = block.timestamp;

        _principal[account] += amount;
        _mint(account, amount);
    }
    
    function burn(address account, uint256 amount) public onlyOwner {
        uint256 balance = _updateBalance(account);
        require(balance >= amount, "Lending: Over than your balances");

        _updateTimestamps[account] = block.timestamp;
        _mint(account, balance - super.balanceOf(account));

        uint256 last = balance - amount;
        if (last <= principal(account))
            _principal[account] = last;

        _burn(account, amount);

        if (last == 0) {
            _timestamps[account] = 0;
            _updateTimestamps[account] = 0;
        }

    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        super._beforeTokenTransfer(from, to, amount);
        if (from != address(0))
            _updateBalance(from);
    }
}