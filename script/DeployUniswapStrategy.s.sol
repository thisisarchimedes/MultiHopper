// SPDX-License-Identifier: UNLICENSED
/* solhint-disable */

pragma solidity ^0.8.19.0;

import { BaseScript } from "script/Base.s.sol";
import "forge-std/Script.sol";
import { UniswapV3Strategy } from "src/UniswapV3Strategy.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TransparentUpgradeableProxy } from "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { console2 } from "forge-std/console2.sol";
/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting

/**
 * @title Deploy
 *
 * @dev A contract for deploying the UniswapV3 Strategy contract
 * @notice we do this in its own script because of the size of the contract and the gas spent
 *
 */
contract DeployUniswapStrategy is Script {
    address MONITOR = address(0); // TODO : set monitor address before deploy
    address deployerPrivateKey = vm.rememberKey(vm.envUint("PRIVATE_KEY")); // mainnet deployer private key
    IUniswapV3Pool public constant WETH_WBTC_POOL = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address feeRecipient = address(0x93B435e55881Ea20cBBAaE00eaEdAf7Ce366BeF2);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        address proxyAdmin = address(0x6e43eE4FE4Bf848211D0b04e8aA61C980DcdFF19);
        (int24 lowerTick, int24 upperTick,) = chooseTicks(95, 105);
        bytes memory initData = abi.encodeWithSelector(
            UniswapV3Strategy.initialize.selector, WETH_WBTC_POOL, lowerTick, upperTick, WETH, feeRecipient
        );
        UniswapV3Strategy uniswapV3Strategy = new UniswapV3Strategy();
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(uniswapV3Strategy), address(proxyAdmin), initData);

        vm.stopBroadcast();
    }

    function chooseTicks(int24 lowerPercentile, int24 upperPercentile) public view returns (int24, int24, int24) {
        (, int24 tick,,,,,) = WETH_WBTC_POOL.slot0();
        int24 tickSpacing = WETH_WBTC_POOL.tickSpacing();
        int24 lowerTick = (int24(int128(tick) * lowerPercentile / 100)) / tickSpacing * tickSpacing;
        int24 upperTick = (int24(int128(tick) * upperPercentile / 100)) / tickSpacing * tickSpacing;
        return (lowerTick, upperTick, tick);
    }
}
