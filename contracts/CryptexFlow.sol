// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title CryptexFlow
 * @notice A decentralized platform for creating, managing, and tracking crypto flows between users.
 */
contract CryptexFlow {

    address public admin;
    uint256 public flowCount;

    struct Flow {
        uint256 id;
        address sender;
        address recipient;
        uint256 amount;         // Total amount to be streamed
        uint256 startTime;
        uint256 endTime;
        uint256 withdrawn;      // Amount already withdrawn by recipient
        bool active;
    }

    mapping(uint256 => Flow) public flows;
    mapping(address => uint256[]) public userFlows;

    event FlowCreated(uint256 indexed id, address indexed sender, address indexed recipient, uint256 amount, uint256 startTime, uint256 endTime);
    event FlowWithdrawn(uint256 indexed id, address indexed recipient, uint256 amount);
    event FlowStopped(uint256 indexed id);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "CryptexFlow: NOT_ADMIN");
        _;
    }

    modifier flowExists(uint256 id) {
        require(id > 0 && id <= flowCount, "CryptexFlow: FLOW_NOT_FOUND");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /// @notice Create a new crypto flow
    function createFlow(address recipient, uint256 amount, uint256 duration) external payable returns (uint256) {
        require(msg.value == amount, "CryptexFlow: INCORRECT_AMOUNT");
        require(recipient != address(0), "CryptexFlow: INVALID_RECIPIENT");
        require(duration > 0, "CryptexFlow: INVALID_DURATION");

        flowCount++;
        flows[flowCount] = Flow({
            id: flowCount,
            sender: msg.sender,
            recipient: recipient,
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            withdrawn: 0,
            active: true
        });

        userFlows[msg.sender].push(flowCount);
        userFlows[recipient].push(flowCount);

        emit FlowCreated(flowCount, msg.sender, recipient, amount, block.timestamp, block.timestamp + duration);
        return flowCount;
    }

    /// @notice Withdraw available funds from an active flow
    function withdraw(uint256 flowId) external flowExists(flowId) {
        Flow storage f = flows[flowId];
        require(f.active, "CryptexFlow: INACTIVE_FLOW");
        require(msg.sender == f.recipient, "CryptexFlow: UNAUTHORIZED");

        uint256 elapsed = block.timestamp > f.endTime ? f.endTime - f.startTime : block.timestamp - f.startTime;
        uint256 totalAvailable = (f.amount * elapsed) / (f.endTime - f.startTime);
        uint256 withdrawable = totalAvailable - f.withdrawn;
        require(withdrawable > 0, "CryptexFlow: NOTHING_TO_WITHDRAW");

        f.withdrawn += withdrawable;
        payable(f.recipient).transfer(withdrawable);

        emit FlowWithdrawn(flowId, f.recipient, withdrawable);
    }

    /// @notice Stop a flow prematurely (only sender or admin)
    function stopFlow(uint256 flowId) external flowExists(flowId) {
        Flow storage f = flows[flowId];
        require(f.active, "CryptexFlow: ALREADY_STOPPED");
        require(msg.sender == f.sender || msg.sender == admin, "CryptexFlow: UNAUTHORIZED");

        // Withdraw any remaining funds to recipient
        uint256 elapsed = block.timestamp > f.endTime ? f.endTime - f.startTime : block.timestamp - f.startTime;
        uint256 totalAvailable = (f.amount * elapsed) / (f.endTime - f.startTime);
        uint256 withdrawable = totalAvailable - f.withdrawn;
        if (withdrawable > 0) {
            f.withdrawn += withdrawable;
            payable(f.recipient).transfer(withdrawable);
            emit FlowWithdrawn(flowId, f.recipient, withdrawable);
        }

        f.active = false;
        emit FlowStopped(flowId);
    }

    function getFlow(uint256 id) external view flowExists(id) returns (Flow memory) {
        return flows[id];
    }

    function getUserFlows(address user) external view returns (uint256[] memory) {
        return userFlows[user];
    }

    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "CryptexFlow: ZERO_ADMIN");
        emit AdminChanged(admin, newAdmin);
        admin = newAdmin;
    }
}
