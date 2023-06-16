// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MultiPoolStrategyFactory } from "../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../src/ConvexPoolAdapter.sol";
import { IBaseRewardPool } from "../src/interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../src/AuraWeightedPoolAdapter.sol";
import { IBooster } from "../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../src/interfaces/ICurvePool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MultiPoolStrategyTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexGenericAdapter;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");
    ///CONSTANTS
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // strategy underlying asset such as
        // USDC,WETH etc.
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    ///ETH/PETH
    address constant CURVE_POOL = 0x68934F60758243eafAf4D2cFeD27BF8010bede3a;
    uint256 constant CONVEX_PID = 158;
    bool constant USE_ETH = false;
    int128 constant CURVE_POOL_TOKEN_INDEX = 2;
    bool constant IS_INDEX_UINT = false;
    uint256 constant POOL_TOKEN_LENGTH = 3;
    address constant ZAPPER = 0x08780fb7E580e492c1935bEe4fA5920b94AA95Da;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_421_496;
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
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        string[] memory inputs = new string[](3);
        inputs[0] = "python3";
        inputs[1] = "test/get_latest_block_number.py";
        inputs[2] = string(abi.encodePacked("https://eth-mainnet.g.alchemy.com/v2/", alchemyApiKey));
        bytes memory result = vm.ffi(inputs);
        uint256 blockNumber;
        assembly {
            blockNumber := mload(add(result, 0x20))
        }
        forkBlockNumber = blockNumber - 10; //set it to 10 blocks before latest block so we can use the
        return blockNumber;
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
                    CURVE_POOL,
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
        vm.startPrank(staker);
        multiPoolStrategy.withdraw(withdrawAmount, address(staker), staker, 0);
        vm.stopPrank();
        uint256 stakerSharesAfter = multiPoolStrategy.balanceOf(staker);
        uint256 stakerWethBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(staker));
        assertGt(withdrawAmount, depositAmount / 2);
        assertEq(stakerSharesAfter, 0);
        assertAlmostEq(stakerWethBalance, withdrawAmount, withdrawAmount * 100 / 10_000); // %1 margin of error
    }
}
