// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import "forge-std/Script.sol";
import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "src/AuraWeightedPoolAdapter.sol";
import { AuraStablePoolAdapter } from "src/AuraStablePoolAdapter.sol";
import { AuraComposableStablePoolAdapter } from "src/AuraComposableStablePoolAdapter.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import { console2 } from "forge-std/console2.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

/**
 * @title Deploy
 *
 * @dev A contract for deploying the MultiPoolStrategyFactory contract
 * @notice we do this in its own script because of the size of the contract and the gas spent
 *
 */
contract DeployFactory is Script {
    address MONITOR = address(0); // TODO : set monitor address before deploy
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // mainnet deployer private key

    function run() public returns (MultiPoolStrategyFactory factory) {
        require(MONITOR != address(0), "Deploy: monitor address not set");

        vm.startBroadcast(deployerPrivateKey);

        //// implementation contract deployments , if there are any issues with script size and deployment you can
        // set the ones you will not use as address(0)
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address AuraWeightedPoolAdapterImplementation = address(new AuraWeightedPoolAdapter());
        address AuraStablePoolAdapterImplementation = address(new AuraStablePoolAdapter());
        address AuraComposableStablePoolAdapterImplementation = address(new AuraComposableStablePoolAdapter());
        address proxyAdmin = address(new ProxyAdmin());
        factory = new MultiPoolStrategyFactory(
            MONITOR,
            ConvexPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation,
            proxyAdmin
            );
        console2.log(
            "deployed MultiPoolStrategyFactory contract at address %s with monitor %s", address(factory), MONITOR
        );

        vm.stopBroadcast();
    }
}
