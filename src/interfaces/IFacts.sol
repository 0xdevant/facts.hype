// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../types/DataTypes.sol";

import {IErrors} from "./IErrors.sol";
import {IEvents} from "./IEvents.sol";

interface IFacts is IErrors, IEvents {
    function ask(
        QuestionType questionType,
        string calldata description,
        address bountyToken,
        uint96 bountyAmount,
        uint96 startHuntAt,
        uint96 extraHuntTime
    ) external payable;
    function submit(uint256 questionId, bytes calldata encodedAnswer) external payable returns (uint16 answerId);
    function vouch(uint256 questionId, uint16 answerId) external payable;
    function challenge(uint256 questionId, bytes calldata encodedAnswer) external payable returns (uint16 answerId);

    function claim(uint256 questionId, bool asHunter) external;
    function withdraw(uint256[] memory questionIds, uint16[] memory answerIds, address recipient) external;

    function settle(uint256 questionId) external;
    function settle(uint256 questionId, uint16 selectedAnswerId, bool challengeSucceeded) external payable;
    function overrideSettlement(uint256 questionId, uint16 finalAnswerId) external;
    function finalize(uint256 questionId) external;

    function getAnswers(uint256 questionId) external view returns (Answer[] memory answers);
    function getAnswer(uint256 questionId, uint16 answerId)
        external
        view
        returns (address hunter, bytes memory encodedAnswer, uint256 totalVouched);
    function getNumOfQuestions() external view returns (uint256);
    function getNumOfAnswers(uint256 questionId) external view returns (uint256);
    function getUserData(address user, uint256 questionId, uint16 answerId)
        external
        view
        returns (uint128 deposited, uint128 hunterClaimable, uint248 vouched, bool claimed);
    function getMostVouchedAnsId(uint256 questionId) external view returns (uint16);

    function calcMinStakeToHunt(uint256 questionId) external view returns (uint256);
    function calcVouchedClaimable(uint256 questionId, address voucher, uint16 answerId, uint256 bountyAmount)
        external
        view
        returns (uint256);
    function calcSlashAmount(uint256 amount, uint64 slashBP) external view returns (uint256);

    function isWithinHuntPeriod(uint256 questionId) external view returns (bool);
    function isWithinChallengePeriod(uint256 questionId) external view returns (bool);
    function isWithinSettlePeriod(uint256 questionId) external view returns (bool);
    function isWithinReviewPeriod(uint256 questionId) external view returns (bool);
}
