// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity ^0.8.19.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "src/interfaces/IBaseRewardPool.sol";
import { MultiPoolStrategyWithFee } from "src/MultiPoolStrategyWithFee.sol";
import { AuraComposableStablePoolAdapter } from "src/AuraComposableStablePoolAdapter.sol";
import { IBooster } from "src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "src/interfaces/ICurvePool.sol";
import { ICVX } from "src/interfaces/ICVX.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BalancerComposableStableUpfrontFeeStrategyTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategyWithFee multiPoolStrategy;
    AuraComposableStablePoolAdapter auraComposableStablePoolAdapter;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");
    ///CONSTANTS
    address constant UNDERLYING_TOKEN = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    /// POOL CONSTANTS
    bytes32 public constant BALANCER_STABLE_POOL_ID = 0x596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659;
    uint256 public constant AURA_PID = 189;

    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 19_784_773;
    uint8 tokenDecimals;

    function getBlockNumber() internal view returns (uint256) {
        return DEFAULT_FORK_BLOCK_NUMBER;
    }

    function setUp() public virtual {
        // solhint-disable-previous-line no-empty-blocks
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }

        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({
            urlOrAlias: "mainnet",
            blockNumber: forkBlockNumber == 0 ? DEFAULT_FORK_BLOCK_NUMBER : forkBlockNumber
        });
        //// we only deploy the adapters we will use in this test
        address ConvexPoolAdapterImplementation = address(0);
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategyWithFee());
        address AuraWeightedPoolAdapterImplementation = address(0);
        address AuraStablePoolAdapterImplementation = address(0);
        address AuraComposableStablePoolAdapterImplementation = address(new AuraComposableStablePoolAdapter());
        address proxyAdmin = address(new ProxyAdmin());
        multiPoolStrategyFactory = new MultiPoolStrategyFactory(
            address(this),
            ConvexPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation,
            address(proxyAdmin)
        );

        MultiPoolStrategyWithFee multiPoolStrategyImp = new MultiPoolStrategyWithFee();

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,string,string)", address(UNDERLYING_TOKEN), address(this), "strat", "strat"
        );
        multiPoolStrategy = MultiPoolStrategyWithFee(
            address(new TransparentUpgradeableProxy(address(multiPoolStrategyImp), address(proxyAdmin), initData))
        );
        multiPoolStrategy.changeFeeRecipient(feeRecipient);
        auraComposableStablePoolAdapter = AuraComposableStablePoolAdapter(
            multiPoolStrategyFactory.createAuraComposableStablePoolAdapter(
                BALANCER_STABLE_POOL_ID, address(multiPoolStrategy), AURA_PID
            )
        );
        multiPoolStrategy.addAdapter(address(auraComposableStablePoolAdapter));
        tokenDecimals = IERC20Metadata(UNDERLYING_TOKEN).decimals();
        deal(UNDERLYING_TOKEN, address(this), 10_000 * 10 ** tokenDecimals);
        deal(UNDERLYING_TOKEN, staker, 50 * 10 ** tokenDecimals);
    }

    function testDeposit() public {
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), type(uint256).max);
        multiPoolStrategy.deposit(1 * 10 ** tokenDecimals, address(this));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        uint256 upfrontFee = _calculateUpfrontFee(1 * 10 ** tokenDecimals);
        assertEq(storedAssets, 1 * 10 ** tokenDecimals - upfrontFee);
    }

    function testUpfrontPeriodFee() public {
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), type(uint256).max);
        multiPoolStrategy.deposit(1 * 10 ** tokenDecimals, address(this));
        uint256 totalAssets = multiPoolStrategy.totalAssets();
        uint256 upfrontFee = _calculateUpfrontFee(1 * 10 ** tokenDecimals);
        vm.warp(block.timestamp + 7 days);
        multiPoolStrategy.claimFutureFeesUpfront(0);
        uint256 fee = totalAssets * multiPoolStrategy.upfrontFee() / 10_000;
        assertEq(multiPoolStrategy.totalAssets(), 1 * 10 ** tokenDecimals - fee - upfrontFee);
    }

    function testUpfrontPeriodFeeAfterAdjustIn() public {
        uint256 depositAmount = 5 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        uint256 upfrontFee = _calculateUpfrontFee(depositAmount);
        MultiPoolStrategyWithFee.Adjust[] memory adjustIns = new MultiPoolStrategyWithFee.Adjust[](1);
        uint256 adapterAdjustAmount = depositAmount * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategyWithFee.Adjust({
            adapter: address(auraComposableStablePoolAdapter),
            amount: adapterAdjustAmount, // %94
            minReceive: 0
        });

        MultiPoolStrategyWithFee.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 7 days);
        multiPoolStrategy.claimFutureFeesUpfront(0);
        uint256 totalAssets = multiPoolStrategy.totalAssets();
        uint256 fee = totalAssets * multiPoolStrategy.upfrontFee() / 10_000;
        uint256 slippage = depositAmount * 10 / 10_000;
        assertAlmostEq(multiPoolStrategy.totalAssets(), depositAmount - fee - upfrontFee, slippage);
    }

    function testUpfrontFeesFor3days() public {
        multiPoolStrategy.changeFeePeriodInDays(3 days);
        uint256 depositAmount = 1 * 10 ** tokenDecimals;
        IERC20(UNDERLYING_TOKEN).approve(address(multiPoolStrategy), depositAmount);
        multiPoolStrategy.deposit(depositAmount, address(this));
        uint256 upfrontFee = _calculateUpfrontFee(depositAmount);
        MultiPoolStrategyWithFee.Adjust[] memory adjustIns = new MultiPoolStrategyWithFee.Adjust[](1);
        uint256 adapterAdjustAmount = depositAmount * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategyWithFee.Adjust({
            adapter: address(auraComposableStablePoolAdapter),
            amount: adapterAdjustAmount, // %94
            minReceive: 0
        });

        MultiPoolStrategyWithFee.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraComposableStablePoolAdapter);

        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        vm.warp(block.timestamp + 4 days);
        multiPoolStrategy.claimFutureFeesUpfront(0);
        uint256 totalAssets = multiPoolStrategy.totalAssets();
        uint256 fee = totalAssets * multiPoolStrategy.upfrontFee() / 10_000;
        uint256 slippage = depositAmount * 10 / 10_000;
        assertAlmostEq(multiPoolStrategy.totalAssets(), depositAmount - fee - upfrontFee, slippage);
    }

    function _calculateUpfrontFee(uint256 _amount) internal view returns (uint256 fee) {
        uint256 upfrontFee = multiPoolStrategy.upfrontFee();
        uint256 feePeriodInDays = multiPoolStrategy.feePeriodInDays();
        uint256 nextFeeCycleTimestamp = multiPoolStrategy.nextFeeCycleTimestamp();

        uint256 feePct = (nextFeeCycleTimestamp - block.timestamp) * 10_000 / feePeriodInDays;

        fee = _amount * upfrontFee * feePct / 1e8;
    }
}
