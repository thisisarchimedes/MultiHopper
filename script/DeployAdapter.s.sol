// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "src/AuraWeightedPoolAdapter.sol";
import { AuraStablePoolAdapter } from "src/AuraStablePoolAdapter.sol";
import { AuraComposableStablePoolAdapter } from "src/AuraComposableStablePoolAdapter.sol";
import { console2 } from "forge-std/console2.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

/**
 * @title Deploy
 *
 * @dev A contract for deploying the Implementation contract of an adapter and then setting it in the factory
 * @notice use the corresponding adapter Contract you want to deploy and set
 *
 */
contract DeployFactory is BaseScript {
    address FACTORY_ADDRESS = address(0);
    // deploy

    function run() public broadcaster {
        require(FACTORY_ADDRESS != address(0), "Deploy: factory address not set");
        console2.log("owner", owner);
        // MultiPoolStrategyFactory factory = MultiPoolStrategyFactory(FACTORY_ADDRESS);
        // address OldAdapter = factory.convexAdapterImplementation();
        //// deploy implementation
        address newAdapter = address(new ConvexPoolAdapter());
        console2.log("new adapter %s ", newAdapter);
    }
}
