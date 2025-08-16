// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {DeployScript} from "./Deploy.s.sol";

contract DeployTestnetScript is DeployScript {
    function setUp() public override {
        scriptData.protocolFeeReceiver = 0x701F7fdfabd99DFC3c0b2B226fD379d4Be93DFf3;
        scriptData.council = 0x08B9b5291a02ABC630995f6C9aE3eB2A252F908C;
        scriptData.explorerUrl = "https://testnet.purrsec.com/address/";
    }
}
