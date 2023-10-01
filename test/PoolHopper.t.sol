// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MultiPoolStrategyFactory } from "../src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "../src/interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { AuraComposableStablePoolAdapter } from "../src/AuraComposableStablePoolAdapter.sol";
import { AuraStablePoolAdapter } from "../src/AuraStablePoolAdapter.sol";
import { ConvexPoolAdapter } from "../src/ConvexPoolAdapter.sol";
import { IBooster } from "../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../src/interfaces/ICurvePool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PoolHopper is PRBTest, StdCheats {
    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexPoolETHpETHAdapter;
    ConvexPoolAdapter convexPoolETHmsETHAdapter;
    AuraStablePoolAdapter auraStablePoolAdapter;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_637_294;

    /**
     * @dev Address of the MultiPoolStrategyFactory contract obtained by running factory deployment script.
     */
    address public constant FACTORY_ADDRESS = 0x745D9719de1826773e665E131D4b6B6e66e7A525;

    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "ETH/xETH";

    function setUp() public virtual {
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

        require(FACTORY_ADDRESS != address(0), "Deploy: factory address not set");

        // get instance of the MultiPoolStrategyFactory contract
        multiPoolStrategyFactory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        console2.log("MultiPoolStrategyFactory: %s", address(multiPoolStrategyFactory));

        address owner = multiPoolStrategyFactory.owner();
        vm.startPrank(owner);

        // create the MultiPoolStrategy contract for the underlying asset
        multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(address(IERC20(UNDERLYING_ASSET)), STRATEGY_NAME)
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

        //vm.stopBroadcast();
        vm.stopPrank();
    }

    function testDeposit() public {
        address depositor = 0x95622e85962BC154c76AB24e48FdF6CdAeDAd6E5;

        vm.deal(depositor, 1000 ether);
        vm.startPrank(depositor, depositor);

        IWETH(payable(UNDERLYING_ASSET)).deposit{ value: 1000 ether }();
        IWETH(payable(UNDERLYING_ASSET)).approve(address(multiPoolStrategy), 1000 ether);
        multiPoolStrategy.deposit(1000 ether, depositor);
        uint256 balance = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
        console2.log("multiPoolStrategy balance: %s", balance);

        vm.stopPrank();

        // Addressing the request logic bug - start
        address owner = multiPoolStrategy.owner();
        vm.startPrank(owner);

        multiPoolStrategy.setMonitor(owner);
        console2.log("owner: ", owner);

        address monitor = multiPoolStrategy.monitor();
        console2.log("monitor: ", monitor);
        // Addressing the request logic bug - end

        // make sure fee recipient is not 0x0..0
        multiPoolStrategy.changeFeeRecipient(owner);

        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](3);

        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexPoolETHmsETHAdapter),
            amount: 20_000_000_000_000_000_000,
            minReceive: 0
        });
        adjustIns[1] = MultiPoolStrategy.Adjust({
            adapter: address(convexPoolETHpETHAdapter),
            amount: 20_000_000_000_000_000_000,
            minReceive: 0
        });
        adjustIns[2] = MultiPoolStrategy.Adjust({
            adapter: address(auraStablePoolAdapter),
            amount: 20_000_000_000_000_000_000,
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](3);
        adapters[0] = address(convexPoolETHmsETHAdapter);
        adapters[1] = address(convexPoolETHpETHAdapter);
        adapters[2] = address(auraStablePoolAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
    }
}
