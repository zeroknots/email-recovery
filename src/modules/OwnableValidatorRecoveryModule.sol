// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { ERC7579ExecutorBase } from "@rhinestone/modulekit/src/Modules.sol";

import { IRecoveryModule } from "../interfaces/IRecoveryModule.sol";
import { IZkEmailRecovery } from "../interfaces/IZkEmailRecovery.sol";

contract OwnableValidatorRecoveryModule is ERC7579ExecutorBase, IRecoveryModule {
    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    address public immutable ZK_EMAIL_RECOVERY;

    mapping(address account => address validator) public validators;

    error InvalidNewOwner();
    error NotTrustedRecoveryContract();

    constructor(address _zkEmailRecovery) {
        ZK_EMAIL_RECOVERY = _zkEmailRecovery;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * Initialize the module with the given data
     * @param data The data to initialize the module with
     */
    function onInstall(bytes calldata data) external {
        (
            address validator,
            address[] memory guardians,
            uint256[] memory weights,
            uint256 threshold,
            uint256 delay,
            uint256 expiry
        ) = abi.decode(data, (address, address[], uint256[], uint256, uint256, uint256));

        validators[msg.sender] = validator;

        bytes memory encodedCall = abi.encodeWithSignature(
            "configureRecovery(address,address[],uint256[],uint256,uint256,uint256)",
            address(this),
            guardians,
            weights,
            threshold,
            delay,
            expiry
        );

        _execute(msg.sender, ZK_EMAIL_RECOVERY, 0, encodedCall);
    }

    /**
     * De-initialize the module with the given data
     * @custom:unusedparam data - the data to de-initialize the module with
     */
    function onUninstall(bytes calldata /* data */ ) external {
        delete validators[msg.sender];
        IZkEmailRecovery(ZK_EMAIL_RECOVERY).deInitRecoveryFromModule(msg.sender);
    }

    /**
     * Check if the module is initialized
     * @param smartAccount The smart account to check
     * @return true if the module is initialized, false otherwise
     */
    function isInitialized(address smartAccount) external view returns (bool) {
        return validators[smartAccount] != address(0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     MODULE LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    function recover(address account, bytes[] memory subjectParams) external {
        if (msg.sender != ZK_EMAIL_RECOVERY) {
            revert NotTrustedRecoveryContract();
        }

        address newOwner = abi.decode(subjectParams[1], (address));
        if (newOwner == address(0)) {
            revert InvalidNewOwner();
        }
        bytes memory encodedCall = abi.encodeWithSignature(
            "changeOwner(address,address,address)", account, address(this), newOwner
        );

        _execute(account, validators[account], 0, encodedCall);
    }

    function getTrustedContract() external view returns (address) {
        return ZK_EMAIL_RECOVERY;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     METADATA
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * The name of the module
     * @return name The name of the module
     */
    function name() external pure returns (string memory) {
        return "OwnableValidatorRecoveryModule";
    }

    /**
     * The version of the module
     * @return version The version of the module
     */
    function version() external pure returns (string memory) {
        return "0.0.1";
    }

    /**
     * Check if the module is of a certain type
     * @param typeID The type ID to check
     * @return true if the module is of the given type, false otherwise
     */
    function isModuleType(uint256 typeID) external pure returns (bool) {
        return typeID == TYPE_EXECUTOR;
    }
}
