// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

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
     * @dev Address of the MultiPoolStrategyFactory contract obtained by running factory deployment script.
     */
    address public constant FACTORY_ADDRESS = 0x745D9719de1826773e665E131D4b6B6e66e7A525;
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /**
     * @dev Address of the Convex booster contract.
     * default: https://etherscan.io/address/0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    address public constant CONVEX_BOOSTER = address(0);

    /**
     * @dev Address of the Curve pool used in the integration.
     * default: ETH/msETH Curve pool
     */
    address public constant CURVE_POOL_ADDRESS = address(0); // https://curve.fi/#/ethereum/pools/factory-v2-252/deposit

    /**
     * @dev Convex pool ID used in the integration.
     * default: ETH/msETH Curve pool PID
     */
    uint256 public constant CONVEX_PID = 0;

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "FRAXBP/UZD Strat";

    /**
     * @dev if the pool uses native ETH as base asset e.g. ETH/msETH
     */
    bool constant USE_ETH = false;

    /**
     * @dev The index of the strategies underlying asset in the pool tokens array
     * e.g. 0 for ETH/msETH since tokens are [ETH,msETH]
     */
    int128 constant CURVE_POOL_TOKEN_INDEX = 2;

    /**
     * @dev True if the calc_withdraw_one_coin method uses uint256 indexes as parameter (check contract on etherscan)
     */
    bool constant IS_INDEX_UINT = false;

    /**
     * @dev the amount of tokens used in this pool , e.g. 2 for ETH/msETH
     */
    uint256 constant POOL_TOKEN_LENGTH = 3;

    /**
     * @dev address of zapper for pool if needed
     */
    address constant ZAPPER = 0x08780fb7E580e492c1935bEe4fA5920b94AA95Da;

    /**
     * @dev Executes the deployment and configuration of the Convex Pool Strategy.
     * It performs the following steps:
     * 1. Gets the instance of the MultiPoolStrategyFactory contract deployed previously.
     * 2. Creates an instance of the MultiPoolStrategy contract by calling createMultiPoolStrategy function
     *    of the MultiPoolStrategyFactory contract.
     * 3. Creates an instance of the ConvexPoolAdapter contract by calling createConvexAdapter function
     *    of the MultiPoolStrategyFactory contract with the parameters defined.
     * 4. Adds the ConvexPoolAdapter to the MultiPoolStrategy contract by calling the addAdapter function.
     * 5. Creates an instance of the ETHZapper contract with the MultiPoolStrategy contract as a parameter.
     */
    function run() public broadcaster {
        require(FACTORY_ADDRESS != address(0), "Deploy: factory address not set");
        require(CURVE_POOL_ADDRESS != address(0), "Deploy: curve pool address not set");
        require(CONVEX_PID != 0, "Deploy: convex pid not set");
        require(CONVEX_BOOSTER != address(0), "Deploy: convex booster address not set");

        MultiPoolStrategyFactory multiPoolStrategyFactory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        console2.log("MultiPoolStrategyFactory: %s", address(multiPoolStrategyFactory));
        MultiPoolStrategy multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(address(IERC20(UNDERLYING_ASSET)), STRATEGY_NAME)
        );
        console2.log("MultiPoolStrategy: %s", address(multiPoolStrategy));
        ConvexPoolAdapter convexPoolAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_POOL_ADDRESS, // address _curvePool
                    address(multiPoolStrategy), // address _multiPoolStrategy
                    CONVEX_PID, // uint256 _convexPid
                    POOL_TOKEN_LENGTH, // uint256 _tokensLength
                    ZAPPER, // address _zapper
                    USE_ETH, // bool _useEth
                    IS_INDEX_UINT, // bool _indexUint
                    CURVE_POOL_TOKEN_INDEX // int128 _underlyingTokenIndex
                )
            )
        );
        console2.log("ConvexPoolAdapter: %s", address(convexPoolAdapter));
        //// add created adapter to strategy
        multiPoolStrategy.addAdapter(address(convexPoolAdapter));
        /// everything successful log the output of the script
        console2.log(
            " created multiPoolStrategyContract on address %s and added Convex adapter on address %s ",
            address(multiPoolStrategy),
            address(convexPoolAdapter)
        );
    }
}
