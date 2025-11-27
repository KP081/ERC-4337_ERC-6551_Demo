// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC6551Registry
 * @notice Creates Token Bound Accounts for NFTs
 */
contract ERC6551Registry {
    // Events
    event ERC6551AccountCreated(
        address account,
        address indexed implementation,
        bytes32 salt,
        uint256 chainId,
        address indexed tokenContract,
        uint256 indexed tokenId
    );

    // Errors
    error InitializationFailed();

    /**
     * @notice Creates a token bound account for an NFT
     * @param implementation The account implementation contract
     * @param chainId The chain ID
     * @param tokenContract The NFT contract address
     * @param tokenId The NFT token ID
     * @param salt Extra salt for deterministic address
     * @param initData Initialization data (optional)
     * @return account The created account address
     */
    function createAccount(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt,
        bytes calldata initData
    ) external returns (address account) {
        // Pack the account data
        bytes memory code = _creationCode(
            implementation,
            chainId,
            tokenContract,
            tokenId,
            salt
        );

        // Calculate deterministic address
        bytes32 saltHash = _getSalt(chainId, tokenContract, tokenId, salt);

        // Check if already deployed
        account = _computeAddress(saltHash, keccak256(code));

        if (account.code.length != 0) {
            // Already deployed, return existing address
            return account;
        }

        // Deploy using CREATE2
        assembly {
            account := create2(0, add(code, 0x20), mload(code), saltHash)
        }

        if (account == address(0)) {
            revert InitializationFailed();
        }

        // Initialize if data provided
        if (initData.length > 0) {
            (bool success, ) = account.call(initData);
            if (!success) {
                revert InitializationFailed();
            }
        }

        emit ERC6551AccountCreated(
            account,
            implementation,
            saltHash,
            chainId,
            tokenContract,
            tokenId
        );
    }

    /**
     * @notice Computes the token bound account address (without deploying)
     * @dev Useful for knowing the address before deployment
     */
    function account(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt
    ) external view returns (address) {
        bytes memory code = _creationCode(
            implementation,
            chainId,
            tokenContract,
            tokenId,
            salt
        );

        bytes32 saltHash = _getSalt(chainId, tokenContract, tokenId, salt);

        return _computeAddress(saltHash, keccak256(code));
    }

    /**
     * @notice Generate creation code for the proxy
     */
    function _creationCode(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt
    ) internal pure returns (bytes memory) {
        // Minimal proxy bytecode that delegates to implementation
        // and stores NFT info in code
        return
            abi.encodePacked(
                // Proxy bytecode (EIP-1167)
                hex"3d60ad80600a3d3981f3363d3d373d3d3d363d73",
                implementation,
                hex"5af43d82803e903d91602b57fd5bf3",
                // Store NFT info at end of bytecode
                abi.encode(salt, chainId, tokenContract, tokenId)
            );
    }

    /**
     * @notice Generate salt for CREATE2
     */
    function _getSalt(
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        uint256 salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(chainId, tokenContract, tokenId, salt));
    }

    /**
     * @notice Compute CREATE2 address
     */
    function _computeAddress(
        bytes32 salt,
        bytes32 bytecodeHash
    ) internal view returns (address) {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                salt,
                                bytecodeHash
                            )
                        )
                    )
                )
            );
    }
}
