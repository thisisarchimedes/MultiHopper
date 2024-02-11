// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19 .0;

import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "univ3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "univ3-periphery/libraries/OracleLibrary.sol";
import "univ3-periphery/interfaces/ISwapRouter.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract UniswapV3Adapter is Initializable, IUniswapV3MintCallback, ERC20Upgradeable {
    using SafeERC20 for IERC20;
    using OracleLibrary for int24;

    IUniswapV3Pool public pool;
    bool public isToken0;
    ISwapRouter public swapRouter;

    int24 public limitLower;
    int24 public limitUpper;
    IERC20 public token0;
    IERC20 public token1;
    bool mintCalled;
    uint256 constant PRECISION = 1e36;
    uint24 poolFee;

    function initialize(
        IUniswapV3Pool _pool,
        int24 _limitLower,
        int24 _limitUpper,
        bool _isToken0
    )
        external
        initializer
    {
        __ERC20_init("UniswapV3Adapter", "UVA");
        pool = _pool;
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
        limitLower = _limitLower;
        limitUpper = _limitUpper;
        isToken0 = _isToken0;
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        poolFee = pool.fee();
    }

    struct DepositParams {
        uint256 amount;
        uint256 amountToSwap;
        uint256 minOutput;
    }

    function deposit(bytes calldata _params) external {
        DepositParams memory params = abi.decode(_params, (DepositParams));
        //calculate shares
        uint256 shares = _calcShares(params.amount);
        isToken0
            ? token0.safeTransferFrom(msg.sender, address(this), params.amount)
            : token1.safeTransferFrom(msg.sender, address(this), params.amount);
        //swap logic
        if (params.amountToSwap > 0) {
            bytes memory path = abi.encodePacked(
                isToken0 ? address(token0) : address(token1), poolFee, isToken0 ? address(token1) : address(token0)
            );
            isToken0
                ? token0.safeApprove(address(swapRouter), params.amountToSwap)
                : token1.safeApprove(address(swapRouter), params.amountToSwap);
            swapRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: params.amountToSwap,
                    amountOutMinimum: params.minOutput
                })
            );
        }

        uint256 token0Bal = token0.balanceOf(address(this));
        uint256 token1Bal = token1.balanceOf(address(this));
        uint128 liquidity = _liquidityForAmounts(limitLower, limitUpper, token0Bal, token1Bal);
        _mintLiquidity(limitLower, limitUpper, liquidity, address(this), token0Bal, token1Bal);
        _mint(msg.sender, shares);
    }

    function underlyingBalance() public view returns (uint256) {
        int24 tick = currentTick();

        (, uint128 amount0, uint128 amount1) = getPosition();
        uint128 curValBal =
            isToken0 ? uint128(token1.balanceOf(address(this))) : uint128(token0.balanceOf(address(this)));
        uint256 amount = isToken0
            ? tick.getQuoteAtTick(amount1 + curValBal, address(token1), address(token0))
            : tick.getQuoteAtTick(amount0 + curValBal, address(token0), address(token1));
        uint256 curUnderlyingBal = isToken0 ? token0.balanceOf(address(this)) : token1.balanceOf(address(this));
        return isToken0 ? amount0 + amount + curUnderlyingBal : amount1 + amount + curUnderlyingBal;
    }

    /// @notice Get the info of the given position
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @return liquidity The amount of liquidity of the position
    /// @return tokensOwed0 Amount of token0 owed
    /// @return tokensOwed1 Amount of token1 owed
    function _position(
        int24 tickLower,
        int24 tickUpper
    )
        internal
        view
        returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1)
    {
        bytes32 positionKey = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        (liquidity,,, tokensOwed0, tokensOwed1) = pool.positions(positionKey);
    }

    /// @notice Get the liquidity amount of the given numbers of token0 and token1
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0 The amount of token0
    /// @param amount0 The amount of token1
    /// @return Amount of liquidity tokens
    function _liquidityForAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    )
        internal
        view
        returns (uint128)
    {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0,
            amount1
        );
    }

    /// @notice Callback function of uniswapV3Pool mint
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
        require(msg.sender == address(pool));
        require(mintCalled == true);
        mintCalled = false;
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
    }

    /// @notice Adds the liquidity for the given position
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param liquidity The amount of liquidity to mint
    /// @param payer Payer Data
    /// @param amount0Min Minimum amount of token0 that should be paid
    /// @param amount1Min Minimum amount of token1 that should be paid

    function _mintLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address payer,
        uint256 amount0Min,
        uint256 amount1Min
    )
        internal
    {
        if (liquidity > 0) {
            mintCalled = true;
            (uint256 amount0, uint256 amount1) =
                pool.mint(address(this), tickLower, tickUpper, liquidity, abi.encode(payer));
            // require(amount0 >= amount0Min && amount1 >= amount1Min, "PSC");
        }
    }

    /// @return tick Uniswap pool's current price tick
    function currentTick() public view returns (int24 tick) {
        (, tick,,,,,) = pool.slot0();
    }

    /// @return liquidity Amount of total liquidity in the  position
    /// @return amount0 Estimated amount of token0 that could be collected by
    /// burning the  position
    /// @return amount1 Estimated amount of token1 that could be collected by
    /// burning the  position
    function getPosition() public view returns (uint128 liquidity, uint128 amount0, uint128 amount1) {
        (uint128 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = _position(limitLower, limitUpper);
        (uint256 _amount0, uint256 _amount1) = _amountsForLiquidity(limitLower, limitUpper, positionLiquidity);
        amount0 = uint128(_amount0) + (tokensOwed0);
        amount1 = uint128(_amount1) + (tokensOwed1);
        liquidity = positionLiquidity;
    }
    /// @notice Get the amounts of the given numbers of liquidity tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param liquidity The amount of liquidity tokens
    /// @return Amount of token0 and token1

    function _amountsForLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    )
        internal
        view
        returns (uint256, uint256)
    {
        (uint160 sqrtRatioX96,,,,,,) = pool.slot0();
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }

    function _calcShares(uint256 amount) internal view returns (uint256) {
        uint256 underlyingBal = underlyingBalance();
        uint256 supply = totalSupply();
        if (supply == 0 || amount == 0) {
            return amount;
        }
        return (amount * supply) / underlyingBal;
    }
}
