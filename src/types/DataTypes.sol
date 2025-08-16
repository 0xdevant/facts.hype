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
/// @dev No strict formatting on the answer except for binary which checks for yes/no
enum QuestionType {
    Binary,
    Number,
    OpenEnded
}

struct Answer {
    address hunter;
    bytes encodedAnswer;
    bool byChallenger;
    uint248 totalVouched;
}

struct UserData {
    uint256 deposited;
    uint256[] engagingQIds;
    mapping(uint256 questionId => Result result) qidToResult;
}

struct Result {
    uint256 hunterClaimable;
    mapping(uint16 answerId => Vouch vouch) ansIdToVouch;
}

struct Vouch {
    uint248 vouched;
    bool claimed;
}

// since bounty amount can go beyond 128 bits, use 256 bits to store the fees
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

struct BountyDistributionConfig {
    uint64 hunterBP;
    uint64 voucherBP;
    uint64 protocolBP;
}

struct ChallengeConfig {
    uint64 slashHunterBP;
    uint64 slashVoucherBP;
    uint64 slashDaoBP;
    uint64 daoOpFeeBP;
}
