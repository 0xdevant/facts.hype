// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct Question {
    QuestionType questionType;
    address seeker;
    string description;
    address bountyToken;
    uint256 bountyAmount;
    SlotData slotData;
}

/// @param startHuntAt The start time of the hunt period
/// @param endHuntAt The end time of the hunt period
/// @param answerId The id of the answer
/// @param overthrownAnswerId The answer id overthrown by Council if settlement is overridden
/// @param challenged Whether the question is challenged
/// @param challengeSucceeded Whether the challenge is successful
/// @param overridden Whether the settlement is overridden by Council
/// @param finalized Whether the question is finalized
struct SlotData {
    // fit in one slot
    uint96 startHuntAt;
    uint96 endHuntAt;
    uint16 answerId;
    uint16 overthrownAnswerId;
    bool challenged;
    bool challengeSucceeded;
    bool overridden;
    bool finalized;
}

/// @dev Could be extended to include more types in future upgrades
/// @dev No strict formatting on the answer except for binary and number
enum QuestionType {
    Binary,
    Number,
    OpenEnded
}

/// @param hunter The hunter of the answer
/// @param encodedAnswer To be decoded by the question type
/// @param byChallenger Whether the answer is coming from a challenger
/// @param totalVouched The total amount vouched for the answer
struct Answer {
    address hunter;
    bytes encodedAnswer;
    bool byChallenger;
    uint248 totalVouched;
}

/// @param deposited The total amount deposited by the user
/// @param engagingQIds The ids of questions the user is engaging in
/// @param qidToResult The result of reward and principal for each question for the user
struct UserData {
    uint256 deposited;
    uint256[] engagingQIds;
    mapping(uint256 questionId => Result result) qidToResult;
}

/// @param hunterClaimable The bounty claimable as hunter for the question
/// @param ansIdToVouch Vouch data for an answer
struct Result {
    uint256 hunterClaimable;
    mapping(uint16 answerId => Vouch vouch) ansIdToVouch;
}

/// @param vouched The amount vouched for an answer
/// @param claimed Whether the voucher has claimed the bounty distributed for that answer
struct Vouch {
    uint248 vouched;
    bool claimed;
}

// since bounty amount can go beyond 128 bits, use 256 bits to store the fees
/// @param protocolFee If challenge successful get half of bounty, or share bounty by protocolBP if no challenge
/// @param daoFee If challenge successful get half of bounty, otherwise get operation fee by daoOpFeeBP
struct Fees {
    uint256 protocolFee;
    uint256 daoFee;
}

struct Config {
    SystemConfig systemConfig;
    BountyDistributionConfig distributionConfig;
    ChallengeConfig challengeConfig;
}

/// @param requiredStakeToHunt The minimum stake required to become a hunter
/// @param requiredStakeForDAO The minimum stake required to settle as owner i.e. DAO
/// @param challengeDeposit The deposit required to challenge an answer
/// @param minVouched The minimum amount required to vouch for an answer
/// @param huntPeriod How long is the hunt period
/// @param challengePeriod How long is the challenge period
/// @param settlePeriod How long is the settle period
/// @param reviewPeriod How long is the review period
struct SystemConfig {
    uint128 requiredStakeForDAO;
    uint128 challengeDeposit;
    uint128 requiredStakeToHunt;
    uint128 minVouched;
    uint64 huntPeriod;
    uint64 challengePeriod;
    uint64 settlePeriod;
    uint64 reviewPeriod;
}

/// @dev protocolBP = BASIS_POINTS - hunterBP - voucherBP to save gas in storage
/// @param hunterBP The bounty distribution percentage for hunter in basis points
/// @param voucherBP The bounty distribution percentage for voucher in basis points
struct BountyDistributionConfig {
    uint128 hunterBP;
    uint128 voucherBP;
}

/// @param slashHunterBP The slash percentage for hunter in basis points
/// @param slashVoucherBP The slash percentage for voucher in basis points
/// @param slashDaoBP The slash percentage for DAO in basis points
/// @param daoOpFeeBP The operation fee for DAO in basis points
struct ChallengeConfig {
    uint64 slashHunterBP;
    uint64 slashVoucherBP;
    uint64 slashDaoBP;
    uint64 daoOpFeeBP;
}
