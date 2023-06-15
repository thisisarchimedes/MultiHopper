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
 * @notice not intended for use on mainnet
 */

contract DeployConvex is BaseScript {
    /*

    @dev Address of the underlying token used in the integration.
    */
    address constant UNDERLYING_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev Address of the Convex booster contract.
     */
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /**
     * @dev Address of the MultiPoolStrategyFactory contract.
     */
    address public constant FACTORY_ADDRESS = 0xE052F5b563bc18D56cFf096Eb7Ec512C2a6C2FEB;

    /**
     * @dev Address of the Curve pool used in the integration.
     */
    address public constant CURVE_POOL_ADDRESS = 0xc897b98272AA23714464Ea2A0Bd5180f1B8C0025; // https://curve.fi/#/ethereum/pools/factory-v2-252/deposit

    /**
     * @dev Convex pool ID used in the integration.
     */
    uint256 public constant CONVEX_PID = 145;

    function run() public broadcaster {
        console2.log("Deployer Address: %s", deployer);
        MultiPoolStrategyFactory multiPoolStrategyFactory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        console2.log("MultiPoolStrategyFactory: %s", address(multiPoolStrategyFactory));
        //// test underlying WETH contract works
        console2.log("deployer eth balance %s", deployer.balance / 1e18);
        IWETH(payable(UNDERLYING_TOKEN)).deposit{ value: 1e18 }();
        uint256 deployerWETHBalance = IERC20(UNDERLYING_TOKEN).balanceOf(deployer);
        console2.log("WETH balance: %s", deployerWETHBalance / 1e18);
        MultiPoolStrategy multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(address(IERC20(UNDERLYING_TOKEN)), "ETHX Strat")
        );
        console2.log("MultiPoolStrategy: %s", address(multiPoolStrategy));
        ConvexPoolAdapter convexPoolAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    /**
                     *   address _curvePool,
                     *     address _multiPoolStrategy,
                     *     uint256 _convexPid,
                     *     uint256 _tokensLength,
                     *     address _zapper,
                     *     bool _useEth,
                     *     bool _indexUint,
                     *     int128 _underlyingTokenIndex
                     */
                    CURVE_POOL_ADDRESS,
                    address(multiPoolStrategy),
                    CONVEX_PID,
                    2,
                    address(0),
                    true,
                    false,
                    0
                )
            )
        );
        console2.log("ConvexPoolAdapter: %s", address(convexPoolAdapter));
        multiPoolStrategy.addAdapter(address(convexPoolAdapter));
        // create  the ETHzapper
        ETHZapper ethZapper = new ETHZapper(address(multiPoolStrategy));
        console2.log("ETHZapper: %s", address(ethZapper));
        // test that everything works correctly doing a deposit through the zapper
        ethZapper.depositETH{ value: 10e18 }(10e18, deployer);
        uint256 strategyTotalAssets = multiPoolStrategy.totalAssets();
        console2.log("Strategy total assets: %s", strategyTotalAssets / 1e18);
        /// everything successful log the output of the script
        console2.log(
            " created multiPoolStrategyContract on address %s and added Convex adapter on address %s with ethZapper on address %s ",
            address(multiPoolStrategy),
            address(convexPoolAdapter),
            address(ethZapper)
        );
    }
}
