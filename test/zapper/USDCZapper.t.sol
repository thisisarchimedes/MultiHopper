// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { StdCheats, StdUtils, console2 } from "forge-std/Test.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IZapper } from "../../src/interfaces/IZapper.sol";
import { ICurveBasePool, ICurve3Pool } from "../../src/interfaces/ICurvePool.sol";
import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../../src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../../src/AuraWeightedPoolAdapter.sol";
import { USDCZapper } from "../../src/zapper/USDCZapper.sol";
import { ERC20Hackable } from "../../src/test/ERC20Hackable.sol";

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

    USDCZapper public usdcZapper;

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

        deal(address(this), 100_000_000 ether);
        deal(UNDERLYING_ASSET, address(this), 100_000_000 ether);
        deal(USDT, address(this), 100_000_000 ether);
        deal(DAI, address(this), 100_000_000 ether);
        deal(FRAX, address(this), 100_000_000 ether);
        deal(CRV, address(this), 100_000_000 ether);
        deal(CRVFRAX, address(this), 100_000_000 ether);

        deal(UNDERLYING_ASSET, staker, 50 ether);

        SafeERC20.safeApprove(IERC20(UNDERLYING_ASSET), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(USDT), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(DAI), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(FRAX), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(CRV), address(usdcZapper), type(uint256).max);
        SafeERC20.safeApprove(IERC20(CRVFRAX), address(usdcZapper), type(uint256).max);
        // shares
        SafeERC20.safeApprove(IERC20(address(multiPoolStrategy)), address(usdcZapper), type(uint256).max);
    }

    // DEPOSIT - POSITIVE TESTS
    function testDepositUSDT(uint256 amountToDeposit) public {
        // get usdt amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 usdtBalanceOfThisPre = IERC20(USDT).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        // get the amount of usdc coin one would receive for swapping amount of usdt coin
        uint256 calculatedUSDCAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(USDT_INDEX, UNDERLYING_ASSET_INDEX, amountToDeposit);

        uint256 shares = usdcZapper.deposit(amountToDeposit, USDT, 0, address(this), address(multiPoolStrategy));

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // check that swap fees are less than 1%
        assertAlmostEq(
            amountToDeposit, usdcDepositedAmountToMultiPoolStrategy, usdcDepositedAmountToMultiPoolStrategy / 100
        );
        // check that swap works correctly
        assertAlmostEq(
            calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy, usdcDepositedAmountToMultiPoolStrategy / 100
        );
        // check usdt amount of this contract after deposit
        assertEq(IERC20(USDT).balanceOf(address(this)), usdtBalanceOfThisPre - amountToDeposit);
        // check usdc deposited amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    function testDepositDAI(uint256 amountToDeposit) public {
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(DAI).decimals(), 10_000_000 * 10 ** IERC20(DAI).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 daiBalanceOfThisPre = IERC20(DAI).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        // get the amount of usdc coin one would receive for swapping amount of dai coin
        uint256 calculatedUSDCAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(DAI_INDEX, UNDERLYING_ASSET_INDEX, amountToDeposit);

        uint256 shares = usdcZapper.deposit(amountToDeposit, DAI, 0, address(this), address(multiPoolStrategy));

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // convert dai 18 decimals to 6 decimals
        uint256 daiAmount6Decimals =
            amountToDeposit / (10 ** (IERC20(DAI).decimals() - IERC20(UNDERLYING_ASSET).decimals()));

        // check that swap fees are less than 1%
        assertAlmostEq(
            daiAmount6Decimals, usdcDepositedAmountToMultiPoolStrategy, usdcDepositedAmountToMultiPoolStrategy / 100
        );

        // check that swap works correctly
        assertAlmostEq(
            calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy, usdcDepositedAmountToMultiPoolStrategy / 100
        );

        // check dai amount of this contract after deposit
        assertEq(IERC20(DAI).balanceOf(address(this)), daiBalanceOfThisPre - amountToDeposit);
        // check deposited usdc amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    function testDepositFRAX(uint256 amountToDeposit) public {
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(FRAX).decimals(), 10_000_000 * 10 ** IERC20(FRAX).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 fraxBalanceOfThisPre = IERC20(FRAX).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
        uint256 shares = usdcZapper.deposit(amountToDeposit, FRAX, 0, address(this), address(multiPoolStrategy));

        // get the amount of usdc coin one would receive for swapping amount of frax coin
        uint256 calculatedUSDCAmount =
            ICurveBasePool(CURVE_FRAXUSDC).get_dy(FRAX_INDEX, UNDERLYING_ASSET_INDEX, amountToDeposit);

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // convert frax 18 decimals to 6 decimals
        uint256 fraxAmount6Decimals =
            amountToDeposit / (10 ** (IERC20(FRAX).decimals() - IERC20(UNDERLYING_ASSET).decimals()));

        // check that swap fees are less than 1%
        assertAlmostEq(
            fraxAmount6Decimals, usdcDepositedAmountToMultiPoolStrategy, usdcDepositedAmountToMultiPoolStrategy / 100
        );

        // check that swap works correctly
        assertAlmostEq(
            calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy, usdcDepositedAmountToMultiPoolStrategy / 100
        );

        // check frax amount of this contract after deposit
        assertEq(IERC20(FRAX).balanceOf(address(this)), fraxBalanceOfThisPre - amountToDeposit);
        // check deposited usdc amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    function testDeposit3CRV(uint256 amountToDeposit) public {
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRV).decimals(), 10_000_000 * 10 ** IERC20(CRV).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 crvBalanceOfThisPre = IERC20(CRV).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        // calculate the amount of USDC received when withdrawing a LP token.
        uint256 calculatedUSDCAmount =
            ICurveBasePool(CURVE_3POOL).calc_withdraw_one_coin(amountToDeposit, UNDERLYING_ASSET_INDEX);

        uint256 shares = usdcZapper.deposit(amountToDeposit, CRV, 0, address(this), address(multiPoolStrategy));

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // check that swap works correctly
        assertEq(calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy);
        // check crv amount of this contract after deposit
        assertEq(IERC20(CRV).balanceOf(address(this)), crvBalanceOfThisPre - amountToDeposit);
        // check deposited usdc amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    function testDepositCRVFRAX(uint256 amountToDeposit) public {
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRVFRAX).decimals(), 10_000_000 * 10 ** IERC20(CRVFRAX).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 crvFraxBalanceOfThisPre = IERC20(CRVFRAX).balanceOf(address(this));
        uint256 usdcBalanceOfMultiPoolStrategyPre = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        // calculate the amount of USDC received when withdrawing a LP token.
        uint256 calculatedUSDCAmount =
            ICurveBasePool(CURVE_FRAXUSDC).calc_withdraw_one_coin(amountToDeposit, UNDERLYING_ASSET_INDEX);

        uint256 shares = usdcZapper.deposit(amountToDeposit, CRVFRAX, 0, address(this), address(multiPoolStrategy));

        uint256 usdcDepositedAmountToMultiPoolStrategy =
            IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy)) - usdcBalanceOfMultiPoolStrategyPre;

        // check that swap works correctly
        assertEq(calculatedUSDCAmount, usdcDepositedAmountToMultiPoolStrategy);
        // check crvfrax amount of this contract after deposit
        assertEq(IERC20(CRVFRAX).balanceOf(address(this)), crvFraxBalanceOfThisPre - amountToDeposit);
        // check deposited usdc amount of multipool strategy after deposit
        assertEq(multiPoolStrategy.storedTotalAssets() - storedTotalAssetsPre, usdcDepositedAmountToMultiPoolStrategy);
        // check shares amount of this contract after deposit
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
        // check shares amount matches usdt amount
        assertAlmostEq(usdcDepositedAmountToMultiPoolStrategy, shares, shares * 1 / 100);
    }

    // DEPOSIT - NEGATIVE TESTS
    function testDepositRevertReentrantCall() public {
        ERC20Hackable erc20Hackable = new ERC20Hackable(usdcZapper, address(multiPoolStrategy));

        usdcZapper.addAsset(
            address(erc20Hackable), USDCZapper.AssetInfo({pool: CURVE_3POOL, index: 0, isLpToken: false})
        );

        vm.expectRevert("ReentrancyGuard: reentrant call");

        usdcZapper.deposit(1, address(erc20Hackable), 0, address(this), address(multiPoolStrategy));
    }

    function testDepositRevertZeroAddress() public {
        address receiver = address(0);

        vm.expectRevert(IZapper.ZeroAddress.selector);
        usdcZapper.deposit(1, USDT, 0, receiver, address(multiPoolStrategy));
    }

    function testDepositRevertStrategyAssetDoesNotMatchUnderlyingAsset() public {
        address strategyWithEth = 0x3836bCA6e2128367ffDBa4B2f82c510F03030F19;

        vm.expectRevert(IZapper.StrategyAssetDoesNotMatchUnderlyingAsset.selector);
        usdcZapper.deposit(1, USDT, 0, address(this), strategyWithEth);
    }

    function testDepositRevertEmptyInput() public {
        uint256 amount = 0;

        vm.expectRevert(IZapper.EmptyInput.selector);
        usdcZapper.deposit(amount, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testDepositRevertMultiPoolStrategyIsPaused() public {
        multiPoolStrategy.togglePause();

        vm.expectRevert(IZapper.StrategyPaused.selector);
        usdcZapper.deposit(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testDepositRevertInvalidAsset() public {
        usdcZapper.removeAsset(USDT);

        vm.expectRevert(IZapper.InvalidAsset.selector);
        usdcZapper.deposit(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testDepositRevertPoolDoesNotExist() public {
        usdcZapper.updateAsset(USDT, USDCZapper.AssetInfo({pool: address(0), index: 0, isLpToken: false}));

        vm.expectRevert(IZapper.PoolDoesNotExist.selector);
        usdcZapper.deposit(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    // WITHDRAW - POSITIVE TESTS
    function testWithdrawAllUSDT(uint256 amountToDeposit) public {
        // get usdt amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, USDT, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 usdtBalanceOfThisPre = IERC20(USDT).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get actual deposited amount and convert it to USDT
        uint256 depositedUSDCAmount = storedTotalAssetsAfterDeposit - storedTotalAssetsPre;
        uint256 depositedUSDTAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(UNDERLYING_ASSET_INDEX, USDT_INDEX, depositedUSDCAmount);

        // withdraw all deposited USDT
        uint256 burntShares =
            usdcZapper.withdraw(depositedUSDTAmount, USDT, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(USDT).balanceOf(address(this)) - usdtBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = depositedUSDCAmount;
        uint256 amountToWithdrawUSDT = depositedUSDTAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawUSDT, withdrawnAmount, withdrawnAmount / 100);
        // check usdt amount of this contract after withdraw
        assertEq(IERC20(USDT).balanceOf(address(this)), usdtBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of with withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawHalfOfUSDT(uint256 amountToDeposit) public {
        // get usdt amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, USDT, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 usdtBalanceOfThisPre = IERC20(USDT).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get half of actual deposited amount and convert it to USDT
        uint256 halfOfDepositedUSDCAmount = (storedTotalAssetsAfterDeposit - storedTotalAssetsPre) / 2;
        uint256 halfOfDepositedUSDTAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(UNDERLYING_ASSET_INDEX, USDT_INDEX, halfOfDepositedUSDCAmount);

        // withdraw all deposited USDT
        uint256 burntShares =
            usdcZapper.withdraw(halfOfDepositedUSDTAmount, USDT, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(USDT).balanceOf(address(this)) - usdtBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = halfOfDepositedUSDCAmount;
        uint256 amountToWithdrawUSDT = halfOfDepositedUSDTAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawUSDT, withdrawnAmount, withdrawnAmount / 100);
        // check usdt amount of this contract after withdraw
        assertEq(IERC20(USDT).balanceOf(address(this)), usdtBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawAllDAI(uint256 amountToDeposit) public {
        // get dai amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(DAI).decimals(), 10_000_000 * 10 ** IERC20(DAI).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, DAI, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 daiBalanceOfThisPre = IERC20(DAI).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get actual deposited amount and convert it to DAI
        uint256 depositedUSDCAmount = storedTotalAssetsAfterDeposit - storedTotalAssetsPre;
        uint256 depositedDAIAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(UNDERLYING_ASSET_INDEX, DAI_INDEX, depositedUSDCAmount);

        // withdraw all deposited DAI
        uint256 burntShares = usdcZapper.withdraw(depositedDAIAmount, DAI, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(DAI).balanceOf(address(this)) - daiBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = depositedUSDCAmount;
        uint256 amountToWithdrawDAI = depositedDAIAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawDAI, withdrawnAmount, withdrawnAmount / 100);
        // check usdt amount of this contract after withdraw
        assertEq(IERC20(DAI).balanceOf(address(this)), daiBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of with withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawHalfOfDAI(uint256 amountToDeposit) public {
        // get dai amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(DAI).decimals(), 10_000_000 * 10 ** IERC20(DAI).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, DAI, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 daiBalanceOfThisPre = IERC20(DAI).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get half of actual deposited amount and convert it to DAI
        uint256 halfOfDepositedUSDCAmount = (storedTotalAssetsAfterDeposit - storedTotalAssetsPre) / 2;
        uint256 halfOfDepositedDAIAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(UNDERLYING_ASSET_INDEX, DAI_INDEX, halfOfDepositedUSDCAmount);

        // withdraw all deposited DAI
        uint256 burntShares =
            usdcZapper.withdraw(halfOfDepositedDAIAmount, DAI, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(DAI).balanceOf(address(this)) - daiBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = halfOfDepositedUSDCAmount;
        uint256 amountToWithdrawDAI = halfOfDepositedDAIAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawDAI, withdrawnAmount, withdrawnAmount / 100);
        // check DAI amount of this contract after withdraw
        assertEq(IERC20(DAI).balanceOf(address(this)), daiBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawAllFRAX(uint256 amountToDeposit) public {
        // get frax amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(FRAX).decimals(), 10_000_000 * 10 ** IERC20(FRAX).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, FRAX, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 fraxBalanceOfThisPre = IERC20(FRAX).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get actual deposited amount and convert it to FRAX
        uint256 depositedUSDCAmount = storedTotalAssetsAfterDeposit - storedTotalAssetsPre;
        uint256 depositedFRAXAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(UNDERLYING_ASSET_INDEX, FRAX_INDEX, depositedUSDCAmount);

        // withdraw all deposited FRAX
        uint256 burntShares =
            usdcZapper.withdraw(depositedFRAXAmount, FRAX, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(FRAX).balanceOf(address(this)) - fraxBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = depositedUSDCAmount;
        uint256 amountToWithdrawFRAX = depositedFRAXAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawFRAX, withdrawnAmount, withdrawnAmount / 100);
        // check frax amount of this contract after withdraw
        assertEq(IERC20(FRAX).balanceOf(address(this)), fraxBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of with withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawHalfOfFRAX(uint256 amountToDeposit) public {
        // get frax amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(FRAX).decimals(), 10_000_000 * 10 ** IERC20(FRAX).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, FRAX, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 fraxBalanceOfThisPre = IERC20(FRAX).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get half of actual deposited amount and convert it to FRAX
        uint256 halfOfDepositedUSDCAmount = (storedTotalAssetsAfterDeposit - storedTotalAssetsPre) / 2;
        uint256 halfOfDepositedFRAXAmount =
            ICurveBasePool(CURVE_3POOL).get_dy(UNDERLYING_ASSET_INDEX, FRAX_INDEX, halfOfDepositedUSDCAmount);

        // withdraw all deposited FRAX
        uint256 burntShares =
            usdcZapper.withdraw(halfOfDepositedFRAXAmount, FRAX, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(FRAX).balanceOf(address(this)) - fraxBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = halfOfDepositedUSDCAmount;
        uint256 amountToWithdrawFRAX = halfOfDepositedFRAXAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawFRAX, withdrawnAmount, withdrawnAmount / 100);
        // check FRAX amount of this contract after withdraw
        assertEq(IERC20(FRAX).balanceOf(address(this)), fraxBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawAll3CRV(uint256 amountToDeposit) public {
        // get CRV amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRV).decimals(), 10_000_000 * 10 ** IERC20(CRV).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, CRV, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 crvBalanceOfThisPre = IERC20(CRV).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get actual deposited amount and convert it to CRV
        uint256 depositedUSDCAmount = storedTotalAssetsAfterDeposit - storedTotalAssetsPre;
        uint256 depositedCRVAmount = ICurveBasePool(CURVE_3POOL).calc_token_amount([0, depositedUSDCAmount, 0], false);

        // withdraw all deposited CRV
        uint256 burntShares = usdcZapper.withdraw(depositedCRVAmount, CRV, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(CRV).balanceOf(address(this)) - crvBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = depositedUSDCAmount;
        uint256 amountToWithdrawCRV = depositedCRVAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawCRV, withdrawnAmount, withdrawnAmount / 100);
        // check CRV amount of this contract after withdraw
        assertEq(IERC20(CRV).balanceOf(address(this)), crvBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of with withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawHalfOf3CRV(uint256 amountToDeposit) public {
        // get CRV amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRV).decimals(), 10_000_000 * 10 ** IERC20(CRV).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, CRV, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 crvBalanceOfThisPre = IERC20(CRV).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get half of actual deposited amount and convert it to CRV
        uint256 halfOfDepositedUSDCAmount = (storedTotalAssetsAfterDeposit - storedTotalAssetsPre) / 2;
        uint256 halfOfDepositedCRVAmount =
            ICurveBasePool(CURVE_3POOL).calc_token_amount([0, halfOfDepositedUSDCAmount, 0], false);

        // withdraw all deposited CRV
        uint256 burntShares =
            usdcZapper.withdraw(halfOfDepositedCRVAmount, CRV, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(CRV).balanceOf(address(this)) - crvBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = halfOfDepositedUSDCAmount;
        uint256 amountToWithdrawCRV = halfOfDepositedCRVAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawCRV, withdrawnAmount, withdrawnAmount / 100);
        // check CRV amount of this contract after withdraw
        assertEq(IERC20(CRV).balanceOf(address(this)), crvBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of with withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawAllCRVFRAX(uint256 amountToDeposit) public {
        // get CRVFRAX amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRVFRAX).decimals(), 10_000_000 * 10 ** IERC20(CRVFRAX).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, CRVFRAX, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 crvfraxBalanceOfThisPre = IERC20(CRVFRAX).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get actual deposited amount and convert it to CRVFRAX
        uint256 depositedUSDCAmount = storedTotalAssetsAfterDeposit - storedTotalAssetsPre;
        uint256 depositedCRVFRAXAmount =
            ICurveBasePool(CURVE_FRAXUSDC).calc_token_amount([0, depositedUSDCAmount], false);

        // withdraw all deposited CRVFRAX
        uint256 burntShares =
            usdcZapper.withdraw(depositedCRVFRAXAmount, CRVFRAX, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(CRVFRAX).balanceOf(address(this)) - crvfraxBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = depositedUSDCAmount;
        uint256 amountToWithdrawCRVFRAX = depositedCRVFRAXAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawCRVFRAX, withdrawnAmount, withdrawnAmount / 100);
        // check CRV amount of this contract after withdraw
        assertEq(IERC20(CRVFRAX).balanceOf(address(this)), crvfraxBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of with withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    function testWithdrawHalfOfCRVFRAX(uint256 amountToDeposit) public {
        // get CRVFRAX amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRVFRAX).decimals(), 10_000_000 * 10 ** IERC20(CRVFRAX).decimals());

        uint256 storedTotalAssetsPre = multiPoolStrategy.storedTotalAssets();

        // firstly deposit
        usdcZapper.deposit(amountToDeposit, CRVFRAX, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before withdraw
        uint256 crvfraxBalanceOfThisPre = IERC20(CRVFRAX).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // get half of actual deposited amount and convert it to CRVFRAX
        uint256 halfOfDepositedUSDCAmount = (storedTotalAssetsAfterDeposit - storedTotalAssetsPre) / 2;
        uint256 halfOfDepositedCRVFRAXAmount =
            ICurveBasePool(CURVE_FRAXUSDC).calc_token_amount([0, halfOfDepositedUSDCAmount], false);

        // withdraw all deposited CRVFRAX
        uint256 burntShares =
            usdcZapper.withdraw(halfOfDepositedCRVFRAXAmount, CRVFRAX, 0, address(this), address(multiPoolStrategy));

        uint256 withdrawnAmount = IERC20(CRVFRAX).balanceOf(address(this)) - crvfraxBalanceOfThisPre;

        // just for naming convention
        uint256 amountToWithdrawUSDC = halfOfDepositedUSDCAmount;
        uint256 amountToWithdrawCRVFRAX = halfOfDepositedCRVFRAXAmount;

        // check that withdraw works correctly and swap fees are less than 1%
        assertAlmostEq(amountToWithdrawCRVFRAX, withdrawnAmount, withdrawnAmount / 100);
        // check CRV amount of this contract after withdraw
        assertEq(IERC20(CRVFRAX).balanceOf(address(this)), crvfraxBalanceOfThisPre + withdrawnAmount);
        // check usdc amount of multipool strategy after withdraw, difference should be less than 1% of with withdrawal amount
        assertAlmostEq(
            multiPoolStrategy.storedTotalAssets(),
            storedTotalAssetsAfterDeposit - amountToWithdrawUSDC,
            amountToWithdrawUSDC / 100
        );
        // check shares amount of this contract after withdraw
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - burntShares);
        // check that burnt shares amount matches usdc withdrawal amount
        assertAlmostEq(amountToWithdrawUSDC, burntShares, burntShares / 100);
    }

    // WITHDRAW - NEGATIVE TESTS
    function testWithdrawRevertZeroAddress() public {
        address receiver = address(0);

        vm.expectRevert(IZapper.ZeroAddress.selector);
        usdcZapper.withdraw(1, USDT, 0, receiver, address(multiPoolStrategy));
    }

    function testWithdrawRevertStrategyAssetDoesNotMatchUnderlyingAsset() public {
        address strategyWithEth = 0x3836bCA6e2128367ffDBa4B2f82c510F03030F19;

        vm.expectRevert(IZapper.StrategyAssetDoesNotMatchUnderlyingAsset.selector);
        usdcZapper.withdraw(1, USDT, 0, address(this), strategyWithEth);
    }

    function testWithdrawRevertEmptyInput() public {
        uint256 amount = 0;

        vm.expectRevert(IZapper.EmptyInput.selector);
        usdcZapper.withdraw(amount, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testWithdrawRevertMultiPoolStrategyIsPaused() public {
        multiPoolStrategy.togglePause();

        vm.expectRevert(IZapper.StrategyPaused.selector);
        usdcZapper.withdraw(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testWithdrawRevertInvalidAsset() public {
        usdcZapper.removeAsset(USDT);

        vm.expectRevert(IZapper.InvalidAsset.selector);
        usdcZapper.withdraw(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testWithdrawRevertPoolDoesNotExist() public {
        usdcZapper.updateAsset(USDT, USDCZapper.AssetInfo({pool: address(0), index: 0, isLpToken: false}));

        vm.expectRevert(IZapper.PoolDoesNotExist.selector);
        usdcZapper.withdraw(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    // REDEEM - POSITIVE TESTS
    function testRedeemUSDT(uint256 amountToDeposit) public {
        // get usdt amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(USDT).decimals(), 10_000_000 * 10 ** IERC20(USDT).decimals());

        // firstly deposit
        uint256 shares = usdcZapper.deposit(amountToDeposit, USDT, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 usdtBalanceOfThisPre = IERC20(USDT).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        uint256 redeemedAmount = usdcZapper.redeem(shares, USDT, 0, address(this), address(multiPoolStrategy));

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, redeemedAmount / 100);
        // check usdt amount of this contract after redeem
        assertEq(IERC20(USDT).balanceOf(address(this)), usdtBalanceOfThisPre + redeemedAmount);
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    function testRedeemDAI(uint256 amountToDeposit) public {
        // get dai amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(DAI).decimals(), 10_000_000 * 10 ** IERC20(DAI).decimals());

        // firstly deposit
        uint256 shares = usdcZapper.deposit(amountToDeposit, DAI, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 daiBalanceOfThisPre = IERC20(DAI).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        uint256 redeemedAmount = usdcZapper.redeem(shares, DAI, 0, address(this), address(multiPoolStrategy));

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, redeemedAmount / 100);
        // check dai amount of this contract after redeem
        assertEq(IERC20(DAI).balanceOf(address(this)), daiBalanceOfThisPre + redeemedAmount);
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    function testRedeemFRAX(uint256 amountToDeposit) public {
        // get frax amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(FRAX).decimals(), 10_000_000 * 10 ** IERC20(FRAX).decimals());

        // firstly deposit
        uint256 shares = usdcZapper.deposit(amountToDeposit, FRAX, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 fraxBalanceOfThisPre = IERC20(FRAX).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        uint256 redeemedAmount = usdcZapper.redeem(shares, FRAX, 0, address(this), address(multiPoolStrategy));

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, redeemedAmount / 100);
        // check frax amount of this contract after redeem
        assertEq(IERC20(FRAX).balanceOf(address(this)), fraxBalanceOfThisPre + redeemedAmount);
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    function testRedeem3CRV(uint256 amountToDeposit) public {
        // get crv amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRV).decimals(), 10_000_000 * 10 ** IERC20(CRV).decimals());

        // firstly deposit
        uint256 shares = usdcZapper.deposit(amountToDeposit, CRV, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 crvBalanceOfThisPre = IERC20(CRV).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        uint256 redeemedAmount = usdcZapper.redeem(shares, CRV, 0, address(this), address(multiPoolStrategy));

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, redeemedAmount / 100);
        // check crv amount of this contract after redeem
        assertEq(IERC20(CRV).balanceOf(address(this)), crvBalanceOfThisPre + redeemedAmount);
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    function testRedeemCRVFRAX(uint256 amountToDeposit) public {
        // get crvfrax amount in the range of 10 to 10_000_000
        amountToDeposit =
            bound(amountToDeposit, 10 * 10 ** IERC20(CRVFRAX).decimals(), 10_000_000 * 10 ** IERC20(CRVFRAX).decimals());

        // firstly deposit
        uint256 shares = usdcZapper.deposit(amountToDeposit, CRVFRAX, 0, address(this), address(multiPoolStrategy));

        uint256 storedTotalAssetsAfterDeposit = multiPoolStrategy.storedTotalAssets();

        // get values before redeem
        uint256 crvFraxBalanceOfThisPre = IERC20(CRVFRAX).balanceOf(address(this));
        uint256 sharesBalanceOfThisPre = IERC20(address(multiPoolStrategy)).balanceOf(address(this));

        // redeem all shares
        uint256 redeemedAmount = usdcZapper.redeem(shares, CRVFRAX, 0, address(this), address(multiPoolStrategy));

        // check that redeem works correctly and swap fees are less than 1%
        assertAlmostEq(amountToDeposit, redeemedAmount, redeemedAmount / 100);
        // check crvfrax amount of this contract after redeem
        assertEq(IERC20(CRVFRAX).balanceOf(address(this)), crvFraxBalanceOfThisPre + redeemedAmount);
        // check usdc amount of multipool strategy after redeem, difference should be less than 1% of redeem amount
        assertAlmostEq(multiPoolStrategy.storedTotalAssets(), storedTotalAssetsAfterDeposit - shares, shares / 100);
        // check shares amount of this contract after redeem
        assertEq(multiPoolStrategy.balanceOf(address(this)), sharesBalanceOfThisPre - shares);
    }

    // REDEEM - NEGATIVE TESTS
    function testRedeemRevertZeroAddress() public {
        address receiver = address(0);

        vm.expectRevert(IZapper.ZeroAddress.selector);
        usdcZapper.redeem(1, USDT, 0, receiver, address(multiPoolStrategy));
    }

    function testRedeemRevertStrategyAssetDoesNotMatchUnderlyingAsset() public {
        address strategyWithEth = 0x3836bCA6e2128367ffDBa4B2f82c510F03030F19;

        vm.expectRevert(IZapper.StrategyAssetDoesNotMatchUnderlyingAsset.selector);
        usdcZapper.redeem(1, USDT, 0, address(this), strategyWithEth);
    }

    function testRedeemRevertEmptyInput() public {
        uint256 amount = 0;

        vm.expectRevert(IZapper.EmptyInput.selector);
        usdcZapper.redeem(amount, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testRedeemRevertMultiPoolStrategyIsPaused() public {
        multiPoolStrategy.togglePause();

        vm.expectRevert(IZapper.StrategyPaused.selector);
        usdcZapper.redeem(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testRedeemRevertInvalidAsset() public {
        usdcZapper.removeAsset(USDT);

        vm.expectRevert(IZapper.InvalidAsset.selector);
        usdcZapper.redeem(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    function testRedeemRevertPoolDoesNotExist() public {
        usdcZapper.updateAsset(USDT, USDCZapper.AssetInfo({pool: address(0), index: 0, isLpToken: false}));

        vm.expectRevert(IZapper.PoolDoesNotExist.selector);
        usdcZapper.redeem(1, USDT, 0, address(this), address(multiPoolStrategy));
    }

    // UTILITY

    function testAddAsset() public {
        usdcZapper.removeAsset(USDT);

        usdcZapper.addAsset(USDT, USDCZapper.AssetInfo(CURVE_3POOL, USDT_INDEX, false));
        assertEq(usdcZapper.assetIsSupported(USDT), true);

        USDCZapper.AssetInfo memory assetInfo = usdcZapper.getAssetInfo(USDT);
        assertEq(assetInfo.pool, CURVE_3POOL);
        assertEq(assetInfo.index, USDT_INDEX);
        assertEq(assetInfo.isLpToken, false);
    }

    function testAddAssetRevertOnlyOwner() public {
        vm.prank(makeAddr("notOwner"));

        vm.expectRevert("Ownable: caller is not the owner");

        usdcZapper.addAsset(USDT, USDCZapper.AssetInfo(CURVE_3POOL, USDT_INDEX, false));
    }

    function testUpdateAsset() public {
        USDCZapper.AssetInfo memory assetInfo1 = usdcZapper.getAssetInfo(USDT);
        assertEq(assetInfo1.pool, CURVE_3POOL);
        assertEq(assetInfo1.index, USDT_INDEX);
        assertEq(assetInfo1.isLpToken, false);

        usdcZapper.updateAsset(USDT, USDCZapper.AssetInfo(CURVE_FRAXUSDC, FRAX_INDEX, true));

        USDCZapper.AssetInfo memory assetInfo2 = usdcZapper.getAssetInfo(USDT);
        assertEq(assetInfo2.pool, CURVE_FRAXUSDC);
        assertEq(assetInfo2.index, FRAX_INDEX);
        assertEq(assetInfo2.isLpToken, true);
    }

    function testUpdateAssetRevertInvalidAsset() public {
        usdcZapper.removeAsset(USDT);

        vm.expectRevert(IZapper.InvalidAsset.selector);

        usdcZapper.updateAsset(USDT, USDCZapper.AssetInfo(CURVE_3POOL, USDT_INDEX, false));
    }

    function testUpdateAssetRevertOnlyOwner() public {
        vm.prank(makeAddr("notOwner"));

        vm.expectRevert("Ownable: caller is not the owner");

        usdcZapper.updateAsset(USDT, USDCZapper.AssetInfo(CURVE_FRAXUSDC, FRAX_INDEX, true));
    }

    function testRemoveAsset() public {
        usdcZapper.removeAsset(USDT);
        assertEq(usdcZapper.assetIsSupported(USDT), false);
    }

    function testRemoveAssetRevertOnlyOwner() public {
        vm.prank(makeAddr("notOwner"));

        vm.expectRevert("Ownable: caller is not the owner");

        usdcZapper.removeAsset(USDT);
    }

    function testStrategyUsesUnderlyingAssetTrue() public {
        assertEq(usdcZapper.strategyUsesUnderlyingAsset(address(multiPoolStrategy)), true);
    }

    function testStrategyUsesUnderlyingAssetFalse() public {
        address strategyWithEth = 0x3836bCA6e2128367ffDBa4B2f82c510F03030F19;
        assertEq(usdcZapper.strategyUsesUnderlyingAsset(address(strategyWithEth)), false);
    }

    function testAssetIsSupportedTrue() public {
        assertEq(usdcZapper.assetIsSupported(USDT), true);
    }

    function testAssetIsSupportedFalse() public {
        usdcZapper.removeAsset(USDT);
        assertEq(usdcZapper.assetIsSupported(USDT), false);
    }

    function testGetAssetInfo() public {
        // test stable coin
        USDCZapper.AssetInfo memory assetInfo1 = usdcZapper.getAssetInfo(USDT);
        assertEq(assetInfo1.pool, CURVE_3POOL);
        assertEq(assetInfo1.index, USDT_INDEX);
        assertEq(assetInfo1.isLpToken, false);

        // test lp token
        USDCZapper.AssetInfo memory assetInfo2 = usdcZapper.getAssetInfo(CRVFRAX);
        assertEq(assetInfo2.pool, CURVE_FRAXUSDC);
        assertEq(assetInfo2.index, UNDERLYING_ASSET_INDEX);
        assertEq(assetInfo2.isLpToken, true);
    }
}
