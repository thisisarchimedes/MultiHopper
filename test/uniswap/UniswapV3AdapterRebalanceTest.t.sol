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
import "univ3-periphery/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract UniswapV3AdapterRebalanceTest is PRBTest, StdCheats {
    using OracleLibrary for int24;

    UniswapV3Adapter uniswapV3Adapter;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    IUniswapV3Pool public constant WETH_WBTC_POOL = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
    ISwapRouter public swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address feeRecipient = makeAddr("feeRecipient");

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

    function testProvideLiquidityInRangeAndRebalance() public {
        (int24 lowerTick, int24 upperTick,) = chooseTicks(97, 103);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient);
        _deposit(50e18);
        (int24 newLowerTick, int24 newUpperTick,) = chooseTicks(95, 105);
        uniswapV3Adapter.rebalance(newLowerTick, newUpperTick, 0, 0);
        int24 currentLowerTick = uniswapV3Adapter.lowerTick();
        int24 currentUpperTick = uniswapV3Adapter.upperTick();
        assertEq(currentLowerTick, newLowerTick);
        assertEq(currentUpperTick, newUpperTick);
        bytes32 positionKey = keccak256(abi.encodePacked(address(uniswapV3Adapter), lowerTick, upperTick));
        (uint128 liquidity,,,,) = WETH_WBTC_POOL.positions(positionKey);
        assertEq(liquidity, 0);
        uint256 underlyingBal = uniswapV3Adapter.underlyingBalance();
        uint256 expectedError = 50e18 * 2 / 1000;
        assertAlmostEq(underlyingBal, 50e18, expectedError);
        positionKey = keccak256(abi.encodePacked(address(uniswapV3Adapter), newLowerTick, newUpperTick));
        (liquidity,,,,) = WETH_WBTC_POOL.positions(positionKey);
        assertGt(liquidity, 0);
    }

    function chooseTicks(int24 lowerPercentile, int24 upperPercentile) public view returns (int24, int24, int24) {
        (, int24 tick,,,,,) = WETH_WBTC_POOL.slot0();
        int24 tickSpacing = WETH_WBTC_POOL.tickSpacing();
        int24 lowerTick = (int24(int128(tick) * lowerPercentile / 100)) / tickSpacing * tickSpacing;
        int24 upperTick = (int24(int128(tick) * upperPercentile / 100)) / tickSpacing * tickSpacing;
        return (lowerTick, upperTick, tick);
    }

    function _deposit(uint256 amount) internal {
        deal(WETH, address(this), amount);
        IERC20(WETH).approve(address(uniswapV3Adapter), amount);
        uniswapV3Adapter.deposit(amount, address(this));
    }
}
