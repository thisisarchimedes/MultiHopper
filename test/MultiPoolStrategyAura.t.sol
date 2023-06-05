// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MultiPoolStrategyFactory } from "../src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "../src/interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../src/AuraWeightedPoolAdapter.sol";
import { IBooster } from "../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../src/interfaces/ICurvePool.sol";

contract MultiPoolStrategyAuraTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    AuraWeightedPoolAdapter graviAuraWethAdapter;

    address public staker = makeAddr("staker");
    ///CONSTANTS
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    /// GRAVI AURA WETH POOL
    bytes32 public constant GRAVI_AURA_WETH_POOL_ID = 0x0578292cb20a443ba1cde459c985ce14ca2bdee5000100000000000000000269;
    uint256 public constant GRAVI_AURA_WETH_POOL_PID = 35;

    /// daiusdcustweth pool
    bytes32 public constant DAI_USDC_USDT_WETH_POOL_ID =
        0x08775ccb6674d6bdceb0797c364c2653ed84f3840002000000000000000004f0;
    uint256 public constant DAI_USDC_USDT_WETH_POOL_PID = 84;

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
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 wethBalanceOfMultiPool = IERC20(WETH).balanceOf(address(multiPoolStrategy));
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(graviAuraWethAdapter),
            amount: wethBalanceOfMultiPool * 94 / 100, // %94
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(graviAuraWethAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 10 weeks);
        IBooster(AURA_BOOSTER).earmarkRewards(GRAVI_AURA_WETH_POOL_PID);
        vm.warp(block.timestamp + 10 weeks);

        /// GRAVI AURA WETH REWARD DATA
        AuraWeightedPoolAdapter.RewardData[] memory rewardData = graviAuraWethAdapter.totalClaimable();

        assertGt(rewardData[0].amount, 0); // expect some BAL rewards

        uint256 totalCrvRewards = rewardData[0].amount;
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
        graviAuraWethAdapter = AuraWeightedPoolAdapter(
            multiPoolStrategyFactory.createAuraWeightedPoolAdapter(
                GRAVI_AURA_WETH_POOL_ID, address(multiPoolStrategy), GRAVI_AURA_WETH_POOL_PID
            )
        );
        multiPoolStrategy.addAdapter(address(graviAuraWethAdapter));

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
        IERC20(WETH).approve(address(multiPoolStrategy), 500e18);
        multiPoolStrategy.deposit(500e18, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(graviAuraWethAdapter), amount: 440e18, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(graviAuraWethAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssetsBefore, 500e18);
        assertEq(storedAssetsAfter, storedAssetsBefore - 440e18);
    }

    function testClaimRewards() public {
        IERC20(WETH).approve(address(multiPoolStrategy), 500e18);
        multiPoolStrategy.deposit(500e18, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(graviAuraWethAdapter), amount: 440e18, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(graviAuraWethAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 1 weeks);
        IBooster(AURA_BOOSTER).earmarkRewards(GRAVI_AURA_WETH_POOL_PID);
        vm.warp(block.timestamp + 1 weeks);

        /// ETH PETH REWARD DATA
        AuraWeightedPoolAdapter.RewardData[] memory rewardData = graviAuraWethAdapter.totalClaimable();

        assertGt(rewardData[0].amount, 0); // expect some BAL rewards

        uint256 totalCrvRewards = rewardData[0].amount;
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
        multiPoolStrategy.withdraw(withdrawAmount, address(staker), staker, 0);
        vm.stopPrank();
        uint256 stakerSharesAfter = multiPoolStrategy.balanceOf(staker);
        uint256 stakerWethBalance = IERC20(WETH).balanceOf(address(staker));
        assertGt(withdrawAmount, 50e18);
        assertEq(stakerSharesAfter, 0);
        assertAlmostEq(stakerWethBalance, withdrawAmount, withdrawAmount * 300 / 10_000); // %3 slippage
    }
}
