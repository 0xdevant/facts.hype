// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFacts} from "./interfaces/IFacts.sol";
import "./types/DataTypes.sol";

contract Facts is Ownable, IFacts {
    /*//////////////////////////////////////////////////////////////
                                CONSTANT
    //////////////////////////////////////////////////////////////*/
    uint256 private constant _BASIS_POINTS = 10000;
    uint256 private constant _WAD = 1e18;

    address public immutable PROTOCOL_FEE_RECEIVER;
    address public immutable COUNCIL;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    Question[] public questions;

    mapping(uint256 questionId => Answer[] answers) public qidToAnswers;
    mapping(address user => mapping(uint256 questionId => UserData userData)) public usersInfo;
    /// @dev bountyToken could be any erc20 so use a mapping with questionId
    mapping(uint256 questionId => Fees fees) public qidToFees;

    Config public config;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(Config memory _config, address _protocolFeeReceiver, address _council) Ownable(msg.sender) {
        config = _config;
        PROTOCOL_FEE_RECEIVER = _protocolFeeReceiver;
        COUNCIL = _council;
    }

    receive() external payable {
        revert NoDirectTransfer();
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @notice Ask a question and get an answer by crowd-sourced fact-checking
    /// @param questionType The type of question
    /// @param description The description of the question
    /// @param bountyToken The token to be used as bounty, use address(0) for native token
    /// @param bountyAmount The amount of bounty
    /// @param startHuntAt The start time of hunting the fact for the question, use block.timestamp to start immediately
    /// @param extraHuntTime This will add extra time to the default total time allowed to gather the fact for the question i.e. DEFAULT_HUNT_PERIOD
    function ask(
        QuestionType questionType,
        string calldata description,
        address bountyToken,
        uint96 bountyAmount,
        uint96 startHuntAt,
        uint96 extraHuntTime
    ) external payable {
        require(bytes(description).length > 0, EmptyContent());
        require(startHuntAt >= block.timestamp, InvalidStartTime());
        if (bountyToken == address(0)) {
            require(msg.value == bountyAmount, InsufficientBounty());
        } else {
            IERC20(bountyToken).transferFrom(msg.sender, address(this), bountyAmount);
        }

        questions.push(
            Question({
                questionType: questionType,
                description: description,
                seeker: msg.sender,
                bountyToken: bountyToken,
                bountyAmount: bountyAmount,
                slotData: SlotData({
                    startHuntAt: startHuntAt,
                    endHuntAt: uint96(startHuntAt + config.systemConfig.huntPeriod + extraHuntTime),
                    answerId: 0,
                    overthrownAnswerId: 0,
                    challenged: false,
                    challengeSucceeded: false,
                    overridden: false,
                    finalized: false
                })
            })
        );

        emit Asked(questions.length - 1, msg.sender, bountyToken, bountyAmount);
    }

    /// @notice Submit an answer to a question
    /// @param questionId The id of the question
    /// @param encodedAnswer The encoded answer to submit
    /// @dev Technically you can submit multiple answers for the same question by staking multiple times
    function submit(uint256 questionId, bytes calldata encodedAnswer) external payable returns (uint16 answerId) {
        Question memory question = questions[questionId];
        require(msg.value == calcMinStakeToHunt(questionId), InsufficientDeposit());
        require(isWithinHuntPeriod(questionId), NotInHuntPeriod());
        require(_isValidAnsFormat(question.questionType, encodedAnswer), InvalidAnsFormat(question.questionType));

        answerId = uint16(qidToAnswers[questionId].length);
        // shouldn't exceed 256 answers, also leave room for challenge
        require(answerId + 1 < type(uint8).max, TooManyAns());
        // hunter should just submit for once, but still they can
        qidToAnswers[questionId].push(
            Answer({hunter: msg.sender, encodedAnswer: encodedAnswer, byChallenger: false, totalVouched: 0})
        );
        usersInfo[msg.sender][questionId].deposited += uint128(msg.value);

        emit Submitted(questionId, answerId, msg.sender);
    }

    /// @notice Vouch for an answer
    /// @param questionId The id of the question
    /// @param answerId The id of the answer to vouch for
    /// @dev Can only vouch if there is a bounty and more than one answer submitted
    function vouch(uint256 questionId, uint16 answerId) external payable {
        require(isWithinHuntPeriod(questionId), NotInHuntPeriod());
        require(msg.value >= config.systemConfig.minVouched, InsufficientVouched());
        require(questions[questionId].bountyAmount > 0, InsufficientBounty());
        require(qidToAnswers[questionId].length > 1, CannotVouchWhenOneAns());
        Answer storage answer = qidToAnswers[questionId][answerId];
        require(answer.hunter != msg.sender, CannotVouchForSelf());

        // user can keep vouching for the same answer multiple times
        usersInfo[msg.sender][questionId].ansIdToVouch[answerId].vouched += uint120(msg.value);
        answer.totalVouched += uint248(msg.value);

        emit Vouched(questionId, answerId, msg.sender, msg.value);
    }

    /*//////////////////////////////////////////////////////////////
                          REWARD RELATED LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Claim the bounty for a question
    /// @param questionId The id of the question
    /// @param asHunter Whether to claim as a hunter
    function claim(uint256 questionId, bool asHunter) external {
        require(questions[questionId].slotData.finalized, NotFinalized());

        uint256 claimAmount = _claimBounty(questionId, msg.sender, asHunter);

        emit Claimed(questionId, msg.sender, claimAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        PRINICPAL RELATED LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Withdraw full amount of stake from deposited OR vouched, only callable when the respective question is finalized to cater for slash events
    /// @param questionIds The ids of the questions to withdraw deposited stake from
    /// @param answerIds The ids of the answers to withdraw vouched stake from
    /// @param recipient The address to receive the withdrawn stake
    /// @dev It won't make sense for user to have both deposited and vouched for the same question,
    ///      so assume user either claims deposited OR vouched stake, and assume user only submitted one answer for each question
    function withdraw(uint256[] calldata questionIds, uint16[] calldata answerIds, address recipient) external {
        if (answerIds.length > 0) {
            require(answerIds.length == questionIds.length, ArrayMismatch());
        }
        uint256 totalAmount;

        for (uint256 i; i < questionIds.length; i++) {
            Question memory question = questions[questionIds[i]];
            require(question.slotData.finalized, NotFinalized());

            UserData storage userData = usersInfo[msg.sender][questionIds[i]];

            // only claim deposited stake
            if (answerIds.length == 0) {
                // claim the whole amount even submitted multiple answers for the same question
                totalAmount += userData.deposited;
                userData.deposited = 0;
            } else {
                // only claim vouched stake and check if the stake will get slashed
                uint256 vouchedAmount = userData.ansIdToVouch[answerIds[i]].vouched;
                // if the answerId the voucher is vouching for happens to be the answer being overthrown, slash the voucher
                if (question.slotData.challengeSucceeded && question.slotData.overthrownAnswerId == answerIds[i]) {
                    vouchedAmount -= calcSlashAmount(vouchedAmount, config.challengeConfig.slashVoucherBP);
                }

                totalAmount += vouchedAmount;
                userData.ansIdToVouch[answerIds[i]].vouched = 0;
            }
        }

        payable(recipient).transfer(totalAmount);
        emit Withdrawn(recipient, totalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                         DISPUTE RELATED LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Challenge the answer with the most vouched stake by paying $HYPE only if there is a bounty for the question
    /// @param questionId The id of the question
    /// @param encodedAnswer The encoded answer to challenge
    /// @dev Only can challenge if the submitted answer is not same as the most vouched answer
    function challenge(uint256 questionId, bytes calldata encodedAnswer) external payable returns (uint16 answerId) {
        require(isWithinChallengePeriod(questionId), NotInChallengePeriod());
        require(msg.value == config.systemConfig.challengeFee, InsufficientChallengeFee());
        uint16 mostVouchedAnsId = getMostVouchedAnsId(questionId);
        require(mostVouchedAnsId != type(uint16).max, UnnecessaryChallenge());
        Answer memory mostVouchedAns = qidToAnswers[questionId][mostVouchedAnsId];
        require(
            // checking if the number is the same applies to both binary and number question types
            abi.decode(encodedAnswer, (uint256)) != abi.decode(mostVouchedAns.encodedAnswer, (uint256)),
            CannotChallengeSameAns()
        );
        require(mostVouchedAns.hunter != msg.sender, CannotChallengeSelf());

        // pay $HYPE to protocol immediately as fee
        payable(PROTOCOL_FEE_RECEIVER).transfer(config.systemConfig.challengeFee);

        questions[questionId].slotData.challenged = true;
        answerId = uint16(qidToAnswers[questionId].length);
        qidToAnswers[questionId].push(
            Answer({hunter: msg.sender, encodedAnswer: encodedAnswer, byChallenger: true, totalVouched: 0})
        );

        emit Challenged(questionId, answerId, msg.sender);
    }

    /// @notice Settle to finalize the question by distributing bounty, callable by anyone as long as no challenge is involved for the question
    /// @dev Can be settled directly after hunt period if no winners found, or after challenge period if no challenge is raised
    /// @param questionId The id of the question
    function settle(uint256 questionId) external {
        Question memory question = questions[questionId];
        require(!question.slotData.challenged, CannotDirectSettle());
        require(!question.slotData.finalized, AlreadyFinalized());

        uint16 mostVouchedAnsId = getMostVouchedAnsId(questionId);
        // `type(uint16).max` means either no answer is submitted or all answers have same vouched amount(or no one vouch) i.e. no winner
        if (mostVouchedAnsId == type(uint16).max) {
            require(afterHuntPeriod(questionId), OnlyAfterHuntPeriod());
            // no winner so bounty will be returned to seeker
            questions[questionId].slotData.finalized = true;
            _transferBounty(question.bountyToken, question.seeker, question.bountyAmount);
        } else if (!question.slotData.challenged) {
            require(afterChallengePeriod(questionId), OnlyAfterChallengePeriod());
            _settleByUser(questionId, mostVouchedAnsId);
        }

        emit Settle(questionId);
    }

    /// @notice Settle the question as owner i.e. DAO by staking $HYPE to determine if challenge succeeded, this decision can be overridden by the council
    /// @param questionId The id of the question
    /// @param selectedAnswerId The selected answer id to replace the most vouched answer
    /// @param challengeSucceeded To indicate if the challenge succeeded
    function settle(uint256 questionId, uint16 selectedAnswerId, bool challengeSucceeded) external payable onlyOwner {
        Question memory question = questions[questionId];
        require(!question.slotData.finalized, AlreadyFinalized());
        require(isWithinSettlePeriod(questionId), NotInSettlePeriod());
        require(msg.value == config.systemConfig.minStakeToSettleAsDAO, NotEligibleToSettleChallenge());
        require(question.slotData.challenged, NotChallenged());
        // only bounty amount > 0 will involve challenge so daoFee != 0 indicates DAO already called settle
        require(qidToFees[questionId].daoFee == 0, AlreadySettledByDAO());

        uint16 mostVouchedAnsId = getMostVouchedAnsId(questionId);
        _settleByDAO(questionId, mostVouchedAnsId, selectedAnswerId, challengeSucceeded);

        emit SettleByDAO(questionId, selectedAnswerId, challengeSucceeded);
    }

    /// @notice Override the settlement result from the DAO as Council
    /// @param questionId The id of the question
    /// @param finalAnswerId The answer id decided to be the final winner
    function overrideSettlement(uint256 questionId, uint16 finalAnswerId) external {
        require(msg.sender == COUNCIL, OnlyCouncil());
        // storage pointer to save gas on reading only certain variables
        Question storage question = questions[questionId];
        require(isWithinReviewPeriod(questionId), NotInReviewPeriod());
        // there exists no scenario where within review period challenged & finalized can both be true so no need to check finalized
        require(question.slotData.challenged, NotChallenged());

        // return all fees back to hunter and voucher
        qidToFees[questionId].protocolFee = 0;
        qidToFees[questionId].daoFee = 0;

        questions[questionId].slotData.answerId = finalAnswerId;
        // must be the opposite of the original challenge result
        question.slotData.challengeSucceeded = !question.slotData.challengeSucceeded;
        question.slotData.overridden = true;

        emit Overridden(questionId, finalAnswerId);
    }

    /// @notice Finalize the question to enable claiming bounty and principal and slash related parties if needed, callable by anyone
    /// @dev Only need to be called when a question involved challenge
    function finalize(uint256 questionId) external {
        SlotData memory slotData = questions[questionId].slotData;
        require(afterReviewPeriod(questionId), OnlyAfterReviewPeriod());
        require(!slotData.finalized, AlreadyFinalized());

        questions[questionId].slotData.finalized = true;

        // if challenge result is overridden, slash DAO
        if (slotData.overridden) {
            _slashDAOToProtocol(questionId);
        } else if (slotData.challengeSucceeded) {
            // if challenge is successful, hunter will be slashed and vouchers will be slashed when they withdraw
            _slashHunterToChallenger(questionId);
        }

        emit Finalized(questionId);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/
    /// @notice Claim platform fees for a list of questions
    /// @param questionIds The ids of the questions
    /// @param recipient The address to receive the platform fees
    function claimPlatformFee(uint256[] memory questionIds, address recipient) external {
        require(msg.sender == owner() || msg.sender == PROTOCOL_FEE_RECEIVER, OnlyOwnerOrFeeReceiver());
        _claimPlatformFee(questionIds, recipient);

        emit ClaimedPlatformFee(recipient);
    }

    /// @notice Set the system config
    /// @param systemConfig The system config to set
    /// @dev Each config must be >0
    function setSystemConfig(SystemConfig memory systemConfig) external onlyOwner {
        require(
            systemConfig.minStakeOfNativeBountyToHuntBP != 0 && systemConfig.minStakeToSettleAsDAO != 0
                && systemConfig.minVouched != 0 && systemConfig.challengeFee != 0 && systemConfig.huntPeriod != 0
                && systemConfig.challengePeriod != 0 && systemConfig.settlePeriod != 0 && systemConfig.reviewPeriod != 0,
            InvalidConfig()
        );

        config.systemConfig = systemConfig;
    }

    /// @notice Set the distribution config
    /// @param distributionConfig The distribution config to set
    /// @dev protocolBP = BASIS_POINTS - hunterBP - voucherBP so hunterBP & voucherBP must add up to <100%
    function setDistributionConfig(BountyDistributionConfig memory distributionConfig) external onlyOwner {
        require(distributionConfig.hunterBP + distributionConfig.voucherBP < _BASIS_POINTS, InvalidConfig());

        config.distributionConfig = distributionConfig;
    }

    /// @notice Set the challenge config
    /// @param challengeConfig The challenge config to set
    /// @dev Each BP must be <=100%
    function setChallengeConfig(ChallengeConfig memory challengeConfig) external onlyOwner {
        require(
            challengeConfig.slashHunterBP <= _BASIS_POINTS && challengeConfig.slashVoucherBP <= _BASIS_POINTS
                && challengeConfig.slashDaoBP <= _BASIS_POINTS && challengeConfig.daoOpFeeBP <= _BASIS_POINTS
                && challengeConfig.slashHunterBP != 0 && challengeConfig.slashVoucherBP != 0
                && challengeConfig.slashDaoBP != 0 && challengeConfig.daoOpFeeBP != 0,
            InvalidConfig()
        );

        config.challengeConfig = challengeConfig;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    function _settleByDAO(uint256 questionId, uint16 mostVouchedAnsId, uint16 selectedAnswerId, bool challengeSucceeded)
        internal
    {
        Question storage question = questions[questionId];
        Fees storage fees = qidToFees[questionId];

        if (challengeSucceeded) {
            question.slotData.answerId = selectedAnswerId;
            question.slotData.overthrownAnswerId = mostVouchedAnsId;
            question.slotData.challengeSucceeded = true;

            // distribute bounty in half to protocol and DAO if challenge is successful
            fees.protocolFee += question.bountyAmount / 2;
            fees.daoFee += question.bountyAmount / 2;
        } else {
            // distribute part of bounty as operation fee to DAO for reviewing the challenge
            fees.daoFee += uint128((question.bountyAmount * config.challengeConfig.daoOpFeeBP) / _BASIS_POINTS);
        }
        usersInfo[msg.sender][questionId].deposited += uint128(msg.value);
    }

    function _settleByUser(uint256 questionId, uint16 mostVouchedAnsId) internal {
        Question storage question = questions[questionId];
        question.slotData.answerId = mostVouchedAnsId;
        question.slotData.finalized = true;

        BountyDistributionConfig memory distributionConfig = config.distributionConfig;
        // if there's only one answer no vouch will be allowed so distribute voucher bounty to hunter as well
        uint256 hunterBP = qidToAnswers[questionId].length == 1
            ? distributionConfig.hunterBP + distributionConfig.voucherBP
            : distributionConfig.hunterBP;
        // remaining goes to protocol
        uint256 protocolBP = _BASIS_POINTS - distributionConfig.hunterBP - distributionConfig.voucherBP;
        address hunter = qidToAnswers[questionId][mostVouchedAnsId].hunter;

        usersInfo[hunter][questionId].hunterClaimable = uint128((question.bountyAmount * hunterBP) / _BASIS_POINTS);
        qidToFees[questionId].protocolFee += uint128((question.bountyAmount * protocolBP) / _BASIS_POINTS);
    }

    function _slashDAOToProtocol(uint256 questionId) internal {
        address dao = owner();
        uint256 slashAmount = calcSlashAmount(usersInfo[dao][questionId].deposited, config.challengeConfig.slashDaoBP);
        usersInfo[dao][questionId].deposited -= uint128(slashAmount);
        // slash DAO voters' $HYPE to protocol
        payable(PROTOCOL_FEE_RECEIVER).transfer(slashAmount);
    }

    function _slashHunterToChallenger(uint256 questionId) internal {
        Answer memory overthrownAnswer = qidToAnswers[questionId][questions[questionId].slotData.overthrownAnswerId];
        Answer memory finalAnswer = qidToAnswers[questionId][questions[questionId].slotData.answerId];

        uint256 slashAmount = calcSlashAmount(
            usersInfo[overthrownAnswer.hunter][questionId].deposited, config.challengeConfig.slashHunterBP
        );
        // slash stake from hunter and send to the challenger
        usersInfo[overthrownAnswer.hunter][questionId].deposited -= uint128(slashAmount);
        payable(finalAnswer.hunter).transfer(uint256(slashAmount));
    }

    function _claimBounty(uint256 questionId, address claimer, bool asHunter) internal returns (uint256 claimAmount) {
        Question memory question = questions[questionId];
        UserData storage userData = usersInfo[claimer][questionId];
        if (asHunter) {
            claimAmount = userData.hunterClaimable;
            userData.hunterClaimable = 0;
        } else {
            uint16 finalAnsId = question.slotData.answerId;
            // vouchers won't be eligible for bounty if challenge is successful
            if (!question.slotData.challengeSucceeded && !userData.ansIdToVouch[finalAnsId].claimed) {
                userData.ansIdToVouch[finalAnsId].claimed = true;
                claimAmount = calcVouchedClaimable(questionId, claimer, finalAnsId, question.bountyAmount);
            }
        }
        _transferBounty(question.bountyToken, claimer, claimAmount);
    }

    function _transferBounty(address bountyToken, address recipient, uint256 amount) internal {
        if (amount == 0) return;

        if (bountyToken == address(0)) {
            payable(recipient).transfer(amount);
        } else {
            IERC20(bountyToken).transfer(recipient, amount);
        }
    }

    function _isValidAnsFormat(QuestionType questionType, bytes calldata encodedAnswer) public pure returns (bool) {
        // will cause panic if use bool so use uint instead
        if (questionType == QuestionType.Binary) {
            return abi.decode(encodedAnswer, (uint256)) == 0 || abi.decode(encodedAnswer, (uint256)) == 1;
        }

        // if indeed it's not a number in the first place, the answer won't be correct so users won't vouch for it anyway
        if (questionType == QuestionType.Number) {
            return abi.decode(encodedAnswer, (uint256)) < type(uint256).max;
        }

        return true;
    }

    function _isDuplicateAnswer(uint256 questionId, bytes calldata answerForChallenge, uint16 mostVouchedAnsId)
        internal
        view
        returns (bool)
    {
        Answer memory mostVouchedAns = qidToAnswers[questionId][mostVouchedAnsId];
        // checking if the number is the same applies to both binary and number question types
        return abi.decode(answerForChallenge, (uint256)) == abi.decode(mostVouchedAns.encodedAnswer, (uint256));
    }

    /// @dev No zero checking since we assume the caller will know which questions have fees to claim beforehand
    function _claimPlatformFee(uint256[] memory questionIds, address recipient) internal {
        bool isProtocolFeeReceiver = msg.sender == PROTOCOL_FEE_RECEIVER;
        uint256 nativeAmount;

        for (uint256 i; i < questionIds.length; i++) {
            require(questions[questionIds[i]].slotData.finalized, NotFinalized());

            address bountyToken = questions[questionIds[i]].bountyToken;
            uint256 protocolFee = qidToFees[questionIds[i]].protocolFee;
            uint256 daoFee = qidToFees[questionIds[i]].daoFee;

            isProtocolFeeReceiver ? qidToFees[questionIds[i]].protocolFee = 0 : qidToFees[questionIds[i]].daoFee = 0;

            if (bountyToken == address(0)) {
                nativeAmount += isProtocolFeeReceiver ? protocolFee : daoFee;
            } else {
                IERC20(bountyToken).transfer(recipient, isProtocolFeeReceiver ? protocolFee : daoFee);
            }
        }
        payable(recipient).transfer(nativeAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    /// @notice Get all answers for a question
    /// @param questionId The id of the question
    /// @return answers The answers for the question
    function getAnswers(uint256 questionId) external view returns (Answer[] memory) {
        return qidToAnswers[questionId];
    }

    /// @notice Get an answer for a question
    /// @param questionId The id of the question
    /// @param answerId The id of the answer
    /// @return hunter The hunter of the answer
    /// @return encodedAnswer The encoded answer
    /// @return totalVouched The total vouched amount of the answer
    function getAnswer(uint256 questionId, uint16 answerId)
        external
        view
        returns (address hunter, bytes memory encodedAnswer, uint256 totalVouched)
    {
        return (
            qidToAnswers[questionId][answerId].hunter,
            qidToAnswers[questionId][answerId].encodedAnswer,
            qidToAnswers[questionId][answerId].totalVouched
        );
    }

    /// @notice Get the number of questions
    /// @return numOfQuestions The number of questions
    function getNumOfQuestions() external view returns (uint256) {
        return questions.length;
    }

    /// @notice Get the number of answers for a question
    /// @param questionId The id of the question
    /// @return numOfAnswers The number of answers for the question
    function getNumOfAnswers(uint256 questionId) external view returns (uint256) {
        return qidToAnswers[questionId].length;
    }

    /// @notice Get the user data of a question for a user
    /// @param user The address of the user
    /// @param questionId The id of the question
    /// @param answerId The id of the answer
    /// @return deposited The amount deposited as bond
    /// @return hunterClaimable The bounty claimable as hunter
    /// @return vouched The amount vouched for an answer
    /// @return claimed Whether the bounty distributed for vouching has been claimed
    function getUserData(address user, uint256 questionId, uint16 answerId)
        external
        view
        returns (uint128 deposited, uint128 hunterClaimable, uint248 vouched, bool claimed)
    {
        UserData storage userData = usersInfo[user][questionId];
        return (
            userData.deposited,
            userData.hunterClaimable,
            userData.ansIdToVouch[answerId].vouched,
            userData.ansIdToVouch[answerId].claimed
        );
    }

    /// @notice Find the most truthful answer by checking which answer has the most vouched amount for a question
    /// @param questionId The id of the question
    /// @return winnerAnsId The id of the most truthful answer, type(uint16).max indicates no winner
    /// @dev When there is no answer submitted OR all answers have same vouched amount(could be no one vouch at all), return type(uint16).max to indicate no winner
    function getMostVouchedAnsId(uint256 questionId) public view returns (uint16 winnerAnsId) {
        Answer[] memory answers = qidToAnswers[questionId];
        if (answers.length == 0) {
            return type(uint16).max;
        }

        // the only answer will be winner
        if (answers.length == 1) {
            return 0;
        }

        uint256 maxVouched = answers[0].totalVouched;
        for (uint256 i = 1; i < answers.length; i++) {
            // only select from non-challenger answers
            if (!answers[i].byChallenger) {
                // if same vouch exists
                if (answers[i].totalVouched == maxVouched) {
                    winnerAnsId = type(uint16).max;
                    break;
                } else if (answers[i].totalVouched > maxVouched) {
                    maxVouched = answers[i].totalVouched;
                    winnerAnsId = uint16(i);
                }
            }
        }
    }

    /// @notice Check if a question is within the hunt period
    /// @param questionId The id of the question
    function isWithinHuntPeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        return block.timestamp > question.slotData.startHuntAt && block.timestamp <= question.slotData.endHuntAt;
    }

    /// @notice Check if a question is within the challenge period
    /// @param questionId The id of the question
    function isWithinChallengePeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        return block.timestamp > question.slotData.endHuntAt
            && block.timestamp <= question.slotData.endHuntAt + config.systemConfig.challengePeriod;
    }

    /// @notice Check if a question is within the settle period
    /// @param questionId The id of the question
    function isWithinSettlePeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        SystemConfig memory systemConfig = config.systemConfig;

        return block.timestamp > question.slotData.endHuntAt + systemConfig.challengePeriod
            && block.timestamp <= question.slotData.endHuntAt + systemConfig.challengePeriod + systemConfig.settlePeriod;
    }

    /// @notice Check if a question is within the review period
    /// @param questionId The id of the question
    function isWithinReviewPeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        SystemConfig memory systemConfig = config.systemConfig;

        return block.timestamp > question.slotData.endHuntAt + systemConfig.challengePeriod + systemConfig.settlePeriod
            && block.timestamp
                <= question.slotData.endHuntAt + systemConfig.challengePeriod + systemConfig.settlePeriod
                    + systemConfig.reviewPeriod;
    }

    /// @notice Check if a question is after the hunt period
    /// @param questionId The id of the question
    function afterHuntPeriod(uint256 questionId) public view returns (bool) {
        return block.timestamp > questions[questionId].slotData.endHuntAt;
    }

    /// @notice Check if a question is after the challenge period
    /// @param questionId The id of the question
    function afterChallengePeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        SystemConfig memory systemConfig = config.systemConfig;
        return block.timestamp > question.slotData.endHuntAt + systemConfig.challengePeriod;
    }

    /// @notice Check if a question is after the review period
    /// @param questionId The id of the question
    function afterReviewPeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        SystemConfig memory systemConfig = config.systemConfig;

        return block.timestamp
            > question.slotData.endHuntAt + systemConfig.challengePeriod + systemConfig.settlePeriod
                + systemConfig.reviewPeriod;
    }

    /// @notice Calculate the minimum stake to submit answer for a question based on its bounty token and bounty amount
    /// @param questionId The id of the question
    function calcMinStakeToHunt(uint256 questionId) public view returns (uint256) {
        Question memory question = questions[questionId];
        return question.bountyToken == address(0)
            ? (question.bountyAmount * config.systemConfig.minStakeOfNativeBountyToHuntBP) / _BASIS_POINTS
            : 1e18;
    }

    /// @notice Calculate the claimable amount for a voucher
    /// @param questionId The id of the question
    /// @param voucher The address of the voucher
    /// @param answerId The id of the answer
    /// @param bountyAmount The bounty amount of the question
    /// @return claimable The claimable amount for the voucher
    function calcVouchedClaimable(uint256 questionId, address voucher, uint16 answerId, uint256 bountyAmount)
        public
        view
        returns (uint256 claimable)
    {
        // get vouched amount from correct answer id
        uint256 vouched = usersInfo[voucher][questionId].ansIdToVouch[answerId].vouched;
        // claim by the share of own vouched amount to the total vouched amount of correct answer
        uint256 share = (vouched * _WAD) / qidToAnswers[questionId][answerId].totalVouched / _WAD;
        claimable = (bountyAmount * share * config.distributionConfig.voucherBP) / _BASIS_POINTS;
    }

    /// @notice Calculate the slash amount
    /// @param amount The total amount to slash from
    /// @param slashBP The slash BP
    function calcSlashAmount(uint256 amount, uint64 slashBP) public pure returns (uint256) {
        return amount * slashBP / _BASIS_POINTS;
    }
}
