// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MultiPoolStrategyFactory } from "../src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "../src/interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { MultiPoolStrategy } from "../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../src/AuraWeightedPoolAdapter.sol";
import { IBooster } from "../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../src/interfaces/ICurvePool.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

/*
 * @title AuraDoHardWorkTest
 * @dev This contract is used for testing the Aura finance integration
 * @dev Test assumes that strategy is already deployed in main net and ran for a bit to accumulate some rewards
 *
 * @dev make sure to set the Balancer and Aura pool information correctly. 
 * @dev set the Aura adopter to the correct type (search for AuraStablePoolAdapter or AuraWeightedPoolAdapter in the
 *      code)
 * @dev TODO: deal with AURA rewards.
 */
contract AuraDoHardWorkTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    //AuraStablePoolAdapter auraPoolAdapter;
    AuraWeightedPoolAdapter auraPoolAdapter;

    address public staker = makeAddr("staker");

    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    // address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    /**
     * @dev AURA and Balancer pool information
     */
    address public constant AURA_BOOSTER = 0x6f6801b49B5D8CA2Ea5FEAD9096F347B9355a330; // Rewards contract address
    bytes32 public constant BALANCER_POOL_ID = 0x42fbd9f666aacc0026ca1b88c94259519e03dd67000200000000000000000507;
    uint256 public constant AURA_PID = 95;

    /**
     * @dev Name of the strategy. Not really used here - but as reference
     */
    string public constant STRATEGY_NAME = "50COIL/50USDC Strat";

    /**
     * /**
     * @dev MultiPoolStrategy mainnet address
     */
    address constant STRATEGY_ADDRESS = 0x0d25652Bd064bAfa47142e853f004bB11DdA5408;

    /**
     * @dev MultiPoolStrategy adopter address
     */
    address constant ADAPTER_ADDRESS = 0xe3fC693004D0ab723578D6B00432b139F5ebA329;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_571_688;

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

        // initalizing contracts with mainnet addreses
        multiPoolStrategy = MultiPoolStrategy(STRATEGY_ADDRESS);
        // auraPoolAdapter = AuraStablePoolAdapter(ADAPTER_ADDRESS);
        auraPoolAdapter = AuraWeightedPoolAdapter(ADAPTER_ADDRESS);

        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();
    }

    function testClaimRewards() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(ADAPTER_ADDRESS);

        /// Get reward information
        // AuraStablePoolAdapter.RewardData[] memory rewardData = auraPoolAdapter.totalClaimable();
        AuraWeightedPoolAdapter.RewardData[] memory rewardData = auraPoolAdapter.totalClaimable();
        uint256 _balRewardAmount = rewardData[0].amount;
        console2.log("Expected BAL Reward: ", _balRewardAmount);

        assertGt(_balRewardAmount, 0); // expect some BAL rewards

        // TODO AUR reward info is currently missing

        // get swap quote from LiFi and building the swap data
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_ASSET, _balRewardAmount, address(multiPoolStrategy));
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](1);
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: _balRewardAmount, callData: txData });

        uint256 wethBalanceBefore = IERC20(UNDERLYING_ASSET).balanceOf(address(this));

        // getting the address of the owner and setting it to also "monitor" so we can "prank"
        // there is a bug in the contract require owner and monitor to be the same
        address owner = multiPoolStrategy.owner();
        vm.startPrank(owner);
        multiPoolStrategy.setMonitor(owner);
        console2.log("owner: ", owner);
        address monitor = multiPoolStrategy.monitor();
        console2.log("monitor: ", monitor);

        // make sure fee recipient is not 0x0..0
        multiPoolStrategy.changeFeeRecipient(owner);

        // do hard work
        multiPoolStrategy.doHardWork(adapters, swapDatas);

        uint256 wethBalanceAfter = IERC20(UNDERLYING_ASSET).balanceOf(address(multiPoolStrategy));
        uint256 balBalanceAfter = IERC20(rewardData[0].token).balanceOf(address(multiPoolStrategy));
        // uint256 auraBalanceAfter = IERC20(rewardData[1].token).balanceOf(address(multiPoolStrategy)); TODO
        uint256 fees = IERC20(UNDERLYING_ASSET).balanceOf(multiPoolStrategy.feeRecipient());

        console2.log("wethBalanceBefore: ", wethBalanceBefore);
        console2.log("wethBalanceAfter: ", wethBalanceAfter);
        console2.log("balBalanceAfter: ", balBalanceAfter);
        // console2.log("auraBalanceAfter: ", auraBalanceAfter); TODO
        console2.log("fees collected: ", fees);

        assertEq(balBalanceAfter, 0);
        // assertEq(auraBalanceAfter, 0);
        assertGt(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_ASSET
        assertGt(fees, 0);
    }
}
