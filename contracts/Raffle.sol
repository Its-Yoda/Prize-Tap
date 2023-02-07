// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";

contract Raffle is Ownable, ReentrancyGuard, VRFConsumerBaseV2{
    VRFCoordinatorV2Interface public COORDINATOR;
    LinkTokenInterface LINKTOKEN;

    address private constant vrfCoordinator = 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D;
    address private constant link_token_contract = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;
    bytes32 private constant keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;

    uint32 private constant callbackGasLimit = 100_000;

    uint32 private constant numWords = 1;

    uint16 private constant requestConfirmations = 3;
 
    uint64 private subscriptionId;

    struct RequestRandomStatus {
        bool fulfilled; 
        bool exists;
        uint[] randomWords;
        uint raffleId;
        address raffleCreatorAddr;
    
    }
    mapping(uint256 => RequestRandomStatus) private requests;


    enum RAFFLE_STATUS{
        FINISHED,
        CLOSED,
        OPEN
        
    }

    struct RaffleStruct{

        RAFFLE_STATUS raffle_status;

        uint raffleStartTime;

        uint raffleEndTime;

        uint prizeAmount;

        address[] participantsAddrList;

        address winnerAddr;

        mapping(address => bool) participants;
        // mapping(address => prizeAmount) prize;
        
    }

    mapping(address => mapping(uint => RaffleStruct)) public raffles;

    event _createRandom(uint256 indexed requestId);


    constructor (
    ) VRFConsumerBaseV2(vrfCoordinator) {

        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        LINKTOKEN = LinkTokenInterface(link_token_contract);

        createSubscription();

        addConsumer(msg.sender);
    }



    function createSubscription() private{
        subscriptionId = COORDINATOR.createSubscription();
    }

    function createNewSubscription() external onlyOwner{
        createSubscription();
    }

    function getSubscription() external view onlyOwner returns(uint64 subId){
        subId = subscriptionId;
    }
    
    function cancelSubscription(address receivingWallet) external onlyOwner {
        // Cancel the subscription and send the remaining LINK to a wallet address.
        COORDINATOR.cancelSubscription(subscriptionId, receivingWallet);
        subscriptionId = 0;
    }

    function addConsumer(address consumerAddress) private {
        // Add a consumer contract to the subscription.
        COORDINATOR.addConsumer(subscriptionId, consumerAddress);
    }

    function removeConsumer(address consumerAddress) private {
        // Remove a consumer contract from the subscription.
        COORDINATOR.removeConsumer(subscriptionId, consumerAddress);
    }

    function topUpSubscription(uint amount) external onlyOwner {
        //send LINK to the subscription balance.
        LINKTOKEN.transferAndCall(address(COORDINATOR), amount * 10**18, abi.encode(subscriptionId));
    }

    function withdraw(uint amount, address to) external onlyOwner nonReentrant{
        //Transfer this contract's funds to an address.
        LINKTOKEN.transfer(to, amount * 10**18);
    }


    function requestRandomWords() private {

        require(!requests[requestId].fulfilled, "Raffle: The winner has already been determined!");

        uint requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        requests[requestId] = RequestRandomStatus({
            randomWords: new uint[](0),
            exists: true,
            fulfilled: false,
            raffleCreatorAddr: raffleCreatorAddr,
            raffleId: raffleId
        });
    }
    

    function fulfillRandomWords(uint requestId, uint[] memory randomWords) internal override {
        require(requests[requestId].exists, "Raffle: Request not found");
        require(randomWords[0] > 0, "Raffle: Random not found");
        
        requests[requestId].fulfilled = true;
        requests[requestId].randomWords = randomWords;

        calculatingWinner(requestId);

    }


    function calculatingWinner(uint requestId) private{

        address raffleCreatorAddr = requests[requestId].raffleCreatorAddr;
        uint raffleId = requests[requestId].raffleId;
        uint randomness = requests[requestId].randomWords[0];

        RaffleStruct storage raffle = raffles[raffleCreatorAddr][raffleId];

        uint indexOfWinner = randomness % raffle.participantsAddrList.length;
        raffle.winnerAddr = raffle.participantsAddrList[indexOfWinner];

        removeConsumer(raffleCreatorAddr);
    }
 
 


    function createRaffle(uint deadLineToDay, uint raffleId) external payable{
        
        uint raffleStartTime = block.timestamp;
        uint raffleEndTime = raffleStartTime + (deadLineToDay * 3600 seconds);

        RaffleStruct storage newRaffle = raffles[msg.sender][raffleId];
        newRaffle.raffle_status = RAFFLE_STATUS.OPEN;
        newRaffle.raffleStartTime = raffleStartTime;
        newRaffle.raffleEndTime = raffleEndTime;
        newRaffle.prizeAmount = msg.value;

        addConsumer(msg.sender);
    
    }


    function registerInRaffle(address raffleCreatorAddr, uint raffleId) external addressAllowed(raffleId) notRegistered(raffleCreatorAddr, raffleId) isOpenRaffleStatus(raffleCreatorAddr, raffleId){
        RaffleStruct storage raffle = raffles[raffleCreatorAddr][raffleId];
       
        raffle.participants[msg.sender] = true;
        raffle.participantsAddrList.push(msg.sender);
           
    }

    
    function closeRaffle(address raffleCreatorAddr, uint raffleId) external isClosedRaffleStatus(raffleCreatorAddr, raffleId) onlyOwner onlyRaffleCreator(raffleCreatorAddr, raffleId){

        RaffleStruct storage raffle = raffles[raffleCreatorAddr][raffleId];
        raffle.raffle_status = RAFFLE_STATUS.CLOSED;

        requestRandomWords(raffleCreatorAddr, raffleId);

    } 

    function claimPrize(address raffleCreatorAddr, uint raffleId) external isClosedRaffleStatus(raffleCreatorAddr, raffleId) onlyWinner(raffleCreatorAddr, raffleId) nonReentrant{
        RaffleStruct storage raffle = raffles[raffleCreatorAddr][raffleId];
        uint prizeAmount = raffle.prizeAmount;

        require(getContractBalance() >= prizeAmount, "Raffle: Not enough balance");

        (bool result, ) = payable(msg.sender).call{value : prizeAmount}("");

        require(result, "Failure to send");
        
        raffle.raffle_status = RAFFLE_STATUS.FINISHED;
    }


    function getContractBalance() public view onlyOwner returns(uint){
        return address(this).balance / 10**18;
    }

    function increaseContractBalance() external payable {}



    //modifiers
    modifier notRegistered(address raffleCreatorAddr, uint raffleId){
        require(!raffles[raffleCreatorAddr][raffleId].participants[msg.sender], "Raffle: You already participant");
        _;
    }

    modifier onlyWinner(address raffleCreatorAddr, uint raffleId){
        require(raffles[raffleCreatorAddr][raffleId].winnerAddr == msg.sender, "Raffle: You didn't won");
        _;
    }

    modifier onlyRaffleCreator(address raffleCreatorAddr, uint raffleId){
        require(raffles[msg.sender][raffleId].raffle_status == RAFFLE_STATUS.OPEN, "Raffle: Only owner or raffle creator can close raffle!");
        _;
    }

    modifier addressAllowed(uint raffleId){
        require(raffles[msg.sender][raffleId].raffle_status == RAFFLE_STATUS.FINISHED, "Raffle: Raffle creator cannot participate!");
        _;
    }

    modifier isClosedRaffleStatus(address raffleCreatorAddr, uint raffleId){
        require(raffles[raffleCreatorAddr][raffleId].raffle_status == RAFFLE_STATUS.CLOSED || 
        raffles[raffleCreatorAddr][raffleId].raffleEndTime < block.timestamp, "Raffle: The current raffle is open yet!");
        _;
    }

    modifier isOpenRaffleStatus(address raffleCreatorAddr, uint raffleId){
        require(raffles[raffleCreatorAddr][raffleId].raffle_status == RAFFLE_STATUS.OPEN || raffles[raffleCreatorAddr][raffleId].raffleEndTime > block.timestamp, "Raffle: Raffle ended!");
        _;
    }

    
}