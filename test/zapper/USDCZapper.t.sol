// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { StdCheats } from "forge-std/Test.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBaseRewardPool } from "../../src/interfaces/IBaseRewardPool.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";
import { IZapper } from "../../src/interfaces/IZapper.sol";
import { ICurveBasePool } from "../../src/interfaces/ICurvePool.sol";
import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../../src/ConvexPoolAdapter.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../../src/AuraWeightedPoolAdapter.sol";
import { FlashLoanAttackTest } from "../../src/test/FlashLoanAttackTest.sol";
import { USDCZapper } from "../../src/zapper/USDCZapper.sol";

contract USDCZapperTest is PRBTest, StdCheats {
    uint256 public constant DEFAULT_FORK_BLOCK_NUMBER = 17_886_763;
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC - mainnet

    IZapper public USDCzapper;

    MultiPoolStrategyFactory public multiPoolStrategyFactory;
    MultiPoolStrategy public multiPoolStrategy;

    ConvexPoolAdapter public convexGenericAdapter;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");

    uint256 public tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();

    function setUp() public virtual {
        vm.createSelectFork({urlOrAlias: "mainnet", blockNumber: DEFAULT_FORK_BLOCK_NUMBER});

        USDCzapper = new USDCZapper();

        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
        address AuraWeightedPoolAdapterImplementation = address(0);
        address AuraStablePoolAdapterImplementation = address(0);
        address AuraComposableStablePoolAdapterImplementation = address(0);

        multiPoolStrategyFactory = new MultiPoolStrategyFactory(
            address(this),
            ConvexPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation
            );

        multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_ASSET, "Generic MultiPool Strategy")
        );
        convexGenericAdapter = ConvexPoolAdapter(
            payable(
                multiPoolStrategyFactory.createConvexAdapter(
                    CURVE_POOL_ADDRESS,
                    address(multiPoolStrategy),
                    CONVEX_PID,
                    POOL_TOKEN_LENGTH,
                    ZAPPER,
                    USE_ETH,
                    IS_INDEX_UINT,
                    CURVE_POOL_TOKEN_INDEX
                )
            )
        );

        multiPoolStrategy.addAdapter(address(convexGenericAdapter));
        multiPoolStrategy.changeFeeRecipient(feeRecipient);

        // (address _curveLpToken,,,,,) = IBooster(CONVEX_BOOSTER).poolInfo(CONVEX_PID);
        // curveLpToken = IERC20(_curveLpToken);

        deal(UNDERLYING_ASSET, address(this), 10_000 ether);
        deal(UNDERLYING_ASSET, staker, 50 ether);
    }

    function testDepositUSDT() public { }
    /*
    *   1. Get random amount of USDT
    *   2. Deposit USDT through zapper
    *   3. check USDT balanceOf strategy
    */
    function testDepositDAI() public { }
    function testDeposit3CRV() public { }
    function testDepositCRVFRAX() public { }
    function testWithdrawUSDT() public { }
    function testWithdrawDAI() public { }
    function testWithdraw3CRV() public { }
    function testWithdrawCRVFRAX() public { }
    function testRedeemUSDT() public { }
    /*
    *   1. Get random amount of USDT
    *   2. Deposit USDT through zapper
    *   3. check USDT balanceOf strategy
    *   4. redeem and check we got the same amount of USDT (almost - minus swap fees - at least 99% of deposited amount)
    */
    function testRedeemDAI() public { }
    function testRedeem3CRV() public { }
    function testRedeemCRVFRAX() public { }
    function testDepositRevert() public { }
    function testWithdrawRevert() public { }
    function testRedeemRevert() public { }
    function testStrategyUsesUnderlyingAsset() public { }
}
