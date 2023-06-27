// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

// Importing dependencies
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
import { ICVX } from "../src/interfaces/ICVX.sol";

/*
 * @title AuraDoHardWorkTest
 * @dev This contract is used for testing the Aura finance integration
 * @dev Test assumes that strategy is already deployed in main net and ran for a bit to accumulate some rewards
 *
 * @dev make sure to set the Balancer and Aura pool information correctly. 
 * @dev set the Aura adopter to the correct type (search for AuraStablePoolAdapter or AuraWeightedPoolAdapter in the
 *      code)
 */
contract AuraDoHardWorkTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    //AuraStablePoolAdapter auraPoolAdapter;
    AuraWeightedPoolAdapter auraPoolAdapter;

    address public staker = makeAddr("staker");

    /// @dev Address of the AURA token
    address public constant AURA = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;

    /// @dev Address of the underlying token used in the integration. By default: WETH
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    // address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

    /// @dev AURA and Balancer pool information
    address public constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234; // same address for all pools
    bytes32 public constant BALANCER_POOL_ID = 0x42fbd9f666aacc0026ca1b88c94259519e03dd67000200000000000000000507;
    uint256 public constant AURA_PID = 95;

    /// @dev Name of the strategy. Not really used here - but as reference
    string public constant STRATEGY_NAME = "50COIL/50USDC Strat";

    /// @dev MultiPoolStrategy mainnet address
    address constant STRATEGY_ADDRESS = 0x0d25652Bd064bAfa47142e853f004bB11DdA5408;

    /// @dev MultiPoolStrategy adopter address
    address constant ADAPTER_ADDRESS = 0xe3fC693004D0ab723578D6B00432b139F5ebA329;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_573_300;

    uint8 tokenDecimals;

    /**
     * @dev Fetches quote data from LiFi for a given source and destination token for swap source->destination
     * @param srcToken The source token address
     * @param dstToken The destination token address
     * @param amount The amount of source tokens to quote
     * @param fromAddress The address initiating the quote request
     * @return _quote The quoted amount of destination tokens that will be received
     * @return data Additional data returned from the quote operation
     */
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

    /**
     * @dev Calculates the amount of AURA rewards for a given amount of BAL token rewards.
     * @param _balRewards The amount of BAL token rewards
     * @return The calculated amount of AURA rewards
     */
    function _calculateAuraRewards(uint256 _balRewards) internal view returns (uint256) {
        (,,, address _auraRewardPool,,) = IBooster(AURA_BOOSTER).poolInfo(AURA_PID);
        uint256 rewardMultiplier = IBooster(AURA_BOOSTER).getRewardMultipliers(_auraRewardPool);
        uint256 auraMaxSupply = 5e25; //50m
        uint256 auraInitMintAmount = 5e25; //50m
        uint256 totalCliffs = 500;
        bytes32 slotVal = vm.load(AURA, bytes32(uint256(7)));
        uint256 minterMinted = uint256(slotVal);
        uint256 mintAmount = _balRewards * rewardMultiplier / 10_000;
        uint256 emissionsMinted = IERC20(AURA).totalSupply() - auraInitMintAmount - minterMinted;
        uint256 cliff = emissionsMinted / ICVX(AURA).reductionPerCliff();
        uint256 auraRewardAmount;

        if (cliff < totalCliffs) {
            uint256 reduction = (totalCliffs - cliff) * 5 / 2 + 700;
            auraRewardAmount = mintAmount * reduction / totalCliffs;
            uint256 amtTillMax = auraMaxSupply - emissionsMinted;
            if (auraRewardAmount > amtTillMax) {
                auraRewardAmount = amtTillMax;
            }
        }
        return auraRewardAmount;
    }

    /**
     * @dev Initializes the test environment, setting up the mainnet fork and contract instances.
     */
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

    /**
     * @dev Executes the entire reward claiming process for BAL and AURA tokens and
     * swaps them for the underlying asset
     *
     * It performs the following steps:
     * 1. Fetches the BAL and AURA rewards that can be claimed.
     * 2. Swaps the rewards by first getting a quote from LiFi and then using that data to perform the swap.
     * 3. (bug) Checks the owner and sets the monitor of the multiPoolStrategy to the same address to allow the
     * following
     * actions.
     * 4. Changes the fee recipient to the contract owner.
     * 5. Calls the doHardWork function in the multiPoolStrategy contract which does the actual work of claiming rewards
     * and swapping.
     * 6. Checks the balances after the operation and ensures the expected state change has occurred.
     */
    function testClaimRewards() public {
        address[] memory adapters = new address[](1);
        adapters[0] = address(ADAPTER_ADDRESS);

        /// Get reward information
        // AuraStablePoolAdapter.RewardData[] memory rewardData = auraPoolAdapter.totalClaimable();
        AuraWeightedPoolAdapter.RewardData[] memory rewardData = auraPoolAdapter.totalClaimable();
        uint256 _balRewardAmount = rewardData[0].amount;
        console2.log("Expected BAL Reward: ", _balRewardAmount);
        assertGt(_balRewardAmount, 0); // expect some BAL rewards

        // TODO: AURA reward info is currently missing
        uint256 _auraRewardAmount = _calculateAuraRewards(_balRewardAmount);
        console2.log("Expected AURA Reward: ", _auraRewardAmount);
        assertGt(_auraRewardAmount, 0); // expect some AURA rewards

        // get swap quote from LiFi and building the swap data
        MultiPoolStrategy.SwapData[] memory swapDatas = new MultiPoolStrategy.SwapData[](2);

        // get BAL quote
        (uint256 quote, bytes memory txData) =
            getQuoteLiFi(rewardData[0].token, UNDERLYING_ASSET, _balRewardAmount, address(multiPoolStrategy));
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: _balRewardAmount, callData: txData });

        // get AURA quote
        (quote, txData) = getQuoteLiFi(AURA, UNDERLYING_ASSET, _auraRewardAmount, address(multiPoolStrategy));
        swapDatas[1] = MultiPoolStrategy.SwapData({ token: AURA, amount: _auraRewardAmount, callData: txData });

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
        uint256 auraBalanceAfter = IERC20(AURA).balanceOf(address(multiPoolStrategy));
        uint256 fees = IERC20(UNDERLYING_ASSET).balanceOf(multiPoolStrategy.feeRecipient());

        console2.log("wethBalanceBefore: ", wethBalanceBefore);
        console2.log("wethBalanceAfter: ", wethBalanceAfter);
        console2.log("balBalanceAfter: ", balBalanceAfter);
        console2.log("auraBalanceAfter: ", auraBalanceAfter);
        console2.log("fees collected: ", fees);

        assertEq(balBalanceAfter, 0);
        assertEq(auraBalanceAfter, 0);
        assertGt(wethBalanceAfter - wethBalanceBefore, 0); // expect receive UNDERLYING_ASSET
        assertGt(fees, 0);
    }
}

/*
 Expected BAL Reward:  44001004201440630
  Expected AURA Reward:  144059287755516622
  owner:  0xE3c8F86695366f9d564643F89ef397B22fAB0db5
  monitor:  0xE3c8F86695366f9d564643F89ef397B22fAB0db5
  wethBalanceBefore:  0
  wethBalanceAfter:  1565528
  balBalanceAfter:  0
  auraBalanceAfter:  0
  fees collected:  20614
*/
