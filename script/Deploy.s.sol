// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

contract Deploy is BaseScript {
    address MONITOR = address(0); // TODO : set monitor address before deploy

    function run() public broadcaster returns (MultiPoolStrategyFactory factory) {
        factory = new MultiPoolStrategyFactory(MONITOR);
    }
}
