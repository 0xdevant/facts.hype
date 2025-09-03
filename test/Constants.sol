// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library Constants {
    uint256 constant BASIS_POINTS = 10000;

    // test configs
    uint256 constant HUNT_START = 2;
    uint256 constant CHALLENGE_START = HUNT_START + DEFAULT_HUNT_PERIOD;
    uint256 constant SETTLE_START = CHALLENGE_START + DEFAULT_CHALLENGE_PERIOD;
    uint256 constant REVIEW_START = SETTLE_START + DEFAULT_SETTLE_PERIOD;

    uint256 constant INITIAL_SUPPLY = 1_000_000_000e18; // 1 billion
    uint256 constant DEFAULT_TOKEN_BALANCE = 100000e18;
    uint256 constant DEFAULT_BOUNTY_AMOUNT = 100e18;

    // deployment configs
    uint256 constant DEFAULT_MIN_STAKE_OF_NATIVE_BOUNTY_TO_HUNT_BP = 5000;
    uint256 constant DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO = 1000e18;
    uint128 constant DEFAULT_MIN_VOUCHED = 1e18;
    uint256 constant DEFAULT_CHALLENGE_FEE = 100e18;

    uint256 constant DEFAULT_HUNT_PERIOD = 24 * 60 * 60; // 24 hours
    uint256 constant DEFAULT_CHALLENGE_PERIOD = 72 * 60 * 60; // 72 hours
    uint256 constant DEFAULT_SETTLE_PERIOD = 24 * 60 * 60; // 24 hours
    uint256 constant DEFAULT_REVIEW_PERIOD = 24 * 60 * 60; // 24 hours

    uint256 constant DEFAULT_HUNTER_BP = 5500;
    uint256 constant DEFAULT_VOUCHER_BP = 3500;
    uint256 constant DEFAULT_PROTOCOL_BP = BASIS_POINTS - DEFAULT_HUNTER_BP - DEFAULT_VOUCHER_BP;

    uint256 constant DEFAULT_SLASH_HUNTER_BP = 5000;
    uint256 constant DEFAULT_SLASH_VOUCHER_BP = 3000;
    uint256 constant DEFAULT_SLASH_DAO_BP = 3000;
    uint256 constant DEFAULT_DAO_OP_FEE_BP = 1000;

    // testnet deployment configs
    uint256 constant TESTNET_MIN_STAKE_TO_SETTLE_AS_DAO = 0.01e18;
    uint256 constant TESTNET_CHALLENGE_FEE = 1e18;
    uint128 constant TESTNET_MIN_VOUCHED = 0.001e18;

    uint256 constant TESTNET_HUNT_PERIOD = 15 minutes;
    uint256 constant TESTNET_CHALLENGE_PERIOD = 15 minutes;
    uint256 constant TESTNET_SETTLE_PERIOD = 15 minutes;
    uint256 constant TESTNET_REVIEW_PERIOD = 15 minutes;
}
