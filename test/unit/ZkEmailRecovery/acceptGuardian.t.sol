// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import { ModuleKitHelpers, ModuleKitUserOp } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR, MODULE_TYPE_VALIDATOR } from "modulekit/external/ERC7579.sol";
import { EmailRecoveryModule } from "src/modules/EmailRecoveryModule.sol";
import { IEmailRecoveryManager } from "src/interfaces/IEmailRecoveryManager.sol";
import { GuardianStorage, GuardianStatus } from "src/libraries/EnumerableGuardianMap.sol";
import { UnitBase } from "../UnitBase.t.sol";
import { OwnableValidator } from "src/test/OwnableValidator.sol";

contract ZkEmailRecovery_acceptGuardian_Test is UnitBase {
    using ModuleKitHelpers for *;
    using ModuleKitUserOp for *;

    OwnableValidator validator;
    EmailRecoveryModule recoveryModule;
    address recoveryModuleAddress;

    function setUp() public override {
        super.setUp();

        validator = new OwnableValidator();
        recoveryModule = new EmailRecoveryModule{ salt: "test salt" }(address(emailRecoveryManager));
        recoveryModuleAddress = address(recoveryModule);

        instance.installModule({
            moduleTypeId: MODULE_TYPE_VALIDATOR,
            module: address(validator),
            data: abi.encode(owner, recoveryModuleAddress)
        });
        // Install recovery module - configureRecovery is called on `onInstall`
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: recoveryModuleAddress,
            data: abi.encode(address(validator), guardians, guardianWeights, threshold, delay, expiry)
        });
    }

    function test_AcceptGuardian_RevertWhen_AlreadyRecovering() public {
        acceptGuardian(accountSalt1);
        vm.warp(12 seconds);
        handleRecovery(recoveryModuleAddress, accountSalt1);

        bytes[] memory subjectParams = new bytes[](1);
        subjectParams[0] = abi.encode(accountAddress);
        bytes32 nullifier = keccak256(abi.encode("nullifier 1"));

        vm.expectRevert(IEmailRecoveryManager.RecoveryInProcess.selector);
        emailRecoveryManager.exposed_acceptGuardian(
            guardian1, templateIdx, subjectParams, nullifier
        );
    }

    function test_AcceptGuardian_RevertWhen_GuardianStatusIsNONE() public {
        bytes[] memory subjectParams = new bytes[](1);
        subjectParams[0] = abi.encode(accountAddress);
        bytes32 nullifier = keccak256(abi.encode("nullifier 1"));

        vm.prank(accountAddress);
        instance.uninstallModule(MODULE_TYPE_EXECUTOR, recoveryModuleAddress, "");
        vm.stopPrank();

        vm.expectRevert(
            abi.encodeWithSelector(
                IEmailRecoveryManager.InvalidGuardianStatus.selector,
                uint256(GuardianStatus.NONE),
                uint256(GuardianStatus.REQUESTED)
            )
        );
        emailRecoveryManager.exposed_acceptGuardian(
            guardian1, templateIdx, subjectParams, nullifier
        );
    }

    function test_AcceptGuardian_RevertWhen_GuardianStatusIsACCEPTED() public {
        bytes[] memory subjectParams = new bytes[](1);
        subjectParams[0] = abi.encode(accountAddress);
        bytes32 nullifier = keccak256(abi.encode("nullifier 1"));

        emailRecoveryManager.exposed_acceptGuardian(
            guardian1, templateIdx, subjectParams, nullifier
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEmailRecoveryManager.InvalidGuardianStatus.selector,
                uint256(GuardianStatus.ACCEPTED),
                uint256(GuardianStatus.REQUESTED)
            )
        );
        emailRecoveryManager.exposed_acceptGuardian(
            guardian1, templateIdx, subjectParams, nullifier
        );
    }

    function test_AcceptGuardian_Succeeds() public {
        bytes[] memory subjectParams = new bytes[](1);
        subjectParams[0] = abi.encode(accountAddress);
        bytes32 nullifier = keccak256(abi.encode("nullifier 1"));

        emailRecoveryManager.exposed_acceptGuardian(
            guardian1, templateIdx, subjectParams, nullifier
        );

        GuardianStorage memory guardianStorage =
            emailRecoveryManager.getGuardian(accountAddress, guardian1);
        assertEq(uint256(guardianStorage.status), uint256(GuardianStatus.ACCEPTED));
        assertEq(guardianStorage.weight, uint256(1));
    }
}
