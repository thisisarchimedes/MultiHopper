// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { StdCheats, StdUtils, console2 } from "forge-std/Test.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IGenericZapper } from "../../src/interfaces/IGenericZapper.sol";
import { ICurveBasePool, ICurve3Pool } from "../../src/interfaces/ICurvePool.sol";
import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../../src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../../src/AuraWeightedPoolAdapter.sol";
import { GenericZapper } from "../../src/zapper/GenericZapper.sol";
import { IGenericZapper } from "../../src/interfaces/IGenericZapper.sol";
import { MultiPoolStrategy as IMultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";

contract GenericZapperTest is PRBTest, StdCheats, StdUtils {
    uint256 public constant ETHER_DECIMALS = 18;

    address public constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC - mainnet, underlying
        // asset
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT - mainnet
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI - mainnet
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX - mainnet
    // address public constant CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // 3CRV - mainnet - LP token
    // address public constant CRVFRAX = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC; // CRVFRAX  - mainnet - LP token

    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address public constant ZAPPER = address(0);

    address public constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7; // DAI+USDC+USDT
    address public constant CURVE_FRAXUSDC = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2; // FRAX+USDC

    uint256 public constant CONVEX_3POOL_PID = 9;
    uint256 public constant CONVEX_FRAXUSDC_PID = 100;

    uint256 constant CURVE_3POOL_TOKEN_LENGTH = 3;
    uint256 constant CURVE_FRAXUSDC_TOKEN_LENGTH = 2;

    int128 public constant UNDERLYING_ASSET_INDEX = 1; // USDC Index - for both 3Pool and FRAXUSDC
    int128 public constant DAI_INDEX = 0; // DAI Index - for 3Pool
    int128 public constant USDT_INDEX = 2; // USDT Index - for 3Pool
    int128 public constant FRAX_INDEX = 0; // FRAX Index - for FRAXUSDC

    string public constant STRATEGY_NAME = "Cool Strategy";

    bool constant USE_ETH = false;
    bool constant IS_INDEX_UINT = true;

    GenericZapper public genericZapper;

    MultiPoolStrategyFactory public multiPoolStrategyFactory;
    MultiPoolStrategy public multiPoolStrategy;

    ConvexPoolAdapter public convex3PoolAdapter;
    ConvexPoolAdapter public convexFraxUsdcAdapter;

    IERC20 public curveLpToken;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public tokenDecimals;

    function setUp() public virtual {
        vm.createSelectFork({ urlOrAlias: "mainnet" });

        genericZapper = new GenericZapper();

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

        deal(address(this), 100_000_000 ether);
        deal(UNDERLYING_ASSET, address(this), 100_000_000 ether);
        deal(USDT, address(this), 100_000_000 ether);
        deal(DAI, address(this), 100_000_000 ether);
        deal(FRAX, address(this), 100_000_000 ether);
        // deal(CRV, address(this), 100_000_000 ether);
        // deal(CRVFRAX, address(this), 100_000_000 ether);

        deal(UNDERLYING_ASSET, staker, 50 ether);

        SafeERC20.safeApprove(IERC20(UNDERLYING_ASSET), address(genericZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(DAI), address(genericZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(FRAX), address(genericZapper), type(uint256).max);
        // SafeERC20.safeApprove(IERC20(CRV), address(genericZapper), type(uint256).max);
        // SafeERC20.safeApprove(IERC20(CRVFRAX), address(genericZapper), type(uint256).max);
        // shares
        SafeERC20.safeApprove(IERC20(address(multiPoolStrategy)), address(genericZapper), type(uint256).max);
    }

    // DEPOSIT - POSITIVE TESTS
    // function testDepositUnderlyingAsset(uint256 amountToDeposit) public {
    function testDepositUnderlyingAsset() public {
        // TODO! once we have the API-KEY setup runs
        // get underlyingAsset amount in the range of 10 to 10_000_000
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(UNDERLYING_ASSET).decimals(), 10_000_000 * 10 **
        // IERC20(UNDERLYING_ASSET).decimals()); // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(UNDERLYING_ASSET).decimals();

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 underlyingAssetBalanceOfThisPre = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 underlyingAssetBalanceOfMultiPoolStrategyPre =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        uint256 shares =
            genericZapper.deposit(amountToDeposit, UNDERLYING_ASSET, 0, address(this), address(multiPoolStrategy), "");

        uint256 underlyingAssetDepositedAmountToMultiPoolStrategy = IERC20(UNDERLYING_ASSET).balanceOf(
            address(multiPoolStrategy)
        ) - underlyingAssetBalanceOfMultiPoolStrategyPre;

        // check exact underlying amount deposit
        assertEq(amountToDeposit, underlyingAssetDepositedAmountToMultiPoolStrategy);
        // check underlyingAsset amount of this contract after deposit
        assertEq(IERC20(UNDERLYING_ASSET).balanceOf(address(this)), underlyingAssetBalanceOfThisPre - amountToDeposit);
        // check underlyingAsset deposited amount of multipool strategy after deposit
        assertEq(
            multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre,
            underlyingAssetDepositedAmountToMultiPoolStrategy
        );
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches underlyingAsset amount
        assertAlmostEq(underlyingAssetDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    // function testDepositUSDT(uint256 amountToDeposit) public {
    function testDepositUSDT() public {
        // TODO! once we have the API-KEY setup runs
        // get usdt amount in the range of 10 to 10_000_000
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 usdtBalanceOfThisPre = IERC20(USDT).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        (uint256 calculatedUSDCAmount, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 shares =
            genericZapper.deposit(amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // check that deposited amount is greater than toAmountMin
        assertTrue(usdcDepositedAmountToMultiPoolStrategy >= toAmountMin);
        // check that swap works correctly
        assertAlmostEq(calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy, calculatedUSDCAmount / 100);
        // check usdt amount of this contract after deposit
        assertEq(IERC20(USDT).balanceOf(address(this)), usdtBalanceOfThisPre - amountToDeposit);
        // check usdc deposited amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    // function testDepositDAI(uint256 amountToDeposit) public { // TODO! once we have the API-KEY setup runs
    function testDepositDAI() public {
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(DAI).decimals(), 10_000_000 * 10 ** IERC20(DAI).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(DAI).decimals();

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 daiBalanceOfThisPre = IERC20(DAI).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        (uint256 calculatedUSDCAmount, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(DAI, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 shares =
            genericZapper.deposit(amountToDeposit, DAI, toAmountMin, address(this), address(multiPoolStrategy), txData);

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // check that deposited amount is greater than toAmountMin
        assertTrue(usdcDepositedAmountToMultiPoolStrategy >= toAmountMin);

        // check that swap works correctly
        assertAlmostEq(calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy, calculatedUSDCAmount / 100);

        // check dai amount of this contract after deposit
        assertEq(IERC20(DAI).balanceOf(address(this)), daiBalanceOfThisPre - amountToDeposit);
        // check deposited usdc amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    // function testDepositFRAX(uint256 amountToDeposit) public { // TODO! once we have the API-KEY setup runs
    function testDepositFRAX() public {
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(FRAX).decimals(), 10_000_000 * 10 ** IERC20(FRAX).decimals());
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(FRAX).decimals();

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 fraxBalanceOfThisPre = IERC20(FRAX).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        (uint256 calculatedUSDCAmount, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(FRAX, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 shares =
            genericZapper.deposit(amountToDeposit, FRAX, toAmountMin, address(this), address(multiPoolStrategy), txData);

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // check that deposited amount is greater than toAmountMin
        assertTrue(usdcDepositedAmountToMultiPoolStrategy >= toAmountMin);

        // check that swap works correctly
        assertAlmostEq(calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy, calculatedUSDCAmount / 100);

        // check frax amount of this contract after deposit
        assertEq(IERC20(FRAX).balanceOf(address(this)), fraxBalanceOfThisPre - amountToDeposit);
        // check deposited usdc amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    // function testDepositToUSDTLyingStrategy(uint256 amountToDeposit) public { // TODO! once we have the API-KEY setup runs
    function testDepositToUSDTLyingStrategy() public {
        // create a strategy with USDT as an underlying asset
        multiPoolStrategy =
            MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(USDT, "Generic MultiPool Strategy"));

        // we swap USDC to USDT, here the underlying asset is USDT
        address USDC = UNDERLYING_ASSET;

        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(FRAX).decimals(), 10_000_000 * 10 ** IERC20(FRAX).decimals());
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDC).decimals();

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 usdcBalanceOfThisPre = IERC20(multiPoolStrategy.asset()).balanceOf(address(this));
        uint256 underlyingAssetBalanceOfMultiPoolStrategyPre =
            IERC20(multiPoolStrategy.asset()).balanceOf(address(multiPoolStrategy));

        (uint256 calculatedUSDTAmount, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDC, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        // USDT fails with normal ERC20 approval here, have to use safeApprove
        uint256 shares =
            genericZapper.deposit(amountToDeposit, USDC, toAmountMin, address(this), address(multiPoolStrategy), txData);

        uint256 underlyingAssetDepositedAmountToMultiPoolStrategy = IERC20(multiPoolStrategy.asset()).balanceOf(
            address(multiPoolStrategy)
        ) - underlyingAssetBalanceOfMultiPoolStrategyPre;

        // // check that deposited amount is greater than toAmountMin
        assertTrue(underlyingAssetDepositedAmountToMultiPoolStrategy >= toAmountMin);
        // check that swap works correctly
        assertAlmostEq(
            calculatedUSDTAmount, underlyingAssetDepositedAmountToMultiPoolStrategy, calculatedUSDTAmount / 100
        );
        // check usdt amount of this contract after deposit
        assertEq(IERC20(USDC).balanceOf(address(this)), usdcBalanceOfThisPre - amountToDeposit);
        // // check usdc deposited amount of multipool multiPoolStrategy after deposit
        assertEq(
            multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre,
            underlyingAssetDepositedAmountToMultiPoolStrategy
        );
        // // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // // check shares amount matches usdt amount
        assertAlmostEq(underlyingAssetDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    // TODO! Add further funcctionality for LP-tokens
    // function testDeposit3CRV(uint256 amountToDeposit) public { // TODO! once we have the API-KEY setup runs
    // function testDeposit3CRV() public {
    //     // uint256 amountToDeposit =
    //     //     bound(amountToDeposit, 10 * 10 ** IERC20(CRV).decimals(), 1_000_000 * 10 ** IERC20(CRV).decimals());
    // // TODO! once we have the API-KEY setup runs
    //     uint256 amountToDeposit = 10 * 10 ** IERC20(CRV).decimals();

    //     uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
    //     uint256 crvBalanceOfThisPre = IERC20(CRV).balanceOf(address(this));
    //     uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

    //     (uint256 calculatedUSDCAmount, bytes memory txData) = getQuoteLiFi(CRV, multiPoolStrategy.asset(),
    // amountToDeposit, address(genericZapper));

    //     uint256 shares = genericZapper.deposit(amountToDeposit, CRV, address(this), address(multiPoolStrategy),
    // txData);

    //     uint256 usdcDepositedAmountToMultiPoolStrategy =
    //         IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

    //     // check that swap works correctly
    //     assertEq(calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy);
    //     // check crv amount of this contract after deposit
    //     assertEq(IERC20(CRV).balanceOf(address(this)), crvBalanceOfThisPre - amountToDeposit);
    //     // check deposited usdc amount of multipool strategy after deposit
    //     assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre,
    // usdcDepositedAmountToMultiPoolStrategy);
    //     // check shares amount of this contract after deposit
    //     assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
    //     // check shares amount matches usdt amount
    //     assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    // }

    // TODO! Add further funcctionality for LP-tokens
    // function testDepositCRVFRAX(uint256 amountToDeposit) public {
    //     amountToDeposit =
    //         bound(amountToDeposit, 10 * 10 ** IERC20(CRVFRAX).decimals(), 10_000_000 * 10 **
    // IERC20(CRVFRAX).decimals());

    //     uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
    //     uint256 crvFraxBalanceOfThisPre = IERC20(CRVFRAX).balanceOf(address(this));
    //     uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

    //     // calculate the amount of USDC received when withdrawing a LP token.
    //     uint256 calculatedUSDCAmount =
    //         ICurveBasePool(CURVE_FRAXUSDC).calc_withdraw_one_coin(amountToDeposit, UNDERLYING_ASSET_INDEX);

    //     (, bytes memory txData) = getQuoteLiFi(CRVFRAX, multiPoolStrategy.asset(), amountToDeposit, address(this));

    //     uint256 shares =
    //         genericZapper.deposit(amountToDeposit, CRVFRAX, address(this), address(multiPoolStrategy), txData);

    //     uint256 usdcDepositedAmountToMultiPoolStrategy =
    //         IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

    //     // check that swap works correctly
    //     assertEq(calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy);
    //     // check crvfrax amount of this contract after deposit
    //     assertEq(IERC20(CRVFRAX).balanceOf(address(this)), crvFraxBalanceOfThisPre - amountToDeposit);
    //     // check deposited usdc amount of multipool strategy after deposit
    //     assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre,
    // usdcDepositedAmountToMultiPoolStrategy);
    //     // check shares amount of this contract after deposit
    //     assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
    //     // check shares amount matches usdt amount
    //     assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    // }

    // function testDepositDifferentAsset(uint256 amountToDeposit) public {
    function testDepositUnderlyingAssetWithDummySwapData() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(UNDERLYING_ASSET).decimals(), 10_000_000 * 10 **
        // IERC20(UNDERLYING_ASSET).decimals()); // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(UNDERLYING_ASSET).decimals();

        (,, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        genericZapper.deposit(
            amountToDeposit, UNDERLYING_ASSET, amountToDeposit, address(this), address(multiPoolStrategy), txData
        );
        genericZapper.deposit(
            amountToDeposit, UNDERLYING_ASSET, amountToDeposit, address(this), address(multiPoolStrategy), ""
        );
    }

    // function testDepositWithCombinedSwapData(uint256 amountToDeposit) public {
    function testDepositWithCombinedSwapData() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (uint256 quote, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        genericZapper.deposit(
            amountToDeposit,
            USDT,
            toAmountMin,
            address(this),
            address(multiPoolStrategy),
            concat(concat(txData, txData), txData)
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        assertEq(quote, storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit);
        assertTrue(toAmountMin < storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit);
    }

    // DEPOSIT - NEGATIVE TESTS
    function testDepositRevertReentrantCall() public {
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        ERC20Hackable erc20Hackable = new ERC20Hackable(genericZapper, address(multiPoolStrategy));

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(this));

        vm.expectRevert();
        genericZapper.deposit(
            amountToDeposit, address(erc20Hackable), toAmountMin, address(this), address(multiPoolStrategy), txData
        );
    }

    function testDepositRevertZeroAddress() public {
        address receiver = address(0);

        (, uint256 toAmountMin, bytes memory txData) = getQuoteLiFi(USDT, multiPoolStrategy.asset(), 1, address(this)); // Using
            // address(this) for the query to pass

        vm.expectRevert(IGenericZapper.ZeroAddress.selector);
        genericZapper.deposit(1, USDT, toAmountMin, receiver, address(multiPoolStrategy), txData);
    }

    function testDepositRevertEmptyInput() public {
        uint256 amount = 0;

        (, uint256 toAmountMin, bytes memory txData) = getQuoteLiFi(USDT, multiPoolStrategy.asset(), 1, address(this));

        vm.expectRevert(IGenericZapper.EmptyInput.selector);
        genericZapper.deposit(amount, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
    }

    function testDepositRevertMultiPoolStrategyIsPaused() public {
        multiPoolStrategy.togglePause();

        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        vm.expectRevert(IGenericZapper.StrategyPaused.selector);
        genericZapper.deposit(amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
    }

    // function testDepositIncreasedAmount(uint256 amountToDeposit, uint256 fakeAmount) public {
    function testDepositIncreasedAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();
        uint256 fakeAmount = 1;

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        vm.expectRevert();
        genericZapper.deposit(
            amountToDeposit + fakeAmount, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData
        );
    }

    // function testDepositDecreasedAmount(uint256 amountToDeposit, uint256 fakeAmount) public {
    function testDepositDecreasedAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();
        uint256 fakeAmount = 1;

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        vm.expectRevert(GenericZapper.SwapFailed.selector);
        genericZapper.deposit(
            amountToDeposit - fakeAmount, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData
        );
    }

    // function testDepositDifferentAsset(uint256 amountToDeposit) public {
    function testDepositDifferentAsset() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        vm.expectRevert(GenericZapper.SwapFailed.selector);
        genericZapper.deposit(amountToDeposit, DAI, toAmountMin, address(this), address(multiPoolStrategy), txData);
    }

    // function testDepositWithEmptySwapData(uint256 amountToDeposit) public {
    function testDepositWithEmptySwapData() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        vm.expectRevert(IGenericZapper.EmptyInput.selector);
        genericZapper.deposit(amountToDeposit, USDT, 0, address(this), address(multiPoolStrategy), "");
    }

    // function testDepositDecreasedSwapAmount(uint256 amountToDeposit) public {
    function testDepositDecreasedSwapAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();
        uint256 fakeAmount = amountToDeposit * 90 / 100;

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        uint256 minAmount = amountToDeposit * 95 / 100;

        (,, bytes memory txData) = getQuoteLiFi(USDT, multiPoolStrategy.asset(), fakeAmount, address(genericZapper));

        vm.expectRevert(GenericZapper.AmountBelowMinimum.selector);
        genericZapper.deposit(amountToDeposit, USDT, minAmount, address(this), address(multiPoolStrategy), txData);
    }

    // function testDepositIncreasedSwapAmount(uint256 amountToDeposit) public {
    function testDepositIncreasedSwapAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();
        uint256 fakeAmount = amountToDeposit * 110 / 100;

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        uint256 minAmount = amountToDeposit * 95 / 100;

        (,, bytes memory txData) = getQuoteLiFi(USDT, multiPoolStrategy.asset(), fakeAmount, address(genericZapper));

        vm.expectRevert(GenericZapper.SwapFailed.selector);
        genericZapper.deposit(amountToDeposit, USDT, minAmount, address(this), address(multiPoolStrategy), txData);
    }

    // function testDepositWithInvalidSwapData(uint256 amountToDeposit) public {
    function testDepositWithInvalidSwapData() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        vm.expectRevert(IGenericZapper.EmptyInput.selector);
        genericZapper.deposit(amountToDeposit, USDT, 0, address(this), address(multiPoolStrategy), "");

        vm.expectRevert(GenericZapper.SwapFailed.selector);
        genericZapper.deposit(amountToDeposit, USDT, 0, address(this), address(multiPoolStrategy), "0000000000");
    }

    // REDEEM - POSITIVE TESTS
    // function testRedeemUnderlyingAsset(uint256 amountToDeposit) public {
    function testRedeemUnderlyingAsset() public {
        // TODO! once we have the API-KEY setup runs
        // get underlying asset amount in the range of 10 to 10_000_000
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(UNDERLYING_ASSET).decimals(), 10_000_000 * 10 **
        // IERC20(UNDERLYING_ASSET).decimals()); // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(UNDERLYING_ASSET).decimals();

        // firstly deposit
        uint256 shares =
            genericZapper.deposit(amountToDeposit, UNDERLYING_ASSET, 0, address(this), address(multiPoolStrategy), "");
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 underlyingAssetBalanceOfThisPre = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        uint256 redeemedAmount =
            genericZapper.redeem(shares, UNDERLYING_ASSET, 0, address(this), address(multiPoolStrategy), "");

        // check that redeem works correctly and we get back the same amount of the underlying asset we deposited
        assertEq(amountToDeposit, redeemedAmount);
        // check underlyingAsset amount of this contract after redeem
        assertEq(IERC20(UNDERLYING_ASSET).balanceOf(address(this)), underlyingAssetBalanceOfThisPre + redeemedAmount);
        // check amountToDeposit and actual balance of tokens after redeem with max delta of 1%
        assertAlmostEq(
            amountToDeposit,
            IERC20(UNDERLYING_ASSET).balanceOf(address(this)) - underlyingAssetBalanceOfThisPre,
            amountToDeposit / 100
        );
        // check underlying asset amount of multipool strategy after redeem, difference should be less than 1% of redeem
        // amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    // function testRedeemUSDT(uint256 amountToDeposit) public {
    function testRedeemUSDT() public {
        // TODO! once we have the API-KEY setup runs
        // get usdt amount in the range of 10 to 10_000_000
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        // firstly deposit
        (, uint256 toAmountMinDeposited, bytes memory depositTxData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));
        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares = genericZapper.deposit(
            amountToDeposit, USDT, toAmountMinDeposited, address(this), address(multiPoolStrategy), depositTxData
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 usdtBalanceOfThisPre = IERC20(USDT).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );
        uint256 redeemedAmount = genericZapper.redeem(
            shares, USDT, toAmountMinRedeemed, address(this), address(multiPoolStrategy), redeemTxData
        );

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, amountToDeposit / 100);
        // check usdt amount of this contract after redeem
        assertEq(IERC20(USDT).balanceOf(address(this)), usdtBalanceOfThisPre + redeemedAmount);
        // check amountToDeposit and actual balance of tokens after redeem with max delta of 1%
        assertAlmostEq(
            amountToDeposit, IERC20(USDT).balanceOf(address(this)) - usdtBalanceOfThisPre, amountToDeposit / 100
        );
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    // function testRedeemDAI(uint256 amountToDeposit) public { // TODO! once we have the API-KEY setup runs
    function testRedeemDAI() public {
        // get dai amount in the range of 10 to 10_000_000
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(DAI).decimals(), 10_000_000 * 10 ** IERC20(DAI).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(DAI).decimals();

        // firstly deposit
        (, uint256 toAmountMinDeposited, bytes memory depositTxData) =
            getQuoteLiFi(DAI, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));
        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares = genericZapper.deposit(
            amountToDeposit, DAI, toAmountMinDeposited, address(this), address(multiPoolStrategy), depositTxData
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 daiBalanceOfThisPre = IERC20(DAI).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            DAI,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );
        uint256 redeemedAmount = genericZapper.redeem(
            shares, DAI, toAmountMinRedeemed, address(this), address(multiPoolStrategy), redeemTxData
        );

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, amountToDeposit / 100);
        // check dai amount of this contract after redeem
        assertEq(IERC20(DAI).balanceOf(address(this)), daiBalanceOfThisPre + redeemedAmount);
        // check amountToDeposit and actual balance of tokens after redeem with max delta of 1%
        assertAlmostEq(
            amountToDeposit, IERC20(DAI).balanceOf(address(this)) - daiBalanceOfThisPre, amountToDeposit / 100
        );
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    // function testRedeemFRAX(uint256 amountToDeposit) public { // TODO! once we have the API-KEY setup runs
    function testRedeemFRAX() public {
        // get frax amount in the range of 10 to 10_000_000
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(FRAX).decimals(), 10_000_000 * 10 ** IERC20(FRAX).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(FRAX).decimals();

        // firstly deposit
        (, uint256 toAmountMinDeposited, bytes memory depositTxData) =
            getQuoteLiFi(FRAX, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));
        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares = genericZapper.deposit(
            amountToDeposit, FRAX, toAmountMinDeposited, address(this), address(multiPoolStrategy), depositTxData
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 fraxBalanceOfThisPre = IERC20(FRAX).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            FRAX,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );
        uint256 redeemedAmount = genericZapper.redeem(
            shares, FRAX, toAmountMinRedeemed, address(this), address(multiPoolStrategy), redeemTxData
        );

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, amountToDeposit / 100);
        // check frax amount of this contract after redeem
        assertEq(IERC20(FRAX).balanceOf(address(this)), fraxBalanceOfThisPre + redeemedAmount);
        // check amountToDeposit and actual balance of tokens after redeem with max delta of 1%
        assertAlmostEq(
            amountToDeposit, IERC20(FRAX).balanceOf(address(this)) - fraxBalanceOfThisPre, amountToDeposit / 100
        );
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    // TODO! Add further funcctionality for LP-tokens
    // function testRedeem3CRV(uint256 amountToDeposit) public {
    //     // get crv amount in the range of 10 to 10_000_000
    //     amountToDeposit =
    //         bound(amountToDeposit, 10 * 10 ** IERC20(CRV).decimals(), 10_000_000 * 10 ** IERC20(CRV).decimals());

    //     // firstly deposit
    //     uint256 shares = genericZapper.deposit(amountToDeposit, CRV, address(this), address(multiPoolStrategy));

    //     uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

    //     // get values before redeem
    //     uint256 crvBalanceOfThisPre = IERC20(CRV).balanceOf(address(this));
    //     uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

    //     // calculate the amount of USDC received when withdrawing a LP token.
    //     uint256 calculatedUSDCAmount =
    //         ICurveBasePool(CURVE_3POOL).calc_withdraw_one_coin(amountToDeposit, UNDERLYING_ASSET_INDEX);

    //     // redeem all shares
    //     uint256 redeemedAmount = genericZapper.redeem(shares, CRV, address(this), address(multiPoolStrategy));

    //     // check that redeem works correctly and swap fees are less than 1%
    //     assertAlmostEq(amountToDeposit, redeemedAmount, amountToDeposit / 100);
    //     // check crv amount of this contract after redeem
    //     assertEq(IERC20(CRV).balanceOf(address(this)), crvBalanceOfThisPre + redeemedAmount);
    //     // check amountToDeposit and actual balance of tokens after redeem with max delta of 0.1%
    //     assertAlmostEq(
    //         amountToDeposit, IERC20(CRV).balanceOf(address(this)) - crvBalanceOfThisPre, amountToDeposit / 1000
    //     );
    //     // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
    //     assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
    //     // check shares amount of this contract after redeem
    //     assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    // }

    // TODO! Add further funcctionality for LP-tokens
    // function testRedeemCRVFRAX(uint256 amountToDeposit) public {
    //     // get crvfrax amount in the range of 10 to 10_000_000
    //     amountToDeposit =
    //         bound(amountToDeposit, 10 * 10 ** IERC20(CRVFRAX).decimals(), 10_000_000 * 10 **
    // IERC20(CRVFRAX).decimals());

    //     // firstly deposit
    //     uint256 shares = genericZapper.deposit(amountToDeposit, CRVFRAX, address(this), address(multiPoolStrategy));

    //     uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

    //     // get values before redeem
    //     uint256 crvFraxBalanceOfThisPre = IERC20(CRVFRAX).balanceOf(address(this));
    //     uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

    //     // calculate the amount of USDC received when withdrawing a LP token.
    //     uint256 calculatedUSDCAmount =
    //         ICurveBasePool(CURVE_FRAXUSDC).calc_withdraw_one_coin(amountToDeposit, UNDERLYING_ASSET_INDEX);

    //     // redeem all shares
    //     uint256 redeemedAmount =
    //         genericZapper.redeem(shares, CRVFRAX, address(this), address(multiPoolStrategy));

    //     // check that redeem works correctly and swap fees are less than 1%
    //     assertAlmostEq(amountToDeposit, redeemedAmount, amountToDeposit / 100);
    //     // check crvfrax amount of this contract after redeem
    //     assertEq(IERC20(CRVFRAX).balanceOf(address(this)), crvFraxBalanceOfThisPre + redeemedAmount);
    //     // check amountToDeposit and actual balance of tokens after redeem with max delta of 0.1%
    //     assertAlmostEq(
    //         amountToDeposit, IERC20(CRVFRAX).balanceOf(address(this)) - crvFraxBalanceOfThisPre, amountToDeposit /
    // 1000
    //     );
    //     // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
    //     assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
    //     // check shares amount of this contract after redeem
    //     assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    // }

    // function testRedeemWithCombinedSwapData(uint256 amountToDeposit) public {
    function testRedeemWithCombinedSwapData() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (uint256 quote, uint256 toAmountMin, bytes memory depositTxData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares = genericZapper.deposit(
            amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), depositTxData
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        assertEq(quote, storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit);
        assertTrue(toAmountMin < storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit);

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );

        assertEq(IERC20(address(multiPoolStrategy)).balanceOf(address(this)), shares);

        uint256 balanceBeforeDeposit = IERC20(USDT).balanceOf(address(this));
        genericZapper.redeem(
            shares,
            USDT,
            toAmountMinRedeemed,
            address(this),
            address(multiPoolStrategy),
            concat(concat(redeemTxData, redeemTxData), redeemTxData)
        );
        uint256 balanceAfterDeposit = IERC20(USDT).balanceOf(address(this));

        assertEq(multiPoolStrategy.storedTotalAssets(), 0);
        assertEq(IERC20(address(multiPoolStrategy)).balanceOf(address(this)), 0);
        assertTrue(toAmountMinRedeemed < balanceAfterDeposit - balanceBeforeDeposit);
    }

    function testRedeemEvenIfMultiPoolStrategyIsPaused() public {
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));
        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares =
            genericZapper.deposit(amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );

        multiPoolStrategy.togglePause();

        genericZapper.redeem(shares, USDT, toAmountMinRedeemed, address(this), address(multiPoolStrategy), redeemTxData);
    }

    // REDEEM - NEGATIVE TESTS
    function testRedeemRevertZeroAddress() public {
        address receiver = address(0);

        (, uint256 toAmountMin, bytes memory txData) = getQuoteLiFi(multiPoolStrategy.asset(), USDT, 1, address(this)); // Using
            // address(this) for the query to pass

        vm.expectRevert(IGenericZapper.ZeroAddress.selector);
        genericZapper.redeem(1, USDT, toAmountMin, receiver, address(multiPoolStrategy), txData);
    }

    function testRedeemRevertEmptyInput() public {
        uint256 amount = 0;

        (, uint256 toAmountMin, bytes memory txData) = getQuoteLiFi(multiPoolStrategy.asset(), USDT, 1, address(this));

        vm.expectRevert(IGenericZapper.EmptyInput.selector);
        genericZapper.redeem(amount, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
    }

    // function testRedeemIncreasedAmount(uint256 amountToDeposit, uint256 fakeAmount) public {
    function testRedeemIncreasedAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();
        uint256 fakeAmount = 1;

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));
        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares =
            genericZapper.deposit(amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );

        vm.expectRevert();
        genericZapper.redeem(
            shares + fakeAmount, USDT, toAmountMinRedeemed, address(this), address(multiPoolStrategy), redeemTxData
        );
    }

    // function testRedeemDecreasedAmount(uint256 amountToDeposit, uint256 fakeAmount) public {
    function testRedeemDecreasedAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();
        uint256 fakeAmount = 1;

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares =
            genericZapper.deposit(amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );

        vm.expectRevert(GenericZapper.SwapFailed.selector);
        genericZapper.redeem(
            shares - fakeAmount, USDT, toAmountMinRedeemed, address(this), address(multiPoolStrategy), redeemTxData
        );
    }

    // function testRedeemDifferentAsset(uint256 amountToDeposit) public {
    function testRedeemDifferentAsset() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares =
            genericZapper.deposit(amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        (, uint256 toAmountMinRedeemed, bytes memory redeemTxData) = getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );

        vm.expectRevert(IGenericZapper.EmptyInput.selector);
        genericZapper.redeem(shares, DAI, toAmountMinRedeemed, address(this), address(multiPoolStrategy), redeemTxData);
    }

    // function testRedeemWithEmptySwapData(uint256 amountToDeposit) public {
    function testRedeemWithEmptySwapData() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        (, uint256 toAmountMin, bytes memory txData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares =
            genericZapper.deposit(amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), txData);
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );

        vm.expectRevert(IGenericZapper.EmptyInput.selector);
        genericZapper.redeem(shares, USDT, 0, address(this), address(multiPoolStrategy), "");
    }

    // function testRedeemDecreasedSwapAmount(uint256 amountToDeposit) public {
    function testRedeemDecreasedSwapAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (, uint256 toAmountMin, bytes memory depositTxData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares = genericZapper.deposit(
            amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), depositTxData
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        uint256 fakeAmount = (storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit) * 90 / 100;
        (,, bytes memory redeemTxData) =
            getQuoteLiFi(multiPoolStrategy.asset(), USDT, fakeAmount, address(genericZapper));

        uint256 minAmount = amountToDeposit * 95 / 100;

        vm.expectRevert(GenericZapper.AmountBelowMinimum.selector);
        genericZapper.redeem(shares, USDT, minAmount, address(this), address(multiPoolStrategy), redeemTxData);
    }

    // function testRedeemIncreasedSwapAmount(uint256 amountToDeposit) public {
    function testRedeemIncreasedSwapAmount() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        // fakeAmount =
        //     bound(fakeAmount, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals()); //
        // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (, uint256 toAmountMin, bytes memory depositTxData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares = genericZapper.deposit(
            amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), depositTxData
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        uint256 fakeAmount = (storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit) * 110 / 100;
        (,, bytes memory redeemTxData) =
            getQuoteLiFi(multiPoolStrategy.asset(), USDT, fakeAmount, address(genericZapper));

        uint256 minAmount = amountToDeposit * 95 / 100;

        vm.expectRevert(GenericZapper.SwapFailed.selector);
        genericZapper.redeem(shares, USDT, minAmount, address(this), address(multiPoolStrategy), redeemTxData);
    }

    // function testRedeemWithInvalidSwapData(uint256 amountToDeposit) public {
    function testRedeemWithInvalidSwapData() public {
        // TODO! once we have the API-KEY setup runs
        // amountToDeposit =
        //     bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());
        // // TODO! once we have the API-KEY setup runs
        uint256 amountToDeposit = 10 * 10 ** IERC20(USDT).decimals();

        // reset approved amount
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), 0);
        SafeERC20.safeApprove(IERC20(USDT), address(genericZapper), amountToDeposit);

        (, uint256 toAmountMin, bytes memory depositTxData) =
            getQuoteLiFi(USDT, multiPoolStrategy.asset(), amountToDeposit, address(genericZapper));

        uint256 storedTotalAssetsBeforeDeposit = multiPoolStrategy.storedTotalAssets();
        uint256 shares = genericZapper.deposit(
            amountToDeposit, USDT, toAmountMin, address(this), address(multiPoolStrategy), depositTxData
        );
        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // redeem all shares
        getQuoteLiFi(
            multiPoolStrategy.asset(),
            USDT,
            storedTotalAssetsAfterDeposit - storedTotalAssetsBeforeDeposit,
            address(genericZapper)
        );

        uint256 minAmount = amountToDeposit * 95 / 100;

        vm.expectRevert(IGenericZapper.EmptyInput.selector);
        genericZapper.redeem(shares, USDT, minAmount, address(this), address(multiPoolStrategy), "");

        vm.expectRevert(GenericZapper.SwapFailed.selector);
        genericZapper.redeem(shares, USDT, minAmount, address(this), address(multiPoolStrategy), "000000000000");
    }

    // UTILS

    /**
     * @notice Calculates the quote for a trade via LiFi protocol.
     * @notice make sure Python environment is active and has the required dependencies installed.
     * @param srcToken The token to be sold.
     * @param dstToken The token to be bought.
     * @param amount The amount of source tokens to be sold.
     * @param fromAddress The address initiating the trade.
     */
    function getQuoteLiFi(
        address srcToken,
        address dstToken,
        uint256 amount,
        address fromAddress
    )
        internal
        returns (uint256 _quote, uint256 _toAmountMin, bytes memory data)
    {
        string[] memory inputs = new string[](7);
        inputs[0] = "python3";
        inputs[1] = "test/get_quote_lifi.py";
        inputs[2] = vm.toString(srcToken);
        inputs[3] = vm.toString(dstToken);
        inputs[4] = vm.toString(amount);
        inputs[5] = vm.toString(fromAddress);
        inputs[6] = vm.toString(true);

        bytes memory resp = vm.ffi(inputs);
        return abi.decode(resp, (uint256, uint256, bytes));
    }

    function concat(bytes memory a, bytes memory b) public pure returns (bytes memory) {
        bytes memory result = new bytes(a.length + b.length);
        uint256 k = 0;
        for (uint256 i = 0; i < a.length; i++) {
            result[k++] = a[i];
        }
        for (uint256 i = 0; i < b.length; i++) {
            result[k++] = b[i];
        }
        return result;
    }
}

// HELPER CONTRACTS

contract ERC20Hackable is ERC20("Hackable", "HACK") {
    IGenericZapper public zapper;
    address public strategyAddress;

    constructor(IGenericZapper _zapper, address _strategyAddress) {
        zapper = _zapper;
        strategyAddress = _strategyAddress;

        _mint(msg.sender, 100 ether);
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // invoke reentrancy attack
        zapper.deposit(amount, address(this), 0, msg.sender, strategyAddress, "");

        return super.transferFrom(from, to, amount);
    }
}
