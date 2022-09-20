// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../lib/forge-std/src/console2.sol";
import "../src/Lending.sol";
import "../src/USDC.sol";
import "../src/DreamOracle.sol";

contract LPTokenTest is Test {
    Lending public lending;
    USDC public usdc;

    DreamOracle[] public oracleList;
    uint256[] ethPrices = [200, 204];

    address internal constant alice = address(1);
    address internal constant bob = address(2);
    address internal constant carol = address(3);
    address internal constant dave = address(4);

    function setUp() public {
        usdc = new USDC("USDC Token", "USDC");
        lending = new Lending(address(usdc));

        for (uint i = 0; i < ethPrices.length; ++i) {
            DreamOracle oracle = new DreamOracle();
            oracle.setPrice(address(0), ethPrices[i]);
            oracle.setPrice(address(usdc), 1);
            lending.addOracle(address(oracle));
            oracleList.push(oracle);
        }

        vm.deal(alice, 0 ether);
        usdc.mint(alice, 10000000 ether);

        vm.deal(bob, 100 ether);

        vm.deal(carol, 0 ether);
        usdc.mint(carol, 10000000 ether);

        vm.deal(dave, 100 ether);
        usdc.mint(dave, 10000000 ether);
    }

    function testUSDCDeposit() public {
        vm.startPrank(alice);

        usdc.approve(address(lending), 10000000 ether);
        lending.deposit(address(usdc), 10000000 ether);
        vm.stopPrank();

        IERC20 aToken = IERC20(lending.getAToken(address(usdc)));
        assertEq(aToken.balanceOf(address(alice)), 10000000 ether);
    }

    function testETHDeposit() public {
        vm.startPrank(bob);

        lending.deposit{value: 100 ether}(address(0), 100 ether);
        vm.stopPrank();

        IERC20 aToken = IERC20(lending.getAToken(address(0)));
        assertEq(aToken.balanceOf(address(bob)), 100 ether);
    }

    function testUSDCWithdraw() public {
        testUSDCDeposit();

        IERC20 aToken = IERC20(lending.getAToken(address(usdc)));

        vm.startPrank(alice);
        lending.withdraw(address(aToken), 20 ether);
        vm.stopPrank();

        assertEq(aToken.balanceOf(address(alice)), 10000000 ether - 20 ether);
        assertEq(usdc.balanceOf(address(alice)), 20 ether);
    }

    function testETHWithdraw() public {
        testETHDeposit();

        IERC20 aToken = IERC20(lending.getAToken(address(0)));

        vm.startPrank(bob);
        lending.withdraw(address(aToken), 20 ether);
        vm.stopPrank();

        assertEq(aToken.balanceOf(address(bob)), 80 ether);
        assertEq(address(bob).balance, 20 ether);
    }

    function testBorrow() public {
        testUSDCDeposit();
        testETHDeposit();

        vm.startPrank(bob);

        lending.borrow(address(usdc), 10000 ether);
        vm.stopPrank();
        
        IERC20 aUSDCToken = IERC20(lending.getAToken(address(usdc)));
        IERC20 aETHToken = IERC20(lending.getAToken(address(0)));
        IERC20 debtUSDCToken = IERC20(lending.getDebtToken(address(usdc)));

        assertEq(aUSDCToken.balanceOf(address(bob)), 0 ether);
        assertEq(aETHToken.balanceOf(address(bob)), 100 ether);

        assertEq(debtUSDCToken.balanceOf(address(bob)), 10000 ether);
        assertEq(usdc.balanceOf(address(bob)), 10000 ether);
    }

    function testFailBorrow() public {
        testUSDCDeposit();
        testETHDeposit();

        vm.startPrank(bob);

        lending.borrow(address(usdc), 10101 ether);
        vm.stopPrank();
        
        IERC20 aUSDCToken = IERC20(lending.getAToken(address(usdc)));
        IERC20 aETHToken = IERC20(lending.getAToken(address(0)));
        IERC20 debtUSDCToken = IERC20(lending.getDebtToken(address(usdc)));

        assertEq(aUSDCToken.balanceOf(address(bob)), 0 ether);
        assertEq(aETHToken.balanceOf(address(bob)), 100 ether);

        assertEq(debtUSDCToken.balanceOf(address(bob)), 10101 ether);
        assertEq(usdc.balanceOf(address(bob)), 10101 ether);
    }

    function testFailOverBorrow() public {
        testBorrow();

        vm.startPrank(bob);
        lending.borrow(address(usdc), 10000 ether);
        vm.stopPrank();
    }

    function testMultiBorrow() public {
        testBorrow();

        vm.startPrank(bob);
        lending.borrow(address(usdc), 10 ether);
        lending.borrow(address(usdc), 20 ether);
        vm.stopPrank();
        
        IERC20 debtUSDCToken = IERC20(lending.getDebtToken(address(usdc)));

        assertEq(debtUSDCToken.balanceOf(address(bob)), 10030 ether);
        assertEq(usdc.balanceOf(address(bob)), 10030 ether);
    }

    function testInterest() public {
        testBorrow();
        IERC20 debtUSDCToken = IERC20(lending.getDebtToken(address(usdc)));

        vm.warp(block.timestamp + 24 hours);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 10010 ether);
        assertEq(usdc.balanceOf(address(bob)), 10000 ether);

        vm.warp(block.timestamp + 24 hours);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 10020.01 ether);
        assertEq(usdc.balanceOf(address(bob)), 10000 ether);
    }

    function testRepay() public {
        testBorrow();
        IERC20 aUSDCToken = IERC20(lending.getAToken(address(usdc)));
        IERC20 debtUSDCToken = IERC20(lending.getDebtToken(address(usdc)));

        vm.warp(block.timestamp + 24 hours);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 10010 ether);
        assertEq(usdc.balanceOf(address(bob)), 10000 ether);

        vm.startPrank(bob);

        lending.repay(address(debtUSDCToken), 10 ether);
        vm.stopPrank();

        assertEq(aUSDCToken.balanceOf(address(alice)), 10000010 ether);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 10000 ether);
        vm.warp(block.timestamp + 24 hours);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 10010 ether);

        vm.startPrank(bob);

        lending.repay(address(debtUSDCToken), 1010 ether);
        vm.stopPrank();

        assertEq(aUSDCToken.balanceOf(address(alice)), 10000020 ether);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 9000 ether);
        vm.warp(block.timestamp + 24 hours);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 9009 ether);
    }

    function testLiquidate() public {
        testBorrow();
        AToken aETHToken = AToken(lending.getAToken(address(0)));
        DebtToken debtUSDCToken = DebtToken(lending.getDebtToken(address(usdc)));

        oracleList[0].setPrice(address(0), 100);
        oracleList[1].setPrice(address(0), 140);
        
        vm.startPrank(carol);
        usdc.approve(address(lending), 1200 ether);
        lending.liquidate(bob, address(debtUSDCToken), 1200 ether);
        vm.stopPrank();
        
        assertEq(aETHToken.liquidate(address(bob)), true);

        vm.startPrank(dave);
        usdc.approve(address(lending), 8800 ether);
        lending.liquidate(bob, address(debtUSDCToken), 8800 ether);
        vm.stopPrank();

        assertEq(address(carol).balance, 10 ether);
        assertEq(debtUSDCToken.balanceOf(address(bob)), 0 ether);
        assertEq(aETHToken.liquidate(address(bob)), false);

    }

}