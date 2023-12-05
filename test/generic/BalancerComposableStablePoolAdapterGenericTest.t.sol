// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19 <0.9.0;

import "forge-std/StdStorage.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "../../src/interfaces/IBaseRewardPool.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraComposableStablePoolAdapter } from "../../src/AuraComposableStablePoolAdapter.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../../src/interfaces/ICurvePool.sol";
import { ICVX } from "../../src/interfaces/ICVX.sol";

contract BalancerComposableStablePoolAdapterGenericTest is PRBTest, StdCheats {
    using stdStorage for StdStorage;

    StdStorage stdstore;

    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    AuraComposableStablePoolAdapter auraComposableStablePoolAdapter;

    address public staker = makeAddr("staker");
    ///CONSTANTS
    address constant UNDERLYING_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    /// POOL CONSTANTS
    bytes32 public constant BALANCER_STABLE_POOL_ID = 0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7;
    uint256 public constant AURA_PID = 76;

    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    address public constant BAL_TOKEN_ADDRESS = 0xba100000625a3754423978a60c9317c58a424e3D;

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
        console2.log("srcToken", srcToken);
        console2.log("dstToken", dstToken);
        console2.log("amount", amount);
        console2.log("fromAddress", fromAddress);

        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "test/get_quote_lifi.py";
        inputs[2] = vm.toString(srcToken);
        inputs[3] = vm.toString(dstToken);
        inputs[4] = vm.toString(amount);
        inputs[5] = vm.toString(fromAddress);

        return abi.decode(vm.ffi(inputs), (uint256, bytes));
    }

    function _calculateAuraRewards(uint256 _balRewards) internal view returns (uint256) {
        (,,, address _auraRewardPool,,) = IBooster(AURA_BOOSTER).poolInfo(AURA_PID);
        uint256 rewardMultiplier = IBooster(AURA_BOOSTER).getRewardMultipliers(_auraRewardPool);
        uint256 auraMaxSupply = 5e25; //50m
        uint256 auraInitMintAmount = 5e25; //50m
        uint256 totalCliffs = 500;
        bytes32 slotVal = vm.load(AURA, bytes32(uint256(7)));
        uint256 minterMinted = uint256(slotVal);
        uint256 mintAmount = _balRewards * rewardMultiplier / 10_000;
        uint256 emissionsMinted = IERC20(AURA).totalSupply() - auraInitMintAmount - minterMinted;
        uint256 cliff = emissionsMinted / ICVX(AURA).reductionPerCliff();
        uint256 auraRewardAmount;

        if (cliff < totalCliffs) {
            uint256 reduction = (totalCliffs - cliff) * 5 / 2 + 700;
            auraRewardAmount = mintAmount * reduction / totalCliffs;
            uint256 amtTillMax = auraMaxSupply - emissionsMinted;
            if (auraRewardAmount > amtTillMax) {
                auraRewardAmount = amtTillMax;
            }
        }
        return auraRewardAmount;
    }

    function getBlockNumber() internal returns (uint256) {
        return DEFAULT_FORK_BLOCK_NUMBER;
    }

    function harvest(uint256 _depositAmount) internal {
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), _depositAmount);
        multiPoolStrategy.deposit(_depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 wethBalanceOfMultiPool = IERC20(UNDERLYING_TOKEN).balanceOf(address(multiPoolStrategy));
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraComposableStablePoolAdapter),
            amount: wethBalanceOfMultiPool * 94 / 100, // %94
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);

        (,,, address _auraRewardPool,,) = IBooster(AURA_BOOSTER).poolInfo(AURA_PID);
        console2.log("auraRewardPool", _auraRewardPool);

        utils_writeAuraPoolReward(_auraRewardPool, address(this), 600 * 10 ** 18);

        /// GRAVI AURA UNDERLYING_TOKEN REWARD DATA
        AuraComposableStablePoolAdapter.RewardData[] memory rewardData =
            auraComposableStablePoolAdapter.totalClaimable();

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
        address AuraStablePoolAdapterImplementation = address(0);
        address AuraComposableStablePoolAdapterImplementation = address(new AuraComposableStablePoolAdapter());
        address proxyAdmin = address(new ProxyAdmin());
        multiPoolStrategyFactory = new MultiPoolStrategyFactory(
            address(this),
            ConvexPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation,
            address(proxyAdmin)
            );
        multiPoolStrategy =
            MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_TOKEN, "generic", "generic"));
        auraComposableStablePoolAdapter = AuraComposableStablePoolAdapter(
            multiPoolStrategyFactory.createAuraComposableStablePoolAdapter(
                BALANCER_STABLE_POOL_ID, address(multiPoolStrategy), AURA_PID
            )
        );
        multiPoolStrategy.addAdapter(address(auraComposableStablePoolAdapter));
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
        uint256 adapterAdjustAmount = depositAmount * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraComposableStablePoolAdapter),
            amount: adapterAdjustAmount, // %94
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();
        uint256 totalAssets = multiPoolStrategy.totalAssets();
        uint256 underlyingBalance = auraComposableStablePoolAdapter.underlyingBalance();

        assertEq(storedAssetsBefore, depositAmount);
        assertEq(storedAssetsAfter, storedAssetsBefore - depositAmount * 94 / 100);
        assertAlmostEq(totalAssets, depositAmount, depositAmount * 2 / 100); // %2 slippage
        assertAlmostEq(underlyingBalance, adapterAdjustAmount, adapterAdjustAmount * 1 / 100);
    }

    function testAdjustOut() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adjustInAmount = depositAmount * 94 / 100;
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraComposableStablePoolAdapter),
            amount: adjustInAmount,
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();

        adjustIns = new MultiPoolStrategy.Adjust[](0);
        adjustOuts = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterLpBalance = auraComposableStablePoolAdapter.lpBalance();
        adjustOuts[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraComposableStablePoolAdapter),
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
            adapter: address(auraComposableStablePoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 underlyingBalanceInAdapterBeforeWithdraw = auraComposableStablePoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 underlyingBalanceOfThisBeforeRedeem = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        multiPoolStrategy.redeem(shares, address(this), address(this), 0);
        uint256 underlyingBalanceInAdapterAfterWithdraw = auraComposableStablePoolAdapter.underlyingBalance();
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
            adapter: address(auraComposableStablePoolAdapter),
            amount: 440 * 10 ** tokenDecimals,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);

        (,,, address _auraRewardPool,,) = IBooster(AURA_BOOSTER).poolInfo(AURA_PID);

        utils_writeAuraPoolReward(_auraRewardPool, address(auraComposableStablePoolAdapter), 600 * 10 ** 18);

        AuraComposableStablePoolAdapter.RewardData[] memory rewardData =
            auraComposableStablePoolAdapter.totalClaimable();

        assertGt(rewardData[0].amount, 0); // expect some BAL rewards
        uint256 totalBalRewards = rewardData[0].amount;
        //// AURA REWARD DATA
        uint256 auraRewardAmount = _calculateAuraRewards(totalBalRewards);
        assertGt(auraRewardAmount, 0); //expect some AURA rewards
        //////

        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_TOKEN, totalBalRewards, address(multiPoolStrategy));
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](1);
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: totalBalRewards, callData: txData });
        uint256 wethBalanceBefore = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 wethBalanceAfter = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        uint256 crvBalanceAfter = IERC20(rewardData[0].token).balanceOf(address(multiPoolStrategy));
        assertEq(crvBalanceAfter, 0);
        assertEq(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_TOKEN
    }

    function testDepositHardWorkWithdraw() public {
        this.testDeposit();
        this.testClaimRewards();
        _adjustInAndWithdraw();
    }

    function testHardWorkDepositWithdraw() public {
        this.testClaimRewards();
        this.testDeposit();
        _adjustInAndWithdraw();
    }

    function _adjustInAndWithdraw() private {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;

        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterAdjustAmount = depositAmount * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraComposableStablePoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        uint256 underlyingBalanceInAdapterBeforeWithdraw = auraComposableStablePoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 underlyingBalanceOfThisBeforeRedeem = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        multiPoolStrategy.redeem(shares, address(this), address(this), 0);
        uint256 underlyingBalanceInAdapterAfterWithdraw = auraComposableStablePoolAdapter.underlyingBalance();
        uint256 underlyingBalanceOfThisAfterRedeem = IERC20(UNDERLYING_TOKEN).balanceOf(address(this));
        assertAlmostEq(underlyingBalanceInAdapterBeforeWithdraw, adapterAdjustAmount, adapterAdjustAmount * 2 / 100);
        assertEq(underlyingBalanceInAdapterAfterWithdraw, 0);
        assertAlmostEq(
            underlyingBalanceOfThisAfterRedeem - underlyingBalanceOfThisBeforeRedeem,
            depositAmount,
            depositAmount * 2 / 100
        );
    }

    function utils_writeAuraPoolReward(address pool, address who, uint256 amount) public {
        stdstore.target(BAL_TOKEN_ADDRESS).sig(IERC20(BAL_TOKEN_ADDRESS).balanceOf.selector).with_key(pool)
            .checked_write(amount);

        stdstore.target(AURA).sig(IERC20(AURA).balanceOf.selector).with_key(pool).checked_write(amount);

        stdstore.target(pool).sig(IBaseRewardPool(pool).rewards.selector).with_key(who).checked_write(amount);
    }

    function testWithdrawExceedContractBalance() public {
        console2.log("1");
        uint256 depositAmount = 100 * 10 ** tokenDecimals;
        vm.startPrank(staker);
        console2.log("2");
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), type(uint256).max);
        multiPoolStrategy.deposit(50 * 10 ** tokenDecimals, address(staker));
        console2.log("3");
        vm.stopPrank();
        harvest(depositAmount);
        console2.log("5");
        vm.warp(block.timestamp + 10 days);
        console2.log("6");
        uint256 stakerShares = multiPoolStrategy.balanceOf(staker);
        uint256 withdrawAmount = multiPoolStrategy.convertToAssets(stakerShares);
        console2.log("7");
        vm.startPrank(staker);
        multiPoolStrategy.withdraw(withdrawAmount, address(staker), staker, 0);
        console2.log("8");
        vm.stopPrank();
        uint256 stakerSharesAfter = multiPoolStrategy.balanceOf(staker);
        console2.log("9");
        uint256 stakerWethBalance = IERC20(UNDERLYING_TOKEN).balanceOf(address(staker));
        assertGt(withdrawAmount, 50 * 10 ** tokenDecimals);
        assertEq(stakerSharesAfter, 0);
        assertAlmostEq(stakerWethBalance, withdrawAmount, withdrawAmount * 300 / 10_000); // %3 slippage
    }
}
