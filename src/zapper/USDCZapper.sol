// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19;

import { IZapper } from "../interfaces/IZapper.sol";
import { ICurveBasePool } from "../interfaces/ICurvePool.sol";
import { MultiPoolStrategy as IMultiPoolStrategy } from "../MultiPoolStrategy.sol";
import { console2 } from "forge-std/console2.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/utils/structs/EnumerableSet.sol";

contract USDCZapper is ReentrancyGuard, IZapper {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct AssetInfo {
        address pool;
        int128 index;
        bool isLpToken;
    }

    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI

    address constant CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490; // CRV
    address constant CRVFRAX = 0x3175Df0976dFA876431C2E9eE6Bc45b65d3473CC; // CRVFRAX

    int128 constant UNDERLYING_ASSET_INDEX = 1; // USDC index in the pool

    EnumerableSet.AddressSet private _supportedAssets;
    mapping(address => AssetInfo) private _supportedAssetsInfo;

    constructor(address[] memory assets, address[] memory pools, int128[] memory indexes, bool[] memory isLpTokens) {
        require(assets.length == pools.length && assets.length == indexes.length, "Arrays length mismatch");

        for (uint256 i = 0; i < assets.length; i++) {
            _supportedAssets.add(assets[i]);
            _supportedAssetsInfo[assets[i]] = AssetInfo(pools[i], indexes[i], isLpTokens[i]);
        }
    }

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
        uint256 underlyingAmount = assetInfo.isLpToken
            ? pool.remove_liquidity_one_coin(amount, assetInfo.index, minAmount)
            : pool.exchange(assetInfo.index, UNDERLYING_ASSET_INDEX, amount, minAmount);

        // we need to approve the strategy to spend underlying asset
        SafeERC20.safeApprove(IERC20(UNDERLYING_ASSET), strategyAddress, 0);
        SafeERC20.safeApprove(IERC20(UNDERLYING_ASSET), strategyAddress, underlyingAmount);

        // deposit
        shares = multipoolStrategy.deposit(underlyingAmount, address(this));

        // transfer shares to receiver
        SafeERC20.safeTransfer(IERC20(strategyAddress), receiver, shares);

        return 0;
    }

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

    function strategyUsesUnderlyingAsset(address strategyAddress) public view override returns (bool) {
        IMultiPoolStrategy multipoolStrategy = IMultiPoolStrategy(strategyAddress);
        return multipoolStrategy.asset() == address(UNDERLYING_ASSET);
    }
}
