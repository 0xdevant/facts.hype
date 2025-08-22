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
    uint256 private constant _MAX_ELEMENTS_TO_DELETE = 10;

    address public immutable PROTOCOL_FEE_RECEIVER;
    address public immutable COUNCIL;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    Question[] public questions;

    mapping(uint256 questionId => Answer[] answers) public qidToAnswers;
    mapping(address user => UserData userData) public usersInfo;
    /// @dev bountyToken could be any erc20 so use a mapping with questionId
    mapping(uint256 questionId => Fees fees) public platformFees;

    Config public config;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(Config memory _config, address _protocolFeeReceiver, address _council) Ownable(msg.sender) {
        config = _config;
        PROTOCOL_FEE_RECEIVER = _protocolFeeReceiver;
        COUNCIL = _council;
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
        uint256 bountyAmount,
        uint96 startHuntAt,
        uint96 extraHuntTime
    ) external payable {
        require(bytes(description).length > 0, IFacts.EmptyContent());
        require(startHuntAt >= block.timestamp, IFacts.InvalidStartTime());
        if (bountyToken == address(0)) {
            require(msg.value == bountyAmount, IFacts.InsufficientBounty());
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
    function submit(uint256 questionId, bytes calldata encodedAnswer) external returns (uint16 answerId) {
        Question memory question = questions[questionId];
        require(isWithinHuntPeriod(questionId), IFacts.NotInHuntPeriod());
        require(isHunter(msg.sender), IFacts.OnlyHunter());
        require(_isValidAnsFormat(question.questionType, encodedAnswer), IFacts.InvalidAnsFormat(question.questionType));
        answerId = uint16(qidToAnswers[questionId].length);
        // shouldn't exceed 256 answers, also leave room for challenge
        require(answerId + 1 < type(uint8).max, IFacts.TooManyAns());
        // hunter should just submit for once, but still they can
        usersInfo[msg.sender].engagingQIds.push(questionId);
        qidToAnswers[questionId].push(
            Answer({hunter: msg.sender, encodedAnswer: encodedAnswer, byChallenger: false, totalVouched: 0})
        );

        emit Submitted(questionId, answerId, msg.sender);
    }

    /// @notice Vouch for an answer
    /// @param questionId The id of the question
    /// @param answerId The id of the answer to vouch for
    function vouch(uint256 questionId, uint16 answerId) external payable {
        require(isWithinHuntPeriod(questionId), IFacts.NotInHuntPeriod());
        require(msg.value >= config.systemConfig.minVouched, IFacts.InsufficientVouched());
        require(qidToAnswers[questionId].length > 1, IFacts.CannotVouchWhenOneAns());
        Answer storage answer = qidToAnswers[questionId][answerId];
        require(answer.hunter != msg.sender, IFacts.CannotVouchForSelf());

        // user can keep vouching for the same answer multiple times
        usersInfo[msg.sender].qidToResult[questionId].ansIdToVouch[answerId].vouched += uint120(msg.value);
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
        require(questions[questionId].slotData.finalized, IFacts.NotFinalized());

        uint256 claimAmount = _claimBounty(questionId, msg.sender, asHunter);

        emit Claimed(questionId, msg.sender, claimAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        PRINICPAL RELATED LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Redeem the vouched amount back from the answer that is not the final truthful answer
    /// @param questionId The id of the question
    /// @param answerId The id of the answer to redeem
    /// @dev Voucher will be slashed at this point if challenge is successful
    function redeem(uint256 questionId, uint16 answerId) external {
        Question memory question = questions[questionId];
        require(question.slotData.finalized, IFacts.NotFinalized());

        uint256 vouched = usersInfo[msg.sender].qidToResult[questionId].ansIdToVouch[answerId].vouched;
        require(vouched > 0, IFacts.EmptyOrRedeemedVouched());

        uint256 amountToRedeem = vouched;
        // if the answerId the voucher is vouching for happens to be the overthrown answer, slash the voucher
        if (question.slotData.challengeSucceeded && question.slotData.overthrownAnswerId == answerId) {
            amountToRedeem -= calcSlashAmount(vouched, config.challengeConfig.slashVoucherBP);
        }

        usersInfo[msg.sender].qidToResult[questionId].ansIdToVouch[answerId].vouched = 0;
        payable(msg.sender).transfer(amountToRedeem);
    }

    /// @notice Deposit to become a hunter/DAO
    /// @dev Deposit could be slashed and disqualify user from being a hunter/DAO,
    /// thus no restriction on deposit amount to allow user to be eligible again
    function deposit() public payable {
        usersInfo[msg.sender].deposited += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Reset engaging questionIds before withdrawing the full stake by checking if each engaged question is finalized
    /// @param numOfIds The number of questionIds to reset, won't verify if `engagingQIds` <=10
    function reset(uint256 numOfIds) external {
        uint256[] storage qIds = usersInfo[msg.sender].engagingQIds;
        uint256 len = qIds.length;
        if (len > _MAX_ELEMENTS_TO_DELETE) require(numOfIds <= qIds.length / 2, IFacts.ResetOutOfBound());

        for (uint256 i; i < (len > _MAX_ELEMENTS_TO_DELETE ? numOfIds : len); i++) {
            require(questions[qIds[i]].slotData.finalized, IFacts.NotFinalized());
            // delete `engagingQIds` directly if len <=10, for >10 use a fixed `numOfIds` to avoid OOG
            if (len <= _MAX_ELEMENTS_TO_DELETE) {
                if (i == len - 1) delete usersInfo[msg.sender].engagingQIds;
            } else {
                qIds[i] = qIds[qIds.length - 1];
                qIds.pop();
            }
        }
    }

    /// @notice Withdraw full amount of stake, only callable when not engaging with any question
    /// @param recipient The address to receive the withdrawn stake
    function withdraw(address recipient) external {
        // to prevent users from withdrawing before finalizing whether they will get slashed or not
        require(usersInfo[msg.sender].engagingQIds.length == 0, IFacts.OnlyWhenNotEngaging());

        uint256 deposited = usersInfo[msg.sender].deposited;
        usersInfo[msg.sender].deposited = 0;
        payable(recipient).transfer(uint256(deposited));

        emit Withdrawn(msg.sender, deposited);
    }

    /*//////////////////////////////////////////////////////////////
                         DISPUTE RELATED LOGIC
    //////////////////////////////////////////////////////////////*/
    /// @notice Challenge the answer with the most vouched stake by paying $HYPE only if there is a bounty for the question
    /// @dev Only can challenge if the submitted answer is not same as the most vouched answer(or as the answer that is the only one but with no vouch)
    /// @param questionId The id of the question
    /// @param encodedAnswer The encoded answer to challenge
    function challenge(uint256 questionId, bytes calldata encodedAnswer) external payable returns (uint16 answerId) {
        require(isWithinChallengePeriod(questionId), IFacts.NotInChallengePeriod());
        require(msg.value == config.systemConfig.challengeDeposit, IFacts.InsufficientDeposit());
        uint16 mostVouchedAnsId = getMostVouchedAnsId(questionId);
        require(
            questions[questionId].bountyAmount > 0 || mostVouchedAnsId != type(uint16).max,
            IFacts.UnnecessaryChallenge()
        );
        Answer memory mostVouchedAns = qidToAnswers[questionId][mostVouchedAnsId];
        require(
            // checking if the number is the same applies to both binary and number question types
            abi.decode(encodedAnswer, (uint256)) != abi.decode(mostVouchedAns.encodedAnswer, (uint256)),
            IFacts.CannotChallengeSameAns()
        );
        require(mostVouchedAns.hunter != msg.sender, IFacts.CannotChallengeSelf());

        // pay $HYPE to protocol immediately as fee
        payable(PROTOCOL_FEE_RECEIVER).transfer(config.systemConfig.challengeDeposit);

        questions[questionId].slotData.challenged = true;
        answerId = uint16(qidToAnswers[questionId].length);
        qidToAnswers[questionId].push(
            Answer({hunter: msg.sender, encodedAnswer: encodedAnswer, byChallenger: true, totalVouched: 0})
        );

        emit Challenged(questionId, answerId, msg.sender);
    }

    /// @notice Settle the question, callable by anyone as long as no challenge is involved for the question, or else only callable by owner
    /// @param questionId The id of the question
    /// @param selectedAnswerId The selected answer id to replace the most vouched answer, only verify this if challenge is involved & called by owner
    /// @param challengeSucceeded To indicate if the challenge is succeeded, only verify this if challenge is involved & called by owner
    function settle(uint256 questionId, uint16 selectedAnswerId, bool challengeSucceeded) external {
        Question memory question = questions[questionId];
        require(!question.slotData.finalized, IFacts.AlreadyFinalized());

        uint16 mostVouchedAnsId = getMostVouchedAnsId(questionId);
        // either no answer is submitted or all answers have same vouched amount(or no one vouch)
        if (mostVouchedAnsId == type(uint16).max) {
            require(afterHuntPeriod(questionId), IFacts.OnlyAfterHuntPeriod());
            // if there's no winner, the question is automatically finalized and no bounty will need to be distributed
            questions[questionId].slotData.finalized = true;
            // return bounty to seeker
            _transferBounty(question.bountyToken, question.seeker, question.bountyAmount);
        } else {
            // NOTE: no matter challengeSucceeded is true or false, the result can still be overridden by the council
            // only bounty amount > 0 will involve challenge so daoFee != 0 means DAO already called settle
            if (question.slotData.challenged && platformFees[questionId].daoFee == 0 && !question.slotData.overridden) {
                // only require to within settle period if challenge is involved
                require(isWithinSettlePeriod(questionId), IFacts.NotInSettlePeriod());
                require(isDAO(msg.sender), IFacts.OnlyDAO());

                _settleByDAO(questionId, mostVouchedAnsId, selectedAnswerId, challengeSucceeded);
            } else if (!question.slotData.challenged) {
                // callable by anyone after challenge period is over and no challenge is raised
                require(afterChallengePeriod(questionId), IFacts.OnlyAfterChallengePeriod());

                _settleByUser(questionId, mostVouchedAnsId);
            } else {
                revert IFacts.AlreadySettledByDAO();
            }
        }
    }

    /// @notice Override the settlement result from the DAO as Council
    /// @param questionId The id of the question
    /// @param finalAnswerId The answer id decided to be the final winner
    function overrideSettlement(uint256 questionId, uint16 finalAnswerId) external {
        require(msg.sender == COUNCIL, IFacts.OnlyCouncil());
        // storage pointer to save gas on reading only certain variables
        Question storage question = questions[questionId];
        require(isWithinReviewPeriod(questionId), IFacts.NotInReviewPeriod());
        // there exists no scenario where within review period challenged & finalized can both be true so no need to check finalized
        require(question.slotData.challenged, IFacts.NotChallenged());

        // return all fees back to hunter and voucher
        platformFees[questionId].protocolFee = 0;
        platformFees[questionId].daoFee = 0;

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
        require(afterReviewPeriod(questionId), IFacts.OnlyAfterReviewPeriod());
        require(!slotData.finalized, IFacts.AlreadyFinalized());

        questions[questionId].slotData.finalized = true;

        // if challenge result is overridden, slash DAO voters
        if (slotData.overridden) {
            _slashDAOToProtocol();
        } else if (slotData.challengeSucceeded) {
            // if result is being challenged successfully, slash hunter
            // vouchers will be slashed individually when they redeem their principal
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
        require(msg.sender == owner() || msg.sender == PROTOCOL_FEE_RECEIVER, IFacts.OnlyOwnerOrFeeReceiver());
        _claimPlatformFee(questionIds, recipient);

        emit ClaimedPlatformFee(recipient);
    }

    /// @notice Set the system config
    /// @param systemConfig The system config to set
    /// @dev Each config must be >0
    function setSystemConfig(SystemConfig memory systemConfig) external onlyOwner {
        require(
            systemConfig.requiredStakeToHunt != 0 && systemConfig.requiredStakeForDAO != 0
                && systemConfig.challengeDeposit != 0 && systemConfig.minVouched != 0 && systemConfig.huntPeriod != 0
                && systemConfig.challengePeriod != 0 && systemConfig.settlePeriod != 0 && systemConfig.reviewPeriod != 0,
            IFacts.InvalidConfig()
        );

        config.systemConfig = systemConfig;
    }

    /// @notice Set the distribution config
    /// @param distributionConfig The distribution config to set
    /// @dev protocolBP = BASIS_POINTS - hunterBP - voucherBP so hunterBP & voucherBP must add up to <100%
    function setDistributionConfig(BountyDistributionConfig memory distributionConfig) external onlyOwner {
        require(distributionConfig.hunterBP + distributionConfig.voucherBP < _BASIS_POINTS, IFacts.InvalidConfig());

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
            IFacts.InvalidConfig()
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
        Fees storage fees = platformFees[questionId];

        if (challengeSucceeded) {
            question.slotData.answerId = selectedAnswerId;
            question.slotData.overthrownAnswerId = mostVouchedAnsId;
            question.slotData.challengeSucceeded = true;

            // distribute bounty in half to protocol and DAO if challenge is successful
            fees.protocolFee += question.bountyAmount / 2;
            fees.daoFee += question.bountyAmount / 2;
        } else {
            // distribute part of bounty as operation fee to DAO for reviewing the challenge
            fees.daoFee += (question.bountyAmount * config.challengeConfig.daoOpFeeBP) / _BASIS_POINTS;
        }
        // to prevent DAO from withdrawing before finalizing whether they will get slashed or not
        usersInfo[owner()].engagingQIds.push(questionId);
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

        usersInfo[hunter].qidToResult[questionId].hunterClaimable = (question.bountyAmount * hunterBP) / _BASIS_POINTS;
        platformFees[questionId].protocolFee += (question.bountyAmount * protocolBP) / _BASIS_POINTS;
    }

    function _slashDAOToProtocol() internal {
        address dao = owner();
        uint256 slashAmount = calcSlashAmount(usersInfo[dao].deposited, config.challengeConfig.slashDaoBP);
        usersInfo[dao].deposited -= slashAmount;
        // slash DAO voters’ $HYPE to protocol
        payable(PROTOCOL_FEE_RECEIVER).transfer(slashAmount);
    }

    function _slashHunterToChallenger(uint256 questionId) internal {
        Answer memory overthrownAnswer = qidToAnswers[questionId][questions[questionId].slotData.overthrownAnswerId];
        Answer memory finalAnswer = qidToAnswers[questionId][questions[questionId].slotData.answerId];

        uint256 slashAmount =
            calcSlashAmount(usersInfo[overthrownAnswer.hunter].deposited, config.challengeConfig.slashHunterBP);
        // slash stake from hunter and send to the challenger
        usersInfo[overthrownAnswer.hunter].deposited -= slashAmount;
        payable(finalAnswer.hunter).transfer(uint256(slashAmount));
    }

    function _claimBounty(uint256 questionId, address claimer, bool asHunter) internal returns (uint256 claimAmount) {
        Question memory question = questions[questionId];
        Result storage result = usersInfo[claimer].qidToResult[questionId];
        if (asHunter) {
            claimAmount = result.hunterClaimable;
            result.hunterClaimable = 0;
        } else {
            uint16 finalAnsId = question.slotData.answerId;
            // vouchers won't be eligible for bounty if challenge is successful
            if (!question.slotData.challengeSucceeded && !result.ansIdToVouch[finalAnsId].claimed) {
                result.ansIdToVouch[finalAnsId].claimed = true;
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
            require(questions[questionIds[i]].slotData.finalized, IFacts.NotFinalized());

            address bountyToken = questions[questionIds[i]].bountyToken;
            uint256 protocolFee = platformFees[questionIds[i]].protocolFee;
            uint256 daoFee = platformFees[questionIds[i]].daoFee;

            isProtocolFeeReceiver
                ? platformFees[questionIds[i]].protocolFee = 0
                : platformFees[questionIds[i]].daoFee = 0;

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

    /// @notice Get the ids of questions that the user is engaging in
    /// @param user The address of the user
    /// @return engagingQIds The ids of questions that the user is engaging in
    function getUserEngagingQIds(address user) external view returns (uint256[] memory) {
        return usersInfo[user].engagingQIds;
    }

    /// @notice Get the result of a question for a user
    /// @param user The address of the user
    /// @param questionId The id of the question
    /// @param answerId The id of the answer
    /// @return hunterClaimable The hunter claimable amount
    /// @return vouched The vouched amount
    /// @return claimed Whether the answer has been claimed
    function getUserQuestionResult(address user, uint256 questionId, uint16 answerId)
        external
        view
        returns (uint256 hunterClaimable, uint248 vouched, bool claimed)
    {
        Result storage result = usersInfo[user].qidToResult[questionId];
        return (result.hunterClaimable, result.ansIdToVouch[answerId].vouched, result.ansIdToVouch[answerId].claimed);
    }

    /// @notice Find the most truthful answer by checking which answer has the most vouched amount for a question
    /// @param questionId The id of the question
    /// @return winnerAnsId The id of the most truthful answer, type(uint16).max indicates no winner is found
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
        uint256 vouched = usersInfo[voucher].qidToResult[questionId].ansIdToVouch[answerId].vouched;
        // claim by the share of own vouched amount to the total vouched amount of correct answer
        uint256 share = (vouched * _WAD) / qidToAnswers[questionId][answerId].totalVouched / _WAD;
        claimable = (bountyAmount * share * config.distributionConfig.voucherBP) / _BASIS_POINTS;
    }

    /// @notice Calculate the slash amount
    /// @param amount The total amount to slash from
    /// @param slashBP The slash BP
    /// @return slashAmount The slash amount
    function calcSlashAmount(uint256 amount, uint64 slashBP) public pure returns (uint256) {
        return amount * slashBP / _BASIS_POINTS;
    }

    /// @notice Check if a user is a hunter
    /// @param user The address of the user
    /// @return isHunter Whether the user is a hunter
    function isHunter(address user) public view returns (bool) {
        return usersInfo[user].deposited >= config.systemConfig.requiredStakeToHunt;
    }

    /// @notice Check if a user is a DAO
    /// @param user The address of the user
    /// @return isDAO Whether the user is a DAO
    function isDAO(address user) public view returns (bool) {
        return user == owner() && usersInfo[user].deposited >= config.systemConfig.requiredStakeForDAO;
    }

    /// @notice Check if a question is within the hunt period
    /// @param questionId The id of the question
    /// @return isWithinHuntPeriod Whether the question is within the hunt period
    function isWithinHuntPeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        return block.timestamp > question.slotData.startHuntAt && block.timestamp <= question.slotData.endHuntAt;
    }

    /// @notice Check if a question is within the challenge period
    /// @param questionId The id of the question
    /// @return isWithinChallengePeriod Whether the question is within the challenge period
    function isWithinChallengePeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        return block.timestamp > question.slotData.endHuntAt
            && block.timestamp <= question.slotData.endHuntAt + config.systemConfig.challengePeriod;
    }

    /// @notice Check if a question is within the settle period
    /// @param questionId The id of the question
    /// @return isWithinSettlePeriod Whether the question is within the settle period
    function isWithinSettlePeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        SystemConfig memory systemConfig = config.systemConfig;

        return block.timestamp > question.slotData.endHuntAt + systemConfig.challengePeriod
            && block.timestamp <= question.slotData.endHuntAt + systemConfig.challengePeriod + systemConfig.settlePeriod;
    }

    /// @notice Check if a question is within the review period
    /// @param questionId The id of the question
    /// @return isWithinReviewPeriod Whether the question is within the review period
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
    /// @return isAfterHuntPeriod Whether the question is after the hunt period
    function afterHuntPeriod(uint256 questionId) public view returns (bool) {
        return block.timestamp > questions[questionId].slotData.endHuntAt;
    }

    /// @notice Check if a question is after the challenge period
    /// @param questionId The id of the question
    /// @return isAfterChallengePeriod Whether the question is after the challenge period
    function afterChallengePeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        SystemConfig memory systemConfig = config.systemConfig;
        return block.timestamp > question.slotData.endHuntAt + systemConfig.challengePeriod;
    }

    /// @notice Check if a question is after the review period
    /// @param questionId The id of the question
    /// @return isAfterReviewPeriod Whether the question is after the review period
    function afterReviewPeriod(uint256 questionId) public view returns (bool) {
        Question memory question = questions[questionId];
        SystemConfig memory systemConfig = config.systemConfig;

        return block.timestamp
            > question.slotData.endHuntAt + systemConfig.challengePeriod + systemConfig.settlePeriod
                + systemConfig.reviewPeriod;
    }
}
