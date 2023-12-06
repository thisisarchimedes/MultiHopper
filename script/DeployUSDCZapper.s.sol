// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19;

import "forge-std/Script.sol";

import { BaseScript } from "script/Base.s.sol";
import { USDCZapper } from "src/zapper/USDCZapper.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @title Deploy
 *
 * @dev A contract for deploying the ETHZapper contract
 */
contract DeployETHZapper is Script {

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // mainnet deployer private key

    function run() public {

        vm.startBroadcast(deployerPrivateKey);

        // create the USDCZapper
        USDCZapper usdcZapper = new USDCZapper();
        console2.log("USDCZapper: %s", address(usdcZapper));

        vm.stopBroadcast();

    }
}
