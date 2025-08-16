// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./shared/BaseTest.sol";
import {Constants} from "./Constants.sol";
import {IFacts} from "../src/interfaces/IFacts.sol";
import "../src/types/DataTypes.sol";

contract FactsTest is BaseTest {
    function test_initialState() public view {
        assertEq(facts.COUNCIL(), council);
        assertEq(facts.PROTOCOL_FEE_RECEIVER(), protocolFeeReceiver);
    }

    function test_ask_initialState() public {
        _askBinaryQuestion(asker);
        (
            ,
            address seeker,
            string memory description,
            address bountyToken,
            uint256 bountyAmount,
            SlotData memory slotData
        ) = facts.questions(0);
        assertEq(description, "Is the sky blue?");
        assertEq(seeker, asker);
        assertEq(bountyToken, address(0));
        assertEq(bountyAmount, Constants.DEFAULT_BOUNTY_AMOUNT);
        assertFalse(slotData.finalized);
        assertEq(slotData.answerId, 0);
        assertFalse(slotData.overridden);
        assertEq(slotData.overthrownAnswerId, 0);
        assertFalse(slotData.challengeSucceeded);
        assertFalse(slotData.challenged);
        assertEq(slotData.startHuntAt, uint96(block.timestamp));
        assertEq(slotData.endHuntAt, uint96(block.timestamp + Constants.DEFAULT_HUNT_PERIOD));
    }

    function test_submit() public asked {
        uint256 questionId = 0;
        vm.prank(hunter0);
        // submit yes
        vm.expectEmit();
        emit IFacts.Submitted(questionId, 0, hunter0);
        facts.submit(questionId, abi.encode(uint256(1)));

        uint256[] memory engagingQIds = facts.getUserEngagingQIds(hunter0);
        assertEq(engagingQIds.length, 1);
        assertEq(engagingQIds[0], questionId);
        (address hunter, bytes memory encodedAnswer, bool byChallenger, uint256 totalVouched) =
            facts.qidToAnswers(questionId, 0);
        assertEq(hunter, hunter0);
        assertEq(encodedAnswer, abi.encode(uint256(1)));
        assertFalse(byChallenger);
        assertEq(totalVouched, 0);
    }

    function test_vouch() public askedAndSubmitted {
        uint256 questionId = 0;
        uint16 answerId = 0;
        uint128 vouchAmount = Constants.DEFAULT_MIN_VOUCHED;

        vm.prank(voucher);
        vm.expectEmit();
        emit IFacts.Vouched(questionId, answerId, voucher, vouchAmount);
        facts.vouch{value: vouchAmount}(questionId, answerId);

        (, uint248 vouched,) = facts.getUserQuestionResult(voucher, questionId, answerId);
        assertEq(vouched, vouchAmount);
        (,, uint256 totalVouched) = facts.getAnswer(questionId, answerId);
        assertEq(totalVouched, vouchAmount);
    }

    function test_challenge() public askedAndSubmittedAndVouched {
        _warpToChallengePeriod();
        uint256 questionId = 0;

        uint256 challengerBalanceBefore = challenger.balance;
        // challenge with "no"
        uint16 answerId = _challenge(challenger, questionId, abi.encode(uint256(0)));
        uint256 challengerBalanceAfter = challenger.balance;

        // challenger need to become hunter to challenge
        assertEq(
            challengerBalanceAfter,
            challengerBalanceBefore - Constants.DEFAULT_CHALLENGE_DEPOSIT - Constants.DEFAULT_REQUIRED_STAKE_TO_HUNT
        );
        (,,,,, SlotData memory slotData) = facts.questions(0);
        assertTrue(slotData.challenged);
        (address hunter, bytes memory encodedAnswer,) = facts.getAnswer(questionId, answerId);
        assertEq(hunter, challenger);
        assertEq(encodedAnswer, abi.encode(uint256(0)));
    }

    function test_settle_withoutChallenge() public askedAndSubmitted {
        _warpToSettlePeriod();
        uint256 questionId = 0;

        // the last two params are not checked if challenge is not involved
        facts.settle(questionId, 0, false);

        (,,,,, SlotData memory slotData) = facts.questions(0);
        assertEq(slotData.finalized, true);
        assertEq(slotData.answerId, 0);

        // ensure bounty is distributed to hunter & protocol
        (uint256 hunterClaimable,,) = facts.getUserQuestionResult(hunter0, questionId, 0);
        assertEq(
            hunterClaimable, Constants.DEFAULT_BOUNTY_AMOUNT * Constants.DEFAULT_HUNTER_BP / Constants.BASIS_POINTS
        );
        (uint256 protocolFees,) = facts.getPlatformFees(questionId);
        assertEq(protocolFees, Constants.DEFAULT_BOUNTY_AMOUNT * Constants.DEFAULT_PROTOCOL_BP / Constants.BASIS_POINTS);
    }

    function test_settle_withChallenge() public askedAndSubmitted {
        _warpToChallengePeriod();
        uint256 questionId = 0;
        _challenge(challenger, questionId, abi.encode(uint256(0)));

        _warpToSettlePeriod();

        // settle as DAO
        _becomeDAO();
        facts.settle(questionId, 1, true);

        (,,,,, SlotData memory slotData) = facts.questions(0);
        assertFalse(slotData.finalized);
        assertEq(slotData.answerId, 1);
        assertEq(slotData.overthrownAnswerId, 0);
        assertTrue(slotData.challengeSucceeded);

        (uint256 protocolFees, uint256 daoFees) = facts.getPlatformFees(questionId);
        assertEq(protocolFees, Constants.DEFAULT_BOUNTY_AMOUNT / 2);
        assertEq(daoFees, Constants.DEFAULT_BOUNTY_AMOUNT / 2);
    }

    function test_overrideSettlement() public settleWithChallenge {
        _warpToReviewPeriod();
        uint256 questionId = 0;

        vm.prank(council);
        facts.overrideSettlement(questionId, 0);

        (,,,,, SlotData memory slotData) = facts.questions(questionId);
        assertFalse(slotData.finalized);
        assertEq(slotData.answerId, 0);
        assertTrue(slotData.overridden);
        assertFalse(slotData.challengeSucceeded);

        (uint256 protocolFees, uint256 daoFees) = facts.getPlatformFees(0);
        assertEq(protocolFees, 0);
        assertEq(daoFees, 0);
    }

    function test_finalize_AfterOverride_SlashDAO() public settleWithChallenge {
        _warpToReviewPeriod();
        uint256 questionId = 0;

        vm.prank(council);
        facts.overrideSettlement(questionId, 0);

        _warpToAfterReviewPeriod();
        uint256 depositedBefore = facts.usersInfo(address(this));
        facts.finalize(questionId);
        uint256 depositedAfter = facts.usersInfo(address(this));

        // slash owner i.e. DAO staked deposits
        uint248 slashAmount = uint248(depositedBefore * Constants.DEFAULT_SLASH_DAO_BP / Constants.BASIS_POINTS);
        assertEq(depositedAfter, depositedBefore - slashAmount);
        // challenger deposit is sent to protocol fee receiver as well
        assertEq(protocolFeeReceiver.balance, slashAmount + Constants.DEFAULT_CHALLENGE_DEPOSIT);
    }
}
