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

contract UniswapV3AdapterFeeCollectTest is PRBTest, StdCheats {
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

    function testProvideLiquidityInRangeAndUserShouldEarnFromFees() public {
        (int24 lowerTick, int24 upperTick,) = chooseTicks(97, 103);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, false, feeRecipient);
        _deposit(50e18);
        _createSwapVolumeWithWBTC(1000e8, 100);
        _deposit(50e18);
        uint256 shares = uniswapV3Adapter.balanceOf(address(this));
        uint256 wethBalBefore = IERC20(WETH).balanceOf(address(this));
        uniswapV3Adapter.redeem(shares, address(this), address(this), 0);
        uint256 wethBalAfter = IERC20(WETH).balanceOf(address(this));
        assertGt(wethBalAfter - wethBalBefore, 100e18);
    }

    function testProvideLiquidityInRangeAndFeeRecipientShouldGetFees() public {
        (int24 lowerTick, int24 upperTick,) = chooseTicks(97, 103);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, false, feeRecipient);
        uint256 feeRecipientBalBeforeWeth = IERC20(WETH).balanceOf(feeRecipient);
        uint256 feeRecipientBalBeforeWbtc = IERC20(WBTC).balanceOf(feeRecipient);
        _deposit(50e18);
        _createSwapVolumeWithWBTC(1000e8, 100);
        _deposit(50e18);
        uint256 feeRecipientBalAfterWeth = IERC20(WETH).balanceOf(feeRecipient);
        uint256 feeRecipientBalAfterWbtc = IERC20(WBTC).balanceOf(feeRecipient);
        assertGt(feeRecipientBalAfterWeth - feeRecipientBalBeforeWeth, 0);
        assertGt(feeRecipientBalAfterWbtc - feeRecipientBalBeforeWbtc, 0);
    }

    function testDoHardWork() public {
        (int24 lowerTick, int24 upperTick,) = chooseTicks(97, 103);
        uniswapV3Adapter.initialize(WETH_WBTC_POOL, lowerTick, upperTick, false, feeRecipient);
        uint256 feeRecipientBalBeforeWeth = IERC20(WETH).balanceOf(feeRecipient);
        uint256 feeRecipientBalBeforeWbtc = IERC20(WBTC).balanceOf(feeRecipient);
        _deposit(50e18);
        (uint128 liquidityBefore,,) = uniswapV3Adapter.getPosition();
        _createSwapVolumeWithWBTC(1000e8, 100);
        uniswapV3Adapter.doHardWork();
        (uint128 liquidityAfter,,) = uniswapV3Adapter.getPosition();

        uint256 feeRecipientBalAfterWeth = IERC20(WETH).balanceOf(feeRecipient);
        uint256 feeRecipientBalAfterWbtc = IERC20(WBTC).balanceOf(feeRecipient);
        assertGt(feeRecipientBalAfterWeth - feeRecipientBalBeforeWeth, 0);
        assertGt(feeRecipientBalAfterWbtc - feeRecipientBalBeforeWbtc, 0);
        assertGt(liquidityAfter - liquidityBefore, 0);
    }

    function chooseTicks(int24 lowerPercentile, int24 upperPercentile) public view returns (int24, int24, int24) {
        (, int24 tick,,,,,) = WETH_WBTC_POOL.slot0();
        int24 tickSpacing = WETH_WBTC_POOL.tickSpacing();
        int24 lowerTick = (int24(int128(tick) * lowerPercentile / 100)) / tickSpacing * tickSpacing;
        int24 upperTick = (int24(int128(tick) * upperPercentile / 100)) / tickSpacing * tickSpacing;
        return (lowerTick, upperTick, tick);
    }

    function _createSwapVolumeWithWBTC(uint256 swapAmount, uint256 swapCount) internal {
        deal(WBTC, address(this), swapAmount);
        IERC20(WETH).approve(address(swapRouter), type(uint256).max);
        IERC20(WBTC).approve(address(swapRouter), type(uint256).max);
        uint24 poolFee = IUniswapV3Pool(WETH_WBTC_POOL).fee();
        bytes memory wbtcToWethPath = abi.encodePacked(WBTC, poolFee, WETH);
        bytes memory wethToWbtcPath = abi.encodePacked(WETH, poolFee, WBTC);
        uint256 receivedWeth = swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: wbtcToWethPath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: swapAmount,
                amountOutMinimum: 0
            })
        );
        for (uint256 i = 0; i < swapCount; i++) {
            uint256 receivedWbtc = swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: wethToWbtcPath,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: receivedWeth,
                    amountOutMinimum: 0
                })
            );
            receivedWeth = swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: wbtcToWethPath,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: receivedWbtc,
                    amountOutMinimum: 0
                })
            );
        }
        swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: wethToWbtcPath,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: receivedWeth,
                amountOutMinimum: 0
            })
        );
    }

    function _deposit(uint256 amount) internal {
        deal(WETH, address(this), amount);
        IERC20(WETH).approve(address(uniswapV3Adapter), amount);
        uniswapV3Adapter.deposit(amount, address(this));
    }
}
