// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity ^0.8.19.0;

import { BaseScript } from "./Base.s.sol";
import "forge-std/Script.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "src/AuraWeightedPoolAdapter.sol";
import { AuraStablePoolAdapter } from "src/AuraStablePoolAdapter.sol";
import { AuraComposableStablePoolAdapter } from "src/AuraComposableStablePoolAdapter.sol";
import { console2 } from "forge-std/console2.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

/**
 * @title Deploy
 *
 * @dev A contract for deploying the MultiPoolStrategyFactory contract
 * @notice we do this in its own script because of the size of the contract and the gas spent
 *
 */
interface ISushiRouter {
    function swapExactEthForTokens(
        uint256,
        address[] calldata,
        address,
        uint256
    )
        external
        payable
        returns (uint256[] memory);
}

contract SetupTenderly is Script {
    address public constant SUSHI_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address MONITOR = address(0x93B435e55881Ea20cBBAaE00eaEdAf7Ce366BeF2);
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // mainnet deployer private key
    address constant UNDERLYING_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
    address public constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    /// POOL CONSTANTS
    bytes32 public constant BALANCER_STABLE_POOL_ID = 0xb08885e6026bab4333a80024ec25a1a3e1ff2b8a000200000000000000000445;
    uint256 public constant AURA_STABLE_PID = 63;

    /// CONVEX CONSTANTS
    address constant CURVE_POOL = 0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA;
    uint256 constant CONVEX_PID = 33;
    uint256 constant TOKEN_LENGTH = 4;
    address constant ZAPPER = 0xA79828DF1850E8a3A3064576f380D90aECDD3359;
    /// AURA COMPOSABLE POOL CONSTANTS
    bytes32 public constant BALANCER_COMPOSABLE_POOL_ID =
        0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
    uint256 public constant AURA_COMPOSABLE_PID = 76;

    function run() public returns (MultiPoolStrategyFactory factory) {
        require(MONITOR != address(0), "Deploy: monitor address not set");

        vm.startBroadcast(deployerPrivateKey);

        //// implementation contract deployments , if there are any issues with script size and deployment you can
        // set the ones you will not use as address(0)
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address AuraWeightedPoolAdapterImplementation = address(new AuraWeightedPoolAdapter());
        address AuraStablePoolAdapterImplementation = address(new AuraStablePoolAdapter());
        address AuraComposableStablePoolAdapterImplementation = address(new AuraComposableStablePoolAdapter());
        factory = new MultiPoolStrategyFactory(
            MONITOR,
            ConvexPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation,
            address(this)
        );
        console2.log(
            "deployed MultiPoolStrategyFactory contract at address %s with monitor %s", address(factory), MONITOR
        );
        address multiPoolStrategy = factory.createMultiPoolStrategy(UNDERLYING_TOKEN, "test", "test");
        console2.log("created MultiPoolStrategy contract at address %s", address(multiPoolStrategy));
        address auraAdapter =
            factory.createAuraStablePoolAdapter(BALANCER_STABLE_POOL_ID, multiPoolStrategy, AURA_STABLE_PID);
        console2.log("created AuraStablePoolAdapter contract at address %s", address(auraAdapter));
        MultiPoolStrategy(multiPoolStrategy).addAdapter(auraAdapter);
        IWETH(payable(WETH)).deposit{ value: 100e18 }();
        IWETH(payable(WETH)).approve(multiPoolStrategy, type(uint256).max);
        MultiPoolStrategy(multiPoolStrategy).deposit(100e18, MONITOR);

        address multiPoolStrategyConvex = factory.createMultiPoolStrategy(USDC, "test", "test");
        console2.log("created MultiPoolStrategyConvex contract at address %s", address(multiPoolStrategyConvex));
        address convexAdapter = factory.createConvexAdapter(
            CURVE_POOL, multiPoolStrategyConvex, CONVEX_PID, TOKEN_LENGTH, ZAPPER, false, false, 2
        );
        console2.log("created ConvexPoolAdapter contract at address %s", address(convexAdapter));
        MultiPoolStrategy(multiPoolStrategyConvex).addAdapter(convexAdapter);
        uint256 usdcBal = IERC20(USDC).balanceOf(address(MONITOR));
        IERC20(USDC).approve(multiPoolStrategyConvex, type(uint256).max);
        MultiPoolStrategy(multiPoolStrategyConvex).deposit(usdcBal / 2, MONITOR);
        address multoPoolStrategyComposable = factory.createMultiPoolStrategy(USDC, "test", "test");
        console2.log("created MultiPoolStrategyComposable contract at address %s", address(multoPoolStrategyComposable));
        address auraComposableAdapter = factory.createAuraComposableStablePoolAdapter(
            BALANCER_COMPOSABLE_POOL_ID, multoPoolStrategyComposable, AURA_COMPOSABLE_PID
        );
        console2.log("created AuraComposableStablePoolAdapter contract at address %s", address(auraComposableAdapter));
        MultiPoolStrategy(multoPoolStrategyComposable).addAdapter(auraComposableAdapter);
        IERC20(USDC).approve(multoPoolStrategyComposable, type(uint256).max);
        usdcBal = IERC20(USDC).balanceOf(address(MONITOR));
        MultiPoolStrategy(multoPoolStrategyComposable).deposit(usdcBal, MONITOR);
        vm.stopBroadcast();
    }
}
