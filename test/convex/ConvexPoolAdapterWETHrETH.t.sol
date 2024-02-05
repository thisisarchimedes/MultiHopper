// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19.0;

import { ConvexPoolAdapterBaseTest } from "test/templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterWETHrETHGenericTest is ConvexPoolAdapterBaseTest {
    constructor() {
        UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0xF9440930043eb3997fc70e1339dBb11F341de7A8;
        CONVEX_PID = 35;

        SALT = "D231003";
        STRATEGY_NAME = "rETH Guard";
        TOKEN_NAME = "psp.WETH:rETH";

        USE_ETH = true;
        CURVE_POOL_TOKEN_INDEX = 0;
        IS_INDEX_UINT = false;
        POOL_TOKEN_LENGTH = 2;
        ZAPPER = address(0);

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
