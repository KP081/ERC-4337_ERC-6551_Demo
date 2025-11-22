// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../interfaces/IPaymaster.sol";
import "../interfaces/IEntryPoint.sol";

/**
 * @title SimplePaymaster
 * @notice Paymaster that sponsors transactions based on whitelist or signature
 */
contract SimplePaymaster is IPaymaster, Ownable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    IEntryPoint public immutable entryPoint;

    // Whitelist mode
    mapping(address => bool) public whitelist;

    // Sponsorship tracking
    mapping(address => uint256) public sponsoredGas;

    // Events
    event UserWhitelisted(address indexed user);
    event UserRemovedFromWhitelist(address indexed user);
    event GasSponsored(address indexed user, uint256 actualGasCost);

    constructor(IEntryPoint _entryPoint) Ownable(msg.sender) {
        entryPoint = _entryPoint;
    }

    /**
     * @notice Validate if we should sponsor this operation
     */
    function validatePaymasterUserOp (
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external override view returns (bytes memory context, uint256 validationData) {
        require(msg.sender == address(entryPoint), "Not from EntryPoint");

        // Check if user is whitelisted
        require(whitelist[userOp.sender], "User not whitelisted");

        // Check if we have enough deposit
        require(
            entryPoint.balanceOf(address(this)) >= maxCost,
            "Insufficient deposit"
        );

        // Return context for postOp
        context = abi.encode(userOp.sender, maxCost);

        // Return 0 for successful validation
        return (context, 0);
    }

    /**
     * @notice Post-operation handler
     */
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external override {
        require(msg.sender == address(entryPoint), "Not from EntryPoint");

        // Decode context
        (address user, ) = abi.decode(context, (address, uint256));

        // Track sponsored gas
        sponsoredGas[user] += actualGasCost;

        emit GasSponsored(user, actualGasCost);
    }

    /**
     * @notice Add user to whitelist
     */
    function addToWhitelist(address user) external onlyOwner {
        whitelist[user] = true;
        emit UserWhitelisted(user);
    }

    /**
     * @notice Remove user from whitelist
     */
    function removeFromWhitelist(address user) external onlyOwner {
        whitelist[user] = false;
        emit UserRemovedFromWhitelist(user);
    }

    /**
     * @notice Deposit to EntryPoint
     */
    function deposit() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }

    /**
     * @notice Get deposit balance at EntryPoint
     */
    function getDeposit() external view returns (uint256) {
        return entryPoint.balanceOf(address(this));
    }

    // Receive ETH
    receive() external payable {
        entryPoint.depositTo{value: msg.value}(address(this));
    }
}
