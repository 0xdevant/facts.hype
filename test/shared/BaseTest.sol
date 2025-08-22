// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Facts} from "../../src/Facts.sol";
import {IFacts} from "../../src/interfaces/IFacts.sol";
import {Constants} from "../Constants.sol";
import "../../src/types/DataTypes.sol";

// expose certain getters for testing
contract FactsHarness is Facts {
    constructor(Config memory _config, address _protocolFeeReceiver, address _council)
        Facts(_config, _protocolFeeReceiver, _council)
    {}

    function getPlatformFees(uint256 questionId) public view returns (uint256 protocolFee, uint256 daoFee) {
        return (platformFees[questionId].protocolFee, platformFees[questionId].daoFee);
    }
}

contract BaseTest is Test {
    address public protocolOwner = makeAddr("protocolOwner");
    address public protocolFeeReceiver = makeAddr("protocolFeeReceiver");
    address public council = makeAddr("council");

    address public asker;
    address public hunter0;
    address public hunter1;
    address public voucher;
    address public challenger;

    FactsHarness public facts;

    function setUp() public virtual {
        createUsers();
        deploy();
    }

    function createUsers() public {
        asker = makeAddr("asker");
        hunter0 = makeAddr("hunter0");
        hunter1 = makeAddr("hunter1");
        voucher = makeAddr("voucher");
        challenger = makeAddr("challenger");
        deal(asker, Constants.DEFAULT_TOKEN_BALANCE);
        deal(hunter0, Constants.DEFAULT_TOKEN_BALANCE);
        deal(hunter1, Constants.DEFAULT_TOKEN_BALANCE);
        deal(voucher, Constants.DEFAULT_TOKEN_BALANCE);
        deal(challenger, Constants.DEFAULT_TOKEN_BALANCE);
    }

    function deploy() public {
        Config memory config = Config({
            systemConfig: SystemConfig({
                requiredStakeToHunt: uint128(Constants.DEFAULT_REQUIRED_STAKE_TO_HUNT),
                requiredStakeForDAO: uint128(Constants.DEFAULT_REQUIRED_STAKE_FOR_DAO),
                challengeDeposit: uint128(Constants.DEFAULT_CHALLENGE_DEPOSIT),
                minVouched: uint128(Constants.DEFAULT_MIN_VOUCHED),
                huntPeriod: uint64(Constants.DEFAULT_HUNT_PERIOD),
                challengePeriod: uint64(Constants.DEFAULT_CHALLENGE_PERIOD),
                settlePeriod: uint64(Constants.DEFAULT_SETTLE_PERIOD),
                reviewPeriod: uint64(Constants.DEFAULT_REVIEW_PERIOD)
            }),
            distributionConfig: BountyDistributionConfig({
                hunterBP: uint128(Constants.DEFAULT_HUNTER_BP),
                voucherBP: uint128(Constants.DEFAULT_VOUCHER_BP)
            }),
            challengeConfig: ChallengeConfig({
                slashHunterBP: uint64(Constants.DEFAULT_SLASH_HUNTER_BP),
                slashVoucherBP: uint64(Constants.DEFAULT_SLASH_VOUCHER_BP),
                slashDaoBP: uint64(Constants.DEFAULT_SLASH_DAO_BP),
                daoOpFeeBP: uint64(Constants.DEFAULT_DAO_OP_FEE_BP)
            })
        });

        facts = new FactsHarness(config, protocolFeeReceiver, council);
    }

    modifier asked() {
        _askBinaryQuestion(asker);
        _warpToHuntPeriod();
        _becomeHunter(hunter0);
        _;
    }

    modifier askedAndSubmitted() {
        _askBinaryQuestion(asker);
        _warpToHuntPeriod();
        _becomeHunter(hunter0);
        _submit(hunter0, 0, true);
        _;
    }

    modifier askedAndSubmittedAndVouched() {
        _askedAndSubmittedAndVouched();
        _;
    }

    modifier settleWithoutChallenge() {
        _askedAndSubmittedAndVouched();
        _warpToSettlePeriod();
        facts.settle(0, 0, false);
        _;
    }

    modifier settleWithChallenge() {
        _askedAndSubmittedAndVouched();
        _warpToChallengePeriod();
        // challenge yes answer with no
        _challenge(challenger, 0, abi.encode(uint256(0)));

        _warpToSettlePeriod();
        _becomeDAO();
        facts.settle(0, 2, true);
        _;
    }

    function _askedAndSubmittedAndVouched() internal {
        _askBinaryQuestion(asker);
        _warpToHuntPeriod();
        _becomeHunter(hunter0);
        _becomeHunter(hunter1);
        // submit "yes"
        _submit(hunter0, 0, true);
        // submit "no"
        _submit(hunter1, 0, false);
        // vouch for "yes" with 2 * DEFAULT_MIN_VOUCHED
        _vouch(voucher, 0, 0, Constants.DEFAULT_MIN_VOUCHED);
        // vouch for "no" with DEFAULT_MIN_VOUCHED
        _vouch(voucher, 0, 1, 0);
    }

    function _askBinaryQuestion(address seeker) internal {
        vm.prank(seeker);
        facts.ask{value: Constants.DEFAULT_BOUNTY_AMOUNT}(
            QuestionType.Binary,
            "Is the sky blue?",
            address(0),
            Constants.DEFAULT_BOUNTY_AMOUNT,
            uint96(block.timestamp),
            0
        );
    }

    function _becomeHunter(address user) internal {
        vm.prank(user);
        facts.deposit{value: Constants.DEFAULT_REQUIRED_STAKE_TO_HUNT}();
    }

    function _becomeDAO() internal {
        facts.deposit{value: Constants.DEFAULT_REQUIRED_STAKE_FOR_DAO}();
    }

    function _submit(address hunter, uint256 questionId, bool isYes) internal returns (uint16 answerId) {
        vm.prank(hunter);
        answerId = facts.submit(questionId, abi.encode(uint256(isYes ? 1 : 0)));
    }

    function _vouch(address user, uint256 questionId, uint16 answerId, uint256 extraAmount) internal {
        vm.prank(user);
        facts.vouch{value: Constants.DEFAULT_MIN_VOUCHED + extraAmount}(questionId, answerId);
    }

    function _challenge(address user, uint256 questionId, bytes memory encodedAnswer)
        internal
        returns (uint16 answerId)
    {
        vm.prank(user);
        answerId = facts.challenge{value: Constants.DEFAULT_CHALLENGE_DEPOSIT}(questionId, encodedAnswer);
    }

    function _warpToHuntPeriod() internal {
        vm.warp(Constants.HUNT_START);
    }

    function _warpToChallengePeriod() internal {
        vm.warp(Constants.CHALLENGE_START);
    }

    function _warpToSettlePeriod() internal {
        vm.warp(Constants.SETTLE_START);
    }

    function _warpToReviewPeriod() internal {
        vm.warp(Constants.REVIEW_START);
    }

    function _warpToAfterHuntPeriod() internal {
        vm.warp(Constants.HUNT_START + Constants.DEFAULT_HUNT_PERIOD + 1);
    }

    function _warpToAfterChallengePeriod() internal {
        vm.warp(Constants.CHALLENGE_START + Constants.DEFAULT_CHALLENGE_PERIOD + 1);
    }

    function _warpToAfterSettlePeriod() internal {
        vm.warp(Constants.SETTLE_START + Constants.DEFAULT_SETTLE_PERIOD + 1);
    }

    function _warpToAfterReviewPeriod() internal {
        vm.warp(Constants.REVIEW_START + Constants.DEFAULT_REVIEW_PERIOD + 1);
    }
}
