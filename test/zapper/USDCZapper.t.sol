// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { StdCheats, StdUtils, console2 } from "forge-std/Test.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IZapper } from "../../src/interfaces/IZapper.sol";
import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../../src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../../src/AuraWeightedPoolAdapter.sol";
import { USDCZapper } from "../../src/zapper/USDCZapper.sol";

contract USDCZapperTest is PRBTest, StdCheats, StdUtils {
    uint256 public constant DEFAULT_FORK_BLOCK_NUMBER = 17_886_763;
    uint256 public constant ETHER_DECIMALS = 18;

    address public constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC - mainnet, underlying asset
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT - mainnet
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI - mainnet
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX - mainnet
    address public constant CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3CRV - mainnet - LP token
    address public constant CRVFRAX = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC; // CRVFRAX  - mainnet - LP token

    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address public constant ZAPPER = address(0);

    address public constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7; // DAI+USDC+USDT
    address public constant CURVE_FRAXUSDC = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7; // FRAX+USDC

    uint256 public constant CONVEX_3POOL_PID = 9;
    uint256 public constant CONVEX_FRAXUSDC_PID = 100;

    uint256 constant CURVE_3POOL_TOKEN_LENGTH = 3;
    uint256 constant CURVE_FRAXUSDC_TOKEN_LENGTH = 2;

    int128 public constant UNDERLYING_ASSET_INDEX = 1; // USDC Index - for both 3Pool and FRAXUSDC

    string public constant STRATEGY_NAME = "Cool Strategy";

    bool constant USE_ETH = false;
    bool constant IS_INDEX_UINT = true;

    IZapper public usdcZapper;

    MultiPoolStrategyFactory public multiPoolStrategyFactory;
    MultiPoolStrategy public multiPoolStrategy;

    ConvexPoolAdapter public convex3PoolAdapter;
    ConvexPoolAdapter public convexFraxUsdcAdapter;

    IERC20 public curveLpToken;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public tokenDecimals;

    function setUp() public virtual {
        vm.createSelectFork({urlOrAlias: "mainnet", blockNumber: DEFAULT_FORK_BLOCK_NUMBER});

        usdcZapper = new USDCZapper();

        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
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

        convex3PoolAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_3POOL,
                    address(multiPoolStrategy),
                    CONVEX_3POOL_PID,
                    CURVE_3POOL_TOKEN_LENGTH,
                    ZAPPER,
                    USE_ETH,
                    IS_INDEX_UINT,
                    UNDERLYING_ASSET_INDEX
                )
            )
        );

        convexFraxUsdcAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_FRAXUSDC,
                    address(multiPoolStrategy),
                    CONVEX_FRAXUSDC_PID,
                    CURVE_FRAXUSDC_TOKEN_LENGTH,
                    ZAPPER,
                    USE_ETH,
                    IS_INDEX_UINT,
                    UNDERLYING_ASSET_INDEX
                )
            )
        );

        multiPoolStrategy.addAdapter(address(convex3PoolAdapter));
        multiPoolStrategy.addAdapter(address(convexFraxUsdcAdapter));
        multiPoolStrategy.changeFeeRecipient(feeRecipient);

        deal(address(this), 1000 ether);
        deal(UNDERLYING_ASSET, address(this), 1000 ether);
        deal(USDT, address(this), 1000 ether);
        deal(DAI, address(this), 1000 ether);
        deal(FRAX, address(this), 1000 ether);
        deal(CRV, address(this), 1000 ether);
        deal(CRVFRAX, address(this), 1000 ether);

        deal(UNDERLYING_ASSET, staker, 50 ether);

        SafeERC20.safeApprove(IERC20(UNDERLYING_ASSET), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(USDT), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(DAI), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(FRAX), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(CRV), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(CRVFRAX), address(usdcZapper), type(uint256).max);
    }

    function testDepositUSDT(uint256 usdtAmount) public {
        usdtAmount = bound(usdtAmount, 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 usdtBalanceOfThisPre = IERC20(USDT).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        uint256 shares = usdcZapper.deposit(usdtAmount, USDT, 0, address(this), address(multiPoolStrategy));

        uint256 usdcActualBalanceOfMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // check that swap fees are less than 1%
        assertAlmostEq(usdtAmount, usdcActualBalanceOfMultiPoolStrategy, usdcActualBalanceOfMultiPoolStrategy / 100);
        // check usdt amount of this contract after deposit
        assertEq(IERC20(USDT).balanceOf(address(this)), usdtBalanceOfThisPre - usdtAmount);
        // check usdc amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcActualBalanceOfMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcActualBalanceOfMultiPoolStrategy, shares, shares * 1 / 100);
    }

    // function testDepositDAI(uint256 daiAmount) public {
    //     daiAmount = 1000 * 10 ** 6;
    //     vm.assume(daiAmount > 10 * 10 ** 6 && daiAmount < 10_000_000 * 10 ** 6);

    //     uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
    //     uint256 daiBalanceOfThisPre = IERC20(DAI).balanceOf(address(this));
    //     uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

    //     uint256 shares = usdcZapper.deposit(daiAmount, DAI, 0, address(this), address(multiPoolStrategy));

    //     uint256 usdcActualBalanceOfMultiPoolStrategy =
    //         IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

    //     // check that swap fees are less than 1%
    //     assertAlmostEq(daiAmount, usdcActualBalanceOfMultiPoolStrategy, usdcActualBalanceOfMultiPoolStrategy / 100);
    //     // check dai amount of this contract after deposit
    //     assertEq(IERC20(DAI).balanceOf(address(this)), daiBalanceOfThisPre - daiAmount);
    //     // check usdc amount of multipool strategy after deposit
    //     assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcActualBalanceOfMultiPoolStrategy);
    //     // check shares amount of this contract after deposit
    //     assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
    //     // check shares amount matches usdt amount
    //     assertAlmostEq(usdcActualBalanceOfMultiPoolStrategy, shares, shares * 1 / 100);
    // }

    // function testDepositFRAX(uint256 fraxAmount) public {
    //     fraxAmount = 1000 * 10 ** 18;
    //     vm.assume(fraxAmount > 10 * 10 ** 18 && fraxAmount < 10_000_000 * 10 ** 18);

    //     uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
    //     uint256 fraxBalanceOfThisPre = IERC20(FRAX).balanceOf(address(this));
    //     uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
    //     uint256 shares = usdcZapper.deposit(fraxAmount, FRAX, 0, address(this), address(multiPoolStrategy));

    //     uint256 usdcActualBalanceOfMultiPoolStrategy =
    //         IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

    //     // check that swap fees are less than 1%
    //     assertAlmostEq(fraxAmount, usdcActualBalanceOfMultiPoolStrategy, usdcActualBalanceOfMultiPoolStrategy / 100);
    //     // check frax amount of this contract after deposit
    //     assertEq(IERC20(FRAX).balanceOf(address(this)), fraxBalanceOfThisPre - fraxAmount);
    //     // check usdc amount of multipool strategy after deposit
    //     assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcActualBalanceOfMultiPoolStrategy);
    //     // check shares amount of this contract after deposit
    //     assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
    //     // check shares amount matches usdt amount
    //     assertAlmostEq(usdcActualBalanceOfMultiPoolStrategy, shares, shares * 1 / 100);
    // }

    function testDeposit3CRV() public { }
    function testDepositCRVFRAX() public { }
    function testWithdrawUSDT() public { }
    function testWithdrawDAI() public { }
    function testWithdraw3CRV() public { }
    function testWithdrawCRVFRAX() public { }
    function testRedeemUSDT() public { }
    /*
    *   1. Get random amount of USDT
    *   2. Deposit USDT through zapper
    *   3. check USDT balanceOf strategy
    *   4. redeem and check we got the same amount of USDT (almost - minus swap fees - at least 99% of deposited amount)
    */
    function testRedeemDAI() public { }
    function testRedeem3CRV() public { }
    function testRedeemCRVFRAX() public { }
    function testDepositRevert() public { }
    function testWithdrawRevert() public { }
    function testRedeemRevert() public { }
    function testStrategyUsesUnderlyingAsset() public { }
}
