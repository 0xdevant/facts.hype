// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEvents {
    event Asked(uint256 indexed questionId, address indexed seeker, address bountyToken, uint96 bountyAmount);
    event Submitted(uint256 indexed questionId, uint16 indexed answerId, address hunter);
    event Vouched(uint256 indexed questionId, uint16 indexed answerId, address vouchedBy, uint256 amount);

    event Challenged(uint256 indexed questionId, uint256 indexed answerId, address challenger);
    event Settle(uint256 indexed questionId);
    event SettleByDAO(uint256 indexed questionId, uint16 indexed selectedAnswerId, bool challengeSucceeded);
    event Overridden(uint256 indexed questionId, uint256 indexed finalAnswerId);
    event Finalized(uint256 indexed questionId);

    event Claimed(uint256 indexed questionId, address claimer, uint256 claimAmount);
    event ClaimedPlatformFee(address indexed recipient);

    event Withdrawn(address indexed user, uint256 amount);
}
