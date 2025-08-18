// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../types/DataTypes.sol";

interface IFacts {
    error ZeroAddress();
    error InvalidConfig();
    error InvalidAnswerFormat(QuestionType questionType);
    error InvalidStartTime();
    error NotChallenged();
    error NotFinalized();
    error AlreadyFinalized();
    error AlreadySettledByDAO();
    error NotHunter();
    error EmptyOrRedeemedVouched();
    error NotInHuntPeriod();
    error NotInChallengePeriod();
    error NotInSettlePeriod();
    error NotInReviewPeriod();
    error CannotVouchForSelf();
    error CannotChallengeSelf();
    error CannotChallengeSameAnswer();
    error EmptyContent();
    error TooManyAnswers();
    error InsufficientBounty();
    error InsufficientVouched();
    error InsufficientDeposit();
    error OnlyCouncil();
    error OnlyDAO();
    error OnlyOwnerOrProtocolFeeReceiver();
    error OnlyAfterHuntPeriod();
    error OnlyAfterChallengePeriod();
    error OnlyAfterReviewPeriod();
    error OnlyWhenNotEngaging();
    error UnnecessaryChallenge();
    error ResetOutOfBound();

    event Asked(uint256 indexed questionId, address indexed seeker, address bountyToken, uint256 bountyAmount);
    event Submitted(uint256 indexed questionId, uint256 indexed answerId, address hunter);
    event Vouched(uint256 indexed questionId, uint256 indexed answerId, address vouchedBy, uint256 amount);

    event Challenged(uint256 indexed questionId, uint256 indexed answerId, address challenger);
    event Overridden(uint256 indexed questionId, uint256 indexed answerId);
    event Finalized(uint256 indexed questionId);

    event Claimed(uint256 indexed questionId, address claimer, uint256 claimAmount);
    event ClaimedPlatformFee(address indexed recipient);

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
}
