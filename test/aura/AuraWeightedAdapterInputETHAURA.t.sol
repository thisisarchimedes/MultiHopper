// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity ^0.8.19.0;

import { AuraWeightedPoolAdapterBaseTest } from "../templates/AuraWeightedAdapterBaseTest.t.sol";

/// @title AuraWeightedPoolAdapterInputETHTest
/// @notice A contract for testing an ETH pegged Aura pool (WETH/rETH) with native ETH input from user using zapper
contract AuraWeightedPoolAdapterInputETHAURATest is AuraWeightedPoolAdapterBaseTest {
    constructor() {
        UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        AURA_BOOSTER = 0x1204f5060bE8b716F5A62b4Df4cE32acD01a69f5;
        BALANCER_WEIGHTED_POOL_ID = 0xcfca23ca9ca720b6e98e3eb9b6aa0ffc4a5c08b9000200000000000000000274;
        AURA_PID = 100;

        SALT = "G231003";
        STRATEGY_NAME = "Aura Guard";
        TOKEN_NAME = "psp.WETH:AURA";

        DEFAULT_FORK_BLOCK_NUMBER = 18_728_043;
    }
}
