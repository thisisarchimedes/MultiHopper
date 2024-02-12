// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19 .0;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "univ3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "univ3-periphery/libraries/OracleLibrary.sol";
import "univ3-periphery/interfaces/ISwapRouter.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { console2 } from "forge-std/console2.sol";

contract UniswapV3Adapter is Initializable, IUniswapV3MintCallback, ERC20Upgradeable {
    using SafeERC20 for IERC20Metadata;
    using OracleLibrary for int24;

    IUniswapV3Pool public pool;
    bool public isToken0;
    ISwapRouter public swapRouter;

    int24 public limitLower;
    int24 public limitUpper;
    IERC20Metadata public token0;
    IERC20Metadata public token1;
    bool mintCalled;
    uint256 constant PRECISION = 1e36;
    uint24 poolFee;

    struct DepositParams {
        uint256 amount;
        address recipient;
        uint256 minOutput;
    }

    struct WithdrawParams {
        uint256 shares;
        uint256 minAmountExpect;
    }

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
        token0 = IERC20Metadata(pool.token0());
        token1 = IERC20Metadata(pool.token1());
        limitLower = _limitLower;
        limitUpper = _limitUpper;
        isToken0 = _isToken0;
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        poolFee = pool.fee();
    }

    function deposit(bytes calldata _params) external {
        DepositParams memory params = abi.decode(_params, (DepositParams));
        bool _isToken0 = isToken0; // gas saving
        //calculate shares
        uint256 shares = _calcShares(params.amount);
        _isToken0
            ? token0.safeTransferFrom(msg.sender, address(this), params.amount)
            : token1.safeTransferFrom(msg.sender, address(this), params.amount);
        //swap logic
        uint256 amountToSwap = _calcAmountToSwap(
            params.amount, limitLower, limitUpper, currentTick(), token0.decimals(), token1.decimals()
        );
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));
        if (amountToSwap > 0) {
            _swapTokens(amountToSwap, params.minOutput, _isToken0);
        }

        uint256 token0BalAfter = amountToSwap > 0 && amountToSwap != params.amount
            ? _isToken0 ? token0Before - amountToSwap : token0.balanceOf(address(this)) - token0Before
            : token0.balanceOf(address(this));
        uint256 token1BalAfter = amountToSwap > 0 && amountToSwap != params.amount
            ? _isToken0 ? token1.balanceOf(address(this)) - token1Before : token1Before - amountToSwap
            : token1.balanceOf(address(this));
        uint128 liquidity = _liquidityForAmounts(limitLower, limitUpper, token0BalAfter, token1BalAfter);
        (uint256 min0Amount, uint256 min1Amount) = _amountsForLiquidity(limitLower, limitUpper, liquidity);
        _mintLiquidity(limitLower, limitUpper, liquidity, address(this), min0Amount, min1Amount);
        _mint(params.recipient, shares);
    }

    function withdraw(bytes calldata _params) external returns (uint256 totalReceive) {
        WithdrawParams memory params = abi.decode(_params, (WithdrawParams));
        bool _isToken0 = isToken0; // gas saving
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));
        uint256 token0FromBal = token0Before * params.shares / totalSupply();
        uint256 token1FromBal = token1Before * params.shares / totalSupply();
        uint128 liqForShares = _liquidityForShares(limitLower, limitUpper, params.shares);

        _burnLiquidity(limitLower, limitUpper, liqForShares, address(this), true, 0, 0);
        uint256 token0After = token0.balanceOf(address(this));
        uint256 token1After = token1.balanceOf(address(this));
        uint256 receivedAmount = _swapTokens(
            isToken0 ? token1After - token1Before + token1FromBal : token0After - token0Before + token0FromBal,
            0,
            !_isToken0
        );
        _burn(msg.sender, params.shares);
        totalReceive = receivedAmount
            + (isToken0 ? token0After - token0Before + token0FromBal : token1After - token1Before + token1FromBal);
        require(totalReceive >= params.minAmountExpect, "PSC");
        _isToken0 ? token0.safeTransfer(msg.sender, totalReceive) : token1.safeTransfer(msg.sender, totalReceive);
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
            require(amount0 >= amount0Min && amount1 >= amount1Min, "PSC");
        }
    }

    /// @notice Burn liquidity from the sender and collect tokens owed for the liquidity
    /// @param tickLower The lower tick of the position for which to burn liquidity
    /// @param tickUpper The upper tick of the position for which to burn liquidity
    /// @param liquidity The amount of liquidity to burn
    /// @param to The address which should receive the fees collected
    /// @param collectAll If true, collect all tokens owed in the pool, else collect the owed tokens of the burn
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function _burnLiquidity(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        address to,
        bool collectAll,
        uint256 amount0Min,
        uint256 amount1Min
    )
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity > 0) {
            /// Burn liquidity
            (uint256 owed0, uint256 owed1) = pool.burn(tickLower, tickUpper, liquidity);
            require(owed0 >= amount0Min && owed1 >= amount1Min, "PSC");

            // Collect amount owed
            uint128 collect0 = collectAll ? type(uint128).max : _uint128Safe(owed0);
            uint128 collect1 = collectAll ? type(uint128).max : _uint128Safe(owed1);
            if (collect0 > 0 || collect1 > 0) {
                (amount0, amount1) = pool.collect(to, tickLower, tickUpper, collect0, collect1);
            }
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
        uint256 supply = totalSupply();
        if (supply == 0 || amount == 0) {
            return amount;
        }
        return (amount * supply) / underlyingBalance();
    }

    function _calcAmountToSwap(
        uint256 amount,
        int24 lowerTick,
        int24 upperTick,
        int24 _currentTick,
        uint8 token0Decimal,
        uint8 token1Decimal
    )
        internal
        view
        returns (uint256)
    {
        if (_currentTick > upperTick) {
            return isToken0 ? amount : 0;
        }
        if (_currentTick < lowerTick) {
            return isToken0 ? 0 : amount;
        }

        bool _isToken0 = isToken0; // gas saving
        uint256 token0InToken1 =
            _currentTick.getQuoteAtTick(uint128(10 ** token0Decimal), address(token0), address(token1));

        uint256 _amount = _isToken0 ? token0InToken1 * amount / 10 ** token0Decimal : amount;
        uint128 liq = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(_currentTick), 10 ** token1Decimal
        );
        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(_currentTick), TickMath.getSqrtRatioAtTick(upperTick), liq
        );
        uint256 amount0inToken1 = amount0 * token0InToken1 / 10 ** token0Decimal;
        uint256 token1InToken0;
        if (_isToken0) {
            token1InToken0 = _currentTick.getQuoteAtTick(uint128(10 ** token1Decimal), address(token1), address(token0));
        }
        return _isToken0
            ? (_amount * 10 ** token1Decimal / (amount0inToken1 + 10 ** token1Decimal)) * token1InToken0
                / 10 ** token1Decimal
            : _amount - (_amount * 10 ** token1Decimal / (amount0inToken1 + 10 ** token1Decimal));
    }

    /// @notice Get the liquidity amount for given liquidity tokens
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param shares Shares of position
    /// @return The amount of liquidity toekn for shares
    function _liquidityForShares(int24 tickLower, int24 tickUpper, uint256 shares) internal view returns (uint128) {
        (uint128 position,,) = _position(tickLower, tickUpper);
        return _uint128Safe(uint256(position) * (shares) / (totalSupply()));
    }

    function _uint128Safe(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
    }

    function _swapTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool fromToken0
    )
        internal
        returns (uint256 receivedAmount)
    {
        fromToken0
            ? token0.safeApprove(address(swapRouter), amountIn)
            : token1.safeApprove(address(swapRouter), amountIn);
        bytes memory path = abi.encodePacked(
            fromToken0 ? address(token0) : address(token1), poolFee, fromToken0 ? address(token1) : address(token0)
        );

        receivedAmount = swapRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin
            })
        );
    }
}
