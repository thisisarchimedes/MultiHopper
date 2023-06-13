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

error Unauthorized();
error StrategyPaused();

contract ETHZapper is Ownable {
    IMultiPoolStrategy public multipoolStrategy;

    constructor() { }

    function initialize(address _strategyAddress) public onlyOwner {
        multipoolStrategy = IMultiPoolStrategy(_strategyAddress);
    }

    function depositETH(uint256 assets, address receiver) public payable returns (uint256 shares) {
        if (multipoolStrategy.paused()) revert StrategyPaused();
        // wrap ether and then call deposit
        require(assets == msg.value, "ERC4626: ETH value mismatch");
        IWETH(payable(multipoolStrategy.asset())).deposit{ value: msg.value }();
        IERC20(multipoolStrategy.asset()).approve(address(multipoolStrategy), 0);
        IERC20(multipoolStrategy.asset()).approve(address(multipoolStrategy), assets);
        shares = multipoolStrategy.deposit(assets, address(this));
        multipoolStrategy.transfer(receiver, shares);
        return shares;
    }

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
        uint256 shares = multipoolStrategy.withdraw(assets, address(this), _owner, minimumReceive);
        IWETH(payable(multipoolStrategy.asset())).withdraw(assets);
        payable(address(receiver)).transfer(assets);
        return shares;
    }

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
        uint256 assets = multipoolStrategy.previewRedeem(shares);
        uint256 received = multipoolStrategy.redeem(shares, address(this), _owner, minimumReceive);
        IWETH(payable(multipoolStrategy.asset())).withdraw(assets);
        payable(address(receiver)).transfer(received);
        return received;
    }

    receive() external payable { }
}
