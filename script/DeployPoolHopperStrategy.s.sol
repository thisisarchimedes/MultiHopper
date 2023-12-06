// SPDX-License-Identifier: UNLICENSED

/* solhint-disable */

pragma solidity >=0.8.19;

import "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "script/Base.s.sol";
import { ETHZapper } from "src/zapper/ETHZapper.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { AuraComposableStablePoolAdapter } from "src/AuraComposableStablePoolAdapter.sol";
import { AuraStablePoolAdapter } from "src/AuraStablePoolAdapter.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
/**
 * @title DeployConvex
 *
 * @dev A contract for deploying and configuring a Single pool Strategy using the ETH/msETH Curve pool
 *
 */

contract DeployPoolHopperStrategy is Script {
    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexPoolETHpETHAdapter;
    ConvexPoolAdapter convexPoolETHmsETHAdapter;
    AuraStablePoolAdapter auraStablePoolAdapter;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;

    /**
     * @dev Address of the MultiPoolStrategyFactory contract obtained by running factory deployment script.
     */
    address public constant FACTORY_ADDRESS = 0x0f152c86FdaDD9B58F7DCE26D819D76a70AD348F;

    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "ETH/xETH Hopper";
    string public constant TOKEN_NAME = "ETH/xETH Hopper";
    string public constant SYMBOL = "ETH/xETH Hopper";

    function run() external {
        // solhint-disable-previous-line no-empty-blocks
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }

        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({
            urlOrAlias: "mainnet",
            blockNumber: forkBlockNumber == 0 ? DEFAULT_FORK_BLOCK_NUMBER : forkBlockNumber
        });

        // get the private key used for signing transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        require(FACTORY_ADDRESS != address(0), "Deploy: factory address not set");

        // get instance of the MultiPoolStrategyFactory contract
        multiPoolStrategyFactory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        console2.log("MultiPoolStrategyFactory: %s", address(multiPoolStrategyFactory));

        // create the MultiPoolStrategy contract for the underlying asset
        multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(address(IERC20(UNDERLYING_ASSET)), TOKEN_NAME, SYMBOL)
        );
        console2.log("MultiPoolStrategy: %s", address(multiPoolStrategy));

        // create the adopters we are going to use with the strategy
        // we do it hard coded and dirty so we don't make any mistakes (hopefully)

        ///////////////////// ETH/msETH Curve/Convex pool /////////////////////
        convexPoolETHmsETHAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    0xc897b98272AA23714464Ea2A0Bd5180f1B8C0025, // address _curvePool
                    address(multiPoolStrategy), // address _multiPoolStrategy
                    145, // uint256 _convexPid
                    2, // uint256 _tokensLength
                    0x0000000000000000000000000000000000000000, // address _zapper
                    true, // bool _useEth
                    false, // bool _indexUint
                    0 // int128 _underlyingTokenIndex
                )
            )
        );
        console2.log("ETH/msETH ConvexPoolAdapter: %s", address(convexPoolETHmsETHAdapter));
        //// add created adapter to strategy
        multiPoolStrategy.addAdapter(address(convexPoolETHmsETHAdapter));

        ///////////////////// ETH/pETH Curve/Convex pool /////////////////////
        convexPoolETHpETHAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    0x9848482da3Ee3076165ce6497eDA906E66bB85C5, // address _curvePool
                    address(multiPoolStrategy), // address _multiPoolStrategy
                    122, // uint256 _convexPid
                    2, // uint256 _tokensLength
                    0x0000000000000000000000000000000000000000, // address _zapper
                    true, // bool _useEth
                    false, // bool _indexUint
                    0 // int128 _underlyingTokenIndex
                )
            )
        );
        console2.log("ETH/msETH ConvexPoolAdapter: %s", address(convexPoolETHpETHAdapter));
        //// add created adapter to strategy
        multiPoolStrategy.addAdapter(address(convexPoolETHpETHAdapter));

        ///////////////////// ETH/rETH Balancer/Aura pool /////////////////////
        auraStablePoolAdapter = AuraStablePoolAdapter(
            multiPoolStrategyFactory.createAuraStablePoolAdapter(
                0xb08885e6026bab4333a80024ec25a1a3e1ff2b8a000200000000000000000445, address(multiPoolStrategy), 63
            )
        );
        console2.log("ETH/rETH AuraStablePoolAdapter: %s", address(auraStablePoolAdapter));
        //// add created adapter to strategy
        multiPoolStrategy.addAdapter(address(auraStablePoolAdapter));

        vm.stopBroadcast();
    }
}
