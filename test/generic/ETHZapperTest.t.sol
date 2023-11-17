// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { ConvexPoolAdapter } from "../../src/ConvexPoolAdapter.sol";
import { IBaseRewardPool } from "../../src/interfaces/IBaseRewardPool.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "../../src/AuraWeightedPoolAdapter.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";
import { FlashLoanAttackTest } from "../../src/test/FlashLoanAttackTest.sol";
import { ICurveBasePool } from "../../src/interfaces/ICurvePool.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";
import { ETHZapper } from "../../src/ETHZapper.sol";

contract ConvexPoolAdapterETHZapperTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    ConvexPoolAdapter convexGenericAdapter;
    IERC20 curveLpToken;
    ETHZapper ethZapper;

    address public staker = makeAddr("staker");
    address public feeRecipient = makeAddr("feeRecipient");
    ///CONSTANTS
    /**
     * @dev Address of the underlying token used in the integration.
     * default: WETH
     */
    address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /**
     * @dev Address of the Convex booster contract.
     * default: https://etherscan.io/address/0xF403C135812408BFbE8713b5A23a04b3D48AAE31
     */
    address public constant CONVEX_BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;

    /**
     * @dev Address of the Curve pool used in the integration.
     * default: ETH/msETH Curve pool
     */
    address public constant CURVE_POOL_ADDRESS = 0x7fb53345f1B21aB5d9510ADB38F7d3590BE6364b;

    /**
     * @dev Convex pool ID used in the integration.
     * default: ETH/msETH Curve pool PID
     */
    uint256 public constant CONVEX_PID = 185;

    /**
     * @dev Name of the strategy.
     */
    string public constant STRATEGY_NAME = "ETH/ETH+ Strat";

    /**
     * @dev if the pool uses native ETH as base asset e.g. ETH/msETH
     */
    bool constant USE_ETH = false;

    /**
     * @dev The index of the strategies underlying asset in the pool tokens array
     * e.g. 0 for ETH/msETH since tokens are [ETH,msETH]
     */
    int128 constant CURVE_POOL_TOKEN_INDEX = 1;

    /**
     * @dev True if the calc_withdraw_one_coin method uses uint256 indexes as parameter (check contract on etherscan)
     */
    bool constant IS_INDEX_UINT = true;

    /**
     * @dev the ethAmount of tokens used in this pool , e.g. 2 for ETH/alETH
     */
    uint256 constant POOL_TOKEN_LENGTH = 2;

    /**
     * @dev address of zapper for pool if needed
     */
    address constant ZAPPER = address(0);

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_637_485;
    uint8 tokenDecimals;

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
        address ConvexPoolAdapterImplementation = address(new ConvexPoolAdapter());
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
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

        ethZapper = new ETHZapper();
        multiPoolStrategy.addAdapter(address(convexGenericAdapter));
        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();
        multiPoolStrategy.changeFeeRecipient(feeRecipient);
        (address _curveLpToken,,,,,) = IBooster(CONVEX_BOOSTER).poolInfo(CONVEX_PID);
        curveLpToken = IERC20(_curveLpToken);
        deal(UNDERLYING_ASSET, address(this), 10_000e18);
        deal(UNDERLYING_ASSET, staker, 50e18);
    }

    function testDeposit(uint256 ethAmount) public {

        // assuming ethAmount is withing reasonable range
        vm.assume(ethAmount > 0);
        vm.assume(ethAmount < 100_000_000 ether);

        // load some ETH into this address
        vm.deal(address(this), ethAmount);

        // get how many assets we have post deposit
        uint256 storedAssetsPre = multiPoolStrategy.storedTotalAssets();

        // deposit ETH to WETH straetgy via zapper
        uint256 shares = ethZapper.depositETH{ value: ethAmount }(address(this), address(multiPoolStrategy));

        // get how many assets we have post deposit
        uint256 storedAssetsPost = multiPoolStrategy.storedTotalAssets();

        // verify that the ethAmount of ETH we deposit is now on Strategy as WETH
        assertEq(storedAssetsPost - storedAssetsPre, ethAmount);

        // verify that the ethAmount of shares we received is correct
        assertEq(multiPoolStrategy.balanceOf(address(this)), shares);
    }

    

    function testWithdraw(uint256 ethAmount) public {

         // assuming ethAmount is withing reasonable range
        vm.assume(ethAmount > 1);
        vm.assume(ethAmount < 100_000_000 ether);
        //ethAmount = ethAmount / 2; // so we don't need to deal with rounding errors

        // load some ETH into this address
        vm.deal(address(this), ethAmount);

         // deposit ETH to WETH straetgy via zapper
        uint256 shares = ethZapper.depositETH{ value: ethAmount }(address(this), address(multiPoolStrategy));

        // approving shares
        IERC20(address(multiPoolStrategy)).approve(address(ethZapper), shares);

        // get how many assets we have on the strategy pre withdraw 
        uint256 storedAssetsPre = multiPoolStrategy.storedTotalAssets();
        uint256 ethBalancePre = address(this).balance;

        // withdraw half the ETH from WETH straetgy via zapper
        uint256 ethRet = ethZapper.withdrawETH(ethAmount / 2, address(this), 0, address(multiPoolStrategy));

        // get how many assets we have on the strategy post withdraw 
        uint256 storedAssetsPost = multiPoolStrategy.storedTotalAssets();
        uint256 ethBalancePost = address(this).balance;

        // we expect the strategy to have half the assets it had before
        assertEq(storedAssetsPre - storedAssetsPost, ethAmount / 2);

        // we expect the ETH balance of this address to increase by half the ethAmount we deposited
        assertEq(ethBalancePost - ethBalancePre, ethAmount / 2);

        // we expect ethRet to be the same as ethBalancePost - ethBalancePre
        assertEq(ethRet, ethBalancePost - ethBalancePre);

        // withdraw the rest of the ETH from WETH straetgy via zapper
        ethRet = ethZapper.withdrawETH(ethAmount / 2, address(this), 0, address(multiPoolStrategy));

        storedAssetsPost = multiPoolStrategy.storedTotalAssets();
        ethBalancePost = address(this).balance;

        // we expect the strategy to have half the assets it had before
        // we need to deal with rounding error here - thus the 1 wei difference
        assertLte(storedAssetsPost, 1);

        // we expect the ETH balance of this address to increase by half the ethAmount we deposited
        // we need to deal with rounding error here - thus the 1 wei difference
        assertLte(ethAmount - ethBalancePost - ethBalancePre, 1);
    }

    function testRedeem(uint256 ethAmount) public {

        // assuming ethAmount is withing reasonable range
        vm.assume(ethAmount > 1);
        vm.assume(ethAmount < 100_000_000 ether);
        //ethAmount = ethAmount / 2; // so we don't need to deal with rounding errors

        // load some ETH into this address
        vm.deal(address(this), ethAmount);

         // deposit ETH to WETH straetgy via zapper
        uint256 shares = ethZapper.depositETH{ value: ethAmount }(address(this), address(multiPoolStrategy));

        // we deposit the ETH just checking that the balance is 0
        assertEq(address(this).balance, 0);

        // approving shares
        IERC20(address(multiPoolStrategy)).approve(address(ethZapper), shares);

        // get how many assets we have on the strategy pre withdraw 
        uint256 storedAssetsPre = multiPoolStrategy.storedTotalAssets();

        uint256 ethRet = ethZapper.redeemETH(shares, address(this), 0, address(multiPoolStrategy));

        uint256 storedAssetsPost = multiPoolStrategy.storedTotalAssets();
        
        // retETH should be the same as the amount of ETH we had on the strategy
        assertEq(ethRet, address(this).balance);

        // did we get all the ETH back?
        assertEq(address(this).balance, ethAmount);

        // we took the right amount of ETH from strategy
        assertEq(storedAssetsPre - storedAssetsPost, ethAmount);
    }

    receive() external payable {
         // solhint-disable-previous-line no-empty-blocks
     }
    
}
