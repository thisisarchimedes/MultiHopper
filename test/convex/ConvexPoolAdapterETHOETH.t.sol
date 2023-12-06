// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ConvexPoolAdapterBaseTest } from "./../templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterETHOETHGenericTest is ConvexPoolAdapterBaseTest {
    constructor() public {
        UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0x94B17476A93b3262d87B9a326965D1E91f9c13E7;
        CONVEX_PID = 174;

        SALT = "A231013";
        STRATEGY_NAME = "OETH Guard";
        TOKEN_NAME = "psp.ETH:OETH";

        USE_ETH = true;
        CURVE_POOL_TOKEN_INDEX = 0;
        IS_INDEX_UINT = false;
        POOL_TOKEN_LENGTH = 2;
        ZAPPER = address(0);

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
