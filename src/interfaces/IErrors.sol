// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {QuestionType} from "../types/DataTypes.sol";

interface IErrors {
    error InvalidConfig();
    error InvalidAnsFormat(QuestionType questionType);
    error InvalidStartTime();
    error AlreadyFinalized();
    error AlreadySettledByDAO();
    error CannotVouchWhenOneAns();
    error CannotVouchForSelf();
    error CannotChallengeSelf();
    error CannotChallengeSameAns();
    error CannotDirectSettle();
    error EmptyContent();
    error TooManyAns();
    error InsufficientBounty();
    error InsufficientVouched();
    error InsufficientDeposit();
    error InsufficientChallengeFee();
    error NoDirectTransfer();
    error NotChallenged();
    error NotFinalized();
    error NotInHuntPeriod();
    error NotInChallengePeriod();
    error NotInSettlePeriod();
    error NotInReviewPeriod();
    error OnlyAfterHuntPeriod();
    error OnlyAfterChallengePeriod();
    error OnlyAfterReviewPeriod();
    error OnlyCouncil();
    error OnlyOwnerOrFeeReceiver();
    error NotEligibleToHunt();
    error NotEligibleToSettleChallenge();
    error UnnecessaryChallenge();
    error ArrayMismatch();
}
