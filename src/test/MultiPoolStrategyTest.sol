// SPDX-License-Identifier: CC BY-NC-ND 4.0
pragma solidity ^0.8.19.0;

import { MultiPoolStrategy } from "../MultiPoolStrategy.sol";

contract MultiPoolStrategyTest is MultiPoolStrategy {
    function setRewardsCycleEnd(uint32 _newTimestamp) external {
        rewardsCycleEnd = _newTimestamp;
    }
}
