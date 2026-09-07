// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";

contract LendingPoolTest is Test {
    LendingPool public pool;
    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    MockPriceOracle public collateralOracle;
    MockPriceOracle public debtOracle;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_COLLATERAL_PRICE = 1e18;
    uint256 public constant INITIAL_DEBT_PRICE = 1e18;
    uint256 public constant POOL_LIQUIDITY = 10_000e18;
    uint256 public constant USER_COLLATERAL_MINT = 1_000e18;

    function setUp() public {
        collateralToken = new MockERC20("Mock Collateral", "mCOL");
        debtToken = new MockERC20("Mock Debt Token", "mDEBT");

        collateralOracle = new MockPriceOracle(INITIAL_COLLATERAL_PRICE);
        debtOracle = new MockPriceOracle(INITIAL_DEBT_PRICE);

        pool = new LendingPool(
            address(collateralToken),
            address(debtToken),
            address(collateralOracle),
            address(debtOracle)
        );

        debtToken.mint(address(pool), POOL_LIQUIDITY);

        collateralToken.mint(alice, USER_COLLATERAL_MINT);
        collateralToken.mint(bob, USER_COLLATERAL_MINT);
    }

    function test_Deposit_IncreasesCollateralBalance() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(alice);
        collateralToken.approve(address(pool), depositAmount);
        pool.deposit(depositAmount);
        vm.stopPrank();

        assertEq(pool.collateralBalances(alice), depositAmount);
    }

    function test_Deposit_RevertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.deposit(0);
    }

    function test_Borrow_SucceedsWithSufficientCollateral() public {
        uint256 depositAmount = 300e18;
        uint256 borrowAmount = 100e18;

        _depositAsAlice(depositAmount);

        vm.prank(alice);
        pool.borrow(borrowAmount);

        assertEq(pool.debtBalances(alice), borrowAmount);
        assertEq(debtToken.balanceOf(alice), borrowAmount);
    }

    function test_Borrow_RevertsWithInsufficientCollateral() public {
        uint256 depositAmount = 100e18;
        uint256 borrowAmount = 100e18;

        _depositAsAlice(depositAmount);

        vm.prank(alice);
        vm.expectRevert(LendingPool.InsufficientCollateral.selector);
        pool.borrow(borrowAmount);
    }

    function test_Borrow_RevertsWhenExceedingBorrowLimit() public {
        uint256 depositAmount = 1_000e18;
        uint256 borrowAmount = 150e18;

        _depositAsAlice(depositAmount);

        vm.prank(alice);
        vm.expectRevert(LendingPool.BorrowLimitExceeded.selector);
        pool.borrow(borrowAmount);
    }

    function test_Repay_IncreasesReputationOnFullRepayment() public {
        uint256 depositAmount = 300e18;
        uint256 borrowAmount = 100e18;

        _depositAsAlice(depositAmount);

        vm.startPrank(alice);
        pool.borrow(borrowAmount);

        debtToken.approve(address(pool), borrowAmount);
        pool.repay(borrowAmount);
        vm.stopPrank();

        assertEq(pool.debtBalances(alice), 0);
        assertEq(pool.reputationScore(alice), 1);
    }

    function test_Repay_DoesNotIncreaseReputationOnPartialRepayment() public {
        uint256 depositAmount = 300e18;
        uint256 borrowAmount = 100e18;
        uint256 partialRepayAmount = 50e18;

        _depositAsAlice(depositAmount);

        vm.startPrank(alice);
        pool.borrow(borrowAmount);

        debtToken.approve(address(pool), partialRepayAmount);
        pool.repay(partialRepayAmount);
        vm.stopPrank();

        assertEq(pool.reputationScore(alice), 0);
        assertEq(pool.debtBalances(alice), borrowAmount - partialRepayAmount);
    }

    function test_RequiredCollateralRatio_DecreasesWithReputation() public {
        uint256 ratioBefore = pool.getRequiredCollateralRatio(alice);
        assertEq(ratioBefore, pool.INITIAL_RATIO());

        _depositAsAlice(300e18);
        vm.startPrank(alice);
        pool.borrow(50e18);
        debtToken.approve(address(pool), 50e18);
        pool.repay(50e18);
        vm.stopPrank();

        uint256 ratioAfter = pool.getRequiredCollateralRatio(alice);

        assertLt(ratioAfter, ratioBefore);
    }

    function test_Liquidate_RevertsWhenPositionIsHealthy() public {
        uint256 depositAmount = 300e18;
        uint256 borrowAmount = 100e18;

        _depositAsAlice(depositAmount);

        vm.prank(alice);
        pool.borrow(borrowAmount);

        vm.prank(bob);
        vm.expectRevert(LendingPool.PositionIsHealthy.selector);
        pool.liquidate(alice, borrowAmount);
    }

    function test_Liquidate_SucceedsWhenCollateralPriceDrops() public {
        uint256 depositAmount = 300e18;
        uint256 borrowAmount = 100e18;

        _depositAsAlice(depositAmount);

        vm.prank(alice);
        pool.borrow(borrowAmount);

        collateralOracle.setPrice(0.30e18);

        debtToken.mint(bob, borrowAmount);

        vm.startPrank(bob);
        debtToken.approve(address(pool), borrowAmount);
        pool.liquidate(alice, borrowAmount);
        vm.stopPrank();

        assertEq(pool.debtBalances(alice), 0);
        assertEq(pool.reputationScore(alice), 0);
        assertGt(collateralToken.balanceOf(bob), 0);
    }

    function test_Liquidate_RevertsWhenDebtPriceSpikeMakesPositionUnhealthy() public {
        uint256 depositAmount = 200e18;
        uint256 borrowAmount = 100e18;

        _depositAsAlice(depositAmount);

        vm.prank(alice);
        pool.borrow(borrowAmount);

        debtOracle.setPrice(3e18);

        assertFalse(_isPositionHealthy(alice));
    }

    function _depositAsAlice(uint256 amount) internal {
        vm.startPrank(alice);
        collateralToken.approve(address(pool), amount);
        pool.deposit(amount);
        vm.stopPrank();
    }

    function _isPositionHealthy(address user) internal view returns (bool) {
        uint256 collateralValue =
            (pool.collateralBalances(user) * collateralOracle.getPrice()) / 1e18;
        uint256 debtValue =
            (pool.debtBalances(user) * debtOracle.getPrice()) / 1e18;
        uint256 requiredRatio = pool.getRequiredCollateralRatio(user);
        uint256 requiredCollateralValue = (debtValue * requiredRatio) / 1e18;

        return collateralValue >= requiredCollateralValue;
    }
}