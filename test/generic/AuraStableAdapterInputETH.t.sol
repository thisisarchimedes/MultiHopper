// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity >=0.8.19 <0.9.0;

import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20Metadata } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { ProxyAdmin } from "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import { MultiPoolStrategyFactory } from "../../src/MultiPoolStrategyFactory.sol";
import { IBaseRewardPool } from "../../src/interfaces/IBaseRewardPool.sol";
import { ETHZapper } from "../../src/ETHZapper.sol";
import { MultiPoolStrategy } from "../../src/MultiPoolStrategy.sol";
import { AuraStablePoolAdapter } from "../../src/AuraStablePoolAdapter.sol";
import { ICurveBasePool } from "../../src/interfaces/ICurvePool.sol";
import { IBooster } from "../../src/interfaces/IBooster.sol";

/// @title AuraStablePoolAdapterInputETHTest
/// @notice A contract for testing an ETH pegged Aura pool (WETH/rETH) with native ETH input from user using zapper
contract AuraStablePoolAdapterInputETHTest is PRBTest, StdCheats {
    MultiPoolStrategyFactory multiPoolStrategyFactory;
    MultiPoolStrategy multiPoolStrategy;
    AuraStablePoolAdapter auraStablePoolAdapter;
    ETHZapper ethZapper;
    address public staker = makeAddr("staker");
    ///CONSTANTS
    address constant UNDERLYING_ASSET = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //strategy underlying asset such as
        // WETH,USDC,DAI,USDT etc.
    address public constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    /// POOL CONSTANTS
    bytes32 public constant BALANCER_STABLE_POOL_ID = 0xb08885e6026bab4333a80024ec25a1a3e1ff2b8a000200000000000000000445;
    uint256 public constant AURA_PID = 63;

    uint256 forkBlockNumber;
    uint256 DEFAULT_FORK_BLOCK_NUMBER = 17_421_496;
    uint256 tokenDecimals;

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
        address auraStablePoolAdapterImplementation = address(0);
        address MultiPoolStrategyImplementation = address(new MultiPoolStrategy());
        address AuraWeightedPoolAdapterImplementation = address(0);
        address AuraStablePoolAdapterImplementation = address(new AuraStablePoolAdapter());
        address AuraComposableStablePoolAdapterImplementation = address(0);
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        multiPoolStrategyFactory = new MultiPoolStrategyFactory(
            address(this),
            auraStablePoolAdapterImplementation,
            MultiPoolStrategyImplementation,
            AuraWeightedPoolAdapterImplementation,
            AuraStablePoolAdapterImplementation,
            AuraComposableStablePoolAdapterImplementation,
            address(proxyAdmin)
            );
        multiPoolStrategy =
            MultiPoolStrategy(multiPoolStrategyFactory.createMultiPoolStrategy(UNDERLYING_ASSET, "ETHX", "ethx"));
        auraStablePoolAdapter = AuraStablePoolAdapter(
            multiPoolStrategyFactory.createAuraStablePoolAdapter(
                BALANCER_STABLE_POOL_ID, address(multiPoolStrategy), AURA_PID
            )
        );
        multiPoolStrategy.addAdapter(address(auraStablePoolAdapter));
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
            adapter: address(auraStablePoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraStablePoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        //// withdraw all shares using this contract as receiver should get same as put in
        uint256 underlyingBalanceInAdapterBeforeWithdraw = auraStablePoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 ETHBalanceOfThisBeforeRedeem = address(this).balance;
        //// need to approve shares to zapper so the zapper can spend the shares on behalf of this contract
        multiPoolStrategy.approve(address(ethZapper), 0);
        multiPoolStrategy.approve(address(ethZapper), shares);
        //// withdraw by shares (reedem)
        ethZapper.redeemETH(shares, address(this), 0, address(multiPoolStrategy));
        uint256 underlyingBalanceInAdapterAfterWithdraw = auraStablePoolAdapter.underlyingBalance();
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
            adapter: address(auraStablePoolAdapter),
            amount: adapterAdjustAmount,
            minReceive: 0
        });
        MultiPoolStrategy.Adjust[] memory adjustOuts;
        address[] memory adapters = new address[](1);
        adapters[0] = address(auraStablePoolAdapter);
        multiPoolStrategy.adjust(adjustIns, adjustOuts, adapters);
        //// withdraw all shares using this contract as receiver should get same as put in
        uint256 underlyingBalanceInAdapterBeforeWithdraw = auraStablePoolAdapter.underlyingBalance();
        uint256 shares = multiPoolStrategy.balanceOf(address(this));
        uint256 ETHBalanceOfThisBeforeRedeem = address(this).balance;
        //// need to approve shares to zapper so the zapper can spend the shares on behalf of this contract
        multiPoolStrategy.approve(address(ethZapper), 0);
        multiPoolStrategy.approve(address(ethZapper), shares);
        //// withdraw by asset ( withdraw )
        uint256 assetstoWithdraw = multiPoolStrategy.previewRedeem(shares);
        ethZapper.withdrawETH(assetstoWithdraw, address(this), 0, address(multiPoolStrategy));
        uint256 underlyingBalanceInAdapterAfterWithdraw = auraStablePoolAdapter.underlyingBalance();
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
