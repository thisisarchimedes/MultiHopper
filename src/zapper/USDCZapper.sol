// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19;

import { IZapper } from "../interfaces/IZapper.sol";

contract USDCZapper is IZapper {
    function deposit(
        uint256 amount,
        address token,
        uint256 minAmount,
        address receiver,
        address strategyAddress
    )
        external
        override
        returns (uint256 shares)
    { }

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

    function strategyUsesUnderlyingAsset(address strategyAddress) external view override returns (bool) { }
}
