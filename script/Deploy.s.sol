// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

contract Deploy is BaseScript {
    address MONITOR = 0x026055f2d5e8b7047B438E6e9291bB39325D1d82; // TODO : set monitor address before deploy

    function run() public broadcaster returns (MultiPoolStrategyFactory factory) {
        require(MONITOR != address(0), "Deploy: monitor address not set");
        factory = new MultiPoolStrategyFactory(MONITOR);
    }
}
