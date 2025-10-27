// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CryptexFlowSystems
 * @dev A decentralized payment streaming and escrow management system
 * @notice This contract enables continuous payment flows and secure fund management
 */
contract CryptexFlowSystems {
    
    // Structs
    struct PaymentStream {
        address sender;
        address recipient;
        uint256 totalAmount;
        uint256 startTime;
        uint256 duration;
        uint256 withdrawnAmount;
        bool active;
    }
    
    struct Escrow {
        address payer;
        address payee;
        uint256 amount;
        bool released;
        bool refunded;
        uint256 deadline;
    }
    
    // State variables
    mapping(uint256 => PaymentStream) public paymentStreams;
    mapping(uint256 => Escrow) public escrows;
    uint256 public streamCounter;
    uint256 public escrowCounter;
    
    // Events
    event StreamCreated(uint256 indexed streamId, address indexed sender, address indexed recipient, uint256 amount, uint256 duration);
    event StreamWithdrawn(uint256 indexed streamId, address indexed recipient, uint256 amount);
    event StreamCancelled(uint256 indexed streamId, uint256 refundAmount);
    event EscrowCreated(uint256 indexed escrowId, address indexed payer, address indexed payee, uint256 amount, uint256 deadline);
    event EscrowReleased(uint256 indexed escrowId, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, uint256 amount);
    
    // Modifiers
    modifier streamExists(uint256 streamId) {
        require(streamId < streamCounter, "Stream does not exist");
        _;
    }
    
    modifier escrowExists(uint256 escrowId) {
        require(escrowId < escrowCounter, "Escrow does not exist");
        _;
    }
    
    /**
     * @dev Creates a new payment stream
     * @param recipient Address that will receive the streamed payments
     * @param duration Duration of the stream in seconds
     * @notice Sender must send ETH with this transaction
     */
    function createPaymentStream(address recipient, uint256 duration) external payable returns (uint256) {
        require(recipient != address(0), "Invalid recipient address");
        require(msg.value > 0, "Must send ETH to create stream");
        require(duration > 0, "Duration must be greater than zero");
        
        uint256 streamId = streamCounter++;
        
        paymentStreams[streamId] = PaymentStream({
            sender: msg.sender,
            recipient: recipient,
            totalAmount: msg.value,
            startTime: block.timestamp,
            duration: duration,
            withdrawnAmount: 0,
            active: true
        });
        
        emit StreamCreated(streamId, msg.sender, recipient, msg.value, duration);
        return streamId;
    }
    
    /**
     * @dev Allows recipient to withdraw available streamed funds
     * @param streamId ID of the payment stream
     */
    function withdrawFromStream(uint256 streamId) external streamExists(streamId) {
        PaymentStream storage stream = paymentStreams[streamId];
        require(msg.sender == stream.recipient, "Only recipient can withdraw");
        require(stream.active, "Stream is not active");
        
        uint256 availableAmount = getAvailableBalance(streamId);
        require(availableAmount > 0, "No funds available to withdraw");
        
        stream.withdrawnAmount += availableAmount;
        
        // Check if stream is completed
        if (block.timestamp >= stream.startTime + stream.duration) {
            stream.active = false;
        }
        
        payable(stream.recipient).transfer(availableAmount);
        emit StreamWithdrawn(streamId, stream.recipient, availableAmount);
    }
    
    /**
     * @dev Cancels an active payment stream and refunds remaining balance
     * @param streamId ID of the payment stream
     */
    function cancelStream(uint256 streamId) external streamExists(streamId) {
        PaymentStream storage stream = paymentStreams[streamId];
        require(msg.sender == stream.sender, "Only sender can cancel stream");
        require(stream.active, "Stream is not active");
        
        uint256 availableToRecipient = getAvailableBalance(streamId);
        uint256 refundToSender = stream.totalAmount - stream.withdrawnAmount - availableToRecipient;
        
        stream.active = false;
        
        if (availableToRecipient > 0) {
            stream.withdrawnAmount += availableToRecipient;
            payable(stream.recipient).transfer(availableToRecipient);
        }
        
        if (refundToSender > 0) {
            payable(stream.sender).transfer(refundToSender);
        }
        
        emit StreamCancelled(streamId, refundToSender);
    }
    
    /**
     * @dev Creates an escrow arrangement with a deadline
     * @param payee Address that will receive funds upon release
     * @param deadline Timestamp after which funds can be refunded
     */
    function createEscrow(address payee, uint256 deadline) external payable returns (uint256) {
        require(payee != address(0), "Invalid payee address");
        require(msg.value > 0, "Must send ETH to create escrow");
        require(deadline > block.timestamp, "Deadline must be in the future");
        
        uint256 escrowId = escrowCounter++;
        
        escrows[escrowId] = Escrow({
            payer: msg.sender,
            payee: payee,
            amount: msg.value,
            released: false,
            refunded: false,
            deadline: deadline
        });
        
        emit EscrowCreated(escrowId, msg.sender, payee, msg.value, deadline);
        return escrowId;
    }
    
    /**
     * @dev Releases escrow funds to the payee
     * @param escrowId ID of the escrow
     */
    function releaseEscrow(uint256 escrowId) external escrowExists(escrowId) {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.payer, "Only payer can release escrow");
        require(!escrow.released && !escrow.refunded, "Escrow already settled");
        
        escrow.released = true;
        payable(escrow.payee).transfer(escrow.amount);
        
        emit EscrowReleased(escrowId, escrow.amount);
    }
    
    /**
     * @dev Refunds escrow funds to payer after deadline
     * @param escrowId ID of the escrow
     */
    function refundEscrow(uint256 escrowId) external escrowExists(escrowId) {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.payer, "Only payer can request refund");
        require(!escrow.released && !escrow.refunded, "Escrow already settled");
        require(block.timestamp >= escrow.deadline, "Deadline has not passed");
        
        escrow.refunded = true;
        payable(escrow.payer).transfer(escrow.amount);
        
        emit EscrowRefunded(escrowId, escrow.amount);
    }
    
    /**
     * @dev Calculates available balance for a payment stream
     * @param streamId ID of the payment stream
     * @return Available amount that can be withdrawn
     */
    function getAvailableBalance(uint256 streamId) public view streamExists(streamId) returns (uint256) {
        PaymentStream memory stream = paymentStreams[streamId];
        
        if (!stream.active) {
            return 0;
        }
        
        uint256 elapsed = block.timestamp - stream.startTime;
        
        if (elapsed >= stream.duration) {
            return stream.totalAmount - stream.withdrawnAmount;
        }
        
        uint256 totalAvailable = (stream.totalAmount * elapsed) / stream.duration;
        return totalAvailable - stream.withdrawnAmount;
    }
    
    /**
     * @dev Gets stream details
     * @param streamId ID of the payment stream
     */
    function getStreamDetails(uint256 streamId) external view streamExists(streamId) returns (
        address sender,
        address recipient,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration,
        uint256 withdrawnAmount,
        bool active
    ) {
        PaymentStream memory stream = paymentStreams[streamId];
        return (
            stream.sender,
            stream.recipient,
            stream.totalAmount,
            stream.startTime,
            stream.duration,
            stream.withdrawnAmount,
            stream.active
        );
    }
    
    /**
     * @dev Gets escrow details
     * @param escrowId ID of the escrow
     */
    function getEscrowDetails(uint256 escrowId) external view escrowExists(escrowId) returns (
        address payer,
        address payee,
        uint256 amount,
        bool released,
        bool refunded,
        uint256 deadline
    ) {
        Escrow memory escrow = escrows[escrowId];
        return (
            escrow.payer,
            escrow.payee,
            escrow.amount,
            escrow.released,
            escrow.refunded,
            escrow.deadline
        );
    }
}