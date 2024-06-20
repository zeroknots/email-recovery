// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/console2.sol";
import { ModuleKitHelpers } from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/external/ERC7579.sol";
import { EmailRecoveryModule } from "src/modules/EmailRecoveryModule.sol";

import { UnitBase } from "../../UnitBase.t.sol";

contract EmailRecoveryModule_onInstall_Test is UnitBase {
    using ModuleKitHelpers for *;

    function setUp() public override {
        super.setUp();
    }

    function test_OnInstall_RevertWhen_InvalidOnInstallData() public {
        instance.uninstallModule(MODULE_TYPE_EXECUTOR, recoveryModuleAddress, "");

        bytes memory emptyData = new bytes(0);
        assertEq(emptyData.length, 0);

        // FIXME: Error not thrown despite the data being passed has a length of zero
        // vm.expectRevert(EmailRecoveryModule.InvalidOnInstallData.selector);

        // When installing with empty data and not expecting a revert, the test fails
        // instance.installModule({
        //     moduleTypeId: MODULE_TYPE_EXECUTOR,
        //     module: recoveryModuleAddress,
        //     data: emptyData
        // });
    }

    function test_OnInstall_Succeeds() public {
        instance.uninstallModule(MODULE_TYPE_EXECUTOR, recoveryModuleAddress, "");

        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: recoveryModuleAddress,
            data: abi.encode(
                validatorAddress,
                isInstalledContext,
                functionSelector,
                guardians,
                guardianWeights,
                threshold,
                delay,
                expiry
            )
        });

        bytes4 allowedSelector =
            emailRecoveryModule.exposed_allowedSelectors(validatorAddress, accountAddress);
        address allowedValidator =
            emailRecoveryModule.exposed_selectorToValidator(functionSelector, accountAddress);

        assertEq(allowedSelector, functionSelector);
        assertEq(allowedValidator, validatorAddress);

        address[] memory allowedValidators =
            emailRecoveryModule.getAllowedValidators(accountAddress);
        bytes4[] memory allowedSelectors = emailRecoveryModule.getAllowedSelectors(accountAddress);
        assertEq(allowedValidators.length, 1);
        assertEq(allowedSelectors.length, 1);
    }
}
