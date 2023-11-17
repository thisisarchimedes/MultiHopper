// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ConvexPoolAdapterBaseTest } from "./../templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterETHETHPlusGenericTest is ConvexPoolAdapterBaseTest {

    constructor() public {

        UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0x7fb53345f1B21aB5d9510ADB38F7d3590BE6364b;
        CONVEX_PID = 185; 

        SALT = "D231003";
        STRATEGY_NAME = "ETH+ Guard"; 
        TOKEN_NAME = "psp.ETH:ETH+";
       
        USE_ETH = false;
        CURVE_POOL_TOKEN_INDEX = 1;
        IS_INDEX_UINT = true;
        POOL_TOKEN_LENGTH = 2;
        ZAPPER = address(0);
    
        DEFAULT_FORK_BLOCK_NUMBER = 18_593_510;

    }
    
    
}

