// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import "forge-std/Script.sol";
import { ETHZapper } from "../src/ETHZapper.sol";
import { console2 } from "forge-std/console2.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";


/**
 * @title Deploy
 *
 * @dev A contract for deploying the ETHZapper contract
 */
contract DeployETHZapper is Script {
    
    // set before deploy
    address MULTIPOOL_STRATEGY = address(0);

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // mainnet deployer private key
    
    

    function run() public {

        vm.startBroadcast(deployerPrivateKey);

        // create  the ETHzapper
        ETHZapper ethZapper = new ETHZapper();
        console2.log("ETHZapper: %s", address(ethZapper));
        console2.log(
            "deployed ETHZapper contract at address %s for strategy %s", address(ethZapper), MULTIPOOL_STRATEGY
        );

        /* =========== START TEST - RUN ONLY WITH A FORK =========== */
        // test that everything works correctly doing a deposit through the zapper | this is just QoL for deployment on
        // fork, uncomment if needed

        //MultiPoolStrategy multiPoolStrategy = MultiPoolStrategy(MULTIPOOL_STRATEGY);
        //ethZapper.depositETH{ value: 10000 }(address(this), MULTIPOOL_STRATEGY);
        //uint256 strategyTotalAssets = multiPoolStrategy.totalAssets();
        //console2.log("Strategy total assets: %s", strategyTotalAssets / 1e18);
        /* =========== END TEST - RUN ONLY WITH A FORK =========== */

        vm.stopBroadcast();

    }
}
