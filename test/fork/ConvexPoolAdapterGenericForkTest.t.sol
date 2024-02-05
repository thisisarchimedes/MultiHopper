// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19.0;

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

/* 
    @title ConvexPoolAdapterGenericForkTest
    @dev This test assumes that all contract already deployed on mainnet. 
    @dev Doesn't deploy any contract. "Prunks" Monitor address to be able to adjust in and out.
*/
contract ConvexPoolAdapterGenericForkTest is PRBTest, StdCheats {
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
    address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

    /**
     * @dev address of zapper for pool if needed
     */
    address constant ZAPPER = 0x08780fb7E580e492c1935bEe4fA5920b94AA95Da;

    address payable constant STRATEGY = payable(0xfA364CBca915f17fEc356E35B61541fC6D4D8269);
    address payable constant ADAPTER = payable(0xAa04430d364458A7fC98643585eA2E45a4955acd);

    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    uint256 public constant CONVEX_PID = 185;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_829_684;
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

    function getBlockNumber() internal view returns (uint256) {
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
        (, bytes memory txData) =
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

        multiPoolStrategy = MultiPoolStrategy(STRATEGY);
        convexGenericAdapter = ConvexPoolAdapter(ADAPTER);

        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();

        (address _curveLpToken,,,,,) = IBooster(CONVEX_BOOSTER).poolInfo(CONVEX_PID);
        curveLpToken = IERC20(_curveLpToken);

        deal(UNDERLYING_ASSET, address(this), 10_000e18);
        deal(UNDERLYING_ASSET, staker, 50e18);
    }

    function testDeposit() public {
        getBlockNumber();

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();

        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), 500 * 10 ** tokenDecimals);
        multiPoolStrategy.deposit(500 * 10 ** tokenDecimals, address(this));
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();

        assertEq(storedAssetsAfter - storedAssetsBefore, 500 * 10 ** tokenDecimals);
    }

    function testAdjustIn() public {
        // assume Monitor address so we can adjust
        address monitor = multiPoolStrategy.monitor();
        vm.startPrank(monitor);
        deal(UNDERLYING_ASSET, monitor, 10_000e18);

        // adjusting in
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        console2.log("dep amount", depositAmount);
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustOutAmount = depositAmount * 94 / 100;
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexGenericAdapter), amount: adjustOutAmount, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();

        assertEq(storedAssetsAfter, storedAssetsBefore - adjustOutAmount);

        vm.stopPrank();
    }

    function testAdjustOut() public {
        // assume Monitor address so we can adjust
        address monitor = multiPoolStrategy.monitor();
        vm.startPrank(monitor);
        deal(UNDERLYING_ASSET, monitor, 10_000e18);

        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustOutAmount = depositAmount * 94 / 100;
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexGenericAdapter), amount: adjustOutAmount, minReceive: 0 });

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

        assertEq(storedAssetsAfter, storedAssetsBefore - adjustOutAmount);
        assertAlmostEq(storedAssetAfterAdjustTwo, depositAmount, depositAmount * 2 / 100);

        vm.stopPrank();
    }

    function testWithdraw() public {
        // assume Monitor address so we can adjust
        address monitor = multiPoolStrategy.monitor();
        vm.startPrank(monitor);
        deal(UNDERLYING_ASSET, monitor, 10_000e18);

        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);

        multiPoolStrategy.deposit(depositAmount, monitor);
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
        uint256 shares = multiPoolStrategy.balanceOf(monitor);
        multiPoolStrategy.redeem(shares, monitor, monitor, 0);
        uint256 underlyingBalanceInAdapterAfterWithdraw = convexGenericAdapter.underlyingBalance();

        assertLt(underlyingBalanceInAdapterAfterWithdraw, underlyingBalanceInAdapterBeforeWithdraw);

        vm.stopPrank();
    }

    function testClaimRewards() public {
        // assume Monitor address so we can adjust
        address monitor = multiPoolStrategy.monitor();
        vm.startPrank(monitor);
        deal(UNDERLYING_ASSET, monitor, 10_000e18);

        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, monitor);
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustOutAmount = depositAmount * 94 / 100;
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexGenericAdapter), amount: adjustOutAmount, minReceive: 0 });

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
        (, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_ASSET, totalCrvRewards, address(multiPoolStrategy));
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](1);
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: totalCrvRewards, callData: txData });
        uint256 wethBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(monitor);
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 wethBalanceAfter = IERC20(UNDERLYING_ASSET).balanceOf(monitor);
        uint256 crvBalanceAfter = IERC20(rewardData[0].token).balanceOf(monitor);
        assertEq(crvBalanceAfter, 0);
        assertEq(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_ASSET

        vm.stopPrank();
    }

    function testWithdrawExceedContractBalance() public {
        // assume Monitor address so we can adjust
        address monitor = multiPoolStrategy.monitor();
        vm.startPrank(monitor);
        deal(UNDERLYING_ASSET, monitor, 10_000e18);

        uint256 depositAmount = 100 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), depositAmount / 2);
        multiPoolStrategy.deposit(depositAmount / 2, monitor);

        harvest(depositAmount);
        vm.warp(block.timestamp + 10 days);

        uint256 stakerShares = multiPoolStrategy.balanceOf(staker);
        uint256 withdrawAmount = multiPoolStrategy.convertToAssets(stakerShares);
        uint256 stakerUnderlyingBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(staker));

        multiPoolStrategy.withdraw(withdrawAmount, monitor, monitor, 0);

        uint256 stakerSharesAfter = multiPoolStrategy.balanceOf(monitor);
        uint256 stakerUnderlyingBalanceAfter = IERC20(UNDERLYING_ASSET).balanceOf(monitor);
        console2.log("balance", stakerUnderlyingBalanceAfter - stakerUnderlyingBalanceBefore);
        console2.log("withdrawAmount", withdrawAmount);

        assertGt(withdrawAmount, depositAmount / 2);
        assertEq(stakerSharesAfter, 0);
        assertAlmostEq(
            stakerUnderlyingBalanceAfter - stakerUnderlyingBalanceBefore, withdrawAmount, withdrawAmount * 100 / 10_000
        ); // %1 margin of error

        vm.stopPrank();
    }
}
