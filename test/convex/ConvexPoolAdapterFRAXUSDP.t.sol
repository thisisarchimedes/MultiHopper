// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ConvexPoolAdapterBaseTest } from "./../templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterFRAXUSDPenericTest is ConvexPoolAdapterBaseTest {

    constructor() public {

        UNDERLYING_ASSET = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0xaE34574AC03A15cd58A92DC79De7B1A0800F1CE3;
        CONVEX_PID = 169; 

        SALT = "D231003";
        STRATEGY_NAME = "USDP Guard"; 
        TOKEN_NAME = "psp.FRAXBP:USDP";
       
        USE_ETH = false;
        CURVE_POOL_TOKEN_INDEX = 0;
        IS_INDEX_UINT = false;
        POOL_TOKEN_LENGTH = 2;
        ZAPPER = address(0);
    
          DEFAULT_FORK_BLOCK_NUMBER = 18_593_713;

    }
    
    
}

