// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "../../src/interfaces/IBaseRewardPool.sol";
import { ETHZapper } from "../../src/ETHZapper.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { ConvexPoolAdapter } from "../../src/ConvexPoolAdapter.sol";
import { ICurveBasePool } from "../../src/interfaces/ICurvePool.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";

/// @title ConvexPoolAdapterInputETHTest
/// @notice A contract for testing an ETH pegged convex pool (ETH/msETH) with native ETH input from user using zapper
contract ConvexPoolAdapterInputETHTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexPoolAdapter;
    ETHZapper ethZapper;
    address public staker = makeAddr("staker");
    ///CONSTANTS
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev Address of the Convex booster contract.
     * default: https://etherscan.io/address/0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /**
     * @dev Address of the Curve pool used in the integration.
     * default: ETH/msETH Curve pool
     */
    address public constant CURVE_POOL_ADDRESS = 0x5ac4fceE123dcaDfAe22bc814c4Cc72b96c93F38; // https://curve.fi/#/ethereum/pools/factory-v2-252/deposit

    /**
     * @dev Convex pool ID used in the integration.
     * default: ETH/msETH Curve pool PID
     */
    uint256 public constant CONVEX_PID = 160;

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "ETH/eCFX Strat";

    /**
     * @dev if the pool uses native ETH as base asset e.g. ETH/msETH
     */
    bool constant USE_ETH = false;

    /**
     * @dev The index of the strategies underlying asset in the pool tokens array
     * e.g. 0 for ETH/msETH since tokens are [ETH,msETH]
     */
    int128 constant CURVE_POOL_TOKEN_INDEX = 1;

    /**
     * @dev True if the calc_withdraw_one_coin method uses uint256 indexes as parameter (check contract on etherscan)
     */
    bool constant IS_INDEX_UINT = true;

    /**
     * @dev the amount of tokens used in this pool , e.g. 2 for ETH/msETH
     */
    uint256 constant POOL_TOKEN_LENGTH = 2;

    /**
     * @dev address of zapper for pool if needed
     */
    address constant ZAPPER = address(0);

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_421_496;
    uint256 tokenDecimals;

    //// get swap quote from LIFI using a python script | this method lives on all tests
    function getQuoteLiFi(
        address srcToken,
        address dstToken,
        uint256 amount,
        address fromAddress
    )
        internal
        returns (uint256 _quote, bytes memory data)
    {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "test/get_quote_lifi.py";
        inputs[2] = vm.toString(srcToken);
        inputs[3] = vm.toString(dstToken);
        inputs[4] = vm.toString(amount);
        inputs[5] = vm.toString(fromAddress);

        return abi.decode(vm.ffi(inputs), (uint256, bytes));
    }
    //// get current block number using a python script that gets the latest number and substracts 10 blocks  | this
    // method lives on all tests

    function getBlockNumber() internal returns (uint256) {
        return DEFAULT_FORK_BLOCK_NUMBER;
    }

    //// setUp function that creates the adapter and adds it to the strategy
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
        // create and initialize the multiPoolStrategy and adapter
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address AuraWeightedPoolAdapterImplementation = address(0);
        address AuraStablePoolAdapterImplementation = address(0);
        address AuraComposableStablePoolAdapterImplementation = address(0);
        multiPoolStrategyFactory = new MultiPoolStrategyFactory(
            address(this),
            ConvexPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation
            );
        multiPoolStrategy =
            MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_ASSET, "ETHX Strat"));
        convexPoolAdapter = ConvexPoolAdapter(
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
                    POOL_TOKEN_LENGTH,
                    ZAPPER,
                    USE_ETH,
                    IS_INDEX_UINT,
                    CURVE_POOL_TOKEN_INDEX
                )
            )
        );
        multiPoolStrategy.addAdapter(address(convexPoolAdapter));
        // create and initialize the ETHzapper
        ethZapper = new ETHZapper();
        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();
        deal(UNDERLYING_ASSET, address(this), 50_000 * 10 ** tokenDecimals);
        deal(UNDERLYING_ASSET, staker, 10_000 * 10 ** tokenDecimals);
    }

    //// ensure deposit works by depositing 10k WETH and checking the stored assets
    function testETHDeposit() public {
        getBlockNumber();
        ethZapper.depositETH{ value: 1000 * 10 ** tokenDecimals }(address(this), address(multiPoolStrategy));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssets, 1000 * 10 ** tokenDecimals);
        assertEq(multiPoolStrategy.balanceOf(address(ethZapper)), 0);
        assertEq(multiPoolStrategy.balanceOf(address(this)), 1000 * 10 ** tokenDecimals);
    }

    function testDeposit() public {
        getBlockNumber();
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), 10_000 * 10 ** tokenDecimals);
        multiPoolStrategy.deposit(10_000 * 10 ** tokenDecimals, address(this));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssets, 10_000 * 10 ** tokenDecimals);
        assertEq(multiPoolStrategy.balanceOf(address(this)), 10_000 * 10 ** tokenDecimals);
    }

    function testETHRedeem() public {
        //// deposit 5k WETH using this address
        uint256 depositAmount = 1 * 10 ** tokenDecimals;
        ethZapper.depositETH{ value: depositAmount }(address(this), address(multiPoolStrategy));
        /// adjust in 94% of the assets to the adapter
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterAdjustAmount = (depositAmount) * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexPoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexPoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        //// withdraw all shares using this contract as receiver should get same as put in
        uint256 underlyingBalanceInAdapterBeforeWithdraw = convexPoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 ETHBalanceOfThisBeforeRedeem = address(this).balance;
        //// need to approve shares to zapper so the zapper can spend the shares on behalf of this contract
        multiPoolStrategy.approve(address(ethZapper), 0);
        multiPoolStrategy.approve(address(ethZapper), shares);
        //// withdraw by shares (reedem)
        ethZapper.redeemETH(shares, address(this), 0, address(multiPoolStrategy));
        uint256 underlyingBalanceInAdapterAfterWithdraw = convexPoolAdapter.underlyingBalance();
        uint256 ETHBalanceOfThisAfterRedeem = address(this).balance;
        assertAlmostEq(underlyingBalanceInAdapterBeforeWithdraw, adapterAdjustAmount, adapterAdjustAmount * 2 / 100);
        assertEq(underlyingBalanceInAdapterAfterWithdraw, 0);
        assertAlmostEq(
            ETHBalanceOfThisAfterRedeem - ETHBalanceOfThisBeforeRedeem, depositAmount, depositAmount * 2 / 100
        );
    }

    function testETHWithdraw() public {
        // //// deposit 5k WETH using this address
        uint256 depositAmount = 5 * 10 ** tokenDecimals;
        ethZapper.depositETH{ value: depositAmount }(address(this), address(multiPoolStrategy));
        /// adjust in 94% of the assets to the adapter
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterAdjustAmount = (depositAmount) * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexPoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexPoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        //// withdraw all shares using this contract as receiver should get same as put in
        uint256 underlyingBalanceInAdapterBeforeWithdraw = convexPoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 ETHBalanceOfThisBeforeRedeem = address(this).balance;
        //// need to approve shares to zapper so the zapper can spend the shares on behalf of this contract
        multiPoolStrategy.approve(address(ethZapper), 0);
        multiPoolStrategy.approve(address(ethZapper), shares);
        //// withdraw by asset ( withdraw )
        uint256 assetstoWithdraw = multiPoolStrategy.previewRedeem(shares);
        ethZapper.withdrawETH(assetstoWithdraw, address(this), 0, address(multiPoolStrategy));
        uint256 underlyingBalanceInAdapterAfterWithdraw = convexPoolAdapter.underlyingBalance();
        uint256 ETHBalanceOfThisAfterRedeem = address(this).balance;
        assertAlmostEq(underlyingBalanceInAdapterBeforeWithdraw, adapterAdjustAmount, adapterAdjustAmount * 2 / 100);
        assertEq(underlyingBalanceInAdapterAfterWithdraw, 0);
        assertAlmostEq(
            ETHBalanceOfThisAfterRedeem - ETHBalanceOfThisBeforeRedeem, depositAmount, depositAmount * 2 / 100
        );
    }

    //// make this contract payable to use ETH methods
    receive() external payable { }
}
