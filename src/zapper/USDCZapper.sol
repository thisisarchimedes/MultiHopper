// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19;

import { IZapper } from "../interfaces/IZapper.sol";
import { ICurveBasePool } from "../interfaces/ICurvePool.sol";
import { MultiPoolStrategy as IMultiPoolStrategy } from "../MultiPoolStrategy.sol";
import { console2 } from "forge-std/console2.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

contract USDCZapper is ReentrancyGuard, Ownable, IZapper {
    // Library for working with the _supportedAssets AddressSet.
    // Elements are added, removed, and checked for existence in constant time (O(1)).
    using EnumerableSet for EnumerableSet.AddressSet;

    struct AssetInfo {
        address pool;
        int128 index;
        bool isLpToken;
    }

    address public constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX

    address public constant CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // CRV
    address public constant CRVFRAX = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC; // CRVFRAX

    address public constant CURVE_3POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7; // DAI+USDC+USDT
    address public constant CURVE_FRAXUSDC = 0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2; // FRAX+USDC

    int128 public constant UNDERLYING_ASSET_INDEX = 1; // USDC Index - for both 3Pool and FRAXUSDC
    int128 public constant DAI_INDEX = 0; // DAI Index - for 3Pool
    int128 public constant USDT_INDEX = 2; // USDT Index - for 3Pool
    int128 public constant FRAX_INDEX = 0; // FRAX Index - for FRAXUSDC

    // Collection of unique addresses representing supported assets
    EnumerableSet.AddressSet private _supportedAssets;
    mapping(address => AssetInfo) private _supportedAssetsInfo;

    constructor() {
        // add stablecoins
        _supportedAssets.add(USDT);
        _supportedAssets.add(DAI);
        _supportedAssets.add(FRAX);
        // add lp tokens
        _supportedAssets.add(CRV);
        _supportedAssets.add(CRVFRAX);

        _supportedAssetsInfo[USDT] = AssetInfo({pool: CURVE_3POOL, index: USDT_INDEX, isLpToken: false});
        _supportedAssetsInfo[DAI] = AssetInfo({pool: CURVE_3POOL, index: DAI_INDEX, isLpToken: false});
        _supportedAssetsInfo[FRAX] = AssetInfo({pool: CURVE_FRAXUSDC, index: FRAX_INDEX, isLpToken: false});
        // for lp tokens indexes are set as int128.max, as we don't need them
        _supportedAssetsInfo[CRV] = AssetInfo({pool: CURVE_3POOL, index: type(int128).max, isLpToken: true});
        _supportedAssetsInfo[CRVFRAX] = AssetInfo({pool: CURVE_FRAXUSDC, index: type(int128).max, isLpToken: true});
    }

    /**
     * @inheritdoc IZapper
     */
    function deposit(
        uint256 amount,
        address token,
        uint256 minAmount,
        address receiver,
        address strategyAddress
    )
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        // check if the reciever is not zero address
        require(receiver != address(0), "Receiver is zero address");

        // check if the correct strategy provided and it matches underlying asset
        if (!strategyUsesUnderlyingAsset(strategyAddress)) revert StrategyAssetDoesNotMatchUnderlyingAsset();
        // check if the amount is not zero
        if (amount == 0) revert EmptyInput();

        // check if the strategy is not paused
        IMultiPoolStrategy multipoolStrategy = IMultiPoolStrategy(strategyAddress);
        if (multipoolStrategy.paused()) revert StrategyPaused();

        // check if the provided token is in the assets array, if false - revert
        if (!_supportedAssets.contains(token)) revert InvalidAsset();

        // find the pool regarding the provided token, if pool not found - revert
        AssetInfo storage assetInfo = _supportedAssetsInfo[token];
        if (assetInfo.pool == address(0)) revert PoolDoesNotExist();

        // transfer tokens to this contract
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
        // approve pool to spend tokens
        SafeERC20.safeIncreaseAllowance(IERC20(token), assetInfo.pool, amount);

        // make swap, approval must be given before calling this function
        // minAmount is checked inside pool so not necessary to check it here
        ICurveBasePool pool = ICurveBasePool(assetInfo.pool);

        // TODO: I'd prefer to use address.call here, as some pool implementations return amount, some not.
        // If call eventually returns some data, we can use it in a upcoming calls, if not we need to call UNDERLYING_ASSET.balanceOf(address(this))
        uint256 balancePre = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

        assetInfo.isLpToken
            ? pool.remove_liquidity_one_coin(amount, assetInfo.index, minAmount)
            : pool.exchange(assetInfo.index, UNDERLYING_ASSET_INDEX, amount, minAmount);

        uint256 underlyingAmount = IERC20(UNDERLYING_ASSET).balanceOf(address(this)) - balancePre;

        // we need to approve the strategy to spend underlying asset
        SafeERC20.safeApprove(IERC20(UNDERLYING_ASSET), strategyAddress, 0);
        SafeERC20.safeApprove(IERC20(UNDERLYING_ASSET), strategyAddress, underlyingAmount);

        // deposit
        shares = multipoolStrategy.deposit(underlyingAmount, address(this));

        // transfer shares to receiver
        SafeERC20.safeTransfer(IERC20(strategyAddress), receiver, shares);

        return shares;
    }

    /**
     * @inheritdoc IZapper
     */
    function withdraw(
        uint256 amount,
        address withdrawToken,
        uint256 minWithdrawAmount,
        uint256 minSwapAmount,
        address receiver,
        address strategyAddress
    )
        external
        override
        returns (uint256 sharesBurnt)
    { }

    /**
     * @inheritdoc IZapper
     */
    function redeem(
        uint256 sharesAmount,
        uint256 minRedeemAmount,
        uint256 minSwapAmount,
        address receiver,
        address strategyAddress,
        address redeemToken
    )
        external
        override
        returns (uint256 amount)
    { }

    /**
     * @inheritdoc IZapper
     */
    function strategyUsesUnderlyingAsset(address strategyAddress) public view override returns (bool) {
        IMultiPoolStrategy multipoolStrategy = IMultiPoolStrategy(strategyAddress);
        return multipoolStrategy.asset() == address(UNDERLYING_ASSET);
    }
}
