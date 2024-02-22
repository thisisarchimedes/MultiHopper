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
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract UniswapV3Adapter is Initializable, IUniswapV3MintCallback, ERC20Upgradeable, OwnableUpgradeable {
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
    uint256 constant BASE = 10_000;
    uint256 public acceptedSlippage;
    uint24 poolFee;

    address public feeRecipient;
    uint256 public fee;

    error NotEnoughToken();
    error CallerNotPool();
    error NotOnMinting();
    error NotEnoughTokenUsed();
    error InvalidRange();

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function initialize(
        IUniswapV3Pool _pool,
        int24 _limitLower,
        int24 _limitUpper,
        bool _isToken0,
        address _feeRecipient
    )
        external
        initializer
    {
        __ERC20_init("UniswapV3Adapter", "UVA");
        __Ownable_init();
        pool = _pool;
        token0 = IERC20Metadata(pool.token0());
        token1 = IERC20Metadata(pool.token1());
        limitLower = _limitLower;
        limitUpper = _limitUpper;
        isToken0 = _isToken0;
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        poolFee = pool.fee();
        feeRecipient = _feeRecipient;
        fee = 1500;
        acceptedSlippage = 9950;
    }

    function deposit(uint256 amount, address receiver) external {
        bool _isToken0 = isToken0; // gas saving
        int24 _limitLower = limitLower;
        int24 _limitUpper = limitUpper;
        uint256 _amount = amount;
        //calculate shares
        uint256 shares = _calcShares(amount);
        _collectFees(_limitLower, _limitUpper);
        _isToken0
            ? token0.safeTransferFrom(msg.sender, address(this), _amount)
            : token1.safeTransferFrom(msg.sender, address(this), _amount);
        //swap logic
        uint256 amountToSwap =
            _calcAmountToSwap(_amount, _limitLower, _limitUpper, currentTick(), token0.decimals(), token1.decimals());
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));
        if (amountToSwap > 0) {
            _swapTokens(amountToSwap, 0, _isToken0);
        }

        uint256 token0BalAfter = amountToSwap > 0 && amountToSwap != _amount
            ? _isToken0 ? token0Before - amountToSwap : token0.balanceOf(address(this)) - token0Before
            : token0.balanceOf(address(this));
        uint256 token1BalAfter = amountToSwap > 0 && amountToSwap != _amount
            ? _isToken0 ? token1.balanceOf(address(this)) - token1Before : token1Before - amountToSwap
            : token1.balanceOf(address(this));
        _checkReceivedAmount(
            _amount, _isToken0 ? token0BalAfter : token1BalAfter, _isToken0 ? token1BalAfter : token0BalAfter, _isToken0
        );
        uint128 liquidity = _liquidityForAmounts(_limitLower, _limitUpper, token0BalAfter, token1BalAfter);
        (uint256 min0Amount, uint256 min1Amount) = _amountsForLiquidity(_limitLower, _limitUpper, liquidity);
        _mintLiquidity(_limitLower, _limitUpper, liquidity, address(this), min0Amount, min1Amount);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, _amount, shares);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner, // TODO implement logic around that
        uint256 minimumReceive
    )
        external
        returns (uint256)
    {
        (int24 _limitLower, int24 _limitUpper, bool _isToken0) = (limitLower, limitUpper, isToken0);
        _collectFees(_limitLower, _limitUpper);
        uint256 totalAmountToSend = _calcAssetsAndBurnLiquidity(_limitLower, _limitUpper, shares, _isToken0);
        _burn(msg.sender, shares);
        if (totalAmountToSend < minimumReceive) revert NotEnoughToken();
        _isToken0 ? token0.safeTransfer(receiver, totalAmountToSend) : token1.safeTransfer(receiver, totalAmountToSend);
        emit Withdraw(msg.sender, receiver, owner, totalAmountToSend, shares);
        return totalAmountToSend;
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

    /// @notice Callback function of uniswapV3Pool mint
    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external override {
        if (msg.sender != address(pool)) revert CallerNotPool();
        if (!mintCalled) revert NotOnMinting();
        mintCalled = false;
        if (amount0 > 0) token0.safeTransfer(msg.sender, amount0);
        if (amount1 > 0) token1.safeTransfer(msg.sender, amount1);
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

    /// @notice Compound pending fees
    function doHardWork() external onlyOwner {
        int24 _limitLower = limitLower;
        int24 _limitUpper = limitUpper;
        _collectFees(_limitLower, _limitUpper);

        uint128 liquidity = _liquidityForAmounts(
            _limitLower, _limitUpper, token0.balanceOf(address(this)), token1.balanceOf(address(this))
        );
        (uint256 min0Amount, uint256 min1Amount) = _amountsForLiquidity(_limitLower, _limitUpper, liquidity);
        _mintLiquidity(_limitLower, _limitUpper, liquidity, address(this), min0Amount, min1Amount);
        // TODO add event
    }

    function rebalance(
        int24 _limitLower,
        int24 _limitUpper,
        uint256 amount0OutMin,
        uint256 amount1OutMin
    )
        external
        onlyOwner
    {
        int24 tickSpacing = pool.tickSpacing();
        // _limitLower = _limitLower / tickSpacing * tickSpacing;
        // _limitUpper = _limitUpper / tickSpacing * tickSpacing;
        if (_limitLower >= _limitUpper) revert InvalidRange();
        if (_limitLower % tickSpacing != 0 || _limitUpper % tickSpacing != 0) revert InvalidRange();
        int24 _currentLimitLower = limitLower;
        int24 _currentLimitUpper = limitUpper;
        _collectFees(_currentLimitLower, _currentLimitUpper);
        (uint128 liquidity,,) = _position(_currentLimitLower, _currentLimitUpper);
        _burnLiquidity(
            _currentLimitLower, _currentLimitUpper, liquidity, address(this), true, amount0OutMin, amount1OutMin
        );
        limitLower = _limitLower;
        limitUpper = _limitUpper;

        uint128 newLiquidity = _liquidityForAmounts(
            _limitLower, _limitUpper, token0.balanceOf(address(this)), token1.balanceOf(address(this))
        );
        (uint256 min0Amount, uint256 min1Amount) = _amountsForLiquidity(_limitLower, _limitUpper, newLiquidity);
        _mintLiquidity(_limitLower, _limitUpper, newLiquidity, address(this), min0Amount, min1Amount);
        // TODO add event
    }

    /// INTERNAL FUNCTIONS

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

    function _collectFees(int24 tickLower, int24 tickUpper) internal returns (uint128 liquidity) {
        (liquidity,,) = _position(tickLower, tickUpper);
        if (liquidity > 0) {
            pool.burn(tickLower, tickUpper, 0);
            (uint256 owed0, uint256 owed1) =
                pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
            if (owed0 > 0) {
                uint256 feeAmount0 = (owed0) * fee / BASE;
                token0.safeTransfer(feeRecipient, feeAmount0);
            }
            if (owed1 > 0) {
                uint256 feeAmount1 = (owed1) * fee / BASE;
                token1.safeTransfer(feeRecipient, feeAmount1);
            }
        }
    }

    function _checkReceivedAmount(
        uint256 initialAmount,
        uint256 currentUnderlyingAmount,
        uint256 receivedAmount,
        bool _isToken0
    )
        internal
        view
    {
        int24 _currentTick = currentTick();
        uint256 amountInOtherToken = _isToken0
            ? _currentTick.getQuoteAtTick(uint128(receivedAmount), address(token1), address(token0))
            : _currentTick.getQuoteAtTick(uint128(receivedAmount), address(token0), address(token1));
        uint256 acceptableAmount = initialAmount * acceptedSlippage / BASE;
        if (currentUnderlyingAmount + amountInOtherToken < acceptableAmount) revert NotEnoughToken();
    }

    function _calcAssetsAndBurnLiquidity(
        int24 _limitLower,
        int24 _limitUpper,
        uint256 _shares,
        bool _isToken0
    )
        internal
        returns (uint256 totalAmountToSend)
    {
        uint256 token0BalBefore = token0.balanceOf(address(this));
        uint256 token1BalBefore = token1.balanceOf(address(this));
        uint256 token0FromBal = token0BalBefore * _shares / totalSupply();
        uint256 token1FromBal = token1BalBefore * _shares / totalSupply();
        uint128 liqShares = _liquidityForShares(_limitLower, _limitUpper, _shares);

        _burnLiquidity(_limitLower, _limitUpper, liqShares, address(this), true, 0, 0);
        uint256 token0After = token0.balanceOf(address(this));
        uint256 token1After = token1.balanceOf(address(this));
        uint256 receivedAmount = _swapTokens(
            _isToken0 ? token1After - token1BalBefore + token1FromBal : token0After - token0BalBefore + token0FromBal,
            0,
            !_isToken0
        );
        totalAmountToSend = receivedAmount
            + (isToken0 ? token0After - token0BalBefore + token0FromBal : token1After - token1BalBefore + token1FromBal);
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

    function _uint128Safe(uint256 x) internal pure returns (uint128) {
        assert(x <= type(uint128).max);
        return uint128(x);
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
            if (amount0 < amount0Min || amount1 < amount1Min) revert NotEnoughTokenUsed();
        }
    }
}
