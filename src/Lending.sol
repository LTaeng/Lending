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
    mapping(address => uint[]) public oraclePrices;


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
    }

    function removeOracle(address addr) public {
        require(msg.sender == owner);
        for (uint i = 0; i < oracleList.length; ++i) {
            if (oracleList[i] == addr) {
                oracleList[i] = oracleList[oracleList.length - 1];
                oracleList.pop();
            }
        }
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
        require(tokens[tokenAddress] != address(0), "Lending: Not support this token");

        AToken token = AToken(tokens[tokenAddress]);
        require(token.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");
        require(!token.guarantee(msg.sender), "Lending: Guarnatee is locked");

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
        uint256 etherPrice = getOraclePrice(address(0));
        uint256 tokenPrice = getOraclePrice(address(tokenAddress));
        uint256 maxLtv = etherPrice / tokenPrice * deposited / 2;

        DebtToken token = DebtToken(debtTokens[tokenAddress]);
        require(maxLtv >= amount + token.balanceOf(msg.sender), "Lending: Over than your LTV");
        require(IERC20(token.original()).balanceOf(address(this)) >= amount, "Lending: Not enough tokens");

        AToken(tokens[address(0)]).setGuarantee(msg.sender, true);
        token.mint(msg.sender, amount);
        IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    // tokenAddress => 갚고자 하는 토큰
    function repay(address tokenAddress, uint256 amount) external lock liquidated {
        require(debtTokens[tokenAddress] != address(0), "Lending: Not support this token");

        DebtToken token = DebtToken(debtTokens[tokenAddress]);
        IERC20 original = IERC20(tokenAddress);

        require(original.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");

        uint interest = token.getLastInterest(msg.sender);
        uint fee = (interest > amount) ? amount : interest;

        AToken(tokens[tokenAddress]).updateInterest(fee);
        token.burn(msg.sender, amount);

        if (token.balanceOf(msg.sender) == 0)
            AToken(tokens[address(0)]).setGuarantee(msg.sender, false);
    }


    // tokenAddress => 갚고자 하는 토큰
    function liquidate(address user, address tokenAddress, uint256 amount) external lock {
        require(debtTokens[tokenAddress] != address(0), "Lending: Not support this token");

        DebtToken debtToken = DebtToken(debtTokens[tokenAddress]);
        IERC20 original = IERC20(tokenAddress);

        AToken aETHToken = AToken(tokens[address(0)]);

        uint256 debt = debtToken.balanceOf(user);
        uint256 deposited = aETHToken.balanceOf(user);
        uint256 etherPrice = getOraclePrice(address(0));
        uint256 tokenPrice = getOraclePrice(address(tokenAddress));
        uint256 limit = deposited * (etherPrice / tokenPrice) * 75 / 100;

        if (!aETHToken.liquidate(user)) {
            require(limit <= debt, "Lending: Not over than limit");
            aETHToken.setLiquidate(user, true);
        }

        require(original.balanceOf(msg.sender) >= amount, "Lending: Over than your balances");
        require(debt >= amount, "Lending: Over than Debt");

        uint256 eth = amount / etherPrice * tokenPrice;
        eth += eth / 1000 * 5;

        aETHToken.burn(user, eth);
        debtToken.burn(user, amount);

        original.transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(eth);

        if (debtToken.balanceOf(user) == 0)
            aETHToken.setLiquidate(user, false);

    }

    function getOraclePrice(address token) public returns (uint256) {
        delete oraclePrices[token];
        for (uint i = 0; i < oracleList.length; ++i) {
            address oracle = oracleList[i];
            oraclePrices[token].push(DreamOracle(oracle).getPrice(token));
        }

        return median(oraclePrices[token], oraclePrices[token].length);
    }

    function swap(uint256[] memory array, uint256 i, uint256 j) internal pure {
        (array[i], array[j]) = (array[j], array[i]);
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    function sort(uint256[] memory array, uint256 begin, uint256 end) internal pure {
        if (begin < end) {
            uint256 j = begin;
            uint256 pivot = array[j];
            for (uint256 i = begin + 1; i < end; ++i) {
                if (array[i] < pivot) {
                    swap(array, i, ++j);
                }
            }
            swap(array, begin, j);
            sort(array, begin, j);
            sort(array, j + 1, end);
        }
    }

    function median(uint256[] memory array, uint256 length) internal pure returns(uint256) {
        sort(array, 0, length);
        return length % 2 == 0 ? average(array[length/2-1], array[length/2]) : array[length/2];
    }

}