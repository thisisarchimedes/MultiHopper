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

contract MultiPoolStrategyTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexEthPEthAdapter;
    ConvexPoolAdapter convexEthMsEthAdapter;
    ConvexPoolAdapter convexEthAlEthAdapter;

    address public staker = makeAddr("staker");
    ///CONSTANTS
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    ///ETH/PETH
    address constant CURVE_ETH_PETH = 0x9848482da3Ee3076165ce6497eDA906E66bB85C5;
    uint256 constant CONVEX_ETH_PETH_PID = 122;
    address constant PETH = 0x836A808d4828586A69364065A1e064609F5078c7;
    ///ETH/msETH
    address constant CURVE_ETH_MS_ETH = 0xc897b98272AA23714464Ea2A0Bd5180f1B8C0025;
    uint256 constant CONVEX_ETH_MS_ETH_PID = 145;
    ///ETH/alETH
    address constant CURVE_ETH_AL_ETH = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e;
    uint256 constant CONVEX_ETH_AL_ETH_PID = 49;
    uint256 forkBlockNumber;

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
        IERC20(WETH).approve(address(multiPoolStrategy), _depositAmount);
        multiPoolStrategy.deposit(_depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](3);
        uint256 wethBalanceOfMultiPool = IERC20(WETH).balanceOf(address(multiPoolStrategy));
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexEthPEthAdapter),
            amount: wethBalanceOfMultiPool * 10 / 20, // %50
            minReceive: 0
        });
        adjustIns[1] = MultiPoolStrategy.Adjust({
            adapter: address(convexEthMsEthAdapter),
            amount: wethBalanceOfMultiPool * 5 / 20, // %25
            minReceive: 0
        });
        adjustIns[2] = MultiPoolStrategy.Adjust({
            adapter: address(convexEthAlEthAdapter),
            amount: wethBalanceOfMultiPool * 3 / 20, // %15
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](3);
        adapters[0] = address(convexEthAlEthAdapter);
        adapters[2] = address(convexEthPEthAdapter);
        adapters[1] = address(convexEthMsEthAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 10 weeks);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_ETH_PETH_PID);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_ETH_MS_ETH_PID);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_ETH_AL_ETH_PID);
        vm.warp(block.timestamp + 10 weeks);

        /// ETH PETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData = convexEthPEthAdapter.totalClaimable();
        /// ETH MS ETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData2 = convexEthMsEthAdapter.totalClaimable();
        /// ETH AL ETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData3 = convexEthAlEthAdapter.totalClaimable();
        assertGt(rewardData[0].amount, 0); // expect some CRV rewards
        assertGt(rewardData2[0].amount, 0); // expect some CRV rewards
        assertGt(rewardData3[0].amount, 0); // expect some CRV rewards
        uint256 totalCrvRewards = rewardData[0].amount + rewardData2[0].amount + rewardData3[0].amount;
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, WETH, totalCrvRewards, address(multiPoolStrategy));
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
        vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: forkBlockNumber == 0 ? 17_359_389 : forkBlockNumber });
        multiPoolStrategyFactory = new MultiPoolStrategyFactory(address(this));
        multiPoolStrategy = MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(WETH, "ETHX Strat"));
        convexEthPEthAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_ETH_PETH, address(multiPoolStrategy), CONVEX_ETH_PETH_PID, 2, address(0), false, true, false
                )
            )
        );
        convexEthMsEthAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_ETH_MS_ETH,
                    address(multiPoolStrategy),
                    CONVEX_ETH_MS_ETH_PID,
                    2,
                    address(0),
                    false,
                    true,
                    false
                )
            )
        );
        convexEthAlEthAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_ETH_AL_ETH,
                    address(multiPoolStrategy),
                    CONVEX_ETH_AL_ETH_PID,
                    2,
                    address(0),
                    false,
                    true,
                    false
                )
            )
        );
        multiPoolStrategy.addAdapter(address(convexEthPEthAdapter));
        multiPoolStrategy.addAdapter(address(convexEthMsEthAdapter));
        multiPoolStrategy.addAdapter(address(convexEthAlEthAdapter));

        deal(WETH, address(this), 10_000e18);
        deal(WETH, staker, 50e18);
    }

    function testDeposit() public {
        getBlockNumber();
        IERC20(WETH).approve(address(multiPoolStrategy), 10_000e18);
        multiPoolStrategy.deposit(10_000e18, address(this));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssets, 10_000e18);
    }

    function testAdjustIn() public {
        IERC20(WETH).approve(address(multiPoolStrategy), 10_000e18);
        multiPoolStrategy.deposit(10_000e18, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](3);
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthPEthAdapter), amount: 2500e18, minReceive: 0 });
        adjustIns[1] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthMsEthAdapter), amount: 5000e18, minReceive: 0 });
        adjustIns[2] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthAlEthAdapter), amount: 2000e18, minReceive: 0 });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](3);
        adapters[0] = address(convexEthAlEthAdapter);
        adapters[1] = address(convexEthPEthAdapter);
        adapters[2] = address(convexEthMsEthAdapter);
        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssetsBefore, 10_000e18);
        assertEq(storedAssetsAfter, storedAssetsBefore - 2500e18 - 5000e18 - 2000e18);
    }

    function testCantAdjustInRewards() public {
        IERC20(WETH).approve(address(multiPoolStrategy), 10_000e18);
        multiPoolStrategy.deposit(10_000e18, address(this));
        deal(WETH, address(multiPoolStrategy), 11_000e18); //mimic the reward distribution
        address[] memory adapters;
        MultiPoolStrategy.SwapData[] memory swapDatas;
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 lastReward = multiPoolStrategy.lastRewardAmount();
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](3);
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthPEthAdapter), amount: 5000e18, minReceive: 0 });
        adjustIns[1] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthMsEthAdapter), amount: 5000e18, minReceive: 0 });
        adjustIns[2] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthAlEthAdapter), amount: 200e18, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        adapters = new address[](3);
        adapters[0] = address(convexEthAlEthAdapter);
        adapters[1] = address(convexEthPEthAdapter);
        adapters[2] = address(convexEthMsEthAdapter);
        vm.expectRevert();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        assertEq(lastReward, 1000e18);
    }

    function testClaimRewards() public {
        IERC20(WETH).approve(address(multiPoolStrategy), 10_000e18);
        multiPoolStrategy.deposit(10_000e18, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](3);
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthPEthAdapter), amount: 2500e18, minReceive: 0 });
        adjustIns[1] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthMsEthAdapter), amount: 5000e18, minReceive: 0 });
        adjustIns[2] =
            MultiPoolStrategy.Adjust({ adapter: address(convexEthAlEthAdapter), amount: 2000e18, minReceive: 0 });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](3);
        adapters[0] = address(convexEthAlEthAdapter);
        adapters[1] = address(convexEthPEthAdapter);
        adapters[2] = address(convexEthMsEthAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 1 weeks);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_ETH_PETH_PID);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_ETH_MS_ETH_PID);
        IBooster(CONVEX_BOOSTER).earmarkRewards(CONVEX_ETH_AL_ETH_PID);
        vm.warp(block.timestamp + 1 weeks);

        /// ETH PETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData = convexEthPEthAdapter.totalClaimable();
        /// ETH MS ETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData2 = convexEthMsEthAdapter.totalClaimable();
        /// ETH AL ETH REWARD DATA
        ConvexPoolAdapter.RewardData[] memory rewardData3 = convexEthAlEthAdapter.totalClaimable();
        assertGt(rewardData[0].amount, 0); // expect some CRV rewards
        assertGt(rewardData2[0].amount, 0); // expect some CRV rewards
        assertGt(rewardData3[0].amount, 0); // expect some CRV rewards
        uint256 totalCrvRewards = rewardData[0].amount + rewardData2[0].amount + rewardData3[0].amount;
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, WETH, totalCrvRewards, address(multiPoolStrategy));
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](1);
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: totalCrvRewards, callData: txData });
        uint256 wethBalanceBefore = IERC20(WETH).balanceOf(address(this));
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 wethBalanceAfter = IERC20(WETH).balanceOf(address(this));
        uint256 crvBalanceAfter = IERC20(rewardData[0].token).balanceOf(address(multiPoolStrategy));
        assertEq(crvBalanceAfter, 0);
        assertEq(wethBalanceAfter - wethBalanceBefore, 0); // expect receive weth
    }

    function testWithdrawExceedContractBalance() public {
        uint256 depositAmount = 100e18;
        vm.startPrank(staker);
        IERC20(WETH).approve(address(multiPoolStrategy), 50e18);
        multiPoolStrategy.deposit(50e18, address(staker));
        vm.stopPrank();
        harvest(depositAmount);
        vm.warp(block.timestamp + 10 days);
        uint256 stakerShares = multiPoolStrategy.balanceOf(staker);
        uint256 withdrawAmount = multiPoolStrategy.convertToAssets(stakerShares);
        vm.startPrank(staker);
        multiPoolStrategy.withdraw(withdrawAmount, address(staker), staker);
        vm.stopPrank();
        uint256 stakerSharesAfter = multiPoolStrategy.balanceOf(staker);
        uint256 stakerWethBalance = IERC20(WETH).balanceOf(address(staker));
        assertGt(withdrawAmount, 50e18);
        assertEq(stakerSharesAfter, 0);
        assertAlmostEq(stakerWethBalance, withdrawAmount, withdrawAmount * 100 / 10_000); // %1 margin of error
    }

    function testFlashLoanAttack() public {
        IERC20(WETH).approve(address(multiPoolStrategy), 100e18);
        multiPoolStrategy.deposit(100e18, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 wethBalanceOfMultiPool = IERC20(WETH).balanceOf(address(multiPoolStrategy));
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexEthPEthAdapter),
            amount: wethBalanceOfMultiPool * 94 / 100,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](3);
        adapters[0] = address(convexEthAlEthAdapter);
        adapters[2] = address(convexEthPEthAdapter);
        adapters[1] = address(convexEthMsEthAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);

        /// attack
        FlashLoanAttackTest flashLoanAttackTest = new FlashLoanAttackTest(
                WETH,
                PETH,
                address(multiPoolStrategy),
                CURVE_ETH_PETH,
                0,
                1
            );
        deal(PETH, address(flashLoanAttackTest), 10_000e18);
        deal(WETH, address(flashLoanAttackTest), 10e18);
        vm.expectRevert(MultiPoolStrategy.AdapterNotHealthy.selector);
        flashLoanAttackTest.attack(10e18, 10_000e18);
    }

    function testAttackTwo() public {
        deal(WETH, address(this), 20_000e18);
        IERC20(WETH).approve(address(multiPoolStrategy), 20_000e18);
        multiPoolStrategy.deposit(20_000e18, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 wethBalanceOfMultiPool = IERC20(WETH).balanceOf(address(multiPoolStrategy));
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(convexEthPEthAdapter),
            amount: wethBalanceOfMultiPool * 94 / 100,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](3);
        adapters[0] = address(convexEthAlEthAdapter);
        adapters[2] = address(convexEthPEthAdapter);
        adapters[1] = address(convexEthMsEthAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);

        /// attack
        FlashLoanAttackTest flashLoanAttackTest = new FlashLoanAttackTest(
                WETH,
                PETH,
                address(multiPoolStrategy),
                CURVE_ETH_PETH,
                0,
                1
            );
        deal(PETH, address(flashLoanAttackTest), 10_000e18);
        deal(WETH, address(staker), 100e18);
        flashLoanAttackTest.destroyRatio(10_000e18);
        multiPoolStrategy.withdraw(1250e18, address(this), address(this)); // update the stored underlying balance
        vm.startPrank(address(staker));
        IERC20(WETH).approve(address(multiPoolStrategy), 100e18);
        vm.expectRevert(MultiPoolStrategy.AdapterNotHealthy.selector);
        multiPoolStrategy.deposit(100e18, address(staker));
        vm.stopPrank();
        flashLoanAttackTest.fixRatio();
        uint256 stakerShares = multiPoolStrategy.balanceOf(address(staker));
        vm.startPrank(staker);
        multiPoolStrategy.redeem(stakerShares, address(staker), address(staker));
        vm.stopPrank();
    }
}
