// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19.0;

import { AuraAdapterBase } from "src/AuraAdapterBase.sol";
import { FixedPoint } from "src/utils/FixedPoint.sol";
import { Math } from "src/utils/Math.sol";
import { IBooster } from "src/interfaces/IBooster.sol";
import { IStablePool } from "src/interfaces/IStablepool.sol";
import { IBalancerVault } from "src/interfaces/IBalancerVault.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

contract AuraComposableStablePoolAdapter is AuraAdapterBase {
    using FixedPoint for uint256;

    uint256 internal constant _AMP_PRECISION = 1e3;

    error ApproveFailed();
    error BalanceDidntConverge();
    error StableInvariantDidntConverge();

    function underlyingBalance() public view override returns (uint256) {
        uint256 lpBal = auraRewardPool.balanceOf(address(this));
        if (lpBal == 0) {
            return 0;
        }
        // get pool balances
        (, uint256[] memory _balances,) = vault.getPoolTokens(poolId);
        // get scaling factors
        uint256[] memory scalingFactors = IStablePool(pool).getScalingFactors();
        // scale up the _balances
        for (uint256 i; i < _balances.length; i++) {
            _balances[i] = _balances[i] * scalingFactors[i] / 1e18;
        }
        // get normalized weights
        (uint256 amp,,) = IStablePool(pool).getAmplificationParameter();
        // get total supply
        uint256 lpTotalSupply = IStablePool(pool).getActualSupply();
        //get swap fee
        uint256 swapFeePercentage = IStablePool(pool).getSwapFeePercentage();
        uint256 poolTokenIndex = IStablePool(pool).getBptIndex();

        uint256[] memory _balancesWithoutBpt = _dropBptItem(_balances, poolTokenIndex);
        uint256 _tokenIndex = tokenIndex;
        if (tokenIndex > poolTokenIndex) {
            _tokenIndex = _tokenIndex - 1;
        }

        // get invariant
        uint256 currentInvariant = _calculateInvariant(amp, _balancesWithoutBpt);

        uint256 tokenOut = _calcTokenOutGivenExactBptIn(
            amp, _balancesWithoutBpt, _tokenIndex, lpBal, lpTotalSupply, currentInvariant, swapFeePercentage
        );
        uint256 scaleDownFactor = scalingFactors[tokenIndex] / 1e18;

        if (scaleDownFactor > 0) {
            tokenOut /= scaleDownFactor;
        }
        return tokenOut;
    }

    function deposit(uint256 _amount, uint256 _minReceiveAmount) external override onlyMultiPoolStrategy {
        if (_amount == 0) {
            storedUnderlyingBalance = underlyingBalance();
            return;
        }
        IBalancerVault.SingleSwap memory swap;
        swap.poolId = poolId;
        swap.kind = 0;
        swap.assetIn = address(underlyingToken);
        swap.assetOut = address(pool);
        swap.amount = _amount;
        swap.userData = "";
        IBalancerVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = address(this);
        funds.toInternalBalance = false;
        vault.swap(swap, funds, _minReceiveAmount, block.timestamp + 20);
        uint256 lpBal = IERC20(pool).balanceOf(address(this));
        IBooster(AURA_BOOSTER).deposit(auraPid, lpBal, true);
        storedUnderlyingBalance = underlyingBalance();
    }

    function withdraw(uint256 _amount, uint256 _minReceiveAmount) external override onlyMultiPoolStrategy {
        uint256 _underlyingBalance = underlyingBalance();
        auraRewardPool.withdrawAndUnwrap(_amount, false);
        IBalancerVault.SingleSwap memory swap;
        swap.poolId = poolId;
        swap.kind = 0;
        swap.assetIn = address(pool);
        swap.assetOut = address(underlyingToken);
        swap.amount = _amount;
        swap.userData = "";
        IBalancerVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = address(this);
        funds.toInternalBalance = false;

        if (!IERC20(pool).approve(address(vault), _amount)) revert ApproveFailed();

        vault.swap(swap, funds, _minReceiveAmount, block.timestamp + 20);
        uint256 underlyingBal = IERC20(underlyingToken).balanceOf(address(this));
        SafeERC20.safeTransfer(IERC20(underlyingToken), multiPoolStrategy, underlyingBal);
        uint256 lpBal = auraRewardPool.balanceOf(address(this));
        if (lpBal == 0) {
            storedUnderlyingBalance = 0;
        } else {
            uint256 healthyBalance = storedUnderlyingBalance - (storedUnderlyingBalance * healthFactor / 10_000);
            if (_underlyingBalance > healthyBalance) {
                storedUnderlyingBalance = _underlyingBalance - underlyingBal;
            } else {
                storedUnderlyingBalance -= underlyingBal;
            }
        }
    }

    function _calcTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    )
        internal
        pure
        returns (uint256)
    {
        // Token out, so we round down overall.

        uint256 newInvariant = bptTotalSupply.sub(bptAmountIn).divUp(bptTotalSupply).mulUp(currentInvariant);

        // Calculate amount out without fee
        uint256 newBalanceTokenIndex =
            _getTokenBalanceGivenInvariantAndAllOtherBalances(amp, balances, newInvariant, tokenIndex);
        uint256 amountOutWithoutFee = balances[tokenIndex].sub(newBalanceTokenIndex);

        // First calculate the sum of all token balances, which will be used to calculate
        // the current weight of each token
        uint256 sumBalances = 0;
        for (uint256 i = 0; i < balances.length; i++) {
            sumBalances = sumBalances.add(balances[i]);
        }

        // We can now compute how much excess balance is being withdrawn as a result of the virtual swaps, which result
        // in swap fees.
        uint256 currentWeight = balances[tokenIndex].divDown(sumBalances);
        uint256 taxablePercentage = currentWeight.complement();

        // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it
        // to 'token out'. This results in slightly larger price impact. Fees are rounded up.
        uint256 taxableAmount = amountOutWithoutFee.mulUp(taxablePercentage);
        uint256 nonTaxableAmount = amountOutWithoutFee.sub(taxableAmount);

        // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
        return nonTaxableAmount.add(taxableAmount.mulDown(FixedPoint.ONE - swapFeePercentage));
    }
    // This function calculates the balance of a given token (tokenIndex)
    // given all the other balances and the invariant

    function _getTokenBalanceGivenInvariantAndAllOtherBalances(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    )
        internal
        pure
        returns (uint256)
    {
        // Rounds result up overall

        uint256 ampTimesTotal = amplificationParameter * balances.length;
        uint256 sum = balances[0];
        uint256 pD = balances[0] * balances.length;
        for (uint256 j = 1; j < balances.length; j++) {
            pD = Math.divDown(Math.mul(Math.mul(pD, balances[j]), balances.length), invariant);
            sum = sum.add(balances[j]);
        }
        // No need to use safe math, based on the loop above `sum` is greater than or equal to `balances[tokenIndex]`
        sum = sum - balances[tokenIndex];

        uint256 inv2 = Math.mul(invariant, invariant);
        // We remove the balance from c by multiplying it
        uint256 c =
            Math.mul(Math.mul(Math.divUp(inv2, Math.mul(ampTimesTotal, pD)), _AMP_PRECISION), balances[tokenIndex]);
        uint256 b = sum.add(Math.mul(Math.divDown(invariant, ampTimesTotal), _AMP_PRECISION));

        // We iterate to find the balance
        uint256 prevTokenBalance = 0;
        // We multiply the first iteration outside the loop with the invariant to set the value of the
        // initial approximation.
        uint256 tokenBalance = Math.divUp(inv2.add(c), invariant.add(b));

        for (uint256 i = 0; i < 255; i++) {
            prevTokenBalance = tokenBalance;

            tokenBalance =
                Math.divUp(Math.mul(tokenBalance, tokenBalance).add(c), Math.mul(tokenBalance, 2).add(b).sub(invariant));

            if (tokenBalance > prevTokenBalance) {
                if (tokenBalance - prevTokenBalance <= 1) {
                    return tokenBalance;
                }
            } else if (prevTokenBalance - tokenBalance <= 1) {
                return tokenBalance;
            }
        }

        // STABLE_GET_BALANCE_DIDNT_CONVERGE
        revert BalanceDidntConverge();
    }

    function _calculateInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    )
        internal
        pure
        returns (uint256)
    {
        /**
         *
         *     // invariant                                                                                 //
         *     // D = invariant                                                  D^(n+1)                    //
         *     // A = amplification coefficient      A  n^n S + D = A D n^n + -----------                   //
         *     // S = sum of balances                                             n^n P                     //
         *     // P = product of balances                                                                   //
         *     // n = number of tokens                                                                      //
         *
         */

        // Always round down, to match Vyper's arithmetic (which always truncates).

        uint256 sum = 0; // S in the Curve version
        uint256 numTokens = balances.length;
        for (uint256 i = 0; i < numTokens; i++) {
            sum = sum.add(balances[i]);
        }
        if (sum == 0) {
            return 0;
        }

        uint256 prevInvariant; // Dprev in the Curve version
        uint256 invariant = sum; // D in the Curve version
        uint256 ampTimesTotal = amplificationParameter * numTokens; // Ann in the Curve version

        for (uint256 i = 0; i < 255; i++) {
            uint256 dP = invariant;

            for (uint256 j = 0; j < numTokens; j++) {
                // (dP * invariant) / (balances[j] * numTokens)
                dP = Math.divDown(Math.mul(dP, invariant), Math.mul(balances[j], numTokens));
            }

            prevInvariant = invariant;

            invariant = Math.divDown(
                Math.mul(
                    // (ampTimesTotal * sum) / AMP_PRECISION + dP * numTokens
                    (Math.divDown(Math.mul(ampTimesTotal, sum), _AMP_PRECISION).add(Math.mul(dP, numTokens))),
                    invariant
                ),
                // ((ampTimesTotal - _AMP_PRECISION) * invariant) / _AMP_PRECISION + (numTokens + 1) * dP
                (
                    Math.divDown(Math.mul((ampTimesTotal - _AMP_PRECISION), invariant), _AMP_PRECISION).add(
                        Math.mul((numTokens + 1), dP)
                    )
                )
            );

            if (invariant > prevInvariant) {
                if (invariant - prevInvariant <= 1) {
                    return invariant;
                }
            } else if (prevInvariant - invariant <= 1) {
                return invariant;
            }
        }

        revert StableInvariantDidntConverge();
    }
    /**
     * @dev Remove the item at `_bptIndex` from an arbitrary array (e.g., amountsIn).
     */

    function _dropBptItem(uint256[] memory amounts, uint256 bptIndex) internal pure returns (uint256[] memory) {
        uint256[] memory amountsWithoutBpt = new uint256[](amounts.length - 1);
        for (uint256 i = 0; i < amountsWithoutBpt.length; i++) {
            amountsWithoutBpt[i] = amounts[i < bptIndex ? i : i + 1];
        }

        return amountsWithoutBpt;
    }
}
