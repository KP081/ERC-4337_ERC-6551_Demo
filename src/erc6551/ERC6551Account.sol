// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title ERC6551Account
 * @notice Token Bound Account implementation
 */
contract ERC6551Account is IERC165, IERC721Receiver, IERC1155Receiver {
    // Storage slot for NFT context (to avoid reading from bytecode)
    bytes32 private constant _CONTEXT_SLOT = keccak256("erc6551.context");

    struct AccountContext {
        uint256 salt;
        uint256 chainId;
        address tokenContract;
        uint256 tokenId;
    }

    // Events
    event TransactionExecuted(
        address indexed target,
        uint256 value,
        bytes data
    );
    event ContextInitialized(
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    );

    // Errors
    error NotAuthorized();
    error InvalidInput();
    error ExecutionFailed();
    error AlreadyInitialized();

    /**
     * @notice Initialize the account context (called once after deployment)
     */
    function initialize(
        uint256 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external {
        AccountContext memory ctx = _getContext();

        // Prevent re-initialization
        if (ctx.chainId != 0) {
            revert AlreadyInitialized();
        }

        // Store context
        _setContext(
            AccountContext({
                salt: salt,
                chainId: chainId,
                tokenContract: tokenContract,
                tokenId: tokenId
            })
        );

        emit ContextInitialized(chainId, tokenContract, tokenId);
    }

    /**
     * @notice Get the NFT that owns this account
     * @dev Reads from storage slot instead of bytecode
     */
    function token()
        public
        view
        returns (uint256 chainId, address tokenContract, uint256 tokenId)
    {
        AccountContext memory ctx = _getContext();

        // If not initialized, try reading from bytecode (fallback)
        if (ctx.chainId == 0) {
            return _tokenFromBytecode();
        }

        return (ctx.chainId, ctx.tokenContract, ctx.tokenId);
    }

    /**
     * @notice Fallback: Read NFT info from bytecode
     */
    function _tokenFromBytecode()
        internal
        view
        returns (uint256 chainId, address tokenContract, uint256 tokenId)
    {
        // EIP-1167 minimal proxy is 45 bytes + 96 bytes of data = 141 bytes minimum
        // Our implementation adds: 45 (proxy) + 96 (data) = 141 bytes

        assembly {
            let size := extcodesize(address())

            // Need at least 96 bytes
            if lt(size, 96) {
                revert(0, 0)
            }

            // Allocate memory for 96 bytes
            let ptr := mload(0x40)

            // Copy last 96 bytes from deployed code
            extcodecopy(address(), ptr, sub(size, 96), 96)

            // Load the values (each 32 bytes)
            // Skip salt (first 32 bytes)
            chainId := mload(add(ptr, 32))
            tokenContract := mload(add(ptr, 64))
            tokenId := mload(add(ptr, 96))
        }
    }

    /**
     * @notice Get the owner of this account (NFT holder)
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
     */
    function executeCall(
        address to,
        uint256 value,
        bytes calldata data
    ) external payable returns (bytes memory result) {
        // Only NFT owner can execute
        address currentOwner = owner();
        if (msg.sender != currentOwner) {
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
            if (result.length > 0) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            } else {
                revert ExecutionFailed();
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

    // ============ Internal Storage Functions ============

    function _getContext() internal view returns (AccountContext memory ctx) {
        bytes32 slot = _CONTEXT_SLOT;
        assembly {
            let ptr := mload(0x40)
            // Load 4 slots (32 bytes each = 128 bytes total)
            mstore(ptr, sload(slot))
            mstore(add(ptr, 32), sload(add(slot, 1)))
            mstore(add(ptr, 64), sload(add(slot, 2)))
            mstore(add(ptr, 96), sload(add(slot, 3)))

            // Decode into struct
            mstore(ctx, mload(ptr)) // salt
            mstore(add(ctx, 32), mload(add(ptr, 32))) // chainId
            mstore(add(ctx, 64), mload(add(ptr, 64))) // tokenContract
            mstore(add(ctx, 96), mload(add(ptr, 96))) // tokenId
        }
    }

    function _setContext(AccountContext memory ctx) internal {
        bytes32 slot = _CONTEXT_SLOT;
        assembly {
            sstore(slot, mload(ctx)) // salt
            sstore(add(slot, 1), mload(add(ctx, 32))) // chainId
            sstore(add(slot, 2), mload(add(ctx, 64))) // tokenContract
            sstore(add(slot, 3), mload(add(ctx, 96))) // tokenId
        }
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
