// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/core/SimpleEntryPoint.sol";
import "../src/core/SimpleAccount.sol";
import "../src/core/SimplePaymaster.sol";

/**
 * @title BundlerSimulator
 * @notice Simulates bundler behavior - collects and submits UserOps
 */
contract BundlerSimulator is Script {
    SimpleEntryPoint public entryPoint;
    SimpleAccount public account;
    SimplePaymaster public paymaster;

    address public owner;
    uint256 public ownerKey;
    address public bundler;

    function setUp() public {
        // Setup accounts
        ownerKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(ownerKey);
        bundler = vm.addr(0x999);

        console.log("Owner:", owner);
        console.log("Bundler:", bundler);
    }

    function run() public {
        vm.startBroadcast(ownerKey);

        // Step 1: Deploy EntryPoint
        console.log("\n=== Deploying EntryPoint ===");
        entryPoint = new SimpleEntryPoint();
        console.log("EntryPoint deployed at:", address(entryPoint));

        // Step 2: Deploy Smart Account
        console.log("\n=== Deploying Smart Account ===");
        account = new SimpleAccount(IEntryPoint(address(entryPoint)), owner);
        console.log("Account deployed at:", address(account));

        // Step 3: Deploy Paymaster
        console.log("\n=== Deploying Paymaster ===");
        paymaster = new SimplePaymaster(IEntryPoint(address(entryPoint)));
        console.log("Paymaster deployed at:", address(paymaster));

        // Step 4: Fund contracts
        console.log("\n=== Funding Contracts ===");

        // Fund account
        payable(address(account)).transfer(1 ether);
        console.log("Account funded with 1 ETH");

        // Deposit to EntryPoint for account
        account.addDeposit{value: 0.5 ether}();
        console.log("Account deposited 0.5 ETH to EntryPoint");

        // Fund and setup paymaster
        paymaster.deposit{value: 1 ether}();
        console.log("Paymaster deposited 1 ETH to EntryPoint");

        // Whitelist account in paymaster
        paymaster.addToWhitelist(address(account));
        console.log("Account whitelisted in Paymaster");

        vm.stopBroadcast();

        // Step 5: Simulate transactions
        _simulateWithoutPaymaster();
        _simulateWithPaymaster();
    }

    /**
     * @notice Simulate transaction WITHOUT paymaster (account pays)
     */
    function _simulateWithoutPaymaster() internal {
        console.log("\n=== Simulating Transaction WITHOUT Paymaster ===");

        vm.startBroadcast(ownerKey);

        // Create target for testing
        address recipient = address(0x123);
        uint256 amount = 0.1 ether;

        // Create UserOperation
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                recipient,
                amount,
                ""
            ),
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: "", // No paymaster
            signature: ""
        });

        // Sign UserOp
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerKey,
            MessageHashUtils.toEthSignedMessageHash(userOpHash)
        );
        userOp.signature = abi.encodePacked(r, s, v);

        // Submit to EntryPoint (as bundler)
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        uint256 bundlerBalanceBefore = bundler.balance;
        uint256 accountDepositBefore = entryPoint.balanceOf(address(account));

        console.log("Bundler balance before:", bundlerBalanceBefore);
        console.log("Account deposit before:", accountDepositBefore);

        entryPoint.handleOps(ops, payable(bundler));

        uint256 bundlerBalanceAfter = bundler.balance;
        uint256 accountDepositAfter = entryPoint.balanceOf(address(account));

        console.log("Bundler balance after:", bundlerBalanceAfter);
        console.log("Account deposit after:", accountDepositAfter);
        console.log("Recipient balance:", recipient.balance);
        console.log(
            "Gas paid by account:",
            accountDepositBefore - accountDepositAfter
        );

        vm.stopBroadcast();
    }

    /**
     * @notice Simulate transaction WITH paymaster (paymaster sponsors)
     */
    function _simulateWithPaymaster() internal {
        console.log("\n=== Simulating Transaction WITH Paymaster ===");

        vm.startBroadcast(ownerKey);

        address recipient = address(0x456);
        uint256 amount = 0.05 ether;

        // Create UserOperation with paymaster
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 1, // Incremented nonce
            initCode: "",
            callData: abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                recipient,
                amount,
                ""
            ),
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: abi.encodePacked(address(paymaster)), // WITH paymaster!
            signature: ""
        });

        // Sign UserOp
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerKey,
            MessageHashUtils.toEthSignedMessageHash(userOpHash)
        );
        userOp.signature = abi.encodePacked(r, s, v);

        // Submit to EntryPoint
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        uint256 paymasterDepositBefore = entryPoint.balanceOf(
            address(paymaster)
        );
        uint256 accountDepositBefore = entryPoint.balanceOf(address(account));

        console.log("Paymaster deposit before:", paymasterDepositBefore);
        console.log("Account deposit before:", accountDepositBefore);

        entryPoint.handleOps(ops, payable(bundler));

        uint256 paymasterDepositAfter = entryPoint.balanceOf(
            address(paymaster)
        );
        uint256 accountDepositAfter = entryPoint.balanceOf(address(account));

        console.log("Paymaster deposit after:", paymasterDepositAfter);
        console.log("Account deposit after:", accountDepositAfter);
        console.log("Recipient balance:", recipient.balance);
        console.log(
            "Gas paid by PAYMASTER:",
            paymasterDepositBefore - paymasterDepositAfter
        );
        console.log(
            "Account deposit UNCHANGED:",
            accountDepositAfter == accountDepositBefore
        );

        vm.stopBroadcast();
    }
}
