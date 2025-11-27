// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title ERC6551Account
 * @notice Token Bound Account implementation
 * @dev Each NFT gets its own smart contract wallet!
 */
contract ERC6551Account is IERC165, IERC721Receiver, IERC1155Receiver {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // Events
    event TransactionExecuted(
        address indexed target,
        uint256 value,
        bytes data
    );

    // Errors
    error NotAuthorized();
    error InvalidInput();
    error ExecutionFailed();

    /**
     * @notice Get the NFT that owns this account
     * @dev Info is stored in the account's bytecode
     * @return chainId The chain ID
     * @return tokenContract The NFT contract address
     * @return tokenId The NFT token ID
     */
    function token()
        public
        view
        returns (uint256 chainId, address tokenContract, uint256 tokenId)
    {
        // The last 96 bytes of deployed code contain NFT info
        bytes memory footer = new bytes(0x60); // 96 bytes

        assembly {
            // Copy from deployed bytecode
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }

        // Decode: salt, chainId, tokenContract, tokenId
        (, chainId, tokenContract, tokenId) = abi.decode(
            footer,
            (uint256, uint256, address, uint256)
        );
    }

    /**
     * @notice Get the owner of this account (NFT holder)
     * @return The current NFT owner's address
     */
    function owner() public view returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();

        // Only valid on the correct chain
        if (chainId != block.chainid) {
            return address(0);
        }

        // Return the NFT owner
        return IERC721(tokenContract).ownerOf(tokenId);
    }

    /**
     * @notice Execute a transaction from this account
     * @dev Only the NFT owner can call this
     * @param to Target contract address
     * @param value Amount of ETH to send
     * @param data Transaction data
     * @return result The return data from the call
     */
    function executeCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory result) {
        // Only NFT owner can execute
        if (msg.sender != owner()) {
            revert NotAuthorized();
        }

        // Validate input
        if (to == address(0)) {
            revert InvalidInput();
        }

        // Execute the call
        bool success;
        (success, result) = to.call{value: value}(data);

        if (!success) {
            // Bubble up the revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit TransactionExecuted(to, value, data);
    }

    /**
     * @notice Get ERC-20 token balance
     */
    function getTokenBalance(address token_) external view returns (uint256) {
        return IERC20(token_).balanceOf(address(this));
    }

    /**
     * @notice Get ETH balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Check if this account is valid on current chain
     */
    function isValidSigner(address signer) public view returns (bool) {
        return signer == owner();
    }

    // ============ ERC-165 Support ============

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // ============ Token Receiver Implementations ============

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    // ============ Receive ETH ============

    receive() external payable {}
}
 