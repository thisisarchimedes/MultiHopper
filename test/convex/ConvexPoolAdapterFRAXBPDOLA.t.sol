// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19.0;

import { ConvexPoolAdapterBaseTest } from "test/templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterFRAXBPDOLAGenericTest is ConvexPoolAdapterBaseTest {
    constructor() {
        UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0xE57180685E3348589E9521aa53Af0BCD497E884d;
        CONVEX_PID = 115;

        SALT = "A231013";
        STRATEGY_NAME = "DOLA Guard";
        TOKEN_NAME = "psp.FRAXBP:DOLA";

        USE_ETH = false;
        CURVE_POOL_TOKEN_INDEX = 2;
        IS_INDEX_UINT = false;
        POOL_TOKEN_LENGTH = 3;
        ZAPPER = address(0x08780fb7E580e492c1935bEe4fA5920b94AA95Da);

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
