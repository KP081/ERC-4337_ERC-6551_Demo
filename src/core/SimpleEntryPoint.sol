// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IEntryPoint.sol";
import "../interfaces/IAccount.sol";
import "../interfaces/IPaymaster.sol";
import "../interfaces/UserOperation.sol";

/**
 * @title SimpleEntryPoint
 * @notice Simplified EntryPoint for demo - Stack optimized version
 */
contract SimpleEntryPoint is IEntryPoint {
    // Storage
    mapping(address => uint256) public deposits;

    // Events
    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost
    );

    event Deposited(address indexed account, uint256 totalDeposit);
    event Withdrawn(address indexed account, uint256 amount);

    // Errors
    error ValidationFailed();
    error ExecutionFailed();
    error InsufficientDeposit();

    /**
     * @notice Main function to handle user operations
     */
    function handleOps(
        UserOperation[] calldata ops,
        address payable beneficiary
    ) external override {
        for (uint256 i = 0; i < ops.length; i++) {
            _handleOp(ops[i], beneficiary);
        }
    }

    /**
     * @notice Process single user operation
     */
    function _handleOp(
        UserOperation calldata userOp,
        address payable beneficiary
    ) internal {
        uint256 preGas = gasleft();
        bytes32 userOpHash = getUserOpHash(userOp);

        // Determine who pays (account or paymaster)
        address paymaster = _getPaymasterAddress(userOp);
        address payer = paymaster != address(0) ? paymaster : userOp.sender;

        // Phase 1: VALIDATION
        if (_validateOp(userOp, userOpHash) != 0) {
            revert ValidationFailed();
        }

        // Phase 2: EXECUTION
        bool success = _executeUserOp(userOp);

        // Phase 3: GAS ACCOUNTING
        uint256 actualGasCost = _calculateGasCost(preGas, userOp);
        _deductAndCompensate(payer, actualGasCost, beneficiary);

        emit UserOperationEvent(
            userOpHash,
            userOp.sender,
            paymaster,
            userOp.nonce,
            success,
            actualGasCost
        );
    }

    /**
     * @notice Calculate gas cost
     */
    function _calculateGasCost(
        uint256 preGas,
        UserOperation calldata userOp
    ) internal view returns (uint256) {
        uint256 gasUsed = preGas - gasleft() + userOp.preVerificationGas;
        // Use userOp.maxFeePerGas as fallback (tx.gasprice is 0 in tests)
        uint256 gasPrice = tx.gasprice > 0 ? tx.gasprice : userOp.maxFeePerGas;
        return gasUsed * gasPrice;
    }

    /**
     * @notice Deduct from payer and compensate bundler
     */
    function _deductAndCompensate(
        address payer,
        uint256 actualGasCost,
        address payable beneficiary
    ) internal {
        if (actualGasCost == 0) return;

        // Cap at available deposit
        uint256 toDeduct = actualGasCost;
        if (deposits[payer] < toDeduct) {
            toDeduct = deposits[payer];
        }

        // Deduct from payer
        deposits[payer] -= toDeduct;

        // Transfer to bundler if we have ETH
        if (toDeduct > 0 && address(this).balance >= toDeduct) {
            (bool sent, ) = beneficiary.call{value: toDeduct}("");
            if (!sent) {
                // Refund if transfer fails
                deposits[payer] += toDeduct;
            }
        }
    }

    /**
     * @notice Validate user operation (simplified to avoid stack issues)
     */
    function _validateOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal returns (uint256) {
        uint256 requiredPrefund = _getRequiredPrefund(userOp);
        address paymaster = _getPaymasterAddress(userOp);

        // Validate paymaster if present
        if (paymaster != address(0)) {
            if (
                !_validatePaymaster(
                    userOp,
                    userOpHash,
                    requiredPrefund,
                    paymaster
                )
            ) {
                return 1;
            }
        } else {
            // Account pays - check deposit
            if (deposits[userOp.sender] < requiredPrefund) {
                revert InsufficientDeposit();
            }
        }

        // Validate account signature
        return _validateAccount(userOp, userOpHash);
    }

    /**
     * @notice Validate paymaster
     */
    function _validatePaymaster(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPrefund,
        address paymaster
    ) internal returns (bool) {
        try
            IPaymaster(paymaster).validatePaymasterUserOp(
                userOp,
                userOpHash,
                requiredPrefund
            )
        returns (bytes memory, uint256 validationData) {
            if (validationData != 0) return false;
            if (deposits[paymaster] < requiredPrefund) {
                revert InsufficientDeposit();
            }
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Validate account signature
     */
    function _validateAccount(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal returns (uint256) {
        try
            IAccount(userOp.sender).validateUserOp(
                userOp,
                userOpHash,
                0 // No prefund request - we use deposit system
            )
        returns (uint256 validationData) {
            return validationData;
        } catch {
            return 1;
        }
    }

    /**
     * @notice Calculate required prefund for UserOp
     */
    function _getRequiredPrefund(
        UserOperation calldata userOp
    ) internal pure returns (uint256) {
        uint256 maxGas = userOp.callGasLimit +
            userOp.verificationGasLimit +
            userOp.preVerificationGas;
        return maxGas * userOp.maxFeePerGas;
    }

    /**
     * @notice Execute user operation
     */
    function _executeUserOp(
        UserOperation calldata userOp
    ) internal returns (bool success) {
        (success, ) = userOp.sender.call{gas: userOp.callGasLimit}(
            userOp.callData
        );
    }

    /**
     * @notice Get paymaster address from userOp
     */
    function _getPaymasterAddress(
        UserOperation calldata userOp
    ) internal pure returns (address) {
        if (userOp.paymasterAndData.length < 20) {
            return address(0);
        }
        return address(bytes20(userOp.paymasterAndData[0:20]));
    }

    /**
     * @notice Calculate hash of user operation
     */
    function getUserOpHash(
        UserOperation calldata userOp
    ) public view override returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    _packUserOpData(userOp),
                    block.chainid,
                    address(this)
                )
            );
    }

    /**
     * @notice Pack UserOp data for hashing (avoids stack too deep)
     */
    function _packUserOpData(
        UserOperation calldata userOp
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    userOp.sender,
                    userOp.nonce,
                    keccak256(userOp.initCode),
                    keccak256(userOp.callData),
                    userOp.callGasLimit,
                    userOp.verificationGasLimit,
                    userOp.preVerificationGas,
                    userOp.maxFeePerGas,
                    userOp.maxPriorityFeePerGas,
                    keccak256(userOp.paymasterAndData)
                )
            );
    }

    /**
     * @notice Deposit funds for gas payments
     */
    function depositTo(address account) external payable override {
        deposits[account] += msg.value;
        emit Deposited(account, deposits[account]);
    }

    /**
     * @notice Get deposit balance
     */
    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return deposits[account];
    }

    /**
     * @notice Withdraw deposit
     */
    function withdrawTo(
        address payable withdrawAddress,
        uint256 amount
    ) external {
        require(deposits[msg.sender] >= amount, "Insufficient deposit");
        deposits[msg.sender] -= amount;

        (bool success, ) = withdrawAddress.call{value: amount}("");
        require(success, "Withdraw failed");

        emit Withdrawn(msg.sender, amount);
    }

    // Receive ETH
    receive() external payable {
        deposits[msg.sender] += msg.value;
        emit Deposited(msg.sender, deposits[msg.sender]);
    }
}
