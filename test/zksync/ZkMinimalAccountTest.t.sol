// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkMinimalAccount} from "src/zksync/ZkMinimalAccount.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@zkaccount-abstraction/contracts/interfaces/IAccount.sol";
import {
    EIP_712_TX_TYPE, 
    Transaction,
    MemoryTransactionHelper
} from "@zkaccount-abstraction/contracts/libraries/MemoryTransactionHelper.sol";
import {
    BOOTLOADER_FORMAL_ADDRESS
} from "@zkaccount-abstraction/contracts/Constants.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
contract ZkMinimalAccountTest is Test {
    using MessageHashUtils for bytes32; 
    using MemoryTransactionHelper for Transaction; 

    ZkMinimalAccount minimalAccount;
    ERC20Mock usdc;
    uint256 constant AMOUNT = 1e18;
    bytes32 constant EMPTY_BYTES32 = bytes32(0);
    address public constant ANVIL_DEFAULT_WALLET = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function setUp() public {
        minimalAccount = new ZkMinimalAccount();
        minimalAccount.transferOwnership(ANVIL_DEFAULT_WALLET); 
        usdc = new ERC20Mock();
        vm.deal(address(minimalAccount), AMOUNT); 
    }

    function testZkOwnerCanExecuteCommands() public {
        // Arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);

        Transaction memory unsignedTx =
            _createUnsignedTransaction(minimalAccount.owner(), EIP_712_TX_TYPE
            , dest, value, functionData);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.executeTransaction(EMPTY_BYTES32, EMPTY_BYTES32, unsignedTx);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testValidateZkTransaction() public {
        // Arrange
        address dest = address(usdc); 
        uint256 value = 0; 
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT); 

        Transaction memory unsignedTx = _createUnsignedTransaction(minimalAccount.owner(), EIP_712_TX_TYPE,
        dest, value, functionData); 
        Transaction memory signedTx = _signTransaction(unsignedTx); 

        // Act
        vm.prank(BOOTLOADER_FORMAL_ADDRESS); 
        bytes4 magic = minimalAccount.validateTransaction(EMPTY_BYTES32, EMPTY_BYTES32, signedTx); 

        // Assert 
        vm.assertEq(magic, ACCOUNT_VALIDATION_SUCCESS_MAGIC); 
    }

    /*/////////////////////////////////////////////////////
                            HELPERS
    /////////////////////////////////////////////////////// */
    function _signTransaction(Transaction memory transaction) internal view returns (Transaction memory) {
        bytes32 unsignedTxHash = MemoryTransactionHelper.encodeHash(transaction);
        bytes32 digest = unsignedTxHash.toEthSignedMessageHash(); 

        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        (v,r,s) = vm.sign(ANVIL_PRIVATE_KEY, digest); 
        Transaction memory signedTx = transaction; 
        signedTx.signature = abi.encodePacked(r, s, v); 
        return signedTx; 
    }
    
    
    function _createUnsignedTransaction(
        address from,
        uint256 transactionType,
        address to,
        uint256 value,
        bytes memory data
    ) internal view returns (Transaction memory) {
        // not super sure if it works here
        uint256 nonce = vm.getNonce(address(minimalAccount));
        bytes32[] memory factoryDeps = new bytes32[](0);
        return Transaction({
            txType: transactionType,
            from: uint256(uint160(from)),
            to: uint256(uint160(to)),
            gasLimit: 16777216,
            gasPerPubdataByteLimit: 16777216,
            maxFeePerGas: 16777216,
            maxPriorityFeePerGas: 16777216,
            paymaster: 0,
            nonce: nonce,
            value: value,
            reserved: [uint256(0), uint256(0), uint256(0), uint256(0)],
            data: data,
            signature: hex"",
            factoryDeps: factoryDeps,
            paymasterInput: hex"",
            reservedDynamic: hex""
        });
    }
}
