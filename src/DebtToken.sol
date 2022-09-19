// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract DebtToken is ERC20 {

    address private owner;
    mapping(address => uint256) internal _timestamps;
    mapping(address => uint256) internal _receivedInterest;

    constructor() ERC20("Debt Token", "LDT") {
        owner = msg.sender;
    }

    function balanceOf(address account) public view virtual override returns(uint256) {
        return super.balanceOf(account) + _getInterest(account) - _receivedInterest[account];
    }

    function getLastInterest(address account) public view returns(uint256) {
        return _getInterest(account) - _receivedInterest[account];
    }

    function _getInterest(address account) internal view returns(uint256 interest) {
        uint256 accountBalance = interest = super.balanceOf(account);
        if (accountBalance == 0)
            return 0;

        uint256 times = (block.timestamp - _timestamps[account]) / 1 days;
        for (uint i = 0; i < times; ++i)
            interest += interest / 1000;
        interest -= accountBalance;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function mint(address account, uint256 amount) public onlyOwner {
        if (_timestamps[account] == 0)
            _timestamps[account] = block.timestamp;

        _mint(account, amount);
    }
    
    function burn(address account, uint256 amount) public onlyOwner {
        require(balanceOf(account) >= amount, "Lending: Over than your balances");

        _receivedInterest[account] += amount;
        uint256 interest = _getInterest(account);
        uint256 received = _receivedInterest[account];

        if (received >= interest) {
            uint256 repay = received - interest;
            _receivedInterest[account] = interest;

            _burn(account, repay);
        }

        uint256 accountBalance = super.balanceOf(account);
        if (accountBalance == 0) {
            _timestamps[account] = 0;
            _receivedInterest[account] = 0;
        }

    }

}