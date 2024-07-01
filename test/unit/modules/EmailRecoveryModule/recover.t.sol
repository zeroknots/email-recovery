// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { console2 } from "forge-std/console2.sol";
import { EmailRecoveryModule } from "src/modules/EmailRecoveryModule.sol";
import { RecoveryModuleBase } from "src/modules/RecoveryModuleBase.sol";
import { EmailRecoveryModuleBase } from "./EmailRecoveryModuleBase.t.sol";

contract EmailRecoveryModule_recover_Test is EmailRecoveryModuleBase {
    function setUp() public override {
        super.setUp();
    }

    function test_Recover_RevertWhen_NotTrustedRecoveryContract() public {
        vm.expectRevert(EmailRecoveryModule.NotTrustedRecoveryManager.selector);
        emailRecoveryModule.recover(accountAddress, recoveryCalldata);
    }

    function test_Recover_RevertWhen_RecoveryNotAuthorizedForAccount() public {
        address invalidAccount = address(1);

        vm.startPrank(emailRecoveryManagerAddress);
        vm.expectRevert(EmailRecoveryModule.RecoveryNotAuthorizedForAccount.selector);
        emailRecoveryModule.recover(invalidAccount, recoveryCalldata);
    }

    function test_Recover_RevertWhen_InvalidCalldataSelector() public {
        bytes4 invalidSelector = bytes4(keccak256(bytes("wrongSelector(address,address,address)")));
        bytes memory invalidCalldata =
            abi.encodeWithSelector(invalidSelector, accountAddress, recoveryModuleAddress, newOwner);

        vm.startPrank(emailRecoveryManagerAddress);
        vm.expectRevert(
            abi.encodeWithSelector(RecoveryModuleBase.InvalidSelector.selector, invalidSelector)
        );
        emailRecoveryModule.recover(accountAddress, invalidCalldata);
    }

    function test_Recover_Succeeds() public {
        vm.startPrank(emailRecoveryManagerAddress);
        emailRecoveryModule.recover(accountAddress, recoveryCalldata);

        address updatedOwner = validator.owners(accountAddress);
        assertEq(updatedOwner, newOwner);
    }
}
