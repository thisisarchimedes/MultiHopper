// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { IPoolWithEth, ICurveBasePool } from "../interfaces/ICurvePool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MultiPoolStrategy } from "../MultiPoolStrategy.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";

contract FlashLoanAttackTest {
    address public underlyingToken;
    address public attackToken;
    address public multiPoolStrategy;
    address public curvePool;
    int128 public underlyingTokenIndex;
    int128 public attackTokenIndex;

    constructor(
        address _underlyingToken,
        address _attackToken,
        address _multiPoolStrategy,
        address _curvePool,
        int128 _underlyingTokenIndex,
        int128 _attackTokenIndex
    ) {
        underlyingToken = _underlyingToken;
        multiPoolStrategy = _multiPoolStrategy;
        curvePool = _curvePool;
        underlyingTokenIndex = _underlyingTokenIndex;
        attackTokenIndex = _attackTokenIndex;
        attackToken = _attackToken;
    }

    function attack(uint256 _depositAmount, uint256 _attackAmount) external {
        IERC20(attackToken).approve(curvePool, _attackAmount);
        /// destroy ratio in curve pool
        IPoolWithEth(curvePool).exchange{ value: 0 }(attackTokenIndex, underlyingTokenIndex, _attackAmount, 0);
        /// deposit into multi pool strategy
        IERC20(underlyingToken).approve(multiPoolStrategy, _depositAmount);
        MultiPoolStrategy(multiPoolStrategy).deposit(_depositAmount, address(this));
        /// swap assets back to attack token
        uint256 ethBal = address(this).balance;
        IPoolWithEth(curvePool).exchange{ value: ethBal }(underlyingTokenIndex, attackTokenIndex, ethBal, 0);
    }

    function destroyRatio(uint256 _attackAmount) external {
        IERC20(attackToken).approve(curvePool, _attackAmount);
        /// destroy ratio in curve pool
        IPoolWithEth(curvePool).exchange{ value: 0 }(attackTokenIndex, underlyingTokenIndex, _attackAmount, 0);
    }

    function fixRatio() external {
        uint256 ethBal = address(this).balance;
        IPoolWithEth(curvePool).exchange{ value: ethBal }(underlyingTokenIndex, attackTokenIndex, ethBal, 0);
    }

    receive() external payable { }
}
