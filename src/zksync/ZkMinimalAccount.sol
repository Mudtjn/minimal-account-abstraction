// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {
    Transaction,
    MemoryTransactionHelper
} from "@zkaccount-abstraction/contracts/libraries/MemoryTransactionHelper.sol";
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@zkaccount-abstraction/contracts/interfaces/IAccount.sol";
import {SystemContractsCaller} from "@zkaccount-abstraction/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "@zkaccount-abstraction/contracts/Constants.sol";
import {INonceHolder} from "@zkaccount-abstraction/contracts/interfaces/INonceHolder.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Utils} from "@zkaccount-abstraction/contracts/libraries/Utils.sol";
/**
 * Lifecycle of type 113 (0x71) tx
 * msg.sender is bootloader contract
 *
 * Validation phasee
 * 1. user sends tx to "zksync api client"
 * 2. API CLient checks to see the nonce is unique by querying the nonceholder
 * 3. APIClient calls validate transaction, which MUST update the nonce
 * 4. APIClient checks nonce is updated.
 * 5. APIClient calls payForTransaction, or prepareForPaymaster & validateAndPayForPaymasterTransaction
 * 6. APIClient verifies bootloader gets paid
 *
 *
 * @title
 * @author
 * @notice
 */

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootloader();
    error ZkMinimalAccount__ExecutionFailed();
    error ZkMinimalAccount__NotFromBootloaderOrOwner();
    error ZkMinimalAccount__FailedToPay();
    error ZkMinimalAccount__TxValidationFailed();

    modifier requireFromBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkMinimalAccount__NotFromBootloader();
        }
        _;
    }

    modifier requireFromBootloaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkMinimalAccount__NotFromBootloaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    receive() external payable {}
    /*////////////////////////////////////////////////
                EXTERNAL FUNCTIONS
    //////////////////////////////////////////////// */
    /**
     * @notice must update the nonce
     * @notice must validate the transaction (check owner signed the transaction)
     * @notice check if we habe enough funds in account
     */

    function validateTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
        requireFromBootloader
        returns (bytes4 magic)
    {
        return _validateTransaction(_transaction);
    }

    // called by bootloader here
    function executeTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
        requireFromBootloaderOrOwner
    {
        _executeTransaction(_transaction);
    }

    // called by accounts other than bootloader
    function executeTransactionFromOutside(Transaction memory _transaction) external payable {
        bytes4 magic = _validateTransaction(_transaction);
        if (magic == bytes4(0)) {
            revert ZkMinimalAccount__TxValidationFailed();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if (!success) {
            revert ZkMinimalAccount__FailedToPay();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {}

    /*////////////////////////////////////////////////
                INTERNAL FUNCTIONS
    //////////////////////////////////////////////// */
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // call nonceholder
        // increment nonce
        // call(x, y, z) -> systems contract call
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );
        // Check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }
        // Check the signature
        bytes32 txHash = _transaction.encodeHash();
        address signer = ECDSA.recover(txHash, _transaction.signature);
        if (signer == owner()) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        // return the "magic" number
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        // in case contract is contract deployment
        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);
        } else {
            bool success;
            assembly ("memory-safe") {
                success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
            }
            if (!success) {
                revert ZkMinimalAccount__ExecutionFailed();
            }
        }
    }
}
