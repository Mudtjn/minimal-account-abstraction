// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount, ECDSA} from "../../src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "../../script/DeployMinimal.s.sol";
import {HelperConfig, EntryPoint} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation, MessageHashUtils} from "../../script/SendPackedUserOp.s.sol";

contract MinimalAccountTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;
    SendPackedUserOp sendPackedUserOp;
    uint256 public constant AMOUNT = 1e18;
    address public randomuser = makeAddr("randomUser");

    function setUp() public {
        DeployMinimal deployMinimal = new DeployMinimal();
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    // test - USDC mint
    // msg.sender -> MinimalAccount
    // approve some amount
    // USDC contract
    // come from entrypoint
    function testOwnerCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act

        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonOwnerCannotExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act

        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function testValidateUserOpsSignature() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory callData = abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory signedUserOp =
            sendPackedUserOp.generateSignedUserPackedOp(callData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOpHash = EntryPoint(payable(helperConfig.getConfig().entryPoint)).getUserOpHash(signedUserOp);

        // Act
        address signer = ECDSA.recover(userOpHash.toEthSignedMessageHash(), signedUserOp.signature);
        // Assert
        assertEq(minimalAccount.owner(), signer);
    }

    function testValidateUserOps() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory callData = abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory signedUserOp =
            sendPackedUserOp.generateSignedUserPackedOp(callData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOpHash = EntryPoint(payable(helperConfig.getConfig().entryPoint)).getUserOpHash(signedUserOp);
        uint256 missingAccountFunds = 1e18;

        // Act
        uint256 validateUserOp = minimalAccount.validateUserOp(signedUserOp, userOpHash, missingAccountFunds);

        //Assert
        assertEq(validateUserOp, 0);
    }

    function testExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory callData = abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory signedUserOp =
            sendPackedUserOp.generateSignedUserPackedOp(callData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOpHash = EntryPoint(payable(helperConfig.getConfig().entryPoint)).getUserOpHash(signedUserOp);
        uint256 missingAccountFunds = 1e18;

        vm.deal(address(minimalAccount), 1e18);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = signedUserOp;

        // Act
        vm.prank(randomuser);
        EntryPoint(payable(helperConfig.getConfig().entryPoint)).handleOps(ops, payable(randomuser));

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }
}
