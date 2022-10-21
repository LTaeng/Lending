// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
    function setPrice(address token, uint256 price) external;
}

struct Deposit {
    uint balance;
    uint interestIndex;
}

struct Borrow {
    uint balance;
    uint principal;
    uint blockNum;
    uint updateBlockNum;
}

struct InterestBlock {
    uint interest;
    uint totalSupply;
}


contract DreamAcademyLending {

    address private owner;
    mapping(address => bool) public tokens;
    mapping(address => bool) public debtTokens;

    IPriceOracle public oracle;

    address[] borrowableToken;

    mapping(address => uint256) totalReserves;
    mapping(address => uint256) totalBorrows;

    mapping(address => uint256) updateBlock;

    mapping(address => mapping(address => Deposit)) private _deposit;
    mapping(address => mapping(address => Borrow)) private _borrow;

    InterestBlock[] interestBlock;

    mapping(address => mapping(address => uint256)) public liquidateAmount;

    constructor(IPriceOracle _oracle, address usdc) {
        owner = msg.sender;
        oracle = _oracle;

        tokens[address(0)] = true;
        tokens[usdc] = true;

        debtTokens[usdc] = true;
        borrowableToken.push(usdc);
    }

    function initializeLendingProtocol(address usdc) external payable {
        IERC20(usdc).transferFrom(msg.sender, address(this), 1);
    }

    function deposit(address tokenAddress, uint256 amount) external payable {
        require(tokens[tokenAddress], "Lending: Not support this token");
        accrueInterest();

        if (tokenAddress != address(0)) {
            require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, "Lending: Over than your balances");
            IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        } else
            require(msg.value == amount, "Lending: Not equal sended ethers");

        totalReserves[tokenAddress] += amount;
        _deposit[tokenAddress][msg.sender].balance += amount;
        _deposit[tokenAddress][msg.sender].interestIndex = interestBlock.length;
    }

    function withdraw(address tokenAddress, uint256 amount) external {
        require(tokens[tokenAddress], "Lending: Not support this token");
        accrueInterest();

        uint balance = getDepositBalance(tokenAddress, msg.sender);

        if (tokenAddress == address(0)) {
            uint etherPrice = getOraclePrice(address(0));
            for (uint i = 0; i < borrowableToken.length; ++i) {
                address token = borrowableToken[i];

                uint tokenPrice = getOraclePrice(token);
                uint limit = (balance - amount) * (etherPrice / tokenPrice) * 75 / 100;
                uint debt = getBorrowBalance(token, msg.sender);

                require(debt == 0 || limit > debt, "Lending: No over than limit");
            }
        }

        require(balance >= amount, "Lending: Over than your balances");

        totalReserves[tokenAddress] -= amount;
        _deposit[tokenAddress][msg.sender].balance -= amount;
        
        if (_deposit[tokenAddress][msg.sender].balance == 0) 
            _deposit[tokenAddress][msg.sender].interestIndex = 2**256 - 1;

        if (tokenAddress == address(0))
            payable(msg.sender).transfer(amount);
        else
            IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    // tokenAddress => 빌리고자 하는 토큰
    function borrow(address tokenAddress, uint256 amount) external {
        require(debtTokens[tokenAddress], "Lending: Not support this token");
        accrueInterest();

        uint256 deposited = getDepositBalance(address(0), msg.sender);
        uint256 etherPrice = getOraclePrice(address(0));
        uint256 tokenPrice = getOraclePrice(address(tokenAddress));
        uint256 maxLtv = etherPrice / tokenPrice * deposited / 2;

        require(maxLtv >= amount + getBorrowBalance(tokenAddress, msg.sender), "Lending: Over than your LTV");
        require(IERC20(tokenAddress).balanceOf(address(this)) >= amount, "Lending: Not enough tokens");

        totalBorrows[tokenAddress] += amount;
        _borrow[tokenAddress][msg.sender].balance += amount;
        _borrow[tokenAddress][msg.sender].principal += amount;
        _borrow[tokenAddress][msg.sender].blockNum = _borrow[tokenAddress][msg.sender].updateBlockNum = block.number;

        IERC20(tokenAddress).transfer(msg.sender, amount);
    }

    // tokenAddress => 갚고자 하는 토큰
    function repay(address tokenAddress, uint256 amount) external {
        require(debtTokens[tokenAddress], "Lending: Not support this token");
        require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, "Lending: Over than your balances");

        accrueInterest();

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        uint balance = getBorrowBalance(tokenAddress, msg.sender);

        totalBorrows[tokenAddress] -= amount;
        _borrow[tokenAddress][msg.sender].balance -= amount;

        if (balance - amount == 0) {
            _borrow[tokenAddress][msg.sender].principal = 0;
        }
    }


    // tokenAddress => 갚고자 하는 토큰
    function liquidate(address user, address tokenAddress, uint256 amount) external {
        require(debtTokens[tokenAddress], "Lending: Not support this token");

        accrueInterest();

        uint debt = getBorrowBalance(tokenAddress, user);
        uint256 etherPrice = getOraclePrice(address(0));
        uint256 tokenPrice = getOraclePrice(address(tokenAddress));

        if (liquidateAmount[user][tokenAddress] == 0) {
            uint deposited = _deposit[address(0)][user].balance;
            uint limit = deposited * (etherPrice / tokenPrice) * 75 / 100;

            require(limit <= debt, "Lending: Not over than limit");

            uint lot = (debt < 100 ether) ? debt : debt / 4;
            liquidateAmount[user][tokenAddress] = lot;
        }

        require(IERC20(tokenAddress).balanceOf(msg.sender) >= amount, "Lending: Over than your balances");
        require(liquidateAmount[user][tokenAddress] >= amount, "Lending: Over than Debt");

        uint256 eth = amount / (etherPrice / 1 ether);
        eth += eth / 1000 * 5;

        totalReserves[address(0)] -= eth;
        _deposit[address(0)][user].balance -= eth;

        totalBorrows[tokenAddress] -= amount;
        _borrow[tokenAddress][user].balance -= amount;
        liquidateAmount[user][tokenAddress] -= amount;

        IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount);
        payable(msg.sender).transfer(eth);

        if (debt - amount == 0)
            liquidateAmount[user][tokenAddress] = 0;

    }

    function getAccruedSupplyAmount(address tokenAddress) external returns (uint256) {
        accrueInterest();
        return getDepositBalance(tokenAddress, msg.sender);
    }

    function getOraclePrice(address token) internal view returns (uint256) {
        return oracle.getPrice(token);
    }




    function accrueInterest() public {

        for (uint i = 0; i < borrowableToken.length; ++i) {
            address token = borrowableToken[i];

            uint borrows = totalBorrows[token];
            for (uint t = 0; t < block.number - updateBlock[token]; ++t)
                borrows += borrows / 100000000000 * 13882;

            uint interest = borrows - totalBorrows[token];

            interestBlock.push(InterestBlock(interest, totalReserves[token]));
            totalReserves[token] += interest;

            totalBorrows[token] = borrows;
            updateBlock[token] = block.number;
        }

    }

    function getDepositBalance(address tokenAddress, address account) public returns (uint256) {
        Deposit memory d = _deposit[tokenAddress][account];
        if (tokenAddress == address(0))
            return d.balance;

        uint256 balance = d.balance;
        if (balance == 0)
            return 0;

        for (uint i = d.interestIndex; i < interestBlock.length; ++i) {
            InterestBlock memory t = interestBlock[i];
            balance += t.interest * balance / t.totalSupply;
        }

        _deposit[tokenAddress][account].balance = balance;
        _deposit[tokenAddress][account].interestIndex = interestBlock.length;

        return balance;
    }

    function getBorrowBalance(address tokenAddress, address account) public returns (uint256) {
        Borrow memory b = _borrow[tokenAddress][account];
        if (b.principal == 0)
            return 0;

        uint balance = b.balance;
        for (uint i = 0; i < block.number - b.updateBlockNum; ++i)
            balance += balance / 100000000000 * 13882;

        _borrow[tokenAddress][account].balance = balance;
        _borrow[tokenAddress][account].updateBlockNum = block.number;

        return balance;
    }


}
