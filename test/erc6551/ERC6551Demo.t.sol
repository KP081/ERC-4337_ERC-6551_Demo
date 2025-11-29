// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/erc6551/ERC6551Registry.sol";
import "../../src/erc6551/ERC6551Account.sol";
import "../../src/erc6551/GameCharacterNFT.sol";
import "../../src/mock/MockERC20.sol";
import "../../src/mock/MockDeFi.sol";

contract ERC6551DemoTest is Test {
    // Contracts
    ERC6551Registry registry;
    ERC6551Account accountImplementation;
    GameCharacterNFT characterNFT;
    MockERC20 goldToken;
    MockERC20 silverToken;
    MockDeFi defiProtocol;
    
    // Users
    address alice;
    address bob;
    address charlie;
    
    function setUp() public {
        // Setup users
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        
        // Deploy ERC-6551 infrastructure
        registry = new ERC6551Registry();
        accountImplementation = new ERC6551Account();
        
        // Deploy game NFT
        characterNFT = new GameCharacterNFT(
            address(registry),
            address(accountImplementation)
        );
        
        // Deploy tokens
        goldToken = new MockERC20("Gold", "GOLD");
        silverToken = new MockERC20("Silver", "SILVER");
        
        // Deploy DeFi protocol
        defiProtocol = new MockDeFi(address(goldToken));
        
        // Give Alice some tokens
        goldToken.mint(alice, 1000 ether);
        silverToken.mint(alice, 500 ether);
        
        console.log("=== Contract Addresses ===");
        console.log("Registry:", address(registry));
        console.log("Account Implementation:", address(accountImplementation));
        console.log("Character NFT:", address(characterNFT));
        console.log("Gold Token:", address(goldToken));
        console.log("DeFi Protocol:", address(defiProtocol));
    }
    
    function testMintCharacterCreatesTBA() public {
        console.log("\n=== Test 1: Mint Character & Create TBA ===");
        
        vm.startPrank(alice);
        
        // Mint character
        (uint256 tokenId, address tbaAddress) = characterNFT.mintCharacter(
            alice,
            "Warrior Alice"
        );
        
        console.log("Character Token ID:", tokenId);
        console.log("TBA Address:", tbaAddress);
        
        // Verify
        assertEq(characterNFT.ownerOf(tokenId), alice, "Alice should own NFT");
        assertTrue(tbaAddress != address(0), "TBA should be created");
        
        // Verify TBA owner
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        assertEq(tba.owner(), alice, "TBA owner should be Alice");
        
        vm.stopPrank();
    }
    
    function testTBAHoldsERC20Tokens() public {
        console.log("\n=== Test 2: TBA Holds ERC-20 Tokens ===");
        
        vm.startPrank(alice);
        
        // Mint character
        (uint256 tokenId, address tbaAddress) = characterNFT.mintCharacter(
            alice,
            "Rich Knight"
        );
        
        console.log("Character:", tokenId);
        console.log("TBA:", tbaAddress);
        
        // Transfer Gold to TBA
        uint256 goldAmount = 100 ether;
        goldToken.transfer(tbaAddress, goldAmount);
        
        // Transfer Silver to TBA
        uint256 silverAmount = 50 ether;
        silverToken.transfer(tbaAddress, silverAmount);
        
        vm.stopPrank();
        
        // Verify balances
        assertEq(
            goldToken.balanceOf(tbaAddress),
            goldAmount,
            "TBA should hold 100 GOLD"
        );
        assertEq(
            silverToken.balanceOf(tbaAddress),
            silverAmount,
            "TBA should hold 50 SILVER"
        );
        
        console.log("TBA Gold Balance:", goldToken.balanceOf(tbaAddress) / 1 ether);
        console.log("TBA Silver Balance:", silverToken.balanceOf(tbaAddress) / 1 ether);
    }
    
    function testTBAExecutesTokenTransfer() public {
        console.log("\n=== Test 3: TBA Executes Token Transfer ===");
        
        vm.startPrank(alice);
        
        // Setup: Mint character and fund TBA
        (uint256 tokenId, address tbaAddress) = characterNFT.mintCharacter(
            alice,
            "Generous Mage"
        );
        goldToken.transfer(tbaAddress, 100 ether);
        
        console.log("Initial TBA Balance:", goldToken.balanceOf(tbaAddress) / 1 ether);
        console.log("Initial Bob Balance:", goldToken.balanceOf(bob) / 1 ether);
        
        // Execute transfer via TBA
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        
        bytes memory transferData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            bob,
            30 ether
        );
        
        tba.executeCall(address(goldToken), 0, transferData);
        
        vm.stopPrank();
        
        // Verify
        assertEq(
            goldToken.balanceOf(tbaAddress),
            70 ether,
            "TBA should have 70 GOLD left"
        );
        assertEq(
            goldToken.balanceOf(bob),
            30 ether,
            "Bob should receive 30 GOLD"
        );
        
        console.log("Final TBA Balance:", goldToken.balanceOf(tbaAddress) / 1 ether);
        console.log("Final Bob Balance:", goldToken.balanceOf(bob) / 1 ether);
    }
    
    function testTBAInteractsWithDeFi() public {
        console.log("\n=== Test 4: TBA Interacts with DeFi Protocol ===");
        
        vm.startPrank(alice);
        
        // Setup
        (uint256 tokenId, address tbaAddress) = characterNFT.mintCharacter(
            alice,
            "DeFi Farmer"
        );
        goldToken.transfer(tbaAddress, 200 ether);
        
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        
        console.log("TBA Initial Gold:", goldToken.balanceOf(tbaAddress) / 1 ether);
        console.log("DeFi TVL Before:", defiProtocol.totalValueLocked() / 1 ether);
        
        // Step 1: Approve DeFi protocol
        bytes memory approveData = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(defiProtocol),
            100 ether
        );
        tba.executeCall(address(goldToken), 0, approveData);
        
        console.log("Approval successful");
        
        // Step 2: Deposit to DeFi
        bytes memory depositData = abi.encodeWithSignature(
            "deposit(uint256)",
            100 ether
        );
        tba.executeCall(address(defiProtocol), 0, depositData);
        
        console.log("Deposit successful");
        
        // Verify deposit
        assertEq(
            defiProtocol.deposits(tbaAddress),
            100 ether,
            "TBA should have 100 GOLD deposited"
        );
        assertEq(
            defiProtocol.totalValueLocked(),
            100 ether,
            "TVL should be 100 GOLD"
        );
        
        console.log("TBA DeFi Deposit:", defiProtocol.deposits(tbaAddress) / 1 ether);
        console.log("DeFi TVL After:", defiProtocol.totalValueLocked() / 1 ether);
        
        // Step 3: Withdraw from DeFi
        bytes memory withdrawData = abi.encodeWithSignature(
            "withdraw(uint256)",
            50 ether
        );
        tba.executeCall(address(defiProtocol), 0, withdrawData);
        
        console.log("Withdrawal successful");
        
        // Verify withdrawal
        assertEq(
            defiProtocol.deposits(tbaAddress),
            50 ether,
            "TBA should have 50 GOLD deposited"
        );
        assertEq(
            goldToken.balanceOf(tbaAddress),
            150 ether,
            "TBA should have 150 GOLD"
        );
        
        console.log("Final TBA Gold:", goldToken.balanceOf(tbaAddress) / 1 ether);
        console.log("Final DeFi Deposit:", defiProtocol.deposits(tbaAddress) / 1 ether);
        
        vm.stopPrank();
    }
    
    function testOwnershipTransferMovesControl() public {
        console.log("\n=== Test 5: NFT Transfer Moves TBA Control ===");
        
        vm.startPrank(alice);
        
        // Setup
        (uint256 tokenId, address tbaAddress) = characterNFT.mintCharacter(
            alice,
            "Traded Hero"
        );
        goldToken.transfer(tbaAddress, 100 ether);
        
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        
        console.log("Initial NFT Owner:", characterNFT.ownerOf(tokenId));
        console.log("Initial TBA Owner:", tba.owner());
        console.log("TBA Gold Balance:", goldToken.balanceOf(tbaAddress) / 1 ether);
        
        // Transfer NFT to Bob
        characterNFT.transferFrom(alice, bob, tokenId);
        
        vm.stopPrank();
        
        console.log("\n--- After Transfer ---");
        console.log("New NFT Owner:", characterNFT.ownerOf(tokenId));
        console.log("New TBA Owner:", tba.owner());
        
        // Verify Bob now controls TBA
        assertEq(characterNFT.ownerOf(tokenId), bob, "Bob should own NFT");
        assertEq(tba.owner(), bob, "Bob should control TBA");
        
        // Bob can now use TBA's funds
        vm.startPrank(bob);
        
        bytes memory transferData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            charlie,
            50 ether
        );
        tba.executeCall(address(goldToken), 0, transferData);
        
        vm.stopPrank();
        
        assertEq(
            goldToken.balanceOf(charlie),
            50 ether,
            "Charlie should receive 50 GOLD"
        );
        
        console.log("Bob transferred 50 GOLD to Charlie");
        console.log("Charlie's Balance:", goldToken.balanceOf(charlie) / 1 ether);
    }
    
    function testOnlyOwnerCanExecute() public {
        console.log("\n=== Test 6: Only Owner Can Execute ===");
        
        vm.prank(alice);
        (uint256 tokenId, address tbaAddress) = characterNFT.mintCharacter(
            alice,
            "Protected Character"
        );
        
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        
        // Bob tries to execute (should fail)
        vm.startPrank(bob);
        
        bytes memory transferData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            bob,
            10 ether
        );
        
        vm.expectRevert(ERC6551Account.NotAuthorized.selector);
        tba.executeCall(address(goldToken), 0, transferData);
        
        vm.stopPrank();
        
        console.log("Non-owner correctly rejected");
    }
    
    function testComplexMultiStepWorkflow() public {
        console.log("\n=== Test 7: Complex Multi-Step Workflow ===");
        
        vm.startPrank(alice);
        
        // Create character
        (uint256 tokenId, address tbaAddress) = characterNFT.mintCharacter(
            alice,
            "Master Trader"
        );
        
        // Fund TBA
        goldToken.transfer(tbaAddress, 500 ether);
        
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        
        console.log("Starting Balance:", goldToken.balanceOf(tbaAddress) / 1 ether);
        
        // Workflow: Approve -> Swap -> Deposit -> Withdraw
        
        // Step 1: Approve DeFi for swap
        bytes memory approveData = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(defiProtocol),
            type(uint256).max
        );
        tba.executeCall(address(goldToken), 0, approveData);
        console.log("1. Approved DeFi");
        
        // Step 2: Swap 100 tokens (1% fee)
        bytes memory swapData = abi.encodeWithSignature(
            "swap(uint256)",
            100 ether
        );
        tba.executeCall(address(defiProtocol), 0, swapData);
        console.log("2. Swapped 100 GOLD (got 99 back)");
        
        uint256 balanceAfterSwap = goldToken.balanceOf(tbaAddress);
        console.log("   Balance after swap:", balanceAfterSwap / 1 ether);
        
        // Step 3: Deposit 200 to DeFi
        bytes memory depositData = abi.encodeWithSignature(
            "deposit(uint256)",
            200 ether
        );
        tba.executeCall(address(defiProtocol), 0, depositData);
        console.log("3. Deposited 200 GOLD");
        
        // Step 4: Transfer some to Bob
        bytes memory transferData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            bob,
            50 ether
        );
        tba.executeCall(address(goldToken), 0, transferData);
        console.log("4. Transferred 50 GOLD to Bob");
        
        // Step 5: Withdraw from DeFi
        bytes memory withdrawData = abi.encodeWithSignature(
            "withdraw(uint256)",
            100 ether
        );
        tba.executeCall(address(defiProtocol), 0, withdrawData);
        console.log("5. Withdrew 100 GOLD from DeFi");
        
        vm.stopPrank();
        
        // Final state
        uint256 finalBalance = goldToken.balanceOf(tbaAddress);
        uint256 defiDeposit = defiProtocol.deposits(tbaAddress);
        uint256 bobBalance = goldToken.balanceOf(bob);
        
        console.log("\n--- Final State ---");
        console.log("TBA Balance:", finalBalance / 1 ether);
        console.log("TBA DeFi Deposit:", defiDeposit / 1 ether);
        console.log("Bob's Balance:", bobBalance / 1 ether);
        
        // Calculations: 500 - 100 (swap) + 99 (swap back) - 200 (deposit) 
        //               - 50 (to bob) + 100 (withdraw) = 349
        assertEq(finalBalance, 349 ether, "Final balance should be 349");
        assertEq(defiDeposit, 100 ether, "DeFi deposit should be 100");
        assertEq(bobBalance, 50 ether, "Bob should have 50");
    }
    
    function testMultipleCharactersIndependentAccounts() public {
        console.log("\n=== Test 8: Multiple Characters = Independent Accounts ===");
        
        vm.startPrank(alice);
        
        // Mint 3 characters
        (uint256 char1, address tba1) = characterNFT.mintCharacter(alice, "Warrior");
        (uint256 char2, address tba2) = characterNFT.mintCharacter(alice, "Mage");
        (uint256 char3, address tba3) = characterNFT.mintCharacter(alice, "Rogue");
        
        console.log("Character 1 TBA:", tba1);
        console.log("Character 2 TBA:", tba2);
        console.log("Character 3 TBA:", tba3);
        
        // Each gets different amounts
        goldToken.transfer(tba1, 100 ether);
        goldToken.transfer(tba2, 200 ether);
        goldToken.transfer(tba3, 300 ether);
        
        vm.stopPrank();
        
        // Verify independence
        assertTrue(tba1 != tba2 && tba2 != tba3 && tba1 != tba3, "All TBAs unique");
        assertEq(goldToken.balanceOf(tba1), 100 ether, "Warrior has 100");
        assertEq(goldToken.balanceOf(tba2), 200 ether, "Mage has 200");
        assertEq(goldToken.balanceOf(tba3), 300 ether, "Rogue has 300");
        
        console.log("Warrior Balance:", goldToken.balanceOf(tba1) / 1 ether);
        console.log("Mage Balance:", goldToken.balanceOf(tba2) / 1 ether);
        console.log("Rogue Balance:", goldToken.balanceOf(tba3) / 1 ether);
        console.log("All accounts independent");
    }
}