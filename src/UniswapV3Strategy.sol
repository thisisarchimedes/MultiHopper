// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19;

import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "univ3-periphery/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "univ3-periphery/libraries/OracleLibrary.sol";
import "univ3-periphery/interfaces/ISwapRouter.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ERC4626UpgradeableModified } from "src/ERC4626UpgradeableModified.sol";
import { IERC20Upgradeable } from "openzeppelin-contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract UniswapV3Strategy is Initializable, IUniswapV3MintCallback, ERC4626UpgradeableModified, OwnableUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using OracleLibrary for int24;

    address constant UNISWAP_ROUTER_ADDRESS = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    IUniswapV3Pool public pool;
    bool isValueTokenToken0;
    ISwapRouter public swapRouter;

    int24 public lowerTick;
    int24 public upperTick;
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

    event DoHardWork(uint256 amount0Collected, uint256 amount1Collected, uint256 amount0Fee, uint256 amount1Fee);
    event Rebalance(
        int24 oldLowerTick, int24 oldUpperTick, int24 newLowerTick, int24 newUpperTick, uint256 amount0, uint256 amount1
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IUniswapV3Pool _pool,
        int24 _lowerTick,
        int24 _upperTick,
        address _stakingToken,
        address _feeRecipient
    )
        external
        initializer
    {
        __ERC4626_init(IERC20Upgradeable(_stakingToken));
        __Ownable_init();
        __ERC20_init_unchained(string(abi.encodePacked("Univ3 strategy")), string(abi.encodePacked("PSPUNIV3")));
        pool = _pool;
        token0 = IERC20Metadata(pool.token0());
        token1 = IERC20Metadata(pool.token1());
        if (address(token0) != _stakingToken && address(token1) != _stakingToken) {
            revert("UniswapV3Adapter: staking token should be token0 or token1"); // TODO change to custom error message
        }
        isValueTokenToken0 = address(token0) == _stakingToken ? true : false;
        lowerTick = _lowerTick;
        upperTick = _upperTick;
        swapRouter = ISwapRouter(UNISWAP_ROUTER_ADDRESS);
        poolFee = pool.fee();
        feeRecipient = _feeRecipient;
        fee = 1000; // 10% protocol fee (out of profits)
        acceptedSlippage = 9950; // 0.5% slippage
    }

    /**
     * @dev Deposits a specified amount of tokens to the contract.
     * @param amount The amount of tokens to deposit.
     * @param receiver The address of the receiver of the deposited tokens.
     */
    function deposit(uint256 amount, address receiver) public override returns (uint256 shares) {
        // local cache for gas saving
        (bool _isValueTokenToken0, int24 _lowerTick, int24 _upperTick) = (isValueTokenToken0, lowerTick, upperTick);

        _collectFees(_lowerTick, _upperTick);

        shares = super.deposit(amount, receiver);

        _swapValueTokenToProportionOfRiskAndValueTokens(amount, _isValueTokenToken0, _lowerTick, _upperTick);

        _depositTokensToUniPool(_lowerTick, _upperTick);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minimumReceive
    )
        public
        override
        returns (uint256)
    {
        if (shares > maxRedeem(owner)) {
            revert RedeemExceedsMax();
        }
        (int24 _lowerTick, int24 _upperTick, bool _isValueTokenToken0) = (lowerTick, upperTick, isValueTokenToken0);
        _collectFees(_lowerTick, _upperTick);

        uint256 assets = _calcAssetsAndWithdrawLiquidity(_lowerTick, _upperTick, shares, _isValueTokenToken0);
        if (assets < minimumReceive) revert NotEnoughToken();

        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 minimumReceive
    )
        public
        override
        returns (uint256 shares)
    {
        if (assets > maxWithdraw(owner)) {
            revert WithdrawExceedsMax();
        }
        (int24 _lowerTick, int24 _upperTick, bool _isValueTokenToken0) = (lowerTick, upperTick, isValueTokenToken0);
        _collectFees(_lowerTick, _upperTick);
        shares = previewWithdraw(assets);
        assets = _calcAssetsAndWithdrawLiquidity(_lowerTick, _upperTick, shares, _isValueTokenToken0);
        if (assets < minimumReceive) revert NotEnoughToken();
        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @notice Fetch all the underlying balances including this contract
     */
    function totalAssets() public view override returns (uint256) {
        return _underlyingBalance(isValueTokenToken0);
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
        (uint128 positionLiquidity, uint128 tokensOwed0, uint128 tokensOwed1) = _position(lowerTick, upperTick);
        (uint256 _amount0, uint256 _amount1) = _amountsForLiquidity(lowerTick, upperTick, positionLiquidity);
        amount0 = uint128(_amount0) + (tokensOwed0);
        amount1 = uint128(_amount1) + (tokensOwed1);
        liquidity = positionLiquidity;
    }

    /// @notice Compound pending fees
    function doHardWork() external onlyOwner {
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;
        (, uint256 amount0Collected, uint256 amount1Collected, uint256 amount0Fee, uint256 amount1Fee) =
            _collectFees(_lowerTick, _upperTick);

        uint128 liquidity = _liquidityForAmounts(
            _lowerTick, _upperTick, token0.balanceOf(address(this)), token1.balanceOf(address(this))
        );
        (uint256 min0Amount, uint256 min1Amount) = _amountsForLiquidity(_lowerTick, _upperTick, liquidity);
        _mintLiquidity(_lowerTick, _upperTick, liquidity, address(this), min0Amount, min1Amount);
        emit DoHardWork(amount0Collected, amount1Collected, amount0Fee, amount1Fee);
    }

    function rebalance(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 amount0OutMin,
        uint256 amount1OutMin
    )
        external
        onlyOwner
    {
        int24 tickSpacing = pool.tickSpacing();
        if (_lowerTick >= _upperTick) revert InvalidRange();
        if (_lowerTick % tickSpacing != 0 || _upperTick % tickSpacing != 0) revert InvalidRange();
        int24 _currentlowerTick = lowerTick;
        int24 _currentupperTick = upperTick;
        _collectFees(_currentlowerTick, _currentupperTick);
        (uint128 liquidity,,) = _position(_currentlowerTick, _currentupperTick);
        _burnLiquidity(
            _currentlowerTick, _currentupperTick, liquidity, address(this), true, amount0OutMin, amount1OutMin
        );
        lowerTick = _lowerTick;
        upperTick = _upperTick;

        uint128 newLiquidity = _liquidityForAmounts(
            _lowerTick, _upperTick, token0.balanceOf(address(this)), token1.balanceOf(address(this))
        );
        (uint256 min0Amount, uint256 min1Amount) = _amountsForLiquidity(_lowerTick, _upperTick, newLiquidity);
        (uint256 amount0Used, uint256 amount1Used) =
            _mintLiquidity(_lowerTick, _upperTick, newLiquidity, address(this), min0Amount, min1Amount);
        emit Rebalance(_currentlowerTick, _currentupperTick, _lowerTick, _upperTick, amount0Used, amount1Used);
    }

    function underlyingBalance() external view returns (uint256) {
        return _underlyingBalance(isValueTokenToken0);
    }
    /// INTERNAL FUNCTIONS

    function _underlyingBalance(bool _isToken0) internal view returns (uint256) {
        int24 tick = currentTick();
        (, uint128 amount0, uint128 amount1) = getPosition();
        uint128 curValBal =
            _isToken0 ? uint128(token1.balanceOf(address(this))) : uint128(token0.balanceOf(address(this)));
        uint256 amount = _isToken0
            ? tick.getQuoteAtTick(amount1 + curValBal, address(token1), address(token0))
            : tick.getQuoteAtTick(amount0 + curValBal, address(token0), address(token1));
        uint256 curUnderlyingBal = _isToken0 ? token0.balanceOf(address(this)) : token1.balanceOf(address(this));
        return _isToken0 ? amount0 + amount + curUnderlyingBal : amount1 + amount + curUnderlyingBal;
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

    function _collectFees(
        int24 tickLower,
        int24 tickUpper
    )
        internal
        returns (uint128 liquidity, uint256 owed0, uint256 owed1, uint256 feeAmount0, uint256 feeAmount1)
    {
        (liquidity,,) = _position(tickLower, tickUpper);
        if (liquidity > 0) {
            pool.burn(tickLower, tickUpper, 0);
            (owed0, owed1) = pool.collect(address(this), tickLower, tickUpper, type(uint128).max, type(uint128).max);
            if (owed0 > 0) {
                feeAmount0 = (owed0) * fee / BASE;
                token0.safeTransfer(feeRecipient, feeAmount0);
            }
            if (owed1 > 0) {
                feeAmount1 = (owed1) * fee / BASE;
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

    function _calcAssetsAndWithdrawLiquidity(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _shares,
        bool _isValueTokenToken0
    )
        internal
        returns (uint256 totalAmountToSend)
    {
        uint256 token0BalBefore = token0.balanceOf(address(this));
        uint256 token1BalBefore = token1.balanceOf(address(this));
        uint256 token0FromBal = token0BalBefore * _shares / totalSupply();
        uint256 token1FromBal = token1BalBefore * _shares / totalSupply();
        uint128 liqShares = _liquidityForShares(_lowerTick, _upperTick, _shares);

        _burnLiquidity(_lowerTick, _upperTick, liqShares, address(this), true, 0, 0);

        uint256 balance0ToSwap = token0.balanceOf(address(this)) - token0BalBefore + token0FromBal;
        uint256 balance1ToSwap = token1.balanceOf(address(this)) - token1BalBefore + token1FromBal;

        // we swapped risk token to value token, now we add the newly recieved value token and the value token we
        // already had
        if (_isValueTokenToken0) {
            uint256 receivedAmount = _swapTokens(balance1ToSwap, 0, !_isValueTokenToken0);
            totalAmountToSend = receivedAmount + balance0ToSwap;
        } else {
            uint256 receivedAmount = _swapTokens(balance0ToSwap, 0, !_isValueTokenToken0);
            totalAmountToSend = receivedAmount + balance1ToSwap;
        }
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

    function _calcAmountToSwap(
        uint256 amount,
        int24 _lowerTick,
        int24 _upperTick,
        int24 _currentTick,
        uint8 token0Decimal,
        uint8 token1Decimal
    )
        internal
        view
        returns (uint256)
    {
        if (_currentTick > _upperTick) {
            return isValueTokenToken0 ? amount : 0;
        }
        if (_currentTick < _lowerTick) {
            return isValueTokenToken0 ? 0 : amount;
        }

        bool _isToken0 = isValueTokenToken0; // gas saving
        uint256 token0InToken1 =
            _currentTick.getQuoteAtTick(uint128(10 ** token0Decimal), address(token0), address(token1));

        uint256 _amount = _isToken0 ? token0InToken1 * amount / 10 ** token0Decimal : amount;
        uint128 liq = LiquidityAmounts.getLiquidityForAmount1(
            TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(_currentTick), 10 ** token1Decimal
        );
        uint256 amount0 = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(_currentTick), TickMath.getSqrtRatioAtTick(_upperTick), liq
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
        returns (uint256 amount0, uint256 amount1)
    {
        if (liquidity > 0) {
            mintCalled = true;
            (amount0, amount1) = pool.mint(address(this), tickLower, tickUpper, liquidity, abi.encode(payer));
            if (amount0 < amount0Min || amount1 < amount1Min) revert NotEnoughTokenUsed();
        }
    }

    function _calcUserDepositAfterSwap(
        uint256 amount,
        bool _isToken0,
        uint256 amountToSwap,
        uint256 token0BalBefore,
        uint256 token1BalBefore
    )
        internal
        view
        returns (uint256 token0BalAfter, uint256 token1BalAfter)
    {
        if (_isToken0) {
            token0BalAfter = amount - amountToSwap;
            token1BalAfter = token1.balanceOf(address(this)) - token1BalBefore;
        } else {
            token0BalAfter = token0.balanceOf(address(this)) - token0BalBefore;
            token1BalAfter = amount - amountToSwap;
        }
    }

    function _transferTokensFromUser(bool _isValueTokenToken0, uint256 _amount) internal {
        if (_isValueTokenToken0) {
            token0.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            token1.safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    function _transferTokensToUser(bool _isValueTokenToken0, uint256 _amount, address _receiver) internal {
        if (_isValueTokenToken0) {
            token0.safeTransfer(_receiver, _amount);
        } else {
            token1.safeTransfer(_receiver, _amount);
        }
    }

    function _swapValueTokenToProportionOfRiskAndValueTokens(
        uint256 _amount,
        bool _isValueTokenToken0,
        int24 _lowerTick,
        int24 _upperTick
    )
        internal
    {
        uint256 amountToSwap =
            _calcAmountToSwap(_amount, _lowerTick, _upperTick, currentTick(), token0.decimals(), token1.decimals());
        uint256 token0Bal = token0.balanceOf(address(this));
        uint256 token1Bal = token1.balanceOf(address(this));
        if (amountToSwap > 0) {
            _swapTokens(amountToSwap, 0, _isValueTokenToken0);
            (token0Bal, token1Bal) =
                _calcUserDepositAfterSwap(_amount, _isValueTokenToken0, amountToSwap, token0Bal, token1Bal);
            _checkReceivedAmount(
                _amount,
                _isValueTokenToken0 ? token0Bal : token1Bal,
                _isValueTokenToken0 ? token1Bal : token0Bal,
                _isValueTokenToken0
            );
        }
    }

    function _depositTokensToUniPool(int24 _lowerTick, int24 _upperTick) internal {
        uint128 liquidity = _liquidityForAmounts(
            _lowerTick, _upperTick, token0.balanceOf(address(this)), token1.balanceOf(address(this))
        );
        (uint256 min0Amount, uint256 min1Amount) = _amountsForLiquidity(_lowerTick, _upperTick, liquidity);
        _mintLiquidity(_lowerTick, _upperTick, liquidity, address(this), min0Amount, min1Amount);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function setAcceptedSlippage(uint256 _acceptedSlippage) external onlyOwner {
        acceptedSlippage = _acceptedSlippage;
    }
}
