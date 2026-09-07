// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";

contract DeployScript is Script {
    uint256 public constant INITIAL_COLLATERAL_PRICE = 1e18;
    uint256 public constant INITIAL_DEBT_PRICE = 1e18;
    uint256 public constant POOL_LIQUIDITY = 10_000e18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        MockERC20 collateralToken = new MockERC20("Mock Collateral", "mCOL");
        MockERC20 debtToken = new MockERC20("Mock Debt Token", "mDEBT");

        MockPriceOracle collateralOracle = new MockPriceOracle(INITIAL_COLLATERAL_PRICE);
        MockPriceOracle debtOracle = new MockPriceOracle(INITIAL_DEBT_PRICE);

        LendingPool pool = new LendingPool(
            address(collateralToken),
            address(debtToken),
            address(collateralOracle),
            address(debtOracle)
        );

        debtToken.mint(address(pool), POOL_LIQUIDITY);
        collateralToken.mint(deployer, 10_000e18);

        vm.stopBroadcast();

        console.log("CollateralToken deployed at:", address(collateralToken));
        console.log("DebtToken deployed at:", address(debtToken));
        console.log("CollateralOracle deployed at:", address(collateralOracle));
        console.log("DebtOracle deployed at:", address(debtOracle));
        console.log("LendingPool deployed at:", address(pool));
    }
}