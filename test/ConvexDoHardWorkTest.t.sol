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
import { ICVX } from "../src/interfaces/ICVX.sol";

/*
 * @title ConvexDoHardWorkTest
 * @dev This contract is used for testing the Convex finance integration
 * @dev Test assumes that strategy is already deployed in main net and ran for a bit to accumulate some rewards
 */
contract ConvexDoHardWorkTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexGenericAdapter;
    IERC20 curveLpToken;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");

    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    uint256 public constant CVX_MAX_SUPPLY = 100 * 1_000_000 * 1e18; //100mil

    ////////////////////////  CONSTANTS ////////////////////////

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
     * @dev Convex pool ID used in the integration.
     */
    uint256 public constant CONVEX_PID = 170;

    /**
     * @dev Name of the strategy. Not really used here - but as reference
     */
    string public constant STRATEGY_NAME = "COIL/FRAXBP Strat";

    /**
     * @dev MultiPoolStrategy mainnet address
     */
    address constant STRATEGY_ADDRESS = 0x46f1325b17Ac070DfbF66F6B87fCaE4bd2570869;

    /**
     * @dev MultiPoolStrategy adopter address
     */
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

    /// @notice Sets up the test environment
    /// @dev This function is called before each test
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

    // @notice Tests the claimRewards function
    /// @dev This function tests the process of claiming rewards (CRV) from the Convex booster
    function testClaimRewards() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(ADAPTER_ADDRESS);

        ConvexPoolAdapter.RewardData[] memory rewardData = convexGenericAdapter.totalClaimable();

        uint256 _crvRewardAmount = rewardData[0].amount;
        uint256 cvxSupply = ICVX(CVX).totalSupply();
        uint256 reductionPerCliff = ICVX(CVX).reductionPerCliff();
        uint256 totalCliffs = ICVX(CVX).totalCliffs();
        uint256 cliff = cvxSupply / reductionPerCliff;
        uint256 _cvxRewardAmount;
        if (cliff < totalCliffs) {
            uint256 reduction = totalCliffs - cliff;
            _cvxRewardAmount = _crvRewardAmount * reduction / totalCliffs;
            uint256 amtTillMax = CVX_MAX_SUPPLY - cvxSupply;
            if (_cvxRewardAmount > amtTillMax) {
                _cvxRewardAmount = amtTillMax;
            }
        }

        console2.log("Expected CRV Reward: ", _crvRewardAmount);
        console2.log("Expected CVX Reward: ", _cvxRewardAmount);
        assertGt(_crvRewardAmount, 0); // expect some CRV rewards
        assertGt(_cvxRewardAmount, 0); // expect some CVX rewards - TODO: FAILS HERE

        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](2);
        uint256 quote;
        bytes memory txData;

        (quote, txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_ASSET, _crvRewardAmount, address(multiPoolStrategy));

        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: _crvRewardAmount, callData: txData });

        (quote, txData) = getQuoteLiFi(CVX, UNDERLYING_ASSET, _crvRewardAmount, address(multiPoolStrategy));
        swapDatas[1] = MultiPoolStrategy.SwapData({ token: CVX, amount: _cvxRewardAmount, callData: txData });

        uint256 wethBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

        // getting the address of the monitor and owner so we can "prank"
        address monitor = multiPoolStrategy.monitor();
        console2.log("monitor: ", monitor);
        address owner = multiPoolStrategy.owner();
        console2.log("owner: ", owner);
        vm.startPrank(monitor);

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
