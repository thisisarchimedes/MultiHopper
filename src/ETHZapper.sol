pragma solidity ^0.8.10;

import {
    ICurveBasePool,
    IPool2,
    IPool3,
    IPool4,
    IPool5,
    IPoolFactory2,
    IPoolFactory3,
    IPoolFactory4,
    IPoolFactory5,
    ICurveMetaPool
} from "./interfaces/ICurvePool.sol";
import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { IBaseRewardPool } from "./interfaces/IBaseRewardPool.sol";
import { IERC20 } from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import { IBooster } from "./interfaces/IBooster.sol";
import { WETH as IWETH } from "solmate/tokens/WETH.sol";
import { MultiPoolStrategy as IMultiPoolStrategy } from "./MultiPoolStrategy.sol";
import { Ownable } from "openzeppelin-contracts/access/Ownable.sol";
//// ERRRORS

error StrategyPaused();
/**
 * @title ETHZapper
 * @dev This contract allows users to deposit, withdraw, and redeem into a MultiPoolStrategy contract using native ETH.
 * It wraps ETH into WETH and interacts with the MultiPoolStrategy contract to perform the operations.
 */

contract ETHZapper is Ownable {
    IMultiPoolStrategy public multipoolStrategy;

    constructor() { }
    /**
     * @dev Initializes the contract with the address of the MultiPoolStrategy contract.
     * @param _strategyAddress The address of the MultiPoolStrategy contract to use.
     */

    function initialize(address _strategyAddress) public onlyOwner {
        multipoolStrategy = IMultiPoolStrategy(_strategyAddress);
    }

    /**
     * @dev Deposits ETH into the MultiPoolStrategy contract.
     * @param assets The amount of ETH to deposit must match msg.value.
     * @param receiver The address to receive the shares.
     * @return shares The amount of shares received.
     */
    function depositETH(uint256 assets, address receiver) public payable returns (uint256 shares) {
        if (multipoolStrategy.paused()) revert StrategyPaused();
        require(assets == msg.value, "ERC4626: ETH value mismatch");
        // wrap ether and then call deposit
        IWETH(payable(multipoolStrategy.asset())).deposit{ value: msg.value }();
        //// we need to approve the strategy to spend our WETH
        IERC20(multipoolStrategy.asset()).approve(address(multipoolStrategy), 0);
        IERC20(multipoolStrategy.asset()).approve(address(multipoolStrategy), assets);
        shares = multipoolStrategy.deposit(assets, address(this));
        multipoolStrategy.transfer(receiver, shares);
        return shares;
    }
    /**
     * @dev Withdraws native ETH from the MultiPoolStrategy contract by assets.
     * @param assets The amount of ETH to withdraw.
     * @param receiver The address to receive the withdrawn native ETH.
     * @param _owner The owner's address for withdrawal.
     * @param minimumReceive The minimum amount of ETH to receive.
     * @return The amount of shares burned.
     * @notice to run this function user needs to approve the zapper to spend strategy token (shares)
     */

    function withdrawETH(
        uint256 assets,
        address receiver,
        address _owner,
        uint256 minimumReceive
    )
        public
        returns (uint256)
    {
        require(assets <= multipoolStrategy.maxWithdraw(_owner), "ERC4626: withdraw more than max");
        /// withdraw from strategy and get WETH
        uint256 shares = multipoolStrategy.withdraw(assets, address(this), _owner, minimumReceive);
        /// unwrap WETH to ETH and send to receiver
        IWETH(payable(multipoolStrategy.asset())).withdraw(assets);
        payable(address(receiver)).transfer(assets);
        return shares;
    }
    /**
     * @dev Withdraws native ETH from the MultiPoolStrategy contract by shares (redeem).
     * @param shares The amount of shares to redeem.
     * @param receiver The address to receive the redeemed ETH.
     * @param _owner The owner's address for redemption.
     * @param minimumReceive The minimum amount of ETH to receive.
     * @return The amount of redeemed ETH received.
     * @notice to run this function user needs to approve the zapper to spend strategy token (shares)
     */

    function redeemETH(
        uint256 shares,
        address receiver,
        address _owner,
        uint256 minimumReceive
    )
        public
        returns (uint256)
    {
        require(shares <= multipoolStrategy.maxRedeem(_owner), "ERC4626: redeem more than max");
        // redeem shares and get WETH from strategy
        uint256 received = multipoolStrategy.redeem(shares, address(this), _owner, minimumReceive);
        // unwrap WETH to ETH and send to receiver
        IWETH(payable(multipoolStrategy.asset())).withdraw(received);
        payable(address(receiver)).transfer(received);
        return received;
    }

    receive() external payable { }
}
