// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/core/SimpleEntryPoint.sol";
import "../src/core/SimpleAccount.sol";
import "../src/core/SimplePaymaster.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract AccountAbstractionTest is Test {
    SimpleEntryPoint entryPoint;
    SimpleAccount account;
    SimplePaymaster paymaster;

    address owner = address(0x1);
    uint256 ownerKey = 0x1;
    address bundler = address(0x2);
    address recipient = address(0x3);

    function setUp() public {
        // Deploy contracts
        entryPoint = new SimpleEntryPoint();
        account = new SimpleAccount(IEntryPoint(address(entryPoint)), owner);
        paymaster = new SimplePaymaster(IEntryPoint(address(entryPoint)));

        // Fund contracts
        vm.deal(address(account), 10 ether);
        vm.deal(address(paymaster), 10 ether);
        vm.deal(bundler, 1 ether);

        // Deposit to EntryPoint
        account.addDeposit{value: 2 ether}();
        paymaster.deposit{value: 2 ether}();

        // Whitelist account
        paymaster.addToWhitelist(address(account));
    }

    function testBasicTransaction() public {
        // Create UserOp
        UserOperation memory userOp = _createUserOp(
            0, // nonce
            recipient,
            0.5 ether,
            "",
            address(0) // no paymaster
        );

        // Sign
        userOp.signature = _signUserOp(userOp, ownerKey);

        // Execute
        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // Verify
        assertEq(recipient.balance, 0.5 ether);
    }

    function testSponsoredTransaction() public {
        uint256 accountDepositBefore = entryPoint.balanceOf(address(account));

        // Create UserOp with paymaster
        UserOperation memory userOp = _createUserOp(
            0,
            recipient,
            0.3 ether,
            "",
            address(paymaster) // WITH paymaster
        );

        userOp.signature = _signUserOp(userOp, ownerKey);

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        vm.prank(bundler);
        entryPoint.handleOps(ops, payable(bundler));

        // Account deposit should be UNCHANGED
        assertEq(entryPoint.balanceOf(address(account)), accountDepositBefore);

        // Recipient received funds
        assertEq(recipient.balance, 0.3 ether);
    }

    function _createUserOp(
        uint256 nonce,
        address target,
        uint256 value,
        bytes memory data,
        address paymasterAddr
    ) internal view returns (UserOperation memory) {
        return
            UserOperation({
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
                paymasterAndData: paymasterAddr == address(0)
                    ? bytes("")
                    : abi.encodePacked(paymasterAddr),
                signature: ""
            });
    }

    function _signUserOp(
        UserOperation memory userOp,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethHash);
        return abi.encodePacked(r, s, v);
    }
}
