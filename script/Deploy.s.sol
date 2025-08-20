// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {Facts} from "../src/Facts.sol";
import "../src/types/DataTypes.sol";

import {Constants} from "../test/Constants.sol";

abstract contract DeployScript is Script {
    struct ScriptData {
        bool isTestnet;
        string explorerUrl;
        address protocolFeeReceiver;
        address council;
    }

    ScriptData public scriptData;

    function setUp() public virtual {}

    function run() public {
        require(scriptData.protocolFeeReceiver != address(0), "protocolFeeReceiver is not set");
        require(scriptData.council != address(0), "council is not set");

        console.log(unicode"🚀 Deploying on chain %s with sender %s...", vm.toString(block.chainid), msg.sender);

        vm.startBroadcast();

        Facts facts = new Facts(_getConfig(scriptData.isTestnet), scriptData.protocolFeeReceiver, scriptData.council);

        vm.stopBroadcast();

        console.log("Facts deployed to:", address(facts));

        string memory log = string.concat(
            "#  ",
            vm.toString(block.chainid),
            "\n",
            "| Contract | Address |\n",
            "|---|---|\n",
            "| Facts | ",
            _toMarkdownLink(scriptData.explorerUrl, address(facts))
        );

        vm.writeFile(string.concat("deployments/", vm.toString(block.chainid), ".md"), log);
    }

    function _getConfig(bool isTestnet) internal pure returns (Config memory) {
        return Config({
            systemConfig: SystemConfig({
                requiredStakeToHunt: uint128(
                    isTestnet ? Constants.TESTNET_REQUIRED_STAKE_TO_HUNT : Constants.DEFAULT_REQUIRED_STAKE_TO_HUNT
                ),
                requiredStakeForDAO: uint128(
                    isTestnet ? Constants.TESTNET_REQUIRED_STAKE_FOR_DAO : Constants.DEFAULT_REQUIRED_STAKE_FOR_DAO
                ),
                challengeDeposit: uint128(isTestnet ? Constants.TESTNET_CHALLENGE_DEPOSIT : Constants.DEFAULT_CHALLENGE_DEPOSIT),
                minVouched: uint128(isTestnet ? Constants.TESTNET_MIN_VOUCHED : Constants.DEFAULT_MIN_VOUCHED),
                huntPeriod: uint64(isTestnet ? Constants.TESTNET_HUNT_PERIOD : Constants.DEFAULT_HUNT_PERIOD),
                challengePeriod: uint64(isTestnet ? Constants.TESTNET_CHALLENGE_PERIOD : Constants.DEFAULT_CHALLENGE_PERIOD),
                settlePeriod: uint64(isTestnet ? Constants.TESTNET_SETTLE_PERIOD : Constants.DEFAULT_SETTLE_PERIOD),
                reviewPeriod: uint64(isTestnet ? Constants.TESTNET_REVIEW_PERIOD : Constants.DEFAULT_REVIEW_PERIOD)
            }),
            distributionConfig: BountyDistributionConfig({
                hunterBP: uint64(Constants.DEFAULT_HUNTER_BP),
                voucherBP: uint64(Constants.DEFAULT_VOUCHER_BP),
                protocolBP: uint64(Constants.DEFAULT_PROTOCOL_BP)
            }),
            challengeConfig: ChallengeConfig({
                slashHunterBP: uint64(Constants.DEFAULT_SLASH_HUNTER_BP),
                slashVoucherBP: uint64(Constants.DEFAULT_SLASH_VOUCHER_BP),
                slashDaoBP: uint64(Constants.DEFAULT_SLASH_DAO_BP),
                daoOpFeeBP: uint64(Constants.DEFAULT_DAO_OP_FEE_BP)
            })
        });
    }

    function _toMarkdownLink(string memory explorerUrl, address contractAddress)
        internal
        pure
        returns (string memory)
    {
        return string.concat("[", vm.toString(contractAddress), "](", explorerUrl, vm.toString(contractAddress), ")");
    }
}
