// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19.0;

import { MonitorProxy } from "src/MonitorProxy.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";

import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IBaseRewardPool } from "src/interfaces/IBaseRewardPool.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";

contract MonitorProxyTest is PRBTest, StdCheats {
    MonitorProxy public monitorProxy;
    MultiPoolStrategy public multiPoolStrategy;
    address UNDERLYING_ASSET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant STRATEGY_ADDRESS = 0x45a56929E41056654B484A0dCe99A301F2F836f0;
    address public staker = makeAddr("staker");
    address public monitor = makeAddr("monitor");

    function setUp() public virtual {
        // solhint-disable-previous-line no-empty-blocks
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }

        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 19_811_089 });

        multiPoolStrategy = MultiPoolStrategy(STRATEGY_ADDRESS);
        monitorProxy = new MonitorProxy();
        monitorProxy.grantRole(monitorProxy.MONITOR_ROLE(), monitor);

        deal(UNDERLYING_ASSET, staker, 5000e6);
    }

    function testAdjustIn() public {
        uint256 depositAmount = 5000e6;
        address owner = multiPoolStrategy.owner();
        vm.startPrank(owner);
        multiPoolStrategy.setMonitor(address(monitorProxy));
        vm.stopPrank();
        vm.startPrank(staker);
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), 50e18);
        multiPoolStrategy.deposit(depositAmount, address(this));
        vm.stopPrank();

        address adapter = multiPoolStrategy.adapters(0);
        IBaseRewardPool rewardPool = IBaseRewardPool(ConvexPoolAdapter(payable(adapter)).convexRewardPool());

        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        MultiPoolStrategy.Adjust[] memory adjustOuts = new MultiPoolStrategy.Adjust[](0);
        address[] memory sortedAdapters = new address[](1);
        sortedAdapters[0] = adapter;
        adjustIns[0] = MultiPoolStrategy.Adjust({ adapter: adapter, amount: depositAmount * 90 / 100, minReceive: 0 });
        vm.prank(monitor);
        uint256 balBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
        monitorProxy.adjust(address(multiPoolStrategy), adjustIns, adjustOuts, sortedAdapters);
        uint256 balAfter = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));

        assertGt(balBefore, balAfter, "balance should be less than before");
    }

    function testAdjustOut() public {
        address owner = multiPoolStrategy.owner();
        vm.startPrank(owner);
        multiPoolStrategy.setMonitor(address(monitorProxy));
        vm.stopPrank();

        address adapter = multiPoolStrategy.adapters(0);
        IBaseRewardPool rewardPool = IBaseRewardPool(ConvexPoolAdapter(payable(adapter)).convexRewardPool());
        uint256 bal = rewardPool.balanceOf(adapter);
        assertGt(bal, 0, "balance should be greater than 0");
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](0);
        MultiPoolStrategy.Adjust[] memory adjustOuts = new MultiPoolStrategy.Adjust[](1);
        address[] memory sortedAdapters = new address[](1);
        sortedAdapters[0] = adapter;
        adjustOuts[0] = MultiPoolStrategy.Adjust({ adapter: adapter, amount: bal, minReceive: 0 });
        uint256 balBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
        vm.prank(monitor);
        monitorProxy.adjust(address(multiPoolStrategy), adjustIns, adjustOuts, sortedAdapters);
        uint256 balAfter = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
        assertGt(balAfter - balBefore, 0);
    }
}
