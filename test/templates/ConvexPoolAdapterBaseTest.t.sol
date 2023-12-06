// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import "forge-std/console.sol";
import "forge-std/StdStorage.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";

import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";
import { IBaseRewardPool } from "src/interfaces/IBaseRewardPool.sol";
import { MultiPoolStrategyTest } from "src/test/MultiPoolStrategyTest.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "src/AuraWeightedPoolAdapter.sol";
import { IBooster } from "src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "src/interfaces/ICurvePool.sol";
import { IBooster } from "src/interfaces/IBooster.sol";
import { ITransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ConvexPoolAdapterBaseTest is PRBTest, StdCheats {
    using SafeERC20 for IERC20;

    using stdStorage for StdStorage;

    StdStorage stdstore;

    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexGenericAdapter;
    IERC20 curveLpToken;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");

    address constant CRV_TOKEN_ADDRESS = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant CVX_TOKEN_ADDRESS = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    ///CONSTANTS
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address public UNDERLYING_ASSET;

    /**
     * @dev Address of the Convex booster contract.
     * default: https://etherscan.io/address/0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    address public CONVEX_BOOSTER;

    /**
     * @dev Address of the Curve pool used in the integration.
     */
    address public CURVE_POOL_ADDRESS;

    /**
     * @dev Convex pool ID used in the integration.
     * default: ETH/msETH Curve pool PID
     */
    uint256 public CONVEX_PID;

    /**
     * @dev Name of the strategy.
     */
    string public SALT;
    string public STRATEGY_NAME;
    string public TOKEN_NAME;
    /**
     * @dev if the pool uses native ETH as base asset e.g. ETH/msETH
     */
    bool public USE_ETH;

    /**
     * @dev The index of the strategies underlying asset in the pool tokens array
     * e.g. 0 for ETH/msETH since tokens are [ETH,msETH]
     */
    int128 public CURVE_POOL_TOKEN_INDEX;

    /**
     * @dev True if the calc_withdraw_one_coin method uses uint256 indexes as parameter (check contract on etherscan)
     */
    bool public IS_INDEX_UINT;

    /**
     * @dev the amount of tokens used in this pool , e.g. 2 for ETH/msETH
     */
    uint256 public POOL_TOKEN_LENGTH;

    /**
     * @dev address of zapper for pool if needed
     */
    address ZAPPER = address(0);

    uint256 forkBlockNumber;
    uint256 public DEFAULT_FORK_BLOCK_NUMBER = 18_721_331;

    uint8 tokenDecimals;

    ProxyAdmin proxyAdmin;

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

        // bytes memory funcResult = vm.ffi(inputs);
        // console.logBytes(funcResult);

        return abi.decode(vm.ffi(inputs), (uint256, bytes));
    }

    function harvest(uint256 _depositAmount) internal {
        IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), _depositAmount);
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

        (,,, address convexRewardPool,,) = IBooster(CONVEX_BOOSTER).poolInfo(CONVEX_PID);

        utils_writeConvexPoolReward(convexRewardPool, address(convexGenericAdapter), 500 * 10 ** 18);

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
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategyTest());
        address AuraWeightedPoolAdapterImplementation = address(0);
        address AuraStablePoolAdapterImplementation = address(0);
        address AuraComposableStablePoolAdapterImplementation = address(0);
        proxyAdmin = new ProxyAdmin();

        multiPoolStrategyFactory = new MultiPoolStrategyFactory(
            address(this),
            ConvexPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation,
            address(proxyAdmin)
            );

        multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(
                address(IERC20(UNDERLYING_ASSET)), STRATEGY_NAME, TOKEN_NAME
            )
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
        uint256 depositAmount = 500 * 10 ** tokenDecimals;

        _deposit(depositAmount);
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();

        assertEq(storedAssets, depositAmount);
    }

    function testAdjustIn() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;

        _deposit(depositAmount);

        uint256 storedAssetsBefore = multiPoolStrategy.storedTotalAssets();

        uint256 adjustInAmount = depositAmount * 94 / 100;
        _adjustIn(adjustInAmount);

        uint256 storedAssetsAfter = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssetsBefore, depositAmount);
        assertEq(storedAssetsAfter, storedAssetsBefore - adjustInAmount);
    }

    function testAdjustOut() public {
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), depositAmount);
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
        //reset approval to avoid "approve from non-zero to non-zero allowance"
        IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), 0);

        uint256 depositAmount = 500 * 10 ** tokenDecimals;

        IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), depositAmount);
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
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);

        (,,, address convexRewardPool,,) = IBooster(CONVEX_BOOSTER).poolInfo(CONVEX_PID);

        utils_writeConvexPoolReward(convexRewardPool, address(convexGenericAdapter), 500 * 10 ** 18);

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

        // console.logBytes(txData);
        // console.log("block number", block.number);

        uint256 wethBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 wethBalanceAfter = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 crvBalanceAfter = IERC20(rewardData[0].token).balanceOf(address(multiPoolStrategy));

        assertEq(crvBalanceAfter, 0);
        assertEq(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_ASSET
    }

    function testDepositHardWorkWithdraw() public {
        this.testDeposit();
        // this.testClaimRewards();
        _adjustInAndWithdraw();
    }

    function testHardWorkDepositWithdraw() public {
        this.testClaimRewards();
        this.testDeposit();
        _adjustInAndWithdraw();
    }

    function _adjustIn(uint256 adjustAmount) private {
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        adjustIns[0] =
            MultiPoolStrategy.Adjust({ adapter: address(convexGenericAdapter), amount: adjustAmount, minReceive: 0 });

        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(convexGenericAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
    }

    function _deposit(uint256 depositAmount) private {
        IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), 0);

        IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
    }

    function _redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minimumReceived
    )
        private
        returns (uint256)
    {
        return multiPoolStrategy.redeem(shares, receiver, owner, minimumReceived);
    }

    function testUpgradeAdapter() public {
        uint256 depositAmount = 5 * 10 ** tokenDecimals;
        uint256 adjustAmount = depositAmount * 94 / 100;

        _deposit(depositAmount);

        _adjustIn(adjustAmount);

        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 balanceBeforeRedeems = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 redeem1 = _redeem(shares / 2, address(this), address(this), 0);

        // UPGRADE
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(convexGenericAdapter)), ConvexPoolAdapterImplementation);

        shares = multiPoolStrategy.balanceOf(address(this));
        uint256 redeem2 = _redeem(shares, address(this), address(this), 0);

        uint256 currentBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

        assertAlmostEq(
            currentBalance - balanceBeforeRedeems, depositAmount, (currentBalance - balanceBeforeRedeems) / 50
        );
        assertAlmostEq(redeem1 + redeem2, currentBalance - balanceBeforeRedeems, (redeem1 + redeem2) / 100);
    }

    function testUpgradeStrategy() public {
        uint256 depositAmount = 5 * 10 ** tokenDecimals;
        uint256 adjustAmount = depositAmount * 94 / 100;

        _deposit(depositAmount);

        _adjustIn(adjustAmount);

        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 balanceBeforeRedeems = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 redeem1 = _redeem(shares / 2, address(this), address(this), 0);

        // UPGRADE
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(multiPoolStrategy)), MultiPoolStrategyImplementation);

        shares = multiPoolStrategy.balanceOf(address(this));
        uint256 redeem2 = _redeem(shares, address(this), address(this), 0);

        uint256 currentBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

        assertAlmostEq(
            currentBalance - balanceBeforeRedeems, depositAmount, (currentBalance - balanceBeforeRedeems) / 50
        );
        assertAlmostEq(redeem1 + redeem2, currentBalance - balanceBeforeRedeems, (redeem1 + redeem2) / 100);
    }

    function testUpgradeAdapterWithoutAdjustingIn() public {
        uint256 depositAmount = 5 * 10 ** tokenDecimals;

        _deposit(depositAmount);

        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 balanceBeforeRedeems = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 redeem1 = _redeem(shares / 2, address(this), address(this), 0);

        // UPGRADE
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(convexGenericAdapter)), ConvexPoolAdapterImplementation);

        shares = multiPoolStrategy.balanceOf(address(this));
        uint256 redeem2 = _redeem(shares, address(this), address(this), 0);

        uint256 currentBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

        assertAlmostEq(
            currentBalance - balanceBeforeRedeems, depositAmount, (currentBalance - balanceBeforeRedeems) / 50
        );
        assertAlmostEq(redeem1 + redeem2, currentBalance - balanceBeforeRedeems, (redeem1 + redeem2) / 100);
    }

    function testUpgradeStrategyWithoutAdjustingIn() public {
        uint256 depositAmount = 5 * 10 ** tokenDecimals;

        _deposit(depositAmount);

        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 balanceBeforeRedeems = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 redeem1 = _redeem(shares / 2, address(this), address(this), 0);

        // UPGRADE
        address MultiPoolStrategyrImplementation = address(new MultiPoolStrategy());
        proxyAdmin.upgrade(ITransparentUpgradeableProxy(address(multiPoolStrategy)), MultiPoolStrategyrImplementation);

        shares = multiPoolStrategy.balanceOf(address(this));
        uint256 redeem2 = _redeem(shares, address(this), address(this), 0);

        uint256 currentBalance = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

        assertAlmostEq(
            currentBalance - balanceBeforeRedeems, depositAmount, (currentBalance - balanceBeforeRedeems) / 50
        );
        assertAlmostEq(redeem1 + redeem2, currentBalance - balanceBeforeRedeems, (redeem1 + redeem2) / 100);
    }

    function _adjustInAndWithdraw() private {
        //reset approval to avoid "approve from non-zero to non-zero allowance"
        // IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), 0);

        uint256 depositAmount = 500 * 10 ** tokenDecimals;

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
        MultiPoolStrategyTest(address(multiPoolStrategy)).setRewardsCycleEnd(uint32(block.timestamp - 100));
    }

    function utils_writeConvexPoolReward(address pool, address who, uint256 amount) public {
        stdstore.target(CRV_TOKEN_ADDRESS).sig(IERC20(CRV_TOKEN_ADDRESS).balanceOf.selector).with_key(pool)
            .checked_write(amount);

        stdstore.target(CVX_TOKEN_ADDRESS).sig(IERC20(CVX_TOKEN_ADDRESS).balanceOf.selector).with_key(pool)
            .checked_write(amount);

        stdstore.target(pool).sig(IBaseRewardPool(pool).rewards.selector).with_key(who).checked_write(amount);
    }

    function testWithdrawExceedContractBalance() public {
        uint256 depositAmount = 100 * 10 ** tokenDecimals;
        vm.startPrank(staker);
        IERC20(UNDERLYING_ASSET).safeApprove(address(multiPoolStrategy), depositAmount / 2);
        multiPoolStrategy.deposit(depositAmount / 2, address(staker));
        vm.stopPrank();
        harvest(depositAmount);
        vm.warp(block.timestamp + 14 days);
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
