// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct Question {
    // 1 slot
    QuestionType questionType;
    address seeker;
    // 1 slot
    string description;
    // 1 slot
    address bountyToken;
    uint96 bountyAmount;
    // 1 slot
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

/// @param deposited The amount deposited as a bond for the question
/// @param hunterClaimable The bounty claimable as hunter for the question
/// @param ansIdToVouch Vouch data for an answer for the question
struct UserData {
    uint128 deposited;
    uint128 hunterClaimable;
    mapping(uint16 answerId => Vouch vouch) ansIdToVouch;
}

/// @param vouched The amount vouched for an answer
/// @param claimed Whether the bounty distributed for vouching has been claimed
struct Vouch {
    uint248 vouched;
    bool claimed;
}

/// @param protocolFee If challenge successful get half of bounty, or share bounty by protocolBP if no challenge
/// @param daoFee If challenge successful get half of bounty, otherwise get operation fee by daoOpFeeBP
struct Fees {
    uint128 protocolFee;
    uint128 daoFee;
}

struct Config {
    SystemConfig systemConfig;
    BountyDistributionConfig distributionConfig;
    ChallengeConfig challengeConfig;
}

/// @param minStakeOfNativeBountyToHuntBP The minimum staked required relative to bounty in native token to submit answer, in basis points
///                                       i.e. 5000 means half of bounty in native token is required to stake to submit answer
/// @param minStakeToSettleAsDAO The minimum stake required to settle as owner i.e. DAO
/// @param minVouched The minimum amount required to vouch for an answer
/// @param challengeFee The fee required to submit a challenge
/// @param huntPeriod How long is the hunt period
/// @param challengePeriod How long is the challenge period
/// @param settlePeriod How long is the settle period
/// @param reviewPeriod How long is the review period
struct SystemConfig {
    uint128 minStakeOfNativeBountyToHuntBP;
    uint128 minStakeToSettleAsDAO;
    uint128 minVouched;
    uint128 challengeFee;
    uint64 huntPeriod;
    uint64 challengePeriod;
    uint64 settlePeriod;
    uint64 reviewPeriod;
}

/// @dev protocolBP = BASIS_POINTS - hunterBP - voucherBP to save gas in storage
/// @param hunterBP The percentage of bounty distributed to hunter, in basis points
/// @param voucherBP The percentage of bounty distributed to voucher, in basis points
struct BountyDistributionConfig {
    uint128 hunterBP;
    uint128 voucherBP;
}

/// @param slashHunterBP The percentage slashed from the hunter stake, in basis points
/// @param slashVoucherBP The percentage slashed from the voucher stake, in basis points
/// @param slashDaoBP The percentage slashed from the DAO stake, in basis points
/// @param daoOpFeeBP The percentage of bounty as operation fee for DAO to review challenge, in basis points
struct ChallengeConfig {
    uint64 slashHunterBP;
    uint64 slashVoucherBP;
    uint64 slashDaoBP;
    uint64 daoOpFeeBP;
}
