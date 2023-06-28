// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import { ETHZapper } from "../src/ETHZapper.sol";
import { console2 } from "forge-std/console2.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

/**
 * @title Deploy
 *
 * @dev A contract for deploying the ETHZapper contract
 */
contract DeployETHZapper is BaseScript {
    address MULTIPOOL_STRATEGY = address(0);
    // before deploy

    function run() public broadcaster {
        require(MULTIPOOL_STRATEGY != address(0), "Deploy: strategy address not set");
        // create  the ETHzapper
        ETHZapper ethZapper = new ETHZapper();
        console2.log("ETHZapper: %s", address(ethZapper));
        console2.log(
            "deployed ETHZapper contract at address %s for strategy %s", address(ethZapper), MULTIPOOL_STRATEGY
        );
        // test that everything works correctly doing a deposit through the zapper | this is just QoL for deployment on
        // fork, uncomment if needed

        // ethZapper.depositETH{ value: 10e18 }(owner,address(multiPoolStrategy));
        // uint256 strategyTotalAssets = multiPoolStrategy.totalAssets();
        // console2.log("Strategy total assets: %s", strategyTotalAssets / 1e18);
    }
}
