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
    address MULTIPOOL_STRATEGY = address(0xf9170610C6d1bac46b904385d497969dA572316B); // TODO : set strategy address
        // before deploy

    function run() public broadcaster {
        require(MULTIPOOL_STRATEGY != address(0), "Deploy: strategy address not set");
        // create  the ETHzapper
        ETHZapper ethZapper = new ETHZapper();
        console2.log("ETHZapper: %s", address(ethZapper));
        console2.log(
            "deployed ETHZapper contract at address %s for strategy %s", address(ethZapper), MULTIPOOL_STRATEGY
        );
    }
}
