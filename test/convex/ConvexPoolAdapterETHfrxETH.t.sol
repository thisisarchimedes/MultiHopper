// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19.0;

import { ConvexPoolAdapterBaseTest } from "test/templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterETHfrxETHGenericTest is ConvexPoolAdapterBaseTest {
    constructor() {
        UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
        CONVEX_PID = 128;

        SALT = "D231003";
        STRATEGY_NAME = "frxETH Guard";
        TOKEN_NAME = "psp.ETH:frxETH";

        USE_ETH = true;
        CURVE_POOL_TOKEN_INDEX = 0;
        IS_INDEX_UINT = false;
        POOL_TOKEN_LENGTH = 2;
        ZAPPER = address(0);

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
