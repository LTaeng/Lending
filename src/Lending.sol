// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AToken.sol";
import "./DebtToken.sol";
import "./DreamOracle.sol";

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Lending {

    address private owner;
    mapping(address => address) public tokens;
    mapping(address => address) public deptTokens;

    address public oracle;


    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "DEX: Locked");
        unlocked = 0;
        _;
        unlocked = 1;
    }


    constructor(address usdc) {
        owner = msg.sender;

        AToken newEthToken = new AToken("Another ETH", "aETH", address(0));
        tokens[address(0)] = address(newEthToken);

        AToken newUsdcToken = new AToken("Another USDC", "aUSDC", address(usdc));
        tokens[usdc] = address(newUsdcToken);

        DebtToken newUsdcDebtToken = new DebtToken("Debt USDC", "dUSDC", address(usdc));
        deptTokens[usdc] = address(newUsdcDebtToken);
    }

    function setOracle(address addr) {
        require(msg.sender == owner);
        oracle = addr;
    }

    // tokenAddress => 투입하고자 하는 토큰 주소, address(0)은 ETH
    function deposit(address tokenAddress, uint256 amount) external payable lock {
        require(tokens[tokenAddress] == address(0), "Lending: Not support this token");

        if (tokenAddress != address(0)) {
            require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, "Lending: Over than your balances");
            IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        } else
            require(msg.value >= amount, "Lending: Over than sended ethers");

        AToken(tokens[tokenAddress]).mint(msg.sender, amount);
    }

    // tokenAddress => 환전하고자 하는 A 토큰
    function withdraw(address tokenAddress, uint256 amount) external lock {
        require(tokenAddress == address(0), "Lending: Not support this token");

        AToken token = AToken(tokenAddress);
        require(token.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");

        token.burn(msg.sender, amount);
        address original = token.original();
        if (original == address(0))
            msg.sender.transfer(amount);
        else
            IERC20(original).transfer(msg.sender, amount);
    }

    // tokenAddress => 빌리고자 하는 토큰
    function borrow(address tokenAddress, uint256 amount) external lock {
        require(deptTokens[tokenAddress] == address(0), "Lending: Not support this token");

        uint256 deposited = IERC20(tokens[address(0)]).balanceOf(msg.sender);
        uint256 price = DreamOracle(oracle).getPrice(address(0));
        uint256 maxLtv = price * deposited / 2;

        DebtToken token = DebtToken(deptTokens[tokenAddress]);
        require(maxLtv >= amount + token.balanceOf(msg.sender), "Lending: Over than your LTV");

        token.mint(msg.sender, amount);
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    // tokenAddress => 갚고자 하는 Dept 토큰
    function repay(address tokenAddress, uint256 amount) external lock {
        DebtToken token = DebtToken(tokenAddress);
        IERC20 origial = IERC20(token.origial());

        require(original.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");

        uint interest = token.getLastInterest(msg.sender);
        uint fee = (interest > amount) ? amount : interest;

        AToken(tokens[origial]).updateInterest(fee);
        token.burn(msg.sender, amount);
    }


    // tokenAddress => 갚고자 하는 Dept 토큰
    function liquidate(address user, address tokenAddress, uint256 amount) external lock {


    }



}