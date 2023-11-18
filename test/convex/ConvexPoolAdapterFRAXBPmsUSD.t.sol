// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ConvexPoolAdapterBaseTest } from "./../templates/ConvexPoolAdapterBaseTest.t.sol";

contract ConvexPoolAdapterFRAXBMSUSDPGenericTest is ConvexPoolAdapterBaseTest {

    constructor() public {

        UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
        CURVE_POOL_ADDRESS = 0xc3b19502F8c02be75F3f77fd673503520DEB51dD;
        CONVEX_PID = 144; 

        SALT = "D231003";
        STRATEGY_NAME = "msUSD Guard"; 
        TOKEN_NAME = "psp.FRAXBP:msUSD";
       
        USE_ETH = false;
        CURVE_POOL_TOKEN_INDEX = 2;
        IS_INDEX_UINT = false;
        POOL_TOKEN_LENGTH = 3;
        ZAPPER = address(0x08780fb7E580e492c1935bEe4fA5920b94AA95Da);
    
          DEFAULT_FORK_BLOCK_NUMBER = 18_593_713;

    }
    
    
}


