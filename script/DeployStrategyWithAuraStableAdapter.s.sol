// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { console2 } from "forge-std/console2.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { AuraStablePoolAdapter } from "../src/AuraStablePoolAdapter.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
/**
 * @title DeployAuraStable
 *
 * @dev A contract for deploying and configuring a Single pool Strategy using an Aura Stable pool adapter
 *
 */

contract DeployAuraStable is BaseScript {
    /**
     * @dev Address of the MultiPoolStrategyFactory contract obtained by running factory deployment script.
     */
    address public constant FACTORY_ADDRESS = address(0);
    address constant UNDERLYING_ASSET = address(0); //strategy underlying asset such as
        // WETH,USDC,DAI,USDT etc.
    address public constant AURA_BOOSTER = address(0);
    /// POOL CONSTANTS
    bytes32 public constant BALANCER_STABLE_POOL_ID = 0;
    uint256 public constant AURA_PID = 0;
    string public constant STRATEGY_NAME = "WETH/rETH Strat";
    /**
     * @dev Executes the deployment and configuration of the Aura Stable Pool Strategy.
     * It performs the following steps:
     *
     */

    function run() public broadcaster {
        require(FACTORY_ADDRESS != address(0), "Deploy: factory address not set");
        require(AURA_BOOSTER != address(0), "Deploy: Aura booster address not set");
        require(BALANCER_STABLE_POOL_ID != 0, "Deploy: Balancer pool ID not set");
        require(AURA_PID != 0, "Deploy: Aura pid not set");

        MultiPoolStrategyFactory multiPoolStrategyFactory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        console2.log("MultiPoolStrategyFactory: %s", address(multiPoolStrategyFactory));
        MultiPoolStrategy multiPoolStrategy =
            MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_ASSET, STRATEGY_NAME));
        console2.log("MultiPoolStrategy: %s", address(multiPoolStrategy));
        AuraStablePoolAdapter AuraPoolAdapter = AuraStablePoolAdapter(
            multiPoolStrategyFactory.createAuraStablePoolAdapter(
                BALANCER_STABLE_POOL_ID, // bytes32 _poolId
                address(multiPoolStrategy), // address _multiPoolStrategy
                AURA_PID // uint256 _auraPid
            )
        );
        console2.log("AuraPoolAdapter: %s", address(AuraPoolAdapter));
        //// add created adapter to strategy
        multiPoolStrategy.addAdapter(address(AuraPoolAdapter));
        /// everything successful log the output of the script
        console2.log(
            " created multiPoolStrategyContract on address %s and added Aura  adapter on address %s ",
            address(multiPoolStrategy),
            address(AuraPoolAdapter)
        );
    }
}
