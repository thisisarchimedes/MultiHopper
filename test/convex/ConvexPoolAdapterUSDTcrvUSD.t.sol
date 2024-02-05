// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19.0;

import { ConvexPoolAdapterBaseTest } from "test/templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterUSDTcrvUSDGenericTest is ConvexPoolAdapterBaseTest {
    constructor() {
        UNDERLYING_ASSET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0x390f3595bCa2Df7d23783dFd126427CCeb997BF4;
        CONVEX_PID = 179;

        SALT = "D231003";
        STRATEGY_NAME = "crvUSD Guard";
        TOKEN_NAME = "psp.USDT:crvUSD";

        USE_ETH = false;
        CURVE_POOL_TOKEN_INDEX = 0;
        IS_INDEX_UINT = false;
        POOL_TOKEN_LENGTH = 2;
        ZAPPER = address(0);

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
