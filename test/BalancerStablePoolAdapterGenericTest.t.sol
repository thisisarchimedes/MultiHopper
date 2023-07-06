// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MultiPoolStrategyFactory } from "../src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "../src/interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { AuraStablePoolAdapter } from "../src/AuraStablePoolAdapter.sol";
import { IBooster } from "../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../src/interfaces/ICurvePool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract BalancerStablePoolAdapterGenericTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    AuraStablePoolAdapter auraStablePoolAdapter;

    address public staker = makeAddr("staker");
    ///CONSTANTS
    address constant UNDERLYING_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //strategy underlying asset such as
        // WETH,USDC,DAI,USDT etc.
    address public constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    /// POOL CONSTANTS
    bytes32 public constant BALANCER_STABLE_POOL_ID = 0xb08885e6026bab4333a80024ec25a1a3e1ff2b8a000200000000000000000445;
    uint256 public constant AURA_PID = 63;

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
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), _depositAmount);
        multiPoolStrategy.deposit(_depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 wethBalanceOfMultiPool = IERC20(UNDERLYING_TOKEN).balanceOf(address(multiPoolStrategy));
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraStablePoolAdapter),
            amount: wethBalanceOfMultiPool * 94 / 100, // %94
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraStablePoolAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 10 weeks);
        IBooster(AURA_BOOSTER).earmarkRewards(AURA_PID);
        vm.warp(block.timestamp + 10 weeks);

        /// GRAVI AURA UNDERLYING_TOKEN REWARD DATA
        AuraStablePoolAdapter.RewardData[] memory rewardData = auraStablePoolAdapter.totalClaimable();

        assertGt(rewardData[0].amount, 0); // expect some BAL rewards

        uint256 totalCrvRewards = rewardData[0].amount;
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_TOKEN, totalCrvRewards, address(multiPoolStrategy));
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
        //// we only deploy the adapters we will use in this test
        address ConvexPoolAdapterImplementation = address(0);
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address AuraWeightedPoolAdapterImplementation = address(0);
        address AuraStablePoolAdapterImplementation = address(new AuraStablePoolAdapter());
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
            MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_TOKEN, "ETHX Strat"));
        auraStablePoolAdapter = AuraStablePoolAdapter(
            multiPoolStrategyFactory.createAuraStablePoolAdapter(
                BALANCER_STABLE_POOL_ID, address(multiPoolStrategy), AURA_PID
            )
        );
        multiPoolStrategy.addAdapter(address(auraStablePoolAdapter));
        tokenDecimals = IERC20Metadata(UNDERLYING_TOKEN).decimals();
        deal(UNDERLYING_TOKEN, address(this), 10_000 * 10 ** tokenDecimals);
        deal(UNDERLYING_TOKEN, staker, 50 * 10 ** tokenDecimals);
    }

    function testDeposit() public {
        getBlockNumber();
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), type(uint256).max);
        multiPoolStrategy.deposit(10_000 * 10 ** tokenDecimals, address(this));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssets, 10_000 * 10 ** tokenDecimals);
    }

    function testAdjustIn() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraStablePoolAdapter),
            amount: depositAmount * 94 / 100, // %94
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraStablePoolAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();
        uint256 totalAssets = multiPoolStrategy.totalAssets();
        uint256 underlyingBalance = auraStablePoolAdapter.underlyingBalance();

        assertEq(storedAssetsBefore, depositAmount);
        assertEq(storedAssetsAfter, storedAssetsBefore - depositAmount * 94 / 100);
        assertAlmostEq(totalAssets, depositAmount, depositAmount * 2 / 100); // %2 slippage
    }

    function testAdjustOut() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustInAmount = depositAmount * 94 / 100;
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(auraStablePoolAdapter), amount: adjustInAmount, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraStablePoolAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();

        adjustIns = new MultiPoolStrategy.Adjust[](0);
        adjustOuts = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterLpBalance = auraStablePoolAdapter.lpBalance();
        adjustOuts[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraStablePoolAdapter),
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
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterAdjustAmount = depositAmount * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraStablePoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraStablePoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 underlyingBalanceInAdapterBeforeWithdraw = auraStablePoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 underlyingBalanceOfThisBeforeRedeem = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        multiPoolStrategy.redeem(shares, address(this), address(this), 0);
        uint256 underlyingBalanceInAdapterAfterWithdraw = auraStablePoolAdapter.underlyingBalance();
        uint256 underlyingBalanceOfThisAfterRedeem = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        assertAlmostEq(underlyingBalanceInAdapterBeforeWithdraw, adapterAdjustAmount, adapterAdjustAmount * 2 / 100);
        assertEq(underlyingBalanceInAdapterAfterWithdraw, 0);
        assertAlmostEq(
            underlyingBalanceOfThisAfterRedeem - underlyingBalanceOfThisBeforeRedeem,
            depositAmount,
            depositAmount * 2 / 100
        );
    }

    function testClaimRewards() public {
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), type(uint256).max);
        multiPoolStrategy.deposit(500 * 10 ** tokenDecimals, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraStablePoolAdapter),
            amount: 440 * 10 ** tokenDecimals,
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraStablePoolAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 1 weeks);
        IBooster(AURA_BOOSTER).earmarkRewards(AURA_PID);
        vm.warp(block.timestamp + 1 weeks);

        /// ETH PETH REWARD DATA
        AuraStablePoolAdapter.RewardData[] memory rewardData = auraStablePoolAdapter.totalClaimable();

        assertGt(rewardData[0].amount, 0); // expect some BAL rewards

        uint256 totalCrvRewards = rewardData[0].amount;
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_TOKEN, totalCrvRewards, address(multiPoolStrategy));
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](1);
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: totalCrvRewards, callData: txData });
        uint256 wethBalanceBefore = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 wethBalanceAfter = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        uint256 crvBalanceAfter = IERC20(rewardData[0].token).balanceOf(address(multiPoolStrategy));
        assertEq(crvBalanceAfter, 0);
        assertEq(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_TOKEN
    }

    function testWithdrawExceedContractBalance() public {
        uint256 depositAmount = 100 * 10 ** tokenDecimals;
        vm.startPrank(staker);
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), type(uint256).max);
        multiPoolStrategy.deposit(50 * 10 ** tokenDecimals, address(staker));
        vm.stopPrank();
        harvest(depositAmount);
        vm.warp(block.timestamp + 10 days);
        uint256 stakerShares = multiPoolStrategy.balanceOf(staker);
        uint256 withdrawAmount = multiPoolStrategy.convertToAssets(stakerShares);
        vm.startPrank(staker);
        multiPoolStrategy.withdraw(withdrawAmount, address(staker), staker, 0);
        vm.stopPrank();
        uint256 stakerSharesAfter = multiPoolStrategy.balanceOf(staker);
        uint256 stakerWethBalance = IERC20(UNDERLYING_TOKEN).balanceOf(address(staker));
        assertGt(withdrawAmount, 50 * 10 ** tokenDecimals);
        assertEq(stakerSharesAfter, 0);
        assertAlmostEq(stakerWethBalance, withdrawAmount, withdrawAmount * 300 / 10_000); // %3 slippage
    }
}
