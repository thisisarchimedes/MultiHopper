// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";

import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { ConvexPoolAdapter } from "src/ConvexPoolAdapter.sol";
import { AuraComposableStablePoolAdapter } from "src/AuraComposableStablePoolAdapter.sol";
import { ICVX } from "src/interfaces/ICVX.sol";

/* 
    * @title DoHardWorkConvexSinglePool
    * @dev Call DoHardWork on a single pool strategy (On Convex)
    * @dev Calculates rewards and invoke the DoHardWork method on the strategy
*/
contract DoHardWorkConvexSinglePool is Script {
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // WETH

    /**
     * @dev Name of the strategy. Not really used here - but as reference
     */
    string public constant STRATEGY_NAME = "COIL/FRAXBP Strat";

    /**
     * @dev MultiPoolStrategy mainnet address
     */
    address constant STRATEGY_ADDRESS = 0x46f1325b17Ac070DfbF66F6B87fCaE4bd2570869;

    /**
     * @dev Adapter mainnet address
     */
    address constant ADAPTER_ADDRESS = 0x05Ab0440577Cc5E468B133B62F5eDDE2944A6F19;

    /**
     * @dev CVX Address and supply used to calc CVX rewards
     */
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    uint256 public constant CVX_MAX_SUPPLY = 100 * 1_000_000 * 1e18; //100mil

    /**
     * @notice Calculates the quote for a trade via LiFi protocol.
     * @notice make sure Python environment is active and has the required dependencies installed.
     * @param srcToken The token to be sold.
     * @param dstToken The token to be bought.
     * @param amount The amount of source tokens to be sold.
     * @param fromAddress The address initiating the trade.
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
     * @notice Calculate CRV and CVX rewards, fetch quotes from LiFi, and return a a swap data array that is
     *         consumable by the MultiPoolStrategy DoHardWork.
     * @param adopter The address of the ConvexPoolAdapter contract.
     * @return swapDatas An array of swap data containing token, amount, and transaction data for each swap.
     */
    function getSwapsData(address adopter) internal returns (MultiPoolStrategy.SwapData[] memory swapDatas) {
        ConvexPoolAdapter convexGenericAdapter = ConvexPoolAdapter(payable(adopter));
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

        // build the swap data for LiFi
        swapDatas = new MultiPoolStrategy.SwapData[](2);
        uint256 quote;
        bytes memory txData;

        // get CRV qoute
        (quote, txData) = getQuoteLiFi(
            rewardData[0].token, UNDERLYING_ASSET, _crvRewardAmount, address(STRATEGY_ADDRESS)
        );
        swapDatas[0] =
            MultiPoolStrategy.SwapData({ token: rewardData[0].token, amount: _crvRewardAmount, callData: txData });

        // get CVX quote
        (quote, txData) =
            getQuoteLiFi(CVX, UNDERLYING_ASSET, _crvRewardAmount, address(STRATEGY_ADDRESS));
        swapDatas[1] = MultiPoolStrategy.SwapData({ token: CVX, amount: _cvxRewardAmount, callData: txData });
    }

    /**
     * @notice Executes the script to perform hard work on a single pool strategy.
     * @dev Requires the environment variable "PRIVATE_KEY" for signing transactions.
     * @dev Remember to run with --broadcast to actually send the tx to the main net
     */
    function run() external {
        // get the private key used for signing transactions
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // create the MultiPoolStrategy contract for the underlying asset
        MultiPoolStrategy multiPoolStrategy = MultiPoolStrategy(STRATEGY_ADDRESS);
        address[] memory adapters = new address[](1);
        adapters[0] = address(ADAPTER_ADDRESS);

        MultiPoolStrategy.SwapData[] memory swapDatas = getSwapsData(ADAPTER_ADDRESS);

        uint256 fees = IERC20(UNDERLYING_ASSET).balanceOf(multiPoolStrategy.feeRecipient());
        console2.log("Fees before: %s", fees);

        multiPoolStrategy.doHardWork(adapters, swapDatas);

        console2.log("MultiPoolStrategy: %s", address(multiPoolStrategy));

        fees = IERC20(UNDERLYING_ASSET).balanceOf(multiPoolStrategy.feeRecipient());
        console2.log("Fees after: %s", fees);
    }
}
