// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import { ETHZapper } from "../src/ETHZapper.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { ConvexPoolAdapter } from "../src/ConvexPoolAdapter.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { console2 } from "forge-std/console2.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
/**
 * @title DeployConvex
 *
 * @dev A contract for deploying and configuring a Single pool Strategy using the ETH/msETH Curve pool
 *
 */

contract DeployConvex is BaseScript {
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev Address of the Convex booster contract.
     * default: https://etherscan.io/address/0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /**
     * @dev Address of the MultiPoolStrategyFactory contract obtained by running factory deployment script.
     */
    address public constant FACTORY_ADDRESS = 0xE052F5b563bc18D56cFf096Eb7Ec512C2a6C2FEB;

    /**
     * @dev Address of the Curve pool used in the integration.
     * default: ETH/msETH Curve pool
     */
    address public constant CURVE_POOL_ADDRESS = 0xc897b98272AA23714464Ea2A0Bd5180f1B8C0025; // https://curve.fi/#/ethereum/pools/factory-v2-252/deposit

    /**
     * @dev Convex pool ID used in the integration.
     * default: ETH/msETH Curve pool PID
     */
    uint256 public constant CONVEX_PID = 145;

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "ETH/msETH Strat";

    function run() public broadcaster {
        require(FACTORY_ADDRESS != address(0), "Deploy: factory address not set");
        require(CURVE_POOL_ADDRESS != address(0), "Deploy: curve pool address not set");
        require(CONVEX_PID != 0, "Deploy: convex pid not set");
        require(CONVEX_BOOSTER != address(0), "Deploy: convex booster address not set");

        console2.log("Owner Address: %s", owner);
        MultiPoolStrategyFactory multiPoolStrategyFactory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        console2.log("MultiPoolStrategyFactory: %s", address(multiPoolStrategyFactory));
        MultiPoolStrategy multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(address(IERC20(UNDERLYING_TOKEN)), STRATEGY_NAME)
        );
        console2.log("MultiPoolStrategy: %s", address(multiPoolStrategy));
        ConvexPoolAdapter convexPoolAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_POOL_ADDRESS, // address _curvePool
                    address(multiPoolStrategy), // address _multiPoolStrategy
                    CONVEX_PID, // uint256 _convexPid
                    2, // uint256 _tokensLength
                    address(0), // address _zapper
                    true, // bool _useEth
                    false, // bool _indexUint
                    0 // int128 _underlyingTokenIndex
                )
            )
        );
        console2.log("ConvexPoolAdapter: %s", address(convexPoolAdapter));
        //// add created adapter to strategy
        multiPoolStrategy.addAdapter(address(convexPoolAdapter));
        // create  the ETHzapper
        ETHZapper ethZapper = new ETHZapper(address(multiPoolStrategy));
        console2.log("ETHZapper: %s", address(ethZapper));
        /// everything successful log the output of the script
        console2.log(
            " created multiPoolStrategyContract on address %s and added Convex adapter on address %s with ethZapper on address %s ",
            address(multiPoolStrategy),
            address(convexPoolAdapter),
            address(ethZapper)
        );

        // test that everything works correctly doing a deposit through the zapper | this is just QoL for deployment on
        // fork, uncomment if needed

        // ethZapper.depositETH{ value: 10e18 }(10e18, owner);
        // uint256 strategyTotalAssets = multiPoolStrategy.totalAssets();
        // console2.log("Strategy total assets: %s", strategyTotalAssets / 1e18);
    }
}
