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

contract UniswapV3AdapterTest is PRBTest, StdCheats {
    using OracleLibrary for int24;

    UniswapV3Adapter uniswapV3Adapter;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    IUniswapV3Pool public constant WETH_WBTC_POOL = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);

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

    // function testUnderlyingBalance() public {
    //     deal(WETH, address(uniswapV3Adapter), 50e18);
    //     deal(WBTC, address(uniswapV3Adapter), 1e8);

    //     (int24 lowerTick, int24 upperTick) = chooseTicks(99, 101);

    //     uniswapV3Adapter.initialize(IUniswapV3Pool(WETH_WBTC_POOL), lowerTick, upperTick, false);
    //     uniswapV3Adapter.deposit(1e8, 0);
    //     uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
    // }

    // function testProvideLiquidityInRange() public { }

    function testProvideLiquidityOutRangeRight() public {
        deal(WETH, address(this), 1e18);
        IERC20(WETH).approve(address(uniswapV3Adapter), 1e18);
        (int24 lowerTick, int24 upperTick, int24 tick) = chooseTicks(101, 102);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, false);
        bytes memory params = abi.encode(UniswapV3Adapter.DepositParams(1e18, 1e18, 0));
        uniswapV3Adapter.deposit(params);
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        assertAlmostEq(underlyingBalance, 1e18, 0.02e18);
    }

    // function testProvideLiquidityOutRangeLeft() public {
    //     deal(WETH, address(uniswapV3Adapter), 5e18);
    //     (int24 lowerTick, int24 upperTick,) = chooseTicks(97, 99);
    //     uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, false);
    //     uniswapV3Adapter.deposit(0, 0);
    //     uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
    //     assertAlmostEq(underlyingBalance, 5e18, 0.02e18);
    // }

    function testProvideLiquidityInRange() public {
        deal(WETH, address(this), 50e18);
        IERC20(WETH).approve(address(uniswapV3Adapter), 50e18);
        (int24 lowerTick, int24 upperTick, int24 currentTick) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, false);
        bool isToken0 = uniswapV3Adapter.isToken0();
        uint256 amountToSwap = getAmountToSwap(50e18, lowerTick, upperTick, currentTick, isToken0, 8, 18);
        bytes memory params = abi.encode(UniswapV3Adapter.DepositParams(50e18, amountToSwap, 0));
        uniswapV3Adapter.deposit(params);
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = 50e18 * 5 / 1000;
        assertAlmostEq(underlyingBalance, 50e18, expectedError);
    }

    function testProvideLiquidityInRangeBTC() public {
        deal(WBTC, address(this), 50e8);
        IERC20(WBTC).approve(address(uniswapV3Adapter), 50e8);
        (int24 lowerTick, int24 upperTick, int24 currentTick) = chooseTicks(99, 101);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, true);
        bool isToken0 = uniswapV3Adapter.isToken0();
        uint256 amountToSwap = getAmountToSwap(50e8, lowerTick, upperTick, currentTick, isToken0, 8, 18);
        bytes memory params = abi.encode(UniswapV3Adapter.DepositParams(50e8, amountToSwap, 0));
        uniswapV3Adapter.deposit(params);
        uint256 underlyingBalance = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = 50e8 * 5 / 1000;
        assertAlmostEq(underlyingBalance, 50e8, expectedError);
    }

    function chooseTicks(int24 lowerPercentile, int24 upperPercentile) public view returns (int24, int24, int24) {
        (, int24 tick,,,,,) = WETH_WBTC_POOL.slot0();
        int24 tickSpacing = WETH_WBTC_POOL.tickSpacing();
        int24 lowerTick = (int24(int128(tick) * lowerPercentile / 100)) / tickSpacing * tickSpacing;
        int24 upperTick = (int24(int128(tick) * upperPercentile / 100)) / tickSpacing * tickSpacing;
        return (lowerTick, upperTick, tick);
    }

    function getAmountToSwap(
        uint256 amount,
        int24 lowerTick,
        int24 upperTick,
        int24 currentTick,
        bool isToken0,
        uint8 token0Decimal,
        uint8 token1Decimal
    )
        internal
        returns (uint256 _amountToSell)
    {
        string[] memory inputs = new string[](9);
        inputs[0] = "python3";
        inputs[1] = "test/calc.py";
        inputs[2] = vm.toString(amount);
        inputs[3] = vm.toString(lowerTick);
        inputs[4] = vm.toString(upperTick);
        inputs[5] = vm.toString(currentTick);
        inputs[6] = vm.toString(isToken0);
        inputs[7] = vm.toString(token0Decimal);
        inputs[8] = vm.toString(token1Decimal);
        return abi.decode(vm.ffi(inputs), (uint256));
    }
}
