// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ConvexPoolAdapterBaseTest } from "./../templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterDOLAFRAXBPGenericTest is ConvexPoolAdapterBaseTest {
    constructor() public {
        UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0xAF4264916B467e2c9C8aCF07Acc22b9EDdDaDF33;
        CONVEX_PID = 170;

        SALT = "D231003";
        STRATEGY_NAME = "COIL Guard";
        TOKEN_NAME = "psp.FRAXBP:COIL";

        USE_ETH = false;
        CURVE_POOL_TOKEN_INDEX = 2;
        IS_INDEX_UINT = true;
        POOL_TOKEN_LENGTH = 3;
        ZAPPER = address(0x5De4EF4879F4fe3bBADF2227D2aC5d0E2D76C895);

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
