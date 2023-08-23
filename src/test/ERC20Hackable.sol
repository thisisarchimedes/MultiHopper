// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { ERC20 } from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import { IZapper } from "../../src/interfaces/IZapper.sol";

contract ERC20Hackable is ERC20("Hackable", "HACK") {
    IZapper public zapper;
    address public strategyAddress;

    constructor(IZapper _zapper, address _strategyAddress) {
        zapper = _zapper;
        strategyAddress = _strategyAddress;

        _mint(msg.sender, 100 ether);
    }

    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // invoke reentrancy attack
        zapper.deposit(amount, address(this), 0, msg.sender, strategyAddress);

        return super.transferFrom(from, to, amount);
    }
}
