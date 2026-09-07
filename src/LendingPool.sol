// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";

contract LendingPool {
    using SafeERC20 for IERC20;

    IERC20 public immutable COLLATERAL_TOKEN;
    IERC20 public immutable DEBT_TOKEN;
    MockPriceOracle public immutable COLLATERAL_PRICE_ORACLE;
    MockPriceOracle public immutable DEBT_PRICE_ORACLE;

    uint256 public constant INITIAL_RATIO = 1.5e18;
    uint256 public constant FLOOR_RATIO = 1.2e18;
    uint256 public constant RATIO_DROP_PER_LEVEL = 0.06e18;
    uint256 public constant BASE_BORROW_LIMIT = 100e18;
    uint256 public constant LIMIT_GROWTH_PER_LEVEL = 0.25e18;
    uint256 public constant LIQUIDATION_BONUS = 0.10e18;
    uint256 public constant PRECISION = 1e18;

    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public debtBalances;
    mapping(address => uint256) public reputationScore;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event ReputationIncreased(address indexed user, uint256 newScore);
    event ReputationReset(address indexed user);
    event Liquidated(
        address indexed liquidator,
        address indexed user,
        uint256 debtCovered,
        uint256 collateralSeized
    );

    error InsufficientCollateral();
    error InsufficientBalance();
    error ZeroAmount();
    error BorrowLimitExceeded();
    error PositionIsHealthy();

        constructor(
        address collateralToken_,
        address debtToken_,
        address collateralPriceOracle_,
        address debtPriceOracle_
    ) {
        COLLATERAL_TOKEN = IERC20(collateralToken_);
        DEBT_TOKEN = IERC20(debtToken_);
        COLLATERAL_PRICE_ORACLE = MockPriceOracle(collateralPriceOracle_);
        DEBT_PRICE_ORACLE = MockPriceOracle(debtPriceOracle_);
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        collateralBalances[msg.sender] += amount;

        emit Deposited(msg.sender, amount);

        COLLATERAL_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (collateralBalances[msg.sender] < amount) revert InsufficientBalance();

        uint256 newCollateralBalance = collateralBalances[msg.sender] - amount;

        if (!_isHealthy(msg.sender, newCollateralBalance, debtBalances[msg.sender])) {
            revert InsufficientCollateral();
        }

        collateralBalances[msg.sender] = newCollateralBalance;

        emit Withdrawn(msg.sender, amount);

        COLLATERAL_TOKEN.safeTransfer(msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        uint256 newDebtBalance = debtBalances[msg.sender] + amount;

        if (!_isHealthy(msg.sender, collateralBalances[msg.sender], newDebtBalance)) {
            revert InsufficientCollateral();
        }

        if (newDebtBalance > getMaxBorrowLimit(msg.sender)) {
            revert BorrowLimitExceeded();
        }

        debtBalances[msg.sender] = newDebtBalance;

        emit Borrowed(msg.sender, amount);

        DEBT_TOKEN.safeTransfer(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (debtBalances[msg.sender] < amount) revert InsufficientBalance();

        debtBalances[msg.sender] -= amount;

        emit Repaid(msg.sender, amount);

        if (debtBalances[msg.sender] == 0) {
            reputationScore[msg.sender] += 1;
            emit ReputationIncreased(msg.sender, reputationScore[msg.sender]);
        }

        DEBT_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
    }

        function liquidate(address user, uint256 debtToCover) external {
        if (debtToCover == 0) revert ZeroAmount();
        if (debtBalances[user] < debtToCover) revert InsufficientBalance();

        bool isHealthy = _isHealthy(user, collateralBalances[user], debtBalances[user]);
        if (isHealthy) revert PositionIsHealthy();

        uint256 collateralPrice = COLLATERAL_PRICE_ORACLE.getPrice();
        uint256 debtPrice = DEBT_PRICE_ORACLE.getPrice();

        uint256 collateralToSeize =
            (debtToCover * debtPrice * (PRECISION + LIQUIDATION_BONUS)) /
            (collateralPrice * PRECISION);

        if (collateralToSeize > collateralBalances[user]) revert InsufficientCollateral();

        debtBalances[user] -= debtToCover;
        collateralBalances[user] -= collateralToSeize;
        reputationScore[user] = 0;

        emit Liquidated(msg.sender, user, debtToCover, collateralToSeize);
        emit ReputationReset(user);

        DEBT_TOKEN.safeTransferFrom(msg.sender, address(this), debtToCover);
        COLLATERAL_TOKEN.safeTransfer(msg.sender, collateralToSeize);
    }

    function getRequiredCollateralRatio(address user) public view returns (uint256) {
        uint256 score = reputationScore[user];
        uint256 level = _log2Floor(score + 1);
        uint256 totalDrop = level * RATIO_DROP_PER_LEVEL;
        uint256 maxDrop = INITIAL_RATIO - FLOOR_RATIO;

        if (totalDrop >= maxDrop) {
            return FLOOR_RATIO;
        }
        return INITIAL_RATIO - totalDrop;
    }

    function getMaxBorrowLimit(address user) public view returns (uint256) {
        uint256 score = reputationScore[user];
        uint256 level = _log2Floor(score + 1);

        uint256 growthMultiplier = PRECISION + (level * LIMIT_GROWTH_PER_LEVEL);
        return (BASE_BORROW_LIMIT * growthMultiplier) / PRECISION;
    }

    function _log2Floor(uint256 x) internal pure returns (uint256) {
        uint256 result = 0;
        while (x > 1) {
            x >>= 1;
            result++;
        }
        return result;
    }

    function _isHealthy(
        address user,
        uint256 collateralAmount,
        uint256 debtAmount
    ) internal view returns (bool) {
        if (debtAmount == 0) return true;

        uint256 collateralPrice = COLLATERAL_PRICE_ORACLE.getPrice();
        uint256 debtPrice = DEBT_PRICE_ORACLE.getPrice();
        uint256 requiredRatio = getRequiredCollateralRatio(user);

        uint256 collateralValue = (collateralAmount * collateralPrice) / PRECISION;
        uint256 requiredCollateralValue =
            (debtAmount * debtPrice * requiredRatio) / (PRECISION * PRECISION);

        return collateralValue >= requiredCollateralValue;
    }
}