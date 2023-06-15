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

contract Deploy is BaseScript {
    // address MONITOR = address(0); // TODO : set monitor address before deploy
    ///CONSTANTS
    address constant UNDERLYING_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address public constant FACTORY_ADDRESS = 0xE052F5b563bc18D56cFf096Eb7Ec512C2a6C2FEB; // factory address from
        // previous script
    /// POOL CONSTANTS
    // https://curve.fi/#/ethereum/pools/factory-v2-252/deposit
    address public constant CURVE_POOL_ADDRESS = 0xc897b98272AA23714464Ea2A0Bd5180f1B8C0025; // ETH/msETH curve pool
    uint256 public constant CONVEX_PID = 145;

    function run() public broadcaster {
        console2.log("Deployer Address: %s", deployer);
        MultiPoolStrategyFactory multiPoolStrategyFactory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        console2.log("MultiPoolStrategyFactory: %s", address(multiPoolStrategyFactory));
        //// test underlying WETH contract works
        console2.log("deployer eth balance %s", deployer.balance / 1e18);
        IWETH(payable(UNDERLYING_TOKEN)).deposit{ value: 1e18 }();
        uint256 deployerWETHBalance = IERC20(payable(UNDERLYING_TOKEN)).balanceOf(deployer);
        console2.log("WETH balance: %s", deployerWETHBalance / 1e18);
        MultiPoolStrategy multiPoolStrategy =
            MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_TOKEN, "ETHX Strat"));
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
        // ethZapper.depositETH{ value: 10e18 }(10e18, deployer);
        uint256 strategyTotalAssets = multiPoolStrategy.totalAssets();
        console2.log("Strategy total assets: %s", strategyTotalAssets / 1e18);
    }
}
