// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

/**
 * @title Deploy
 *
 * @dev A contract for deploying the MultiPoolStrategyFactory contract
 * @notice we do this in its own script because of the size of the contract and the gas spent
 *
 */
contract DeployFactory is BaseScript {
    address MONITOR = address(0); // TODO : set monitor address before deploy

    function run() public broadcaster returns (MultiPoolStrategyFactory factory) {
        require(MONITOR != address(0), "Deploy: monitor address not set");

        factory = new MultiPoolStrategyFactory(MONITOR);
    }
}
