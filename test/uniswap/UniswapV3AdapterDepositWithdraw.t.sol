// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19.0;

import "forge-std/console.sol";
import "forge-std/StdStorage.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";

import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { UniswapV3Adapter } from "src/UniswapV3Adapter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "univ3-periphery/libraries/OracleLibrary.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract UniswapV3AdapterDepositWithdrawTest is PRBTest, StdCheats {
    using OracleLibrary for int24;

    UniswapV3Adapter uniswapV3Adapter;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    IUniswapV3Pool public constant WETH_WBTC_POOL = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
    address feeRecipient = makeAddr("feeRecipient");
    address staker = makeAddr("staker");
    address staker2 = makeAddr("staker2");

    function setUp() public virtual {
        // solhint-disable-previous-line no-empty-blocks
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }

        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_183_629 });

        uniswapV3Adapter = new UniswapV3Adapter();
    }

    function testProvideLiquidityOutRangeRight() public {
        deal(WETH, address(this), 1e18);
        IERC20(WETH).approve(address(uniswapV3Adapter), 1e18);
        (int24 lowerTick, int24 upperTick,) = chooseTicks(102, 103);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uniswapV3Adapter.deposit(1e18, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        assertAlmostEq(underlyingBalance, 1e18, 0.02e18);
    }

    function testProvideLiquidityOutRangeLeft() public {
        deal(WETH, address(this), 5e18);
        IERC20(WETH).approve(address(uniswapV3Adapter), 5e18);
        (int24 lowerTick, int24 upperTick,) = chooseTicks(97, 99);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uniswapV3Adapter.deposit(5e18, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        assertAlmostEq(underlyingBalance, 5e18, 1); // some rounding error
    }

    function testProvideLiquidityOutRangeLeftBTC() public {
        deal(WBTC, address(this), 5e8);
        IERC20(WBTC).approve(address(uniswapV3Adapter), 5e8);
        (int24 lowerTick, int24 upperTick,) = chooseTicks(97, 99);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WBTC, feeRecipient);
        uniswapV3Adapter.deposit(5e8, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = 5e8 * 3 / 1000;
        assertAlmostEq(underlyingBalance, 5e8, expectedError);
    }

    function testProvideLiquidityOutRangeRightBTC() public {
        deal(WBTC, address(this), 5e8);
        IERC20(WBTC).approve(address(uniswapV3Adapter), 5e8);
        (int24 lowerTick, int24 upperTick,) = chooseTicks(101, 103);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WBTC, feeRecipient);
        uniswapV3Adapter.deposit(5e8, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        assertAlmostEq(underlyingBalance, 5e8, 1); // some rounding error
    }

    function testProvideLiquidityInRange() public {
        deal(WETH, address(this), 50e18);
        IERC20(WETH).approve(address(uniswapV3Adapter), 50e18);
        (int24 lowerTick, int24 upperTick, int24 currentTick) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uniswapV3Adapter.deposit(50e18, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = 50e18 * 2 / 1000;
        assertAlmostEq(underlyingBalance, 50e18, expectedError);
    }

    function testProvideLiquidityInRangeBTC() public {
        deal(WBTC, address(this), 50e8);
        IERC20(WBTC).approve(address(uniswapV3Adapter), 50e8);
        (int24 lowerTick, int24 upperTick, int24 currentTick) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WBTC, feeRecipient);
        uniswapV3Adapter.deposit(50e8, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = 50e8 * 2 / 1000;
        assertAlmostEq(underlyingBalance, 50e8, expectedError);
    }

    function testProvideLiquidityInRangeAndWithdraw() public {
        deal(WETH, address(this), 50e18);
        IERC20(WETH).approve(address(uniswapV3Adapter), 50e18);
        (int24 lowerTick, int24 upperTick,) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uniswapV3Adapter.deposit(50e18, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = 50e18 * 2 / 1000;
        assertAlmostEq(underlyingBalance, 50e18, expectedError);
        uint256 shares = uniswapV3Adapter.balanceOf(address(this));
        uniswapV3Adapter.redeem(shares, address(this), address(this), 0);
        uint256 wethBal = IERC20(WETH).balanceOf(address(uniswapV3Adapter));
        uint256 wbtcBal = IERC20(WBTC).balanceOf(address(uniswapV3Adapter));
        uint256 underlyingBalanceAfter = uniswapV3Adapter.underlyingBalance();
        assertEq(wbtcBal, 0);
        assertEq(wethBal, 0);
        assertAlmostEq(underlyingBalanceAfter, 0, 1);
    }

    function testProvideLiquidityInRangeAndWithdrawHalf() public {
        uint256 depositAmount = 50e18;
        deal(WETH, address(this), depositAmount);
        IERC20(WETH).approve(address(uniswapV3Adapter), depositAmount);
        (int24 lowerTick, int24 upperTick,) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uniswapV3Adapter.deposit(depositAmount, address(this));
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = depositAmount * 2 / 1000;
        assertAlmostEq(underlyingBalance, depositAmount, expectedError);
        uint256 shares = uniswapV3Adapter.balanceOf(address(this)) / 2;
        uniswapV3Adapter.redeem(shares, address(this), address(this), 0);
        uint256 underlyingBalanceAfter = uniswapV3Adapter.underlyingBalance();
        assertAlmostEq(underlyingBalanceAfter, depositAmount / 2, expectedError / 2);
    }

    function testCalculateMultipleStakersSharesProperly() public {
        uint256 depositAmount = 50e18;
        deal(WETH, address(this), depositAmount);
        deal(WETH, staker, depositAmount / 2);
        deal(WETH, staker2, depositAmount / 2);
        IERC20(WETH).approve(address(uniswapV3Adapter), depositAmount);
        vm.prank(staker);
        IERC20(WETH).approve(address(uniswapV3Adapter), depositAmount);
        vm.prank(staker2);
        IERC20(WETH).approve(address(uniswapV3Adapter), depositAmount);

        (int24 lowerTick, int24 upperTick,) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uniswapV3Adapter.deposit(depositAmount, address(this));
        vm.prank(staker);
        uniswapV3Adapter.deposit(depositAmount / 2, staker);
        vm.prank(staker2);
        uniswapV3Adapter.deposit(depositAmount / 2, staker2);

        uint256 shares = uniswapV3Adapter.balanceOf(address(this));
        uint256 sharesStaker = uniswapV3Adapter.balanceOf(staker);
        uint256 sharesStaker2 = uniswapV3Adapter.balanceOf(staker2);
        uint256 expectedError = shares * 2 / 1000;
        assertAlmostEq(shares, sharesStaker + sharesStaker2, expectedError);
    }

    function testCalculateMultipleStakersSharesProperlyAndWithdraw() public {
        uint256 depositAmount = 50e18;
        uint256 stakersDepositAmount = 25e18;
        deal(WETH, address(this), depositAmount);
        deal(WETH, staker, stakersDepositAmount);
        deal(WETH, staker2, stakersDepositAmount);
        IERC20(WETH).approve(address(uniswapV3Adapter), depositAmount);
        vm.prank(staker);
        IERC20(WETH).approve(address(uniswapV3Adapter), stakersDepositAmount);
        vm.prank(staker2);
        IERC20(WETH).approve(address(uniswapV3Adapter), stakersDepositAmount);

        (int24 lowerTick, int24 upperTick,) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uniswapV3Adapter.deposit(depositAmount, address(this));
        vm.prank(staker);
        uniswapV3Adapter.deposit(stakersDepositAmount, staker);
        vm.prank(staker2);
        uniswapV3Adapter.deposit(stakersDepositAmount, staker2);

        uint256 shares = uniswapV3Adapter.balanceOf(address(this));
        uint256 sharesStaker = uniswapV3Adapter.balanceOf(staker);
        uint256 sharesStaker2 = uniswapV3Adapter.balanceOf(staker2);
        uint256 expectedError = shares * 2 / 1000;
        uint256 wethBalBefore = IERC20(WETH).balanceOf(address(this));
        assertAlmostEq(shares, sharesStaker + sharesStaker2, expectedError);
        vm.prank(staker);
        uniswapV3Adapter.redeem(sharesStaker, address(this), staker, 0);
        vm.prank(staker2);
        uniswapV3Adapter.redeem(sharesStaker2, address(this), staker2, 0);
        uniswapV3Adapter.redeem(shares, address(this), address(this), 0);
        uint256 wethBalAfter = IERC20(WETH).balanceOf(address(this));
        uint256 underlyingBalanceAfter = uniswapV3Adapter.underlyingBalance();
        assertEq(underlyingBalanceAfter, 0);
        expectedError = (depositAmount + stakersDepositAmount * 2) * 3 / 1000;
        assertAlmostEq(wethBalAfter - wethBalBefore, 100e18, expectedError);
    }

    function testRedeemShouldRevertIfOwnerDidNotApprove() public {
        (int24 lowerTick, int24 upperTick,) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        uint256 depositAmount = 50e18;
        deal(WETH, address(staker), depositAmount);
        vm.startPrank(staker);
        IERC20(WETH).approve(address(uniswapV3Adapter), depositAmount);
        uniswapV3Adapter.deposit(depositAmount, address(staker));
        uint256 shares = uniswapV3Adapter.balanceOf(address(staker));
        vm.stopPrank();
        vm.expectRevert("ERC20: insufficient allowance");
        uniswapV3Adapter.redeem(shares, address(this), address(staker), 0);
    }

    function chooseTicks(int24 lowerPercentile, int24 upperPercentile) public view returns (int24, int24, int24) {
        (, int24 tick,,,,,) = WETH_WBTC_POOL.slot0();
        int24 tickSpacing = WETH_WBTC_POOL.tickSpacing();
        int24 lowerTick = (int24(int128(tick) * lowerPercentile / 100)) / tickSpacing * tickSpacing;
        int24 upperTick = (int24(int128(tick) * upperPercentile / 100)) / tickSpacing * tickSpacing;
        return (lowerTick, upperTick, tick);
    }
}
