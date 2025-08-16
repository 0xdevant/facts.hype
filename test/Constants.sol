// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Constants {
    uint256 constant BASIS_POINTS = 10000;

    // test configs
    uint256 constant HUNT_START = 2;
    uint256 constant DEFAULT_REQUIRED_STAKE_TO_HUNT = 1e18;
    uint256 constant DEFAULT_REQUIRED_STAKE_FOR_DAO = 1000e18;
    uint256 constant DEFAULT_CHALLENGE_DEPOSIT = 100e18;
    uint128 constant DEFAULT_MIN_VOUCHED = 1e18;

    uint256 constant DEFAULT_HUNT_PERIOD = 24 * 60 * 60; // 24 hours
    uint256 constant DEFAULT_CHALLENGE_PERIOD = 72 * 60 * 60; // 72 hours
    uint256 constant DEFAULT_SETTLE_PERIOD = 24 * 60 * 60; // 24 hours
    uint256 constant DEFAULT_REVIEW_PERIOD = 24 * 60 * 60; // 24 hours

    uint256 constant DEFAULT_HUNTER_BP = 5500;
    uint256 constant DEFAULT_VOUCHER_BP = 3500;
    uint256 constant DEFAULT_PROTOCOL_BP = 1000;

    uint256 constant DEFAULT_SLASH_HUNTER_BP = 5000;
    uint256 constant DEFAULT_SLASH_VOUCHER_BP = 3000;
    uint256 constant DEFAULT_SLASH_DAO_BP = 3000;
    uint256 constant DEFAULT_DAO_OP_FEE_BP = 1000;

    uint256 constant INITIAL_SUPPLY = 1_000_000_000e18; // 1 billion
    uint256 constant DEFAULT_TOKEN_BALANCE = 100000e18;
    uint256 constant DEFAULT_BOUNTY_AMOUNT = 100e18;

    address constant DEFAULT_PROTOCOL_OWNER = 0x701F7fdfabd99DFC3c0b2B226fD379d4Be93DFf3;

    // testnet deployment configs
    uint256 constant TESTNET_REQUIRED_STAKE_TO_HUNT = 0.001e18;
    uint256 constant TESTNET_REQUIRED_STAKE_FOR_DAO = 0.01e18;
    uint256 constant TESTNET_CHALLENGE_DEPOSIT = 1e18;
    uint128 constant TESTNET_MIN_VOUCHED = 0.001e18;

    uint256 constant TESTNET_HUNT_PERIOD = 5 minutes;
    uint256 constant TESTNET_CHALLENGE_PERIOD = 5 minutes;
    uint256 constant TESTNET_SETTLE_PERIOD = 5 minutes;
    uint256 constant TESTNET_REVIEW_PERIOD = 5 minutes;
}
