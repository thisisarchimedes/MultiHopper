// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../../src/ConvexPoolAdapter.sol";
import { IBaseRewardPool } from "../../src/interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../../src/AuraWeightedPoolAdapter.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../../src/interfaces/ICurvePool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";

contract ConvexPoolAdapterFRAXBPalUSDPGenericTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexGenericAdapter;
    IERC20 curveLpToken;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");
    ///CONSTANTS
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC; // FRAXBP

    /**
     * @dev Address of the Convex booster contract.
     * default: https://etherscan.io/address/0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /**
     * @dev Address of the Curve pool used in the integration.
     * default: ETH/msETH Curve pool
     */
    address public constant CURVE_POOL_ADDRESS = 0xB30dA2376F63De30b42dC055C93fa474F31330A5; // https://curve.fi/#/ethereum/pools/factory-v2-147/deposit

    /**
     * @dev Convex pool ID used in the integration.
     * default: ETH/msETH Curve pool PID
     */
    uint256 public constant CONVEX_PID = 106;

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "FRAXBP/alUSD Stra";

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
    bool constant IS_INDEX_UINT = false;

    /**
     * @dev the amount of tokens used in this pool , e.g. 2 for ETH/msETH
     */
    uint256 constant POOL_TOKEN_LENGTH = 2;

    /**
     * @dev address of zapper for pool if needed
     */
    address constant ZAPPER = address(0);

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_637_485;
    uint8 tokenDecimals;

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

    function getBlockNumber() internal returns (uint256) {
        return DEFAULT_FORK_BLOCK_NUMBER;
    }

    function harvest(uint256 _depositAmount) internal {
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), _depositAmount);
        multiPoolStrategy.deposit(_depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 wethBalanceOfMultiPool = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexGenericAdapter),
            amount: wethBalanceOfMultiPool * 94 / 100, // %50
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 10 weeks);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_PID);

        vm.warp(block.timestamp + 10 weeks);

        /// ETH PETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData = convexGenericAdapter.totalClaimable();

        assertGt(rewardData[0].amount, 0); // expect some CRV rewards

        uint256 totalCrvRewards = rewardData[0].amount;
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_ASSET, totalCrvRewards, address(multiPoolStrategy));
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](1);
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: totalCrvRewards, callData: txData });
        multiPoolStrategy.doHardWork(adapters, swapDatas);
    }

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
        multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_ASSET, "Generic MultiPool Strategy")
        );
        convexGenericAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
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

        multiPoolStrategy.addAdapter(address(convexGenericAdapter));
        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();
        multiPoolStrategy.changeFeeRecipient(feeRecipient);
        (address _curveLpToken,,,,,) = IBooster(CONVEX_BOOSTER).poolInfo(CONVEX_PID);
        curveLpToken = IERC20(_curveLpToken);
        deal(UNDERLYING_ASSET, address(this), 10_000e18);
        deal(UNDERLYING_ASSET, staker, 50e18);
    }

    function testDeposit() public {
        getBlockNumber();
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), 500 * 10 ** tokenDecimals);
        multiPoolStrategy.deposit(500 * 10 ** tokenDecimals, address(this));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssets, 500 * 10 ** tokenDecimals);
    }

    function testAdjustIn() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        console2.log("dep amount", depositAmount);
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        uint256 curveLPBalance = curveLpToken.balanceOf(address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustInAmount = depositAmount * 94 / 100;
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexGenericAdapter), amount: adjustInAmount, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssetsBefore, depositAmount);
        assertEq(storedAssetsAfter, storedAssetsBefore - adjustInAmount);
    }

    function testAdjustOut() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustInAmount = depositAmount * 94 / 100;
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexGenericAdapter), amount: adjustInAmount, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();

        adjustIns = new MultiPoolStrategy.Adjust[](0);
        adjustOuts = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterLpBalance = convexGenericAdapter.lpBalance();
        adjustOuts[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexGenericAdapter),
            amount: adapterLpBalance,
            minReceive: 0
        });

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetAfterAdjustTwo = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssetsBefore, depositAmount);
        assertEq(storedAssetsAfter, storedAssetsBefore - adjustInAmount);
        assertAlmostEq(storedAssetAfterAdjustTwo, depositAmount, depositAmount * 2 / 100);
    }

    function testWithdraw() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterAdjustAmount = depositAmount * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexGenericAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 underlyingBalanceInAdapterBeforeWithdraw = convexGenericAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 underlyingBalanceOfThisBeforeRedeem = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        multiPoolStrategy.redeem(shares, address(this), address(this), 0);
        uint256 underlyingBalanceInAdapterAfterWithdraw = convexGenericAdapter.underlyingBalance();
        uint256 underlyingBalanceOfThisAfterRedeem = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        assertAlmostEq(underlyingBalanceInAdapterBeforeWithdraw, adapterAdjustAmount, adapterAdjustAmount * 2 / 100);
        assertEq(underlyingBalanceInAdapterAfterWithdraw, 0);
        assertAlmostEq(
            underlyingBalanceOfThisAfterRedeem - underlyingBalanceOfThisBeforeRedeem,
            depositAmount,
            depositAmount * 2 / 100
        );
    }

    function testClaimRewards() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustInAmount = depositAmount * 94 / 100;
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexGenericAdapter), amount: adjustInAmount, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 1 weeks);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_PID);
        vm.warp(block.timestamp + 1 weeks);

        /// ETH PETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData = convexGenericAdapter.totalClaimable();

        assertGt(rewardData[0].amount, 0); // expect some CRV rewards
        assertGt(rewardData[1].amount, 0); // expect some CVX rewards

        uint256 totalCrvRewards = rewardData[0].amount;
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_ASSET, totalCrvRewards, address(multiPoolStrategy));
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](1);
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: totalCrvRewards, callData: txData });
        uint256 wethBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 wethBalanceAfter = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 crvBalanceAfter = IERC20(rewardData[0].token).balanceOf(address(multiPoolStrategy));
        assertEq(crvBalanceAfter, 0);
        assertEq(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_ASSET
    }

    function testWithdrawExceedContractBalance() public {
        uint256 depositAmount = 100 * 10 ** tokenDecimals;
        vm.startPrank(staker);
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount / 2);
        multiPoolStrategy.deposit(depositAmount / 2, address(staker));
        vm.stopPrank();
        harvest(depositAmount);
        vm.warp(block.timestamp + 10 days);
        uint256 stakerShares = multiPoolStrategy.balanceOf(staker);
        uint256 withdrawAmount = multiPoolStrategy.convertToAssets(stakerShares);
        uint256 stakerUnderlyingBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(staker));
        vm.startPrank(staker);
        multiPoolStrategy.withdraw(withdrawAmount, address(staker), staker, 0);
        vm.stopPrank();
        uint256 stakerSharesAfter = multiPoolStrategy.balanceOf(staker);
        uint256 stakerUnderlyingBalanceAfter = IERC20(UNDERLYING_ASSET).balanceOf(address(staker));
        console2.log("balance", stakerUnderlyingBalanceAfter - stakerUnderlyingBalanceBefore);
        console2.log("withdrawAmount", withdrawAmount);
        assertGt(withdrawAmount, depositAmount / 2);
        assertEq(stakerSharesAfter, 0);
        assertAlmostEq(
            stakerUnderlyingBalanceAfter - stakerUnderlyingBalanceBefore, withdrawAmount, withdrawAmount * 100 / 10_000
        ); // %1 margin of error
    }
}
