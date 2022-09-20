// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./AToken.sol";
import "./DebtToken.sol";
import "./DreamOracle.sol";

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "../lib/forge-std/src/console2.sol";

contract Lending {

    address private owner;
    mapping(address => address) public tokens;
    mapping(address => address) public debtTokens;

    address[] public oracleList;
    mapping(address => bool) public oracleState;


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
        debtTokens[usdc] = address(newUsdcDebtToken);
    }

    function addOracle(address addr) public {
        require(msg.sender == owner);
        oracleList.push(addr);
        oracleState[addr] = true;
    }

    function removeOracle(address addr) public {
        require(msg.sender == owner);
        oracleState[addr] = false;
    }

    function getAToken(address token) public view returns (address) {
        return tokens[token];
    }

    function getDebtToken(address token) public view returns (address) {
        return debtTokens[token];
    }

    modifier liquidated() {
        AToken aToken = AToken(tokens[address(0)]);
        require(!aToken.liquidate(msg.sender), "Lending: ETH is locked");
        _;
    }


    // tokenAddress => 투입하고자 하는 토큰 주소, address(0)은 ETH
    function deposit(address tokenAddress, uint256 amount) external payable lock {
        require(tokens[tokenAddress] != address(0), "Lending: Not support this token");

        if (tokenAddress != address(0)) {
            require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, "Lending: Over than your balances");
            IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        } else
            require(msg.value == amount, "Lending: Not equal sended ethers");

        AToken(tokens[tokenAddress]).mint(msg.sender, amount);
    }

    // tokenAddress => 환전하고자 하는 A 토큰
    function withdraw(address tokenAddress, uint256 amount) external lock liquidated {
        require(tokenAddress != address(0), "Lending: Not support this token");

        AToken token = AToken(tokenAddress);
        require(token.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");

        token.burn(msg.sender, amount);
        address original = token.original();
        if (original == address(0))
            payable(msg.sender).transfer(amount);
        else
            IERC20(original).transfer(msg.sender, amount);
    }

    // tokenAddress => 빌리고자 하는 토큰
    function borrow(address tokenAddress, uint256 amount) external lock liquidated {
        require(debtTokens[tokenAddress] != address(0), "Lending: Not support this token");

        uint256 deposited = IERC20(tokens[address(0)]).balanceOf(msg.sender);
        uint256 price = getOraclePrice(address(0));
        uint256 maxLtv = price * deposited / 2;

        DebtToken token = DebtToken(debtTokens[tokenAddress]);
        require(maxLtv >= amount + token.balanceOf(msg.sender), "Lending: Over than your LTV");
        require(IERC20(token.original()).balanceOf(address(this)) >= amount, "Lending: Not enough tokens");

        token.mint(msg.sender, amount);
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    // tokenAddress => 갚고자 하는 Debt 토큰
    function repay(address tokenAddress, uint256 amount) external lock liquidated {
        DebtToken token = DebtToken(tokenAddress);
        IERC20 original = IERC20(token.original());

        require(original.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");

        uint interest = token.getLastInterest(msg.sender);
        uint fee = (interest > amount) ? amount : interest;

        AToken(tokens[address(original)]).updateInterest(fee);
        token.burn(msg.sender, amount);
    }


    // tokenAddress => 갚고자 하는 Debt 토큰
    function liquidate(address user, address tokenAddress, uint256 amount) external lock {
        DebtToken debtToken = DebtToken(tokenAddress);
        IERC20 original = IERC20(debtToken.original());

        AToken aETHToken = AToken(tokens[address(0)]);
        AToken aToken = AToken(tokens[address(original)]);

        uint256 debt = debtToken.balanceOf(user);
        uint256 deposited = aToken.balanceOf(user);
        uint256 price = getOraclePrice(address(0));
        uint256 limit = deposited * price * 75 / 100;

        if (!aETHToken.liquidate(user)) {
            require(limit <= debt, "Lending: Not over than limit");
            aETHToken.setLiquidate(user, true);
        }

        require(original.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");
        require(debt >= amount, "Lending: Over than Debt");

        uint256 eth = amount / price;
        aETHToken.burn(user, eth);
        debtToken.burn(user, amount);

        original.transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(eth);

        if (debtToken.balanceOf(user) == 0)
            aETHToken.setLiquidate(user, false);

    }

    function getOraclePrice(address token) public view returns (uint256 prices) {
        uint256 num;
        for (uint i = 0; i < oracleList.length; ++i) {
            address oracle = oracleList[i];
            if (!oracleState[oracle])
                continue;
            prices += DreamOracle(oracle).getPrice(token);
            num++;
        }

        prices /= num;
    }



}