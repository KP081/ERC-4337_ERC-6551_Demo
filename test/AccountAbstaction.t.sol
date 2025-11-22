// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/SimpleEntryPoint.sol";
import "../src/core/SimpleAccount.sol";
import "../src/core/SimplePaymaster.sol";
import "../src/interfaces/UserOperation.sol";
import "../src/interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract AccountAbstractionTest is Test {
    using MessageHashUtils for bytes32;

    SimpleEntryPoint entryPoint;
    SimpleAccount account;
    SimplePaymaster paymaster;
    
    // ✅ FIX: Use vm.addr() to derive address from private key
    uint256 constant OWNER_PRIVATE_KEY = 0xA11CE; // Any non-zero value
    address owner;  // Will be derived from OWNER_PRIVATE_KEY
    
    address bundler;
    address recipient;
    
    function setUp() public {
        // ✅ FIX: Derive owner address from private key
        owner = vm.addr(OWNER_PRIVATE_KEY);
        bundler = makeAddr("bundler");
        recipient = makeAddr("recipient");
        
        console.log("Owner address:", owner);
        console.log("Bundler address:", bundler);
        console.log("Recipient address:", recipient);
        
        // Deploy contracts
        entryPoint = new SimpleEntryPoint();
        console.log("EntryPoint deployed at:", address(entryPoint));
        
        // ✅ Deploy account with correct owner
        account = new SimpleAccount(IEntryPoint(address(entryPoint)), owner);
        console.log("Account deployed at:", address(account));
        
        paymaster = new SimplePaymaster(IEntryPoint(address(entryPoint)));
        console.log("Paymaster deployed at:", address(paymaster));
        
        // Fund contracts
        vm.deal(address(account), 10 ether);
        vm.deal(address(paymaster), 10 ether);
        vm.deal(bundler, 1 ether);
        vm.deal(address(entryPoint), 10 ether); // Fund EntryPoint for refunds
        
        // Deposit to EntryPoint
        vm.prank(address(account));
        account.addDeposit{value: 2 ether}();
        
        paymaster.deposit{value: 2 ether}();
        
        // Whitelist account in paymaster
        paymaster.addToWhitelist(address(account));
        
        console.log("Setup complete!");
        console.log("Account deposit:", entryPoint.balanceOf(address(account)));
        console.log("Paymaster deposit:", entryPoint.balanceOf(address(paymaster)));
    }
    
    function testBasicTransaction() public {
        console.log("\n=== Testing Basic Transaction (No Paymaster) ===");
        
        uint256 recipientBalanceBefore = recipient.balance;
        uint256 accountDepositBefore = entryPoint.balanceOf(address(account));
        
        // Create UserOp
        UserOperation memory userOp = _createUserOp(
            0,  // nonce
            recipient,
            0.5 ether,
            "",
            address(0)  // no paymaster
        );
        
        // ✅ FIX: Sign with correct private key
        userOp.signature = _signUserOp(userOp, OWNER_PRIVATE_KEY);
        
        // Execute
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;
        
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));
        
        // Verify
        console.log("Recipient balance before:", recipientBalanceBefore);
        console.log("Recipient balance after:", recipient.balance);
        console.log("Account deposit before:", accountDepositBefore);
        console.log("Account deposit after:", entryPoint.balanceOf(address(account)));
        
        assertEq(recipient.balance, 0.5 ether, "Recipient should receive 0.5 ETH");
        assertTrue(
            entryPoint.balanceOf(address(account)) < accountDepositBefore,
            "Account deposit should decrease (paid gas)"
        );
    }
    
    function testSponsoredTransaction() public {
        console.log("\n=== Testing Sponsored Transaction (With Paymaster) ===");
        
        uint256 accountDepositBefore = entryPoint.balanceOf(address(account));
        uint256 paymasterDepositBefore = entryPoint.balanceOf(address(paymaster));
        
        // Create UserOp with paymaster
        UserOperation memory userOp = _createUserOp(
            0,
            recipient,
            0.3 ether,
            "",
            address(paymaster)  // WITH paymaster
        );
        
        // ✅ FIX: Sign with correct private key
        userOp.signature = _signUserOp(userOp, OWNER_PRIVATE_KEY);
        
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;
        
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));
        
        uint256 accountDepositAfter = entryPoint.balanceOf(address(account));
        uint256 paymasterDepositAfter = entryPoint.balanceOf(address(paymaster));
        
        console.log("Account deposit before:", accountDepositBefore);
        console.log("Account deposit after:", accountDepositAfter);
        console.log("Paymaster deposit before:", paymasterDepositBefore);
        console.log("Paymaster deposit after:", paymasterDepositAfter);
        console.log("Recipient balance:", recipient.balance);
        
        // Account deposit should be UNCHANGED (paymaster paid)
        assertEq(
            accountDepositAfter, 
            accountDepositBefore, 
            "Account deposit should remain unchanged"
        );
        
        // Paymaster deposit should decrease
        assertTrue(
            paymasterDepositAfter < paymasterDepositBefore,
            "Paymaster deposit should decrease (paid gas)"
        );
        
        // Recipient received funds
        assertEq(recipient.balance, 0.3 ether, "Recipient should receive 0.3 ETH");
    }
    
    function testBatchTransaction() public {
        console.log("\n=== Testing Batch Transaction ===");
        
        address recipient2 = makeAddr("recipient2");
        address recipient3 = makeAddr("recipient3");
        
        // Create batch calldata
        address[] memory targets = new address[](3);
        targets[0] = recipient;
        targets[1] = recipient2;
        targets[2] = recipient3;
        
        uint256[] memory values = new uint256[](3);
        values[0] = 0.1 ether;
        values[1] = 0.2 ether;
        values[2] = 0.3 ether;
        
        bytes[] memory datas = new bytes[](3);
        datas[0] = "";
        datas[1] = "";
        datas[2] = "";
        
        bytes memory batchCallData = abi.encodeWithSignature(
            "executeBatch(address[],uint256[],bytes[])",
            targets,
            values,
            datas
        );
        
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: batchCallData,
            callGasLimit: 300000,
            verificationGasLimit: 150000,
            preVerificationGas: 21000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: abi.encodePacked(address(paymaster)),
            signature: ""
        });
        
        userOp.signature = _signUserOp(userOp, OWNER_PRIVATE_KEY);
        
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;
        
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));
        
        // Verify all recipients received funds
        assertEq(recipient.balance, 0.1 ether, "Recipient 1 should receive 0.1 ETH");
        assertEq(recipient2.balance, 0.2 ether, "Recipient 2 should receive 0.2 ETH");
        assertEq(recipient3.balance, 0.3 ether, "Recipient 3 should receive 0.3 ETH");
        
        console.log("Batch transaction successful!");
        console.log("Recipient 1:", recipient.balance);
        console.log("Recipient 2:", recipient2.balance);
        console.log("Recipient 3:", recipient3.balance);
    }
    
    function testInvalidSignature() public {
        console.log("\n=== Testing Invalid Signature ===");
        
        // Create UserOp
        UserOperation memory userOp = _createUserOp(
            0,
            recipient,
            0.5 ether,
            "",
            address(0)
        );
        
        // Sign with WRONG private key
        uint256 wrongPrivateKey = 0xDEAD;
        userOp.signature = _signUserOp(userOp, wrongPrivateKey);
        
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;
        
        vm.prank(bundler);
        vm.expectRevert(); // Should revert with ValidationFailed
        entryPoint.handleOps(ops, payable(bundler));
        
        console.log("Invalid signature correctly rejected!");
    }
    
    function testNonWhitelistedPaymaster() public {
        console.log("\n=== Testing Non-Whitelisted User ===");
        
        // Create a new account that's NOT whitelisted
        uint256 newOwnerKey = 0xBEEF;
        address newOwner = vm.addr(newOwnerKey);
        
        SimpleAccount newAccount = new SimpleAccount(
            IEntryPoint(address(entryPoint)), 
            newOwner
        );
        
        vm.deal(address(newAccount), 10 ether);
        
        // Try to use paymaster without being whitelisted
        UserOperation memory userOp = UserOperation({
            sender: address(newAccount),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                recipient,
                0.1 ether,
                ""
            ),
            callGasLimit: 200000,
            verificationGasLimit: 150000,
            preVerificationGas: 21000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: abi.encodePacked(address(paymaster)),
            signature: ""
        });
        
        userOp.signature = _signUserOp(userOp, newOwnerKey);
        
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;
        
        vm.prank(bundler);
        vm.expectRevert(); // Should revert - not whitelisted
        entryPoint.handleOps(ops, payable(bundler));
        
        console.log("Non-whitelisted user correctly rejected!");
    }
    
    function testMultipleUserOps() public {
        console.log("\n=== Testing Multiple UserOps in Batch ===");
        
        // Create second account
        uint256 bobKey = 0xB0B;
        address bob = vm.addr(bobKey);
        
        SimpleAccount bobAccount = new SimpleAccount(
            IEntryPoint(address(entryPoint)), 
            bob
        );
        
        vm.deal(address(bobAccount), 10 ether);
        vm.prank(address(bobAccount));
        bobAccount.addDeposit{value: 1 ether}();
        
        // Whitelist Bob's account
        paymaster.addToWhitelist(address(bobAccount));
        
        // Create UserOps for both accounts
        address aliceRecipient = makeAddr("aliceRecipient");
        address bobRecipient = makeAddr("bobRecipient");
        
        UserOperation memory aliceOp = _createUserOp(
            0,
            aliceRecipient,
            0.2 ether,
            "",
            address(paymaster)
        );
        aliceOp.signature = _signUserOp(aliceOp, OWNER_PRIVATE_KEY);
        
        UserOperation memory bobOp = UserOperation({
            sender: address(bobAccount),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                bobRecipient,
                0.3 ether,
                ""
            ),
            callGasLimit: 200000,
            verificationGasLimit: 150000,
            preVerificationGas: 21000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: abi.encodePacked(address(paymaster)),
            signature: ""
        });
        
        // Sign Bob's UserOp
        bytes32 bobOpHash = entryPoint.getUserOpHash(bobOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, bobOpHash.toEthSignedMessageHash());
        bobOp.signature = abi.encodePacked(r, s, v);
        
        // Bundle both ops
        UserOperation[] memory ops = new UserOperation[](2);
        ops[0] = aliceOp;
        ops[1] = bobOp;
        
        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));
        
        // Verify
        assertEq(aliceRecipient.balance, 0.2 ether, "Alice's recipient should receive 0.2 ETH");
        assertEq(bobRecipient.balance, 0.3 ether, "Bob's recipient should receive 0.3 ETH");
        
        console.log("Multiple UserOps processed successfully!");
        console.log("Alice's recipient:", aliceRecipient.balance);
        console.log("Bob's recipient:", bobRecipient.balance);
    }
    
    // ==================== HELPER FUNCTIONS ====================
    
    function _createUserOp(
        uint256 nonce,
        address target,
        uint256 value,
        bytes memory data,
        address paymasterAddr
    ) internal view returns (UserOperation memory) {
        return UserOperation({
            sender: address(account),
            nonce: nonce,
            initCode: "",
            callData: abi.encodeWithSignature(
                "execute(address,uint256,bytes)",
                target,
                value,
                data
            ),
            callGasLimit: 200000,
            verificationGasLimit: 150000,
            preVerificationGas: 21000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: paymasterAddr == address(0) ? 
                bytes("") : abi.encodePacked(paymasterAddr),
            signature: ""
        });
    }
    
    function _signUserOp(
        UserOperation memory userOp,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 ethHash = userOpHash.toEthSignedMessageHash();
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethHash);
        return abi.encodePacked(r, s, v);
    }
}