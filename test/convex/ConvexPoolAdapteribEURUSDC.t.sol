// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ConvexPoolAdapterBaseTest } from "test/templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapteribEURUSDCGenericTest is ConvexPoolAdapterBaseTest {
    constructor() {
        UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0x1570af3dF649Fc74872c5B8F280A162a3bdD4EB6;
        CONVEX_PID = 86;

        SALT = "D231003";
        STRATEGY_NAME = "ibUSD Guard";
        TOKEN_NAME = "psp.ibEUR:USDC";

        USE_ETH = false;
        CURVE_POOL_TOKEN_INDEX = 1;
        IS_INDEX_UINT = true;
        POOL_TOKEN_LENGTH = 2;
        ZAPPER = address(0);

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
