// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MultiPoolStrategyFactory } from "../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../src/ConvexPoolAdapter.sol";
import { IBaseRewardPool } from "../src/interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../src/AuraWeightedPoolAdapter.sol";
import { IBooster } from "../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../src/interfaces/ICurvePool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IBooster } from "../src/interfaces/IBooster.sol";

contract ConvexDoHardWorkTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexGenericAdapter;
    IERC20 curveLpToken;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");
    ///CONSTANTS
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /**
     * @dev Address of the Convex booster contract.
     * default: https://etherscan.io/address/0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /**
     * @dev Address of the Curve pool used in the integration.
     * default: ETH/msETH Curve pool
     */
    address public constant CURVE_POOL_ADDRESS = 0x68934F60758243eafAf4D2cFeD27BF8010bede3a; // https://curve.fi/#/ethereum/pools/factory-v2-252/deposit

    /**
     * @dev Convex pool ID used in the integration.
     * default: ETH/msETH Curve pool PID
     */
    uint256 public constant CONVEX_PID = 158;

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "FAXBP/UZD Strat";

    /**
     * @dev if the pool uses native ETH as base asset e.g. ETH/msETH
     */
    bool constant USE_ETH = false;

    /**
     * @dev The index of the strategies underlying asset in the pool tokens array
     * e.g. 0 for ETH/msETH since tokens are [ETH,msETH]
     */
    int128 constant CURVE_POOL_TOKEN_INDEX = 2;

    /**
     * @dev True if the calc_withdraw_one_coin method uses uint256 indexes as parameter (check contract on etherscan)
     */
    bool constant IS_INDEX_UINT = false;

    /**
     * @dev the amount of tokens used in this pool , e.g. 2 for ETH/msETH
     */
    uint256 constant POOL_TOKEN_LENGTH = 3;

    /**
     * @dev address of zapper for pool if needed
     */
    address constant ZAPPER = 0x08780fb7E580e492c1935bEe4fA5920b94AA95Da;

    address constant STRATEGY_ADDRESS = 0x46f1325b17Ac070DfbF66F6B87fCaE4bd2570869;
    address constant ADAPTER_ADDRESS = 0x05Ab0440577Cc5E468B133B62F5eDDE2944A6F19;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_550_982;
    uint8 tokenDecimals;

    function getQuoteLiFi(
        address srcToken,
        address dstToken,
        uint256 amount,
        address fromAddress
    )
        internal
        returns (uint256 _quote, bytes memory data)
    {
        string[] memory inputs = new string[](6);
        inputs[0] = "python3";
        inputs[1] = "test/get_quote_lifi.py";
        inputs[2] = vm.toString(srcToken);
        inputs[3] = vm.toString(dstToken);
        inputs[4] = vm.toString(amount);
        inputs[5] = vm.toString(fromAddress);

        return abi.decode(vm.ffi(inputs), (uint256, bytes));
    }

    function getBlockNumber() internal returns (uint256) {
        string memory alchemyApiKey = vm.envOr("API_KEY_ALCHEMY", string(""));
        string[] memory inputs = new string[](3);
        inputs[0] = "python3";
        inputs[1] = "test/get_latest_block_number.py";
        inputs[2] = string(abi.encodePacked("https://eth-mainnet.g.alchemy.com/v2/", alchemyApiKey));
        bytes memory result = vm.ffi(inputs);
        uint256 blockNumber;
        assembly {
            blockNumber := mload(add(result, 0x20))
        }
        forkBlockNumber = blockNumber - 10; //set it to 10 blocks before latest block so we can use the
        return blockNumber;
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

        multiPoolStrategy = MultiPoolStrategy(STRATEGY_ADDRESS);
        convexGenericAdapter = ConvexPoolAdapter(payable(ADAPTER_ADDRESS));

        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();
        (address _curveLpToken,,,,,) = IBooster(CONVEX_BOOSTER).poolInfo(CONVEX_PID);
        curveLpToken = IERC20(_curveLpToken);
    }

    function testClaimRewards() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(ADAPTER_ADDRESS);

        ConvexPoolAdapter.RewardData[] memory rewardData = convexGenericAdapter.totalClaimable();

        console2.log("Expected CRV Reward: ", rewardData[0].amount);
        console2.log("Expected CVX Reward: ", rewardData[1].amount);
        assertGt(rewardData[0].amount, 0); // expect some CRV rewards
        assertGt(rewardData[1].amount, 0); // expect some CVX rewards - TODO: FAILS HERE

        uint256 totalCrvRewards = rewardData[0].amount;
        uint256 totalCvxRewards = rewardData[1].amount;
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](2);
        uint256 quote;
        bytes memory txData;

        (quote, txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_ASSET, totalCrvRewards, address(multiPoolStrategy));
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: totalCrvRewards, callData: txData });

        (quote, txData) =
            getQuoteLiFi(rewardData[1].token, UNDERLYING_ASSET, totalCrvRewards, address(multiPoolStrategy));
        swapDatas[1] =
            MultiPoolStrategy.SwapData({ token: rewardData[1].token, amount: totalCvxRewards, callData: txData });

        uint256 wethBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        multiPoolStrategy.doHardWork(adapters, swapDatas);
        uint256 wethBalanceAfter = IERC20(UNDERLYING_ASSET).balanceOf(address(this));
        uint256 crvBalanceAfter = IERC20(rewardData[0].token).balanceOf(address(multiPoolStrategy));
        uint256 cvxBalanceAfter = IERC20(rewardData[1].token).balanceOf(address(multiPoolStrategy));

        console2.log("wethBalanceBefore: ", wethBalanceBefore);
        console2.log("wethBalanceAfter: ", wethBalanceAfter);
        console2.log("crvBalanceAfter: ", crvBalanceAfter);
        console2.log("cvxBalanceAfter: ", cvxBalanceAfter);

        assertEq(crvBalanceAfter, 0);
        assertEq(cvxBalanceAfter, 0);
        assertEq(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_ASSET
    }
}
