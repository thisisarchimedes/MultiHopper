// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { MultiPoolStrategyFactory } from "src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "src/interfaces/IBaseRewardPool.sol";
import { ETHZapper } from "src/zapper/ETHZapper.sol";
import { MultiPoolStrategy } from "src/MultiPoolStrategy.sol";
import { AuraWeightedPoolAdapter } from "src/AuraWeightedPoolAdapter.sol";
import { ICurveBasePool } from "src/interfaces/ICurvePool.sol";
import { IBooster } from "src/interfaces/IBooster.sol";

/// @title AuraWeightedPoolAdapterInputETHTest
/// @notice A contract for testing an ETH pegged Aura pool (WETH/rETH) with native ETH input from user using zapper
contract AuraWeightedPoolAdapterBaseTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    AuraWeightedPoolAdapter auraWeightedPoolAdapter;
    ETHZapper ethZapper;
    address public staker = makeAddr("staker");
    ///CONSTANTS
    address public UNDERLYING_ASSET;
    address public  AURA_BOOSTER;
    /// POOL CONSTANTS
    bytes32 public  BALANCER_WEIGHTED_POOL_ID;
    uint256 public  AURA_PID;

    string public  SALT;
    string public  STRATEGY_NAME;
    string public  TOKEN_NAME;

    uint256 public forkBlockNumber;
    uint256 public DEFAULT_FORK_BLOCK_NUMBER;
    uint256 public tokenDecimals;

    //// get swap quote from LIFI using a python script | this method lives on all tests
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
    //// get current block number using a python script that gets the latest number and substracts 10 blocks  | this
    // method lives on all tests

    function getBlockNumber() internal returns (uint256) {
        return DEFAULT_FORK_BLOCK_NUMBER;
    }

    //// setUp function that creates the adapter and adds it to the strategy
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
        address auraWeightedPoolAdapterImplementation = address(0);
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address AuraWeightedPoolAdapterImplementation = address(new AuraWeightedPoolAdapter());
        address AuraComposableWeightedPoolAdapterImplementation = address(0);
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        multiPoolStrategyFactory = new MultiPoolStrategyFactory(
            address(this),
            auraWeightedPoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraComposableWeightedPoolAdapterImplementation,
            address(proxyAdmin)
            );
        multiPoolStrategy = MultiPoolStrategy(
            multiPoolStrategyFactory.createMultiPoolStrategy(
                address(IERC20(UNDERLYING_ASSET)),  STRATEGY_NAME, TOKEN_NAME
            )
        );

        auraWeightedPoolAdapter = AuraWeightedPoolAdapter(
            multiPoolStrategyFactory.createAuraWeightedPoolAdapter(
                BALANCER_WEIGHTED_POOL_ID, address(multiPoolStrategy), AURA_PID
            )
        );
        multiPoolStrategy.addAdapter(address(auraWeightedPoolAdapter));
        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();
        // create and initialize the ETHzapper
        ethZapper = new ETHZapper();
        tokenDecimals = IERC20Metadata(UNDERLYING_ASSET).decimals();
        deal(UNDERLYING_ASSET, address(this), 10_000 * 10 ** tokenDecimals);
        deal(UNDERLYING_ASSET, staker, 50 * 10 ** tokenDecimals);
    }

    //// ensure deposit works by depositing 10k WETH and checking the stored assets
    function testETHDeposit() public {
        getBlockNumber();
        ethZapper.depositETH{ value: 10 * 10 ** tokenDecimals }(address(this), address(multiPoolStrategy));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssets, 10 * 10 ** tokenDecimals);
        assertEq(multiPoolStrategy.balanceOf(address(ethZapper)), 0);
        assertEq(multiPoolStrategy.balanceOf(address(this)), 10 * 10 ** tokenDecimals);
    }

    function testDeposit() public {
        getBlockNumber();
        IERC20(UNDERLYING_ASSET).approve(address(multiPoolStrategy), type(uint256).max);
        multiPoolStrategy.deposit(10_000 * 10 ** tokenDecimals, address(this));
        uint256 storedAssets = multiPoolStrategy.storedTotalAssets();
        assertEq(storedAssets, 10_000 * 10 ** tokenDecimals);
    }

    function testETHRedeem() public {
        //// deposit 5k WETH using this address
        uint256 depositAmount = 1 * 10 ** tokenDecimals;
        ethZapper.depositETH{ value: depositAmount }(address(this), address(multiPoolStrategy));
        /// adjust in 94% of the assets to the adapter
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterAdjustAmount = (depositAmount) * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraWeightedPoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraWeightedPoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        //// withdraw all shares using this contract as receiver should get same as put in
        uint256 underlyingBalanceInAdapterBeforeWithdraw = auraWeightedPoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 ETHBalanceOfThisBeforeRedeem = address(this).balance;
        //// need to approve shares to zapper so the zapper can spend the shares on behalf of this contract
        multiPoolStrategy.approve(address(ethZapper), 0);
        multiPoolStrategy.approve(address(ethZapper), shares);
        //// withdraw by shares (reedem)
        ethZapper.redeemETH(shares, address(this), 0, address(multiPoolStrategy));
        uint256 underlyingBalanceInAdapterAfterWithdraw = auraWeightedPoolAdapter.underlyingBalance();
        uint256 ETHBalanceOfThisAfterRedeem = address(this).balance;
        assertAlmostEq(underlyingBalanceInAdapterBeforeWithdraw, adapterAdjustAmount, adapterAdjustAmount * 2 / 100);
        assertEq(underlyingBalanceInAdapterAfterWithdraw, 0);
        assertAlmostEq(
            ETHBalanceOfThisAfterRedeem - ETHBalanceOfThisBeforeRedeem, depositAmount, depositAmount * 2 / 100
        );
    }

    function testETHWithdraw() public {
        // //// deposit 5k WETH using this address
        uint256 depositAmount = 500 * 10 ** tokenDecimals;
        ethZapper.depositETH{ value: depositAmount }(address(this), address(multiPoolStrategy));
        /// adjust in 94% of the assets to the adapter
        MultiPoolStrategy.Adjust[] memory adjustIns = new MultiPoolStrategy.Adjust[](1);
        uint256 adapterAdjustAmount = (depositAmount) * 94 / 100; // %94
        adjustIns[0] = MultiPoolStrategy.Adjust({
            adapter: address(auraWeightedPoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraWeightedPoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        //// withdraw all shares using this contract as receiver should get same as put in
        uint256 underlyingBalanceInAdapterBeforeWithdraw = auraWeightedPoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 ETHBalanceOfThisBeforeRedeem = address(this).balance;
        //// need to approve shares to zapper so the zapper can spend the shares on behalf of this contract
        multiPoolStrategy.approve(address(ethZapper), 0);
        multiPoolStrategy.approve(address(ethZapper), shares);
        //// withdraw by asset ( withdraw )
        uint256 assetstoWithdraw = multiPoolStrategy.previewRedeem(shares);
        ethZapper.withdrawETH(assetstoWithdraw, address(this), 0, address(multiPoolStrategy));
        uint256 underlyingBalanceInAdapterAfterWithdraw = auraWeightedPoolAdapter.underlyingBalance();
        uint256 ETHBalanceOfThisAfterRedeem = address(this).balance;
        assertAlmostEq(underlyingBalanceInAdapterBeforeWithdraw, adapterAdjustAmount, adapterAdjustAmount * 2 / 100);
        assertEq(underlyingBalanceInAdapterAfterWithdraw, 0);
        assertAlmostEq(
            ETHBalanceOfThisAfterRedeem - ETHBalanceOfThisBeforeRedeem, depositAmount, depositAmount * 2 / 100
        );
    }

    //// make this contract payable to use ETH methods
    receive() external payable { }
}
