// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title CryptexFlow
 * @notice A decentralized liquidity stream management contract that allows users to
 *         deposit, stream, and withdraw tokens over time in a trustless manner.
 */
contract Project {
    address public admin;
    uint256 public streamCount;

    struct Stream {
        uint256 id;
        address sender;
        address receiver;
        uint256 deposit;
        uint256 ratePerSecond;
        uint256 startTime;
        uint256 stopTime;
        bool active;
    }

    mapping(uint256 => Stream) public streams;

    event StreamCreated(uint256 indexed id, address indexed sender, address indexed receiver, uint256 deposit, uint256 duration);
    event StreamCancelled(uint256 indexed id);
    event Withdrawn(uint256 indexed id, address indexed receiver, uint256 amount);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can execute this");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /**
     * @notice Create a new streaming payment
     * @param _receiver Address of the receiver
     * @param _duration Duration of the stream in seconds
     */
    function createStream(address _receiver, uint256 _duration) external payable {
        require(msg.value > 0, "Deposit required");
        require(_receiver != address(0), "Invalid receiver");
        require(_duration > 0, "Invalid duration");

        uint256 ratePerSecond = msg.value / _duration;

        streamCount++;
        streams[streamCount] = Stream(
            streamCount,
            msg.sender,
            _receiver,
            msg.value,
            ratePerSecond,
            block.timestamp,
            block.timestamp + _duration,
            true
        );

        emit StreamCreated(streamCount, msg.sender, _receiver, msg.value, _duration);
    }

    /**
     * @notice Withdraw available funds from an active stream
     * @param _id Stream ID
     */
    function withdraw(uint256 _id) external {
        Stream storage s = streams[_id];
        require(s.active, "Stream inactive");
        require(msg.sender == s.receiver, "Only receiver can withdraw");

        uint256 elapsed = block.timestamp - s.startTime;
        if (block.timestamp > s.stopTime) elapsed = s.stopTime - s.startTime;

        uint256 owed = elapsed * s.ratePerSecond;
        require(owed <= s.deposit, "No balance available");

        s.deposit -= owed;
        payable(s.receiver).transfer(owed);

        if (block.timestamp >= s.stopTime) {
            s.active = false;
        }

        emit Withdrawn(_id, s.receiver, owed);
    }

    /**
     * @notice Cancel an active stream (admin only)
     * @param _id Stream ID
     */
    function cancelStream(uint256 _id) external onlyAdmin {
        Stream storage s = streams[_id];
        require(s.active, "Stream already inactive");

        s.active = false;
        payable(s.sender).transfer(s.deposit);

        emit StreamCancelled(_id);
    }

    /**
     * @notice Get details of a stream
     * @param _id Stream ID
     */
    function getStream(uint256 _id) external view returns (Stream memory) {
        return streams[_id];
    }
}
