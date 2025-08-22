// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../types/DataTypes.sol";

interface IFacts {
    error InvalidConfig();
    error InvalidAnsFormat(QuestionType questionType);
    error InvalidStartTime();
    error NotChallenged();
    error NotFinalized();
    error AlreadyFinalized();
    error AlreadySettledByDAO();
    error EmptyOrRedeemedVouched();
    error NotInHuntPeriod();
    error NotInChallengePeriod();
    error NotInSettlePeriod();
    error NotInReviewPeriod();
    error CannotVouchWhenOneAns();
    error CannotVouchForSelf();
    error CannotChallengeSelf();
    error CannotChallengeSameAns();
    error EmptyContent();
    error TooManyAns();
    error InsufficientBounty();
    error InsufficientVouched();
    error InsufficientDeposit();
    error OnlyHunter();
    error OnlyCouncil();
    error OnlyDAO();
    error OnlyOwnerOrFeeReceiver();
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
    event Overridden(uint256 indexed questionId, uint256 indexed finalAnswerId);
    event Finalized(uint256 indexed questionId);

    event Claimed(uint256 indexed questionId, address claimer, uint256 claimAmount);
    event ClaimedPlatformFee(address indexed recipient);

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function ask(
        QuestionType questionType,
        string calldata description,
        address bountyToken,
        uint256 bountyAmount,
        uint96 startHuntAt,
        uint96 extraHuntTime
    ) external payable;
    function submit(uint256 questionId, bytes calldata encodedAnswer) external returns (uint16 answerId);
    function vouch(uint256 questionId, uint16 answerId) external payable;
    function challenge(uint256 questionId, bytes calldata encodedAnswer) external payable returns (uint16 answerId);

    function claim(uint256 questionId, bool asHunter) external;
    function redeem(uint256 questionId, uint16 answerId) external;
    function deposit() external payable;
    function reset(uint256 numOfIds) external;
    function withdraw(address recipient) external;

    function settle(uint256 questionId, uint16 selectedAnswerId, bool challengeSucceeded) external;
    function overrideSettlement(uint256 questionId, uint16 finalAnswerId) external;
    function finalize(uint256 questionId) external;

    function getAnswers(uint256 questionId) external view returns (Answer[] memory answers);
    function getAnswer(uint256 questionId, uint16 answerId)
        external
        view
        returns (address hunter, bytes memory encodedAnswer, uint256 totalVouched);
    function getNumOfQuestions() external view returns (uint256);
    function getNumOfAnswers(uint256 questionId) external view returns (uint256);
    function getUserEngagingQIds(address user) external view returns (uint256[] memory questionIds);
    function getUserQuestionResult(address user, uint256 questionId, uint16 answerId)
        external
        view
        returns (uint256 hunterClaimable, uint248 vouched, bool claimed);
    function getMostVouchedAnsId(uint256 questionId) external view returns (uint16);

    function calcVouchedClaimable(uint256 questionId, address voucher, uint16 answerId, uint256 bountyAmount)
        external
        view
        returns (uint256);
    function calcSlashAmount(uint256 amount, uint64 slashBP) external view returns (uint256);

    function isHunter(address user) external view returns (bool);
    function isDAO(address user) external view returns (bool);
    function isWithinHuntPeriod(uint256 questionId) external view returns (bool);
    function isWithinChallengePeriod(uint256 questionId) external view returns (bool);
    function isWithinSettlePeriod(uint256 questionId) external view returns (bool);
    function isWithinReviewPeriod(uint256 questionId) external view returns (bool);
}
