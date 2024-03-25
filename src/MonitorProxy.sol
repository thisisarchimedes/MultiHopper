// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19.0;

import { AccessControl } from "openzeppelin-contracts/access/AccessControl.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";

contract MonitorProxy is AccessControl {
    bytes32 public constant MONITOR_ROLE = keccak256("MONITOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor() {
        _setupRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(MONITOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    function adjust(
        address _strategy,
        MultiPoolStrategy.Adjust[] memory _adjustIns,
        MultiPoolStrategy.Adjust[] memory _adjustOuts,
        address[] memory _sortedAdapters
    )
        public
        onlyRole(MONITOR_ROLE)
    {
        MultiPoolStrategy(_strategy).adjust(_adjustIns, _adjustOuts, _sortedAdapters);
    }

    function doHardwork(
        address _strategy,
        address[] calldata _adaptersToClaim,
        MultiPoolStrategy.SwapData[] calldata _swapDatas
    )
        public
        onlyRole(MONITOR_ROLE)
    {
        MultiPoolStrategy(_strategy).doHardWork(_adaptersToClaim, _swapDatas);
    }
}
