// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19;

import { BaseScript } from "./Base.s.sol";
import "forge-std/Script.sol";
import { GenericZapper } from "../src/zapper/GenericZapper.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title Deploy
 *
 * @dev A contract for deploying the ETHZapper contract
 */
contract DeployGenericZapper is Script {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // mainnet deployer private key

    function run() public {

        vm.startBroadcast(deployerPrivateKey);

        // create the USDCZapper
        GenericZapper genericZapper = new GenericZapper();
        console2.log("GenericZapper: %s", address(genericZapper));

        vm.stopBroadcast();

    }
}
