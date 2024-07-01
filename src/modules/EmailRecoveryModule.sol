// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC7579ExecutorBase } from "@rhinestone/modulekit/src/Modules.sol";
import { IERC7579Account } from "erc7579/interfaces/IERC7579Account.sol";
import { IModule } from "erc7579/interfaces/IERC7579Module.sol";
import { IEmailRecoveryModule } from "../interfaces/IEmailRecoveryModule.sol";
import { IEmailRecoveryManager } from "../interfaces/IEmailRecoveryManager.sol";
import { RecoveryModuleBase } from "./RecoveryModuleBase.sol";

/**
 * @title EmailRecoveryModule
 * @notice This contract provides a simple mechanism for recovering account validators by
 * permissioning certain functions to be called on validators. It facilitates recovery by
 * integration with a trusted email recovery manager. The module defines how a recovery request is
 * executed on a validator, while the trusted recovery manager defines what a valid
 * recovery request is
 */
contract EmailRecoveryModule is RecoveryModuleBase {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    CONSTANTS & STORAGE                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * Trusted email recovery manager contract that handles recovery requests
     */
    address public immutable VALIDATOR_MODULE;

    bytes4 public immutable RECOVERY_SELECTOR;

    /**
     * Account address to authorized validator
     */
    mapping(address account => bool isAuthorized) internal authorized;

    event RecoveryExecuted();

    error InvalidOnInstallData();
    error NotTrustedRecoveryManager();
    error RecoveryNotAuthorizedForAccount();

    constructor(
        address _emailRecoveryManager,
        address _validator,
        bytes4 _selector
    )
        RecoveryModuleBase(_emailRecoveryManager)
    {
        _requireSafeSelectors(_selector);

        VALIDATOR_MODULE = _validator;
        RECOVERY_SELECTOR = _selector;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          CONFIG                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * Initializes the module with the threshold and guardians
     * @dev data is encoded as follows: abi.encode(validator, isInstalledContext, initialSelector,
     * guardians, weights, threshold, delay, expiry)
     *
     * @param data encoded data for recovery configuration
     */
    function onInstall(bytes calldata data) external {
        if (data.length == 0) revert InvalidOnInstallData();
        (
            bytes memory isInstalledContext,
            address[] memory guardians,
            uint256[] memory weights,
            uint256 threshold,
            uint256 delay,
            uint256 expiry
        ) = abi.decode(data, (bytes, address[], uint256[], uint256, uint256, uint256));

        authorized[msg.sender] = true;

        _requireModuleInstalled({
            account: msg.sender,
            module: VALIDATOR_MODULE,
            context: isInstalledContext
        });

        _configureRecoveryManager({
            guardians: guardians,
            weights: weights,
            threshold: threshold,
            delay: delay,
            expiry: expiry
        });
    }

    /**
     * Handles the uninstallation of the module and clears the recovery configuration
     * @dev the data parameter is not used
     */
    function onUninstall(bytes calldata /* data */ ) external {
        authorized[msg.sender] = false;
        EMAIL_RECOVERY_MANAGER.deInitRecoveryFromModule(msg.sender);
    }

    function isAuthorizedToRecover(address smartAccount) external view returns (bool) {
        return authorized[smartAccount];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        MODULE LOGIC                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Executes recovery on a validator. Must be called by the trusted recovery manager
     * @param account The account to execute recovery for
     * @param recoveryCalldata The recovery calldata that should be executed on the validator
     * being recovered
     */
    function recover(
        address account,
        bytes calldata recoveryCalldata
    )
        external
        onlyRecoveryManager
    {
        if (!authorized[account]) {
            revert RecoveryNotAuthorizedForAccount();
        }

        bytes4 calldataSelector = bytes4(recoveryCalldata[:4]);
        if (calldataSelector != RECOVERY_SELECTOR) {
            revert InvalidSelector(calldataSelector);
        }

        _execute({ account: account, to: VALIDATOR_MODULE, value: 0, data: recoveryCalldata });

        emit RecoveryExecuted();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         METADATA                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * Returns the name of the module
     * @return name of the module
     */
    function name() external pure returns (string memory) {
        return "ZKEmail.EmailRecoveryModule";
    }

    /**
     * Returns the version of the module
     * @return version of the module
     */
    function version() external pure returns (string memory) {
        return "0.0.1";
    }
}
