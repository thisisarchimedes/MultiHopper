// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IZapper {
    error StrategyPaused();
    error StrategyAssetDoesNotMatchUnderlyingAsset();
    error EmptyInput();
    error WithdrawalAmountZero();
    error ZeroAddress();
    error InvalidAsset();
    error PoolDoesNotExist();

    /**
     * @dev Deposits asset into the MultiPoolStrategy contract.
     * @param amount The asset amount user wants to deposit.
     * @param token The deposited asset address (like: USDT address).
     * @param minAmount Minimum amount of underlying asset to receive after the swap of the provided asset.
     * @param receiver The address to receive the shares.
     * @param strategyAddress The address of the MultiPoolStrategy contract to deposit into.
     * @return shares The amount of shares received.
     */

    function deposit(
        uint256 amount,
        address token,
        uint256 minAmount,
        address receiver,
        address strategyAddress
    )
        external
        returns (uint256 shares);

    /**
     * @dev Withdraws deposited asset from the MultiPoolStrategy contract.
     * @param amount The amount to withdraw (in token user's choice - like: USDT).
     * @param withdrawToken The token address to withdraw (like: USDT address).
     * @param minWithdrawAmount Minimum amount of required asset (like: USDT) to recieve after withdraw.
     * @param minSwapAmount Minimum amount of required asset to receive after the swap of the underlying asset (if the strategy is using USDC as underlying, this min USDC we accept when withdrawing shares)
     * @param receiver The address to receive the withdrawn asset.
     * @param strategyAddress The address of the MultiPoolStrategy contract to withdraw from.
     * @return sharesBurnt The amount of shares burned.
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
        returns (uint256 sharesBurnt);
    /**
     * 1. User specifies how much USDT (param: amount) they want to get (from a USDC strategy)
     *         2. Withdraw estimates the amount of USDC we should ask from the strategy (preview_swap(USDT->USDC))
     *         3. Withdraw(USDC amount): take shares from user and withdraw USDC to zapper (param: minWithdrawAmount - might not be needed because we revert on minSwapAmount alter)
     *         4. Swap: USDC -> USDT (param: minSwapAmount) - Curve checks that
     *         5. Send USDT to user
     */

    /**
     * @dev Redeems asset from the MultiPoolStrategy contract.
     * @param sharesAmount The amount of shares to redeem.
     * @param minRedeemAmount Minimum amount of required asset to recieve after redeem.
     * @param minSwapAmount Minimum amount of required asset to receive after the swap of the underlying asset.
     * @param receiver The address to receive the redeemed asset.
     * @param strategyAddress The address of the MultiPoolStrategy contract to redeem from.
     * @param redeemToken The token address redeem.
     * @return amount The amount of shares burned.
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
        returns (uint256 amount);
    /**
     * 1. User sepcifies how many shares they want to redeem (param: sharesAmount)
     *     2. Call redeem on the strategy, swaping shares with USDC
     *     3. Swap USDC with USDT  (Curve reverts if we don't get at least minSwapAmount)
     *     4. Send USDT to user
     */

    /**
     * @dev Checks if the MultiPoolStrategy underlying asset matches Zapper underlying asset.
     * @param strategyAddress The address of the MultiPoolStrategy contract to check.
     * @return True if the underlying asset matches, false otherwise.
     */
    function strategyUsesUnderlyingAsset(address strategyAddress) external view returns (bool);
}
