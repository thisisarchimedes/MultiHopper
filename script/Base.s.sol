// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { Script } from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    /// @dev Needed for the deterministic deployments.
    bytes32 internal constant ZERO_SALT = bytes32(0);

    /// @dev The address of the contract owner.
    address internal owner;

    /// @dev Used to derive the owner's address.
    string internal mnemonic;

    constructor() {
        owner = vm.rememberKey(vm.envUint("OWNER_PKEY"));
    }

    /**
     * @dev Modifier to enable broadcasting of events and logs.
     * It starts the broadcast, executes the modified function's body, and stops the broadcast.
     * vm.startBroadcast starts a broadcast, which indicates that the following logic should take place on-chain.
     * vm.stopBroadcast stops the broadcast
     * https://book.getfoundry.sh/tutorials/solidity-scripting?highlight=broadcast#deploying-our-contract
     */
    modifier broadcaster() {
        vm.startBroadcast(owner);
        _;
        vm.stopBroadcast();
    }
}
