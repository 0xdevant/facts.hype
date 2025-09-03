// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console} from "forge-std/console.sol";
import {BaseTest} from "./shared/BaseTest.sol";
import {Constants} from "./Constants.sol";
import {IErrors, IEvents} from "../src/interfaces/IFacts.sol";
import "../src/types/DataTypes.sol";

contract FactsTest is BaseTest {
    function test_initialState() public view {
        assertEq(facts.COUNCIL(), council);
        assertEq(facts.PROTOCOL_FEE_RECEIVER(), protocolFeeReceiver);
    }

    function test_receive_RevertWhenNoDirectTransfer() public {
        vm.expectRevert(IErrors.NoDirectTransfer.selector);
        (bool success,) = address(facts).call{value: 100}("");
        assertTrue(success);
    }

    function test_ask() public {
        vm.expectEmit();
        emit IEvents.Asked(0, asker, address(0), uint96(Constants.DEFAULT_BOUNTY_AMOUNT));
        _askBinaryQuestion(asker, true);

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

    function test_ask_RevertWhenEmptyDescription() public {
        vm.expectRevert(IErrors.EmptyContent.selector);
        facts.ask(QuestionType.Binary, "", address(0), 0, uint96(block.timestamp), 0);
    }

    function test_ask_RevertWhenInvalidStartTime() public {
        vm.expectRevert(IErrors.InvalidStartTime.selector);
        facts.ask(QuestionType.Binary, "Is the sky blue?", address(0), 0, uint96(block.timestamp - 1), 0);
    }

    function test_ask_RevertWhenInsufficientBounty() public {
        vm.expectRevert(IErrors.InsufficientBounty.selector);
        facts.ask{value: 0}(QuestionType.Binary, "Is the sky blue?", address(0), 1, uint96(block.timestamp), 0);
    }

    function test_submit() public asked {
        uint256 questionId = 0;
        vm.startPrank(hunter0);
        // submit yes
        vm.expectEmit();
        emit IEvents.Submitted(questionId, 0, hunter0);
        facts.submit{value: facts.calcMinStakeToHunt(questionId)}(questionId, abi.encode(uint256(1)));
        vm.stopPrank();

        (address hunter, bytes memory encodedAnswer, bool byChallenger, uint256 totalVouched) =
            facts.qidToAnswers(questionId, 0);
        assertEq(hunter, hunter0);
        assertEq(encodedAnswer, abi.encode(uint256(1)));
        assertFalse(byChallenger);
        assertEq(totalVouched, 0);
    }

    function test_submit_RevertWhenInsufficientDeposit() public asked {
        vm.startPrank(hunter0);
        vm.expectRevert(IErrors.InsufficientDeposit.selector);
        facts.submit{value: 0}(0, abi.encode(uint256(1)));
        vm.stopPrank();
    }

    function test_submit_RevertWhenNotInHuntPeriod() public asked {
        uint256 minStakeToHunt = facts.calcMinStakeToHunt(0);
        _warpToChallengePeriod();
        vm.prank(hunter0);
        vm.expectRevert(IErrors.NotInHuntPeriod.selector);
        facts.submit{value: minStakeToHunt}(0, abi.encode(uint256(1)));
    }

    function test_submit_RevertWhenInvalidAnswerFormat() public asked {
        uint256 minStakeToHunt = facts.calcMinStakeToHunt(0);
        vm.prank(hunter0);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InvalidAnsFormat.selector, QuestionType.Binary));
        facts.submit{value: minStakeToHunt}(0, abi.encode(uint256(3)));
    }

    function test_submit_RevertWhenTooManyAns() public asked {
        uint256 minStakeToHunt = facts.calcMinStakeToHunt(0);
        for (uint256 i = 0; i < 254; i++) {
            facts.submit{value: minStakeToHunt}(0, abi.encode(uint256(1)));
        }

        vm.prank(hunter0);
        vm.expectRevert(IErrors.TooManyAns.selector);
        facts.submit{value: minStakeToHunt}(0, abi.encode(uint256(1)));
    }

    function test_vouch() public askedAndSubmitted {
        uint256 questionId = 0;
        uint16 answerId = 0;
        uint128 vouchAmount = Constants.DEFAULT_MIN_VOUCHED;

        // submit another answer
        _submit(hunter1, 0, false);

        vm.prank(voucher0);
        vm.expectEmit();
        emit IEvents.Vouched(questionId, answerId, voucher0, vouchAmount);
        facts.vouch{value: vouchAmount}(questionId, answerId);

        (,, uint248 vouched,) = facts.getUserData(voucher0, questionId, answerId);
        assertEq(vouched, vouchAmount);
        (,, uint256 totalVouched,) = facts.getUserData(voucher0, questionId, answerId);
        assertEq(totalVouched, vouchAmount);
    }

    function test_vouch_RevertWhenNotInHuntPeriod() public askedAndSubmitted {
        _warpToChallengePeriod();
        vm.expectRevert(IErrors.NotInHuntPeriod.selector);
        facts.vouch{value: Constants.DEFAULT_MIN_VOUCHED}(0, 0);
    }

    function test_vouch_RevertWhenInsufficientBounty() public {
        facts.ask(QuestionType.Binary, "Is the sky blue?", address(0), 0, uint96(block.timestamp), 0);
        _warpToHuntPeriod();
        vm.expectRevert(IErrors.InsufficientBounty.selector);
        facts.vouch{value: Constants.DEFAULT_MIN_VOUCHED}(0, 0);
    }

    function test_vouch_RevertWhenCannotVouchWhenOneAns() public asked {
        vm.expectRevert(IErrors.CannotVouchWhenOneAns.selector);
        facts.vouch{value: Constants.DEFAULT_MIN_VOUCHED}(0, 0);
    }

    function test_vouch_RevertWhenInsufficientVouched() public askedAndSubmitted {
        vm.expectRevert(IErrors.InsufficientVouched.selector);
        facts.vouch(0, 0);
    }

    function test_vouch_RevertWhenCannotVouchForSelf() public askedAndSubmitted {
        // submit another answer
        _submit(hunter1, 0, false);

        vm.prank(hunter0);
        vm.expectRevert(IErrors.CannotVouchForSelf.selector);
        facts.vouch{value: Constants.DEFAULT_MIN_VOUCHED}(0, 0);
    }

    function test_claim_asHunter() public settleWithoutChallenge {
        uint256 hunterBalanceBefore = hunter0.balance;
        (, uint256 hunterClaimable,,) = facts.getUserData(hunter0, 0, 0);
        assertEq(
            hunterClaimable, Constants.DEFAULT_BOUNTY_AMOUNT * Constants.DEFAULT_HUNTER_BP / Constants.BASIS_POINTS
        );

        vm.prank(hunter0);
        vm.expectEmit();
        emit IEvents.Claimed(
            0, hunter0, Constants.DEFAULT_BOUNTY_AMOUNT * Constants.DEFAULT_HUNTER_BP / Constants.BASIS_POINTS
        );
        facts.claim(0, true);

        assertEq(hunter0.balance, hunterBalanceBefore + hunterClaimable);
    }

    function test_claim_asVoucher() public settleWithoutChallenge {
        uint256 voucherBalanceBefore = voucher0.balance;
        uint256 voucherClaimable = facts.calcVouchedClaimable(0, voucher0, 0, Constants.DEFAULT_BOUNTY_AMOUNT);

        vm.startPrank(voucher0);
        vm.expectEmit();
        emit IEvents.Claimed(0, voucher0, voucherClaimable);
        facts.claim(0, false);
        vm.stopPrank();
        (,, uint248 vouched, bool claimed) = facts.getUserData(voucher0, 0, 0);

        assertEq(voucher0.balance, voucherBalanceBefore + voucherClaimable);
        assertEq(vouched, Constants.DEFAULT_MIN_VOUCHED * 2);
        assertTrue(claimed);
    }

    function test_claim_RevertWhenNotFinalized() public askedAndSubmitted {
        vm.expectRevert(IErrors.NotFinalized.selector);
        facts.claim(0, false);
    }

    function test_withdraw_onlyClaimDepositedStake() public settleWithoutChallenge {
        uint256[] memory questionIds = new uint256[](1);
        uint16[] memory answerIds = new uint16[](0);
        questionIds[0] = 0;
        uint256 hunterBalanceBefore = hunter0.balance;

        vm.prank(hunter0);
        facts.withdraw(questionIds, answerIds, hunter0);

        (uint256 deposited,,,) = facts.getUserData(hunter0, 0, 0);
        assertEq(deposited, 0);
        assertEq(hunter0.balance, hunterBalanceBefore + facts.calcMinStakeToHunt(0));
    }

    function test_withdraw_onlyClaimVouchedStake() public settleWithoutChallenge {
        uint256[] memory questionIds = new uint256[](1);
        uint16[] memory answerIds = new uint16[](1);
        questionIds[0] = 0;
        answerIds[0] = 0;
        uint256 voucherBalanceBefore = voucher0.balance;

        vm.prank(voucher0);
        facts.withdraw(questionIds, answerIds, voucher0);

        (,, uint248 vouched,) = facts.getUserData(voucher0, 0, 0);
        assertEq(vouched, 0);
        assertEq(voucher0.balance, voucherBalanceBefore + Constants.DEFAULT_MIN_VOUCHED * 2);
    }

    function test_challenge() public askedAndSubmittedAndVouched {
        _warpToChallengePeriod();
        uint256 questionId = 0;

        uint256 challengerBalanceBefore = challenger.balance;
        // challenge with "no"
        uint16 answerId = _challenge(challenger, questionId, abi.encode(uint256(0)));
        uint256 challengerBalanceAfter = challenger.balance;

        // challenger need to become hunter to challenge
        assertEq(challengerBalanceAfter, challengerBalanceBefore - Constants.DEFAULT_CHALLENGE_FEE);
        (,,,,, SlotData memory slotData) = facts.questions(0);
        assertTrue(slotData.challenged);
        (address hunter, bytes memory encodedAnswer,) = facts.getAnswer(questionId, answerId);
        assertEq(hunter, challenger);
        assertEq(encodedAnswer, abi.encode(uint256(0)));
    }

    function test_challenge_RevertWhenNotInChallengePeriod() public askedAndSubmittedAndVouched {
        vm.expectRevert(IErrors.NotInChallengePeriod.selector);
        _challenge(challenger, 0, abi.encode(uint256(0)));
    }

    function test_challenge_RevertWhenInsufficientChallengeFee() public askedAndSubmittedAndVouched {
        _warpToChallengePeriod();
        vm.expectRevert(IErrors.InsufficientChallengeFee.selector);
        facts.challenge{value: 0}(0, abi.encode(uint256(0)));
    }

    function test_settle_withoutChallenge() public askedAndSubmitted {
        _warpToSettlePeriod();
        uint256 questionId = 0;

        facts.settle(questionId);

        (,,,,, SlotData memory slotData) = facts.questions(0);
        assertEq(slotData.finalized, true);
        assertEq(slotData.answerId, 0);

        // ensure bounty is distributed to hunter & protocol
        // hunter gets voucher's bounty when only one answer is submitted
        (, uint256 hunterClaimable,,) = facts.getUserData(hunter0, questionId, 0);
        assertEq(
            hunterClaimable,
            Constants.DEFAULT_BOUNTY_AMOUNT * (Constants.DEFAULT_HUNTER_BP + Constants.DEFAULT_VOUCHER_BP)
                / Constants.BASIS_POINTS
        );
        (uint256 protocolFees,) = facts.qidToFees(questionId);
        assertEq(protocolFees, Constants.DEFAULT_BOUNTY_AMOUNT * Constants.DEFAULT_PROTOCOL_BP / Constants.BASIS_POINTS);
    }

    function test_settle_asDAO_withChallenge() public askedAndSubmitted {
        _warpToChallengePeriod();
        uint256 questionId = 0;
        _challenge(challenger, questionId, abi.encode(uint256(0)));

        _warpToSettlePeriod();

        // settle as DAO
        facts.settle{value: Constants.DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO}(questionId, 1, true);

        (,,,,, SlotData memory slotData) = facts.questions(0);
        assertFalse(slotData.finalized);
        assertEq(slotData.answerId, 1);
        assertEq(slotData.overthrownAnswerId, 0);
        assertTrue(slotData.challengeSucceeded);

        (uint256 protocolFees, uint256 daoFees) = facts.qidToFees(questionId);
        assertEq(protocolFees, Constants.DEFAULT_BOUNTY_AMOUNT / 2);
        assertEq(daoFees, Constants.DEFAULT_BOUNTY_AMOUNT / 2);

        (uint256 deposited,,,) = facts.getUserData(address(this), questionId, 0);
        assertEq(deposited, Constants.DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO);
    }

    function test_settle_RevertWhenCannotDirectSettle() public settleWithChallenge {
        _warpToSettlePeriod();
        vm.expectRevert(IErrors.CannotDirectSettle.selector);
        facts.settle(0);
    }

    function test_settle_RevertWhenAlreadyFinalized() public settleWithoutChallenge {
        vm.expectRevert(IErrors.AlreadyFinalized.selector);
        facts.settle(0);
    }

    function test_settle_asDAO_RevertWhenAlreadyFinalized() public askedAndSubmitted {
        _warpToSettlePeriod();
        facts.settle(0);
        vm.expectRevert(IErrors.AlreadyFinalized.selector);
        facts.settle{value: Constants.DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO}(0, 0, true);
    }

    function test_settle_asDAO_RevertWhenNotEligibleToSettleChallenge() public askedAndSubmitted {
        _warpToSettlePeriod();
        vm.expectRevert(IErrors.NotEligibleToSettleChallenge.selector);
        facts.settle{value: 0}(0, 0, true);
    }

    function test_settle_asDAO_RevertWhenNotChallenged() public askedAndSubmitted {
        _warpToSettlePeriod();
        vm.expectRevert(IErrors.NotChallenged.selector);
        facts.settle{value: Constants.DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO}(0, 0, true);
    }

    function test_settle_asDAO_RevertWhenNotInSettlePeriod() public settleWithChallenge {
        _warpToReviewPeriod();
        vm.expectRevert(IErrors.NotInSettlePeriod.selector);
        facts.settle{value: Constants.DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO}(0, 0, true);
    }

    function test_settle_asDAO_RevertWhenAlreadySettledByDAO() public settleWithChallenge {
        _warpToSettlePeriod();
        vm.expectRevert(IErrors.AlreadySettledByDAO.selector);
        facts.settle{value: Constants.DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO}(0, 0, true);
    }

    function test_overrideSettlement() public settleWithChallenge {
        _warpToReviewPeriod();
        uint256 questionId = 0;

        vm.prank(council);
        vm.expectEmit();
        emit IEvents.Overridden(questionId, 0);
        facts.overrideSettlement(questionId, 0);

        (,,,,, SlotData memory slotData) = facts.questions(questionId);
        assertFalse(slotData.finalized);
        assertEq(slotData.answerId, 0);
        assertTrue(slotData.overridden);
        assertFalse(slotData.challengeSucceeded);

        (uint256 protocolFees, uint256 daoFees) = facts.qidToFees(0);
        assertEq(protocolFees, 0);
        assertEq(daoFees, 0);
    }

    function test_overrideSettlement_RevertWhenNotCouncil() public settleWithChallenge {
        vm.expectRevert(IErrors.OnlyCouncil.selector);
        facts.overrideSettlement(0, 0);
    }

    function test_overrideSettlement_RevertWhenNotInReviewPeriod() public settleWithChallenge {
        vm.prank(council);
        vm.expectRevert(IErrors.NotInReviewPeriod.selector);
        facts.overrideSettlement(0, 0);
    }

    function test_overrideSettlement_RevertWhenNotChallenged() public settleWithoutChallenge {
        _warpToReviewPeriod();
        vm.prank(council);
        vm.expectRevert(IErrors.NotChallenged.selector);
        facts.overrideSettlement(0, 0);
    }

    function test_finalize_AfterOverride_SlashDAO() public settleWithChallenge {
        _warpToReviewPeriod();
        uint256 questionId = 0;

        vm.prank(council);
        facts.overrideSettlement(questionId, 0);

        _warpToAfterReviewPeriod();
        (uint256 depositedBefore,,,) = facts.getUserData(address(this), 0, 0);
        vm.expectEmit();
        emit IEvents.Finalized(questionId);
        facts.finalize(questionId);

        // slash owner i.e. DAO staked deposits
        uint248 slashAmount = uint248(depositedBefore * Constants.DEFAULT_SLASH_DAO_BP / Constants.BASIS_POINTS);

        (,,,,, SlotData memory slotData) = facts.questions(0);
        assertTrue(slotData.finalized);
        (uint256 depositedAfter,,,) = facts.getUserData(address(this), 0, 0);
        assertEq(depositedAfter, depositedBefore - slashAmount);
        // challenger deposit is sent to protocol fee receiver as well
        assertEq(protocolFeeReceiver.balance, slashAmount + Constants.DEFAULT_CHALLENGE_FEE);
    }

    function test_finalize_NoOverride_SlashHunter() public settleWithChallenge {
        _warpToAfterReviewPeriod();
        uint256 questionId = 0;

        (uint256 depositedBefore,,,) = facts.getUserData(hunter0, 0, 0);
        uint256 challengerBalanceBefore = challenger.balance;

        facts.finalize(questionId);
        // slash hunter
        uint248 slashAmount = uint248(depositedBefore * Constants.DEFAULT_SLASH_HUNTER_BP / Constants.BASIS_POINTS);
        (uint256 depositedAfter,,,) = facts.getUserData(hunter0, 0, 0);
        assertEq(depositedAfter, depositedBefore - slashAmount);
        // and sent to challenger
        assertEq(challenger.balance, challengerBalanceBefore + slashAmount);
    }

    function test_finalize_RevertWhenNotAfterReviewPeriod() public settleWithChallenge {
        vm.expectRevert(IErrors.OnlyAfterReviewPeriod.selector);
        facts.finalize(0);
    }

    function test_finalize_RevertWhenAlreadyFinalized() public settleWithoutChallenge {
        _warpToAfterReviewPeriod();
        vm.expectRevert(IErrors.AlreadyFinalized.selector);
        facts.finalize(0);
    }

    function test_setSystemConfig() public {
        SystemConfig memory systemConfig = SystemConfig({
            minStakeOfNativeBountyToHuntBP: uint128(Constants.DEFAULT_MIN_STAKE_OF_NATIVE_BOUNTY_TO_HUNT_BP),
            minStakeToSettleAsDAO: uint128(Constants.DEFAULT_MIN_STAKE_TO_SETTLE_AS_DAO),
            minVouched: uint128(Constants.DEFAULT_MIN_VOUCHED),
            challengeFee: uint128(Constants.DEFAULT_CHALLENGE_FEE),
            huntPeriod: uint64(Constants.DEFAULT_HUNT_PERIOD),
            challengePeriod: uint64(Constants.DEFAULT_CHALLENGE_PERIOD),
            settlePeriod: uint64(Constants.DEFAULT_SETTLE_PERIOD),
            reviewPeriod: uint64(Constants.DEFAULT_REVIEW_PERIOD)
        });
        facts.setSystemConfig(systemConfig);
    }

    function test_setSystemConfig_RevertWhenInvalidConfig() public {
        SystemConfig memory systemConfig = SystemConfig({
            minStakeOfNativeBountyToHuntBP: 0,
            minStakeToSettleAsDAO: 1e18,
            minVouched: 1e18,
            challengeFee: 1e18,
            huntPeriod: 15 minutes,
            challengePeriod: 15 minutes,
            settlePeriod: 15 minutes,
            reviewPeriod: 15 minutes
        });
        vm.expectRevert(IErrors.InvalidConfig.selector);
        facts.setSystemConfig(systemConfig);
    }

    function test_setDistributionConfig() public {
        BountyDistributionConfig memory distributionConfig = BountyDistributionConfig({
            hunterBP: uint128(Constants.DEFAULT_HUNTER_BP),
            voucherBP: uint128(Constants.DEFAULT_VOUCHER_BP)
        });
        facts.setDistributionConfig(distributionConfig);
    }

    function test_setDistributionConfig_RevertWhenInvalidConfig() public {
        // should not add up to BASIS_POINTS
        BountyDistributionConfig memory distributionConfig = BountyDistributionConfig({hunterBP: 8000, voucherBP: 2000});
        vm.expectRevert(IErrors.InvalidConfig.selector);
        facts.setDistributionConfig(distributionConfig);
    }

    function test_setChallengeConfig() public {
        ChallengeConfig memory challengeConfig = ChallengeConfig({
            slashHunterBP: uint64(Constants.DEFAULT_SLASH_HUNTER_BP),
            slashVoucherBP: uint64(Constants.DEFAULT_SLASH_VOUCHER_BP),
            slashDaoBP: uint64(Constants.DEFAULT_SLASH_DAO_BP),
            daoOpFeeBP: uint64(Constants.DEFAULT_DAO_OP_FEE_BP)
        });
        facts.setChallengeConfig(challengeConfig);
    }

    function test_setChallengeConfig_RevertWhenInvalidConfig() public {
        ChallengeConfig memory challengeConfig =
            ChallengeConfig({slashHunterBP: 11000, slashVoucherBP: 1000, slashDaoBP: 1000, daoOpFeeBP: 1000});
        vm.expectRevert(IErrors.InvalidConfig.selector);
        facts.setChallengeConfig(challengeConfig);

        challengeConfig = ChallengeConfig({slashHunterBP: 1000, slashVoucherBP: 1000, slashDaoBP: 1000, daoOpFeeBP: 0});
        vm.expectRevert(IErrors.InvalidConfig.selector);
        facts.setChallengeConfig(challengeConfig);
    }

    function test_getAnswers() public askedAndSubmitted {
        Answer[] memory answers = facts.getAnswers(0);
        assertEq(answers.length, 1);
        assertEq(answers[0].hunter, hunter0);
        assertEq(answers[0].encodedAnswer, abi.encode(uint256(1)));
        assertEq(answers[0].totalVouched, 0);
    }

    function test_getAnswer() public askedAndSubmitted {
        (address hunter, bytes memory encodedAnswer, uint256 totalVouched) = facts.getAnswer(0, 0);
        assertEq(hunter, hunter0);
        assertEq(encodedAnswer, abi.encode(uint256(1)));
        assertEq(totalVouched, 0);
    }

    function test_getNumOfQuestions() public asked {
        assertEq(facts.getNumOfQuestions(), 1);
    }

    function test_getNumOfAnswers() public askedAndSubmitted {
        assertEq(facts.getNumOfAnswers(0), 1);
    }

    function test_getUserData() public settleWithoutChallenge {
        (uint256 deposited, uint256 hunterClaimable, uint248 vouched, bool claimed) = facts.getUserData(voucher0, 0, 0);
        assertEq(deposited, 0);
        assertEq(hunterClaimable, 0);
        assertEq(vouched, Constants.DEFAULT_MIN_VOUCHED * 2);
        assertEq(claimed, false);
    }

    function test_getMostVouchedAnsId() public askedAndSubmittedAndVouched {
        uint16 mostVouchedAnsId = facts.getMostVouchedAnsId(0);
        assertEq(mostVouchedAnsId, 0);
    }

    function test_calcVouchedClaimable() public settleWithoutChallenge {
        uint256 claimable = facts.calcVouchedClaimable(0, voucher0, 0, Constants.DEFAULT_BOUNTY_AMOUNT);
        assertEq(claimable, Constants.DEFAULT_BOUNTY_AMOUNT * Constants.DEFAULT_VOUCHER_BP / Constants.BASIS_POINTS);
    }

    function test_calcMinStakeToHunt_NativeBounty() public asked {
        uint256 minStakeToHunt = facts.calcMinStakeToHunt(0);
        assertEq(
            minStakeToHunt,
            Constants.DEFAULT_BOUNTY_AMOUNT * Constants.DEFAULT_MIN_STAKE_OF_NATIVE_BOUNTY_TO_HUNT_BP
                / Constants.BASIS_POINTS
        );
    }

    function test_calcMinStakeToHunt_ERC20Bounty() public asked {
        _askBinaryQuestion(asker, false);
        uint256 minStakeToHunt = facts.calcMinStakeToHunt(1);
        assertEq(minStakeToHunt, 1e18);
    }

    function test_calcSlashAmount() public view {
        uint256 amount = 1e18;
        uint64 slashBP = uint64(Constants.DEFAULT_SLASH_HUNTER_BP);
        uint256 slashAmount = facts.calcSlashAmount(amount, slashBP);
        assertEq(slashAmount, amount * slashBP / Constants.BASIS_POINTS);
    }

    function test_isWithinHuntPeriod() public asked {
        assertTrue(facts.isWithinHuntPeriod(0));
    }

    function test_isWithinChallengePeriod() public asked {
        _warpToChallengePeriod();
        assertTrue(facts.isWithinChallengePeriod(0));
    }

    function test_isWithinSettlePeriod() public asked {
        _warpToSettlePeriod();
        assertTrue(facts.isWithinSettlePeriod(0));
    }

    function test_isWithinReviewPeriod() public asked {
        _warpToReviewPeriod();
        assertTrue(facts.isWithinReviewPeriod(0));
    }

    function test_afterHuntPeriod() public asked {
        _warpToAfterHuntPeriod();
        assertTrue(facts.afterHuntPeriod(0));
    }

    function test_afterChallengePeriod() public asked {
        _warpToAfterChallengePeriod();
        assertTrue(facts.afterChallengePeriod(0));
    }

    function test_afterReviewPeriod() public asked {
        _warpToAfterReviewPeriod();
        assertTrue(facts.afterReviewPeriod(0));
    }
}
