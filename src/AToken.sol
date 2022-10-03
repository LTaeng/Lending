// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "../lib/forge-std/src/console2.sol";

contract AToken is ERC20 {

    address private owner;
    mapping(address => uint) private _guarantee;

    struct Tx {
        uint timestamp;
        uint price;
        uint totalSupply;
    }

    Tx[] txList;
    mapping(address => uint) private _appliedIdx;

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
        _appliedIdx[account] = txList.length;
    }

    function addInterestTx(uint timestamp, uint price) public onlyOwner {
        txList.push(Tx(timestamp, price, totalSupply()));
        _mint(owner, price);
    }

    function balanceOf(address account) public view virtual override returns(uint256) {
        uint balance = super.balanceOf(account);

        for (uint i = _appliedIdx[account]; i < txList.length; ++i) {
            Tx memory t = txList[i];
            balance += t.price * balance / t.totalSupply;
        }
        return balance;
    }


    function _updateBalance(address account) internal returns (uint256 balance) {
        balance = balanceOf(account);
        _appliedIdx[account] = txList.length;
        
        uint gap = balance - super.balanceOf(account);
        _burn(owner, gap);
        _mint(account, gap);
    }


    function burn(address account, uint256 amount) public onlyOwner {
        _updateBalance(account);
        _burn(account, amount);
    }

    function addGuarantee(address account, uint amount) public onlyOwner {
        _guarantee[account] += amount;
    }

    function resetGuarantee(address account) public onlyOwner {
        _guarantee[account] = 0;
    }

    function guarantee(address account) public view returns (uint) {
        return _guarantee[account];
    }

    function appliedIdx(address account) public view returns (uint) {
        return _appliedIdx[account];
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        super._beforeTokenTransfer(from, to, amount);

        if (from != address(0))
            require(balanceOf(from) - amount >= guarantee(from), "AToken: Over than guarantees");

        if (to != address(0) && from != address(0))
            _updateBalance(from);

    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual {
        super._afterTokenTransfer(from, to, amount);
        
        if (super.balanceOf(from) == 0)
            _appliedIdx[from] = 2**256 - 1;
    }


}