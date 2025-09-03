// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TestERC20 is ERC20 {
    constructor(address account) ERC20("TestERC20", "TEST") {
        _mint(account, 100000e18);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
