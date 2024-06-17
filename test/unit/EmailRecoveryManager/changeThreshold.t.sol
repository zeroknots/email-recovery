// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import { ModuleKitHelpers, ModuleKitUserOp } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR, MODULE_TYPE_VALIDATOR } from "modulekit/external/ERC7579.sol";
import { UnitBase } from "../UnitBase.t.sol";
import { IEmailRecoveryManager } from "src/interfaces/IEmailRecoveryManager.sol";
import { EmailRecoveryModule } from "src/modules/EmailRecoveryModule.sol";
import { OwnableValidator } from "src/test/OwnableValidator.sol";

error SetupNotCalled();
error ThresholdCannotExceedTotalWeight();
error ThresholdCannotBeZero();

event ChangedThreshold(address indexed account, uint256 threshold);

contract ZkEmailRecovery_changeThreshold_Test is UnitBase {
    function setUp() public override {
        super.setUp();
    }

    // function test_RevertWhen_AlreadyRecovering() public {
    //     acceptGuardian(accountSalt1);
    //     vm.warp(12 seconds);
    //     handleRecovery(recoveryModuleAddress, accountSalt1);

    //     vm.startPrank(accountAddress);
    //     vm.expectRevert(IEmailRecoveryManager.RecoveryInProcess.selector);
    //     emailRecoveryManager.changeThreshold(threshold);
    // }

    // function test_RevertWhen_SetupNotCalled() public {
    //     vm.expectRevert(SetupNotCalled.selector);
    //     emailRecoveryManager.changeThreshold(threshold);
    // }

    // function test_RevertWhen_ThresholdExceedsTotalWeight() public {
    //     uint256 highThreshold = totalWeight + 1;

    //     vm.startPrank(accountAddress);
    //     vm.expectRevert(ThresholdCannotExceedTotalWeight.selector);
    //     emailRecoveryManager.changeThreshold(highThreshold);
    // }

    // function test_RevertWhen_ThresholdIsZero() public {
    //     uint256 zeroThreshold = 0;

    //     vm.startPrank(accountAddress);
    //     vm.expectRevert(ThresholdCannotBeZero.selector);
    //     emailRecoveryManager.changeThreshold(zeroThreshold);
    // }

    // function test_ChangeThreshold_IncreaseThreshold() public {
    //     uint256 newThreshold = threshold + 1;

    //     vm.startPrank(accountAddress);
    //     vm.expectEmit();
    //     emit ChangedThreshold(accountAddress, newThreshold);
    //     emailRecoveryManager.changeThreshold(newThreshold);

    //     IEmailRecoveryManager.GuardianConfig memory guardianConfig =
    //         emailRecoveryManager.getGuardianConfig(accountAddress);
    //     assertEq(guardianConfig.guardianCount, guardians.length);
    //     assertEq(guardianConfig.threshold, newThreshold);
    // }

    // function test_ChangeThreshold_DecreaseThreshold() public {
    //     uint256 newThreshold = threshold - 1;

    //     vm.startPrank(accountAddress);
    //     vm.expectEmit();
    //     emit ChangedThreshold(accountAddress, newThreshold);
    //     emailRecoveryManager.changeThreshold(newThreshold);

    //     IEmailRecoveryManager.GuardianConfig memory guardianConfig =
    //         emailRecoveryManager.getGuardianConfig(accountAddress);
    //     assertEq(guardianConfig.guardianCount, guardians.length);
    //     assertEq(guardianConfig.threshold, newThreshold);
    // }
}