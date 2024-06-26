// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { EmailAccountRecovery } from
    "ether-email-auth/packages/contracts/src/EmailAccountRecovery.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IModule } from "erc7579/interfaces/IERC7579Module.sol";

import { IZkEmailRecovery } from "./interfaces/IZkEmailRecovery.sol";
import { IEmailAuth } from "./interfaces/IEmailAuth.sol";
import { IUUPSUpgradable } from "./interfaces/IUUPSUpgradable.sol";
import { IRecoveryModule } from "./interfaces/IRecoveryModule.sol";
import { EmailAccountRecoveryRouter } from "./EmailAccountRecoveryRouter.sol";
import {
    EnumerableGuardianMap,
    GuardianStorage,
    GuardianStatus
} from "./libraries/EnumerableGuardianMap.sol";

/**
 * @title ZkEmailRecovery
 * @notice Provides a mechanism for account recovery using email guardians
 * @dev The underlying EmailAccountRecovery contract provides some base logic for deploying
 * guardian contracts and handling email verification.
 *
 * This contract defines a default implementation for email-based recovery. It is designed to
 * provide the core logic for email based account recovery that can be used across different account
 * implementations.
 *
 * ZkEmailRecovery relies on a dedicated recovery module to execute a recovery attempt. This
 * (ZkEmailRecovery) contract defines "what a valid recovery attempt is for an account", and the
 * recovery module defines “how that recovery attempt is executed on the account”.
 *
 * The core functions that must be called in the end-to-end flow for recovery are
 * 1. configureRecovery (does not need to be called again for subsequent recovery attempts)
 * 2. handleAcceptance - called for each guardian. Defined on EmailAccountRecovery.sol, calls
 * acceptGuardian in this contract
 * 3. handleRecovery - called for each guardian. Defined on EmailAccountRecovery.sol, calls
 * processRecovery in this contract
 * 4. completeRecovery
 */
contract ZkEmailRecovery is EmailAccountRecovery, IZkEmailRecovery {
    using EnumerableGuardianMap for EnumerableGuardianMap.AddressToGuardianMap;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    CONSTANTS & STORAGE                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * Minimum required time window between when a recovery attempt becomes valid and when it
     * becomes invalid
     */
    uint256 public constant MINIMUM_RECOVERY_WINDOW = 2 days;

    /**
     * Account address to recovery config
     */
    mapping(address account => RecoveryConfig recoveryConfig) internal recoveryConfigs;

    /**
     * Account address to recovery request
     */
    mapping(address account => RecoveryRequest recoveryRequest) internal recoveryRequests;

    /**
     * Account address to guardian address to guardian storage
     */
    mapping(address account => EnumerableGuardianMap.AddressToGuardianMap guardian) internal
        guardiansStorage;

    /**
     * Account to guardian config
     */
    mapping(address account => GuardianConfig guardianConfig) internal guardianConfigs;

    /**
     * Email account recovery router address to account address
     */
    mapping(address router => address account) internal routerToAccount;

    /**
     * Account address to email account recovery router address.
     * These are stored for frontends to easily find the router contract address from the given
     * account account address
     */
    mapping(address account => address router) internal accountToRouter;

    constructor(address _verifier, address _dkimRegistry, address _emailAuthImpl) {
        verifierAddr = _verifier;
        dkimAddr = _dkimRegistry;
        emailAuthImplementationAddr = _emailAuthImpl;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*            RECOVERY CONFIG AND REQUEST GETTERS             */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Retrieves the recovery configuration for a given account
     * @param account The address of the account for which the recovery configuration is being
     * retrieved
     * @return RecoveryConfig The recovery configuration for the specified account
     */
    function getRecoveryConfig(address account) external view returns (RecoveryConfig memory) {
        return recoveryConfigs[account];
    }

    /**
     * @notice Retrieves the recovery request details for a given account
     * @param account The address of the account for which the recovery request details are being
     * retrieved
     * @return RecoveryRequest The recovery request details for the specified account
     */
    function getRecoveryRequest(address account) external view returns (RecoveryRequest memory) {
        return recoveryRequests[account];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     CONFIGURE RECOVERY                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Configures recovery for the caller's account. This is the first core function
     * that must be called during the end-to-end recovery flow
     * @dev Can only be called once for configuration. Sets up the guardians, deploys a router
     * contract, and validates config parameters, ensuring that no recovery is in process
     * @param recoveryModule The address of the recovery module
     * @param guardians An array of guardian addresses
     * @param weights An array of weights corresponding to each guardian
     * @param threshold The threshold weight required for recovery
     * @param delay The delay period before recovery can be executed
     * @param expiry The expiry time after which the recovery attempt is invalid
     */
    function configureRecovery(
        address recoveryModule,
        address[] memory guardians,
        uint256[] memory weights,
        uint256 threshold,
        uint256 delay,
        uint256 expiry
    )
        external
    {
        address account = msg.sender;

        // setupGuardians contains a check that ensures this function can only be called once
        setupGuardians(account, guardians, weights, threshold);

        address router = deployRouterForAccount(account);

        RecoveryConfig memory recoveryConfig = RecoveryConfig(recoveryModule, delay, expiry);
        updateRecoveryConfig(recoveryConfig);

        emit RecoveryConfigured(account, recoveryModule, guardians.length, router);
    }

    /**
     * @notice Sets up guardians for a given account with specified weights and threshold
     * @dev This function can only be called once and ensures the guardians, weights, and threshold
     * are correctly configured
     * @param account The address of the account for which guardians are being set up
     * @param guardians An array of guardian addresses
     * @param weights An array of weights corresponding to each guardian
     * @param threshold The threshold weight required for guardians to approve recovery attempts
     */
    function setupGuardians(
        address account,
        address[] memory guardians,
        uint256[] memory weights,
        uint256 threshold
    )
        internal
    {
        // Threshold can only be 0 at initialization.
        // Check ensures that setup function can only be called once.
        if (guardianConfigs[account].threshold > 0) {
            revert SetupAlreadyCalled();
        }

        uint256 guardianCount = guardians.length;

        if (guardianCount != weights.length) {
            revert IncorrectNumberOfWeights();
        }

        if (threshold == 0) {
            revert ThresholdCannotBeZero();
        }

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < guardianCount; i++) {
            address guardian = guardians[i];
            uint256 weight = weights[i];

            if (guardian == address(0) || guardian == account) {
                revert InvalidGuardianAddress();
            }

            // As long as weights are 1 or above, there will be enough total weight to reach the
            // required threshold. This is because we check the guardian count cannot be less
            // than the threshold and there is an equal amount of guardians to weights.
            if (weight == 0) {
                revert InvalidGuardianWeight();
            }

            GuardianStorage memory guardianStorage = guardiansStorage[account].get(guardian);
            if (guardianStorage.status != GuardianStatus.NONE) {
                revert AddressAlreadyGuardian();
            }

            guardiansStorage[account].set({
                key: guardian,
                value: GuardianStorage(GuardianStatus.REQUESTED, weight)
            });
            totalWeight += weight;
        }

        if (threshold > totalWeight) {
            revert ThresholdCannotExceedTotalWeight();
        }

        guardianConfigs[account] = GuardianConfig(guardianCount, totalWeight, threshold);
    }

    /**
     * @notice Deploys a new router for the specified account
     * @dev Deploys a new EmailAccountRecoveryRouter contract using Create2 and associates it with
     * the account
     * @param account The address of the account for which the router is being deployed
     * @return address The address of the deployed router
     */
    function deployRouterForAccount(address account) internal returns (address) {
        bytes32 salt = keccak256(abi.encode(account));
        address routerAddress = computeRouterAddress(salt);

        // It possible the router has already been deployed. For example, if the account
        // configured recovery, and then cleared state using `deInitializeRecovery`. In
        // this case, set the address in storage without deploying the contract
        if (routerAddress.code.length > 0) {
            routerToAccount[routerAddress] = account;
            accountToRouter[account] = routerAddress;

            return routerAddress;
        } else {
            EmailAccountRecoveryRouter emailAccountRecoveryRouter =
                new EmailAccountRecoveryRouter{ salt: salt }(address(this));
            routerAddress = address(emailAccountRecoveryRouter);

            routerToAccount[routerAddress] = account;
            accountToRouter[account] = routerAddress;

            return routerAddress;
        }
    }

    /**
     * @notice Updates and validates the recovery configuration for the caller's account
     * @dev Validates and sets the new recovery configuration for the caller's account, ensuring
     * that no
     * recovery is in process. Reverts if the recovery module address is invalid, if the
     * delay is greater than the expiry, or if the recovery window is too short
     * @param recoveryConfig The new recovery configuration to be set for the caller's account
     */
    function updateRecoveryConfig(RecoveryConfig memory recoveryConfig)
        public
        onlyWhenNotRecovering
    {
        address account = msg.sender;

        if (guardianConfigs[account].threshold == 0) {
            revert AccountNotConfigured();
        }
        if (recoveryConfig.recoveryModule == address(0)) {
            revert InvalidRecoveryModule();
        }
        bool isInitialized = IModule(recoveryConfig.recoveryModule).isInitialized(account);
        if (!isInitialized) {
            revert RecoveryModuleNotInstalled();
        }
        if (recoveryConfig.delay > recoveryConfig.expiry) {
            revert DelayMoreThanExpiry();
        }
        if (recoveryConfig.expiry - recoveryConfig.delay < MINIMUM_RECOVERY_WINDOW) {
            revert RecoveryWindowTooShort();
        }

        recoveryConfigs[account] = recoveryConfig;

        emit RecoveryConfigUpdated(
            account, recoveryConfig.recoveryModule, recoveryConfig.delay, recoveryConfig.expiry
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HANDLE ACCEPTANCE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Returns a two-dimensional array of strings representing the subject templates for an
     * acceptance by a new guardian.
     * @dev This function is overridden from EmailAccountRecovery. It is also virtual so can be
     * re-implemented by inheriting contracts
     * to define different acceptance subject templates. This is useful for account implementations
     * which require different data
     * in the subject or if the email should be in a language that is not English.
     * @return string[][] A two-dimensional array of strings, where each inner array represents a
     * set of fixed strings and matchers for a subject template.
     */
    function acceptanceSubjectTemplates()
        public
        pure
        virtual
        override
        returns (string[][] memory)
    {
        string[][] memory templates = new string[][](1);
        templates[0] = new string[](5);
        templates[0][0] = "Accept";
        templates[0][1] = "guardian";
        templates[0][2] = "request";
        templates[0][3] = "for";
        templates[0][4] = "{ethAddr}";
        return templates;
    }

    /**
     * @notice Accepts a guardian for the specified account. This is the second core function
     * that must be called during the end-to-end recovery flow
     * @dev Called once per guardian added. Although this adds an extra step to recovery, this
     * acceptance
     * flow is an important security feature to ensure that no typos are made when adding a guardian
     * and that the guardian explicitly consents to the role. Called as part of handleAcceptance
     * in EmailAccountRecovery
     * @param guardian The address of the guardian to be accepted
     * @param templateIdx The index of the template used for acceptance
     * @param subjectParams An array of bytes containing the subject parameters
     */
    function acceptGuardian(
        address guardian,
        uint256 templateIdx,
        bytes[] memory subjectParams,
        bytes32
    )
        internal
        override
    {
        address accountInEmail = validateAcceptanceSubjectTemplates(templateIdx, subjectParams);

        if (recoveryRequests[accountInEmail].currentWeight > 0) {
            revert RecoveryInProcess();
        }

        // This check ensures GuardianStatus is correct and also that the
        // account in email is a valid account
        GuardianStorage memory guardianStorage = getGuardian(accountInEmail, guardian);
        if (guardianStorage.status != GuardianStatus.REQUESTED) {
            revert InvalidGuardianStatus(guardianStorage.status, GuardianStatus.REQUESTED);
        }

        guardiansStorage[accountInEmail].set({
            key: guardian,
            value: GuardianStorage(GuardianStatus.ACCEPTED, guardianStorage.weight)
        });

        emit GuardianAccepted(accountInEmail, guardian);
    }

    /**
     * @notice Validates the acceptance subject templates and extracts the account address
     * @dev Can be overridden by an inheriting contract if using different acceptance subject
     * templates. This function reverts if the subject parameters are invalid. The function
     * should extract and return the account address as this is required by the core recovery logic.
     * @param templateIdx The index of the template used for acceptance
     * @param subjectParams An array of bytes containing the subject parameters
     * @return accountInEmail The extracted account address from the subject parameters
     */
    function validateAcceptanceSubjectTemplates(
        uint256 templateIdx,
        bytes[] memory subjectParams
    )
        internal
        pure
        virtual
        returns (address)
    {
        if (templateIdx != 0) {
            revert InvalidTemplateIndex();
        }

        if (subjectParams.length != 1) revert InvalidSubjectParams();

        // The GuardianStatus check in acceptGuardian implicitly
        // validates the account, so no need to re-validate here
        address accountInEmail = abi.decode(subjectParams[0], (address));

        return accountInEmail;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      HANDLE RECOVERY                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Returns a two-dimensional array of strings representing the subject templates for
     * email recovery.
     * @dev This function is overridden from EmailAccountRecovery. It is also virtual so can be
     * re-implemented by inheriting contracts
     * to define different recovery subject templates. This is useful for account implementations
     * which require different data
     * in the subject or if the email should be in a language that is not English.
     * @return string[][] A two-dimensional array of strings, where each inner array represents a
     * set of fixed strings and matchers for a subject template.
     */
    function recoverySubjectTemplates() public pure virtual override returns (string[][] memory) {
        string[][] memory templates = new string[][](1);
        templates[0] = new string[](11);
        templates[0][0] = "Recover";
        templates[0][1] = "account";
        templates[0][2] = "{ethAddr}";
        templates[0][3] = "to";
        templates[0][4] = "new";
        templates[0][5] = "owner";
        templates[0][6] = "{ethAddr}";
        templates[0][7] = "using";
        templates[0][8] = "recovery";
        templates[0][9] = "module";
        templates[0][10] = "{ethAddr}";
        return templates;
    }

    /**
     * @notice Processes a recovery request for a given account. This is the third core function
     * that must be called during the end-to-end recovery flow
     * @dev Reverts if the guardian address is invalid, if the template index is not zero, or if the
     * guardian status is not accepted
     * @param guardian The address of the guardian initiating the recovery
     * @param templateIdx The index of the template used for the recovery request
     * @param subjectParams An array of bytes containing the subject parameters
     */
    function processRecovery(
        address guardian,
        uint256 templateIdx,
        bytes[] memory subjectParams,
        bytes32
    )
        internal
        override
    {
        address accountInEmail = validateRecoverySubjectTemplates(templateIdx, subjectParams);

        // This check ensures GuardianStatus is correct and also that the
        // account in email is a valid account
        GuardianStorage memory guardianStorage = getGuardian(accountInEmail, guardian);
        if (guardianStorage.status != GuardianStatus.ACCEPTED) {
            revert InvalidGuardianStatus(guardianStorage.status, GuardianStatus.ACCEPTED);
        }

        RecoveryRequest storage recoveryRequest = recoveryRequests[accountInEmail];

        recoveryRequest.currentWeight += guardianStorage.weight;

        uint256 threshold = getGuardianConfig(accountInEmail).threshold;
        if (recoveryRequest.currentWeight >= threshold) {
            uint256 executeAfter = block.timestamp + recoveryConfigs[accountInEmail].delay;
            uint256 executeBefore = block.timestamp + recoveryConfigs[accountInEmail].expiry;

            recoveryRequest.executeAfter = executeAfter;
            recoveryRequest.executeBefore = executeBefore;
            recoveryRequest.subjectParams = subjectParams;

            emit RecoveryProcessed(accountInEmail, executeAfter, executeBefore);

            // If delay is set to zero, an account can complete recovery straight away without
            // needing an additional call to completeRecovery
            if (executeAfter == block.timestamp) {
                completeRecovery(accountInEmail);
            }
        }
    }

    /**
     * @notice Validates the recovery subject templates and extracts the account and recovery module
     * addresses
     * @dev Can be overridden by an inheriting contract if using different acceptance subject
     * templates. This function reverts if the subject parameters are invalid. The function
     * should extract and return the account address and the recovery module as they are required by
     * the core recovery logic.
     * @param templateIdx The index of the template used for the recovery request
     * @param subjectParams An array of bytes containing the subject parameters
     * @return accountInEmail The extracted account address from the subject parameters
     */
    function validateRecoverySubjectTemplates(
        uint256 templateIdx,
        bytes[] memory subjectParams
    )
        internal
        view
        virtual
        returns (address)
    {
        if (templateIdx != 0) {
            revert InvalidTemplateIndex();
        }

        if (subjectParams.length != 3) revert InvalidSubjectParams();

        // The GuardianStatus check in processRecovery implicitly
        // validates the account, so no need to re-validate here
        address accountInEmail = abi.decode(subjectParams[0], (address));
        address newOwnerInEmail = abi.decode(subjectParams[1], (address));
        address recoveryModuleInEmail = abi.decode(subjectParams[2], (address));

        if (newOwnerInEmail == address(0)) {
            revert InvalidNewOwner();
        }

        address expectedRecoveryModule = recoveryConfigs[accountInEmail].recoveryModule;
        if (recoveryModuleInEmail == address(0) || recoveryModuleInEmail != expectedRecoveryModule)
        {
            revert InvalidRecoveryModule();
        }

        return accountInEmail;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     COMPLETE RECOVERY                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Completes the recovery process.
     */
    function completeRecovery() external override {
        address account = getAccountForRouter(msg.sender);
        completeRecovery(account);
    }

    /**
     * @notice Completes the recovery process for a given account. This is the forth and final
     * core function that must be called during the end-to-end recovery flow. Can be called by
     * anyone.
     * @dev Validates the recovery request by checking the total weight, that the delay has passed,
     * and the request has not expired. Triggers the recovery module to perform the recovery. The
     * recovery module trusts that this contract has validated the recovery attempt. Deletes the
     * recovery
     * request but recovery config state is maintained so future recovery requests can be made
     * without having to reconfigure everything
     * @param account The address of the account for which the recovery is being completed
     */
    function completeRecovery(address account) public {
        if (account == address(0)) {
            revert InvalidAccountAddress();
        }
        RecoveryRequest memory recoveryRequest = recoveryRequests[account];

        uint256 threshold = getGuardianConfig(account).threshold;
        if (recoveryRequest.currentWeight < threshold) {
            revert NotEnoughApprovals();
        }

        if (block.timestamp < recoveryRequest.executeAfter) {
            revert DelayNotPassed();
        }

        if (block.timestamp >= recoveryRequest.executeBefore) {
            revert RecoveryRequestExpired();
        }

        delete recoveryRequests[account];

        address recoveryModule = recoveryConfigs[account].recoveryModule;

        IRecoveryModule(recoveryModule).recover(account, recoveryRequest.subjectParams);

        emit RecoveryCompleted(account);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    CANCEL/DE-INIT LOGIC                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Cancels the recovery request for the caller's account
     * @dev Deletes the current recovery request associated with the caller's account
     * Can be overridden by a child contract so custom access control can be added. Adding
     * additional
     * access control can be helpful to protect against malicious actors who have stolen a users
     * private key. The default implementation of this account primarily protects against lost
     * private keys
     * @custom:unusedparam data - unused parameter, can be used when overridden
     */
    function cancelRecovery(bytes calldata /* data */ ) external virtual {
        address account = msg.sender;
        delete recoveryRequests[account];
        emit RecoveryCancelled(account);
    }

    /**
     * @notice Removes all state related to an account. Must be called from a configured recovery
     * module
     * @dev In order to prevent unexpected behaviour when reinstalling account modules, the module
     * should be deinitialized. This should include remove state accociated with an account.
     * @param account The account to delete state for
     */
    function deInitRecoveryFromModule(address account) external {
        address recoveryModule = recoveryConfigs[account].recoveryModule;
        if (recoveryModule != msg.sender) {
            revert NotRecoveryModule();
        }

        if (recoveryRequests[account].currentWeight > 0) {
            revert RecoveryInProcess();
        }

        delete recoveryConfigs[account];
        delete recoveryRequests[account];

        EnumerableGuardianMap.AddressToGuardianMap storage guardians = guardiansStorage[account];

        guardians.removeAll(guardians.keys());
        delete guardianConfigs[account];

        address accountToRouterAddr = accountToRouter[account];
        delete accountToRouter[account];
        delete routerToAccount[accountToRouterAddr];

        emit RecoveryDeInitialized(account);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       GUARDIAN LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Retrieves the guardian configuration for a given account
     * @param account The address of the account for which the guardian configuration is being
     * retrieved
     * @return GuardianConfig The guardian configuration for the specified account
     */
    function getGuardianConfig(address account) public view returns (GuardianConfig memory) {
        return guardianConfigs[account];
    }

    /**
     * @notice Retrieves the guardian storage details for a given guardian and account
     * @param account The address of the account associated with the guardian
     * @param guardian The address of the guardian
     * @return GuardianStorage The guardian storage details for the specified guardian and account
     */
    function getGuardian(
        address account,
        address guardian
    )
        public
        view
        returns (GuardianStorage memory)
    {
        return guardiansStorage[account].get(guardian);
    }

    /**
     * @notice Adds a guardian for the caller's account with a specified weight and updates the
     * threshold if necessary
     * @dev This function can only be called by the account associated with the guardian and only if
     * no recovery is in process
     * @param guardian The address of the guardian to be added
     * @param weight The weight assigned to the guardian
     * @param threshold The new threshold for guardian approvals
     */
    function addGuardian(
        address guardian,
        uint256 weight,
        uint256 threshold
    )
        external
        onlyWhenNotRecovering
    {
        address account = msg.sender;

        // Threshold can only be 0 at initialization.
        // Check ensures that setup function should be called first
        if (guardianConfigs[account].threshold == 0) {
            revert SetupNotCalled();
        }

        GuardianStorage memory guardianStorage = guardiansStorage[account].get(guardian);

        if (guardian == address(0) || guardian == account) {
            revert InvalidGuardianAddress();
        }

        if (guardianStorage.status != GuardianStatus.NONE) {
            revert AddressAlreadyGuardian();
        }

        if (weight == 0) {
            revert InvalidGuardianWeight();
        }

        guardiansStorage[account].set({
            key: guardian,
            value: GuardianStorage(GuardianStatus.REQUESTED, weight)
        });
        guardianConfigs[account].guardianCount++;
        guardianConfigs[account].totalWeight += weight;

        emit AddedGuardian(account, guardian);

        // Change threshold if threshold was changed.
        if (guardianConfigs[account].threshold != threshold) {
            changeThreshold(threshold);
        }
    }

    /**
     * @notice Removes a guardian for the caller's account and updates the threshold if necessary
     * @dev This function can only be called by the account associated with the guardian and only if
     * no recovery is in process
     * @param guardian The address of the guardian to be removed
     * @param threshold The new threshold for guardian approvals
     */
    function removeGuardian(
        address guardian,
        uint256 threshold
    )
        external
        onlyAccountForGuardian(guardian)
        onlyWhenNotRecovering
    {
        address account = msg.sender;
        GuardianConfig memory guardianConfig = guardianConfigs[account];
        GuardianStorage memory guardianStorage = guardiansStorage[account].get(guardian);

        // Only allow guardian removal if threshold can still be reached.
        if (guardianConfig.totalWeight - guardianStorage.weight < guardianConfig.threshold) {
            revert ThresholdCannotExceedTotalWeight();
        }

        guardiansStorage[account].remove(guardian);
        guardianConfigs[account].guardianCount--;
        guardianConfigs[account].totalWeight -= guardianStorage.weight;

        emit RemovedGuardian(account, guardian);

        // Change threshold if threshold was changed.
        if (guardianConfig.threshold != threshold) {
            changeThreshold(threshold);
        }
    }

    /**
     * @notice Changes the threshold for guardian approvals for the caller's account
     * @dev This function can only be called if no recovery is in process
     * @param threshold The new threshold for guardian approvals
     */
    function changeThreshold(uint256 threshold) public onlyWhenNotRecovering {
        address account = msg.sender;

        // Threshold can only be 0 at initialization.
        // Check ensures that setup function should be called first
        if (guardianConfigs[account].threshold == 0) {
            revert SetupNotCalled();
        }

        // Validate that threshold is smaller than the total weight.
        if (threshold > guardianConfigs[account].totalWeight) {
            revert ThresholdCannotExceedTotalWeight();
        }

        // There has to be at least one Account guardian.
        if (threshold == 0) {
            revert ThresholdCannotBeZero();
        }

        guardianConfigs[account].threshold = threshold;
        emit ChangedThreshold(account, threshold);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ROUTER LOGIC                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Retrieves the account address associated with a given recovery router
     * @param recoveryRouter The address of the recovery router
     * @return address The account address associated with the specified recovery router
     */
    function getAccountForRouter(address recoveryRouter) public view returns (address) {
        return routerToAccount[recoveryRouter];
    }

    /**
     * @notice Retrieves the recovery router address associated with a given account
     * @param account The address of the account
     * @return address The recovery router address associated with the specified account
     */
    function getRouterForAccount(address account) external view returns (address) {
        return accountToRouter[account];
    }

    /**
     * @notice Computes the address of the router using the provided salt
     * @dev Uses Create2 to compute the address based on the salt and the creation code of the
     * EmailAccountRecoveryRouter contract
     * @param salt The salt used to compute the address
     * @return address The computed address of the router
     */
    function computeRouterAddress(bytes32 salt) public view returns (address) {
        return Create2.computeAddress(
            salt,
            keccak256(
                abi.encodePacked(
                    type(EmailAccountRecoveryRouter).creationCode, abi.encode(address(this))
                )
            )
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EMAIL AUTH LOGIC                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice Updates the DKIM registry address for the specified guardian
     * @dev This function can only be called by the account associated with the guardian and only if
     * no recovery is in process
     * @param guardian The address of the guardian
     * @param dkimRegistryAddr The new DKIM registry address to be set for the guardian
     */
    function updateGuardianDKIMRegistry(
        address guardian,
        address dkimRegistryAddr
    )
        external
        onlyAccountForGuardian(guardian)
        onlyWhenNotRecovering
    {
        IEmailAuth(guardian).updateDKIMRegistry(dkimRegistryAddr);
    }

    /**
     * @notice Updates the verifier address for the specified guardian
     * @dev This function can only be called by the account associated with the guardian and only if
     * no recovery is in process
     * @param guardian The address of the guardian
     * @param verifierAddr The new verifier address to be set for the guardian
     */
    function updateGuardianVerifier(
        address guardian,
        address verifierAddr
    )
        external
        onlyAccountForGuardian(guardian)
        onlyWhenNotRecovering
    {
        IEmailAuth(guardian).updateVerifier(verifierAddr);
    }

    /**
     * @notice Upgrades the implementation of the specified guardian and calls the provided data
     * @dev This function can only be called by the account associated with the guardian and only if
     * no recovery is in process
     * @param guardian The address of the guardian
     * @param newImplementation The new implementation address for the guardian
     * @param data The data to be called with the new implementation
     */
    function upgradeEmailAuthGuardian(
        address guardian,
        address newImplementation,
        bytes memory data
    )
        external
        onlyAccountForGuardian(guardian)
        onlyWhenNotRecovering
    {
        IUUPSUpgradable(guardian).upgradeToAndCall(newImplementation, data);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Modifier to check recovery status. Reverts if recovery is in process for the account
     */
    modifier onlyWhenNotRecovering() {
        if (recoveryRequests[msg.sender].currentWeight > 0) {
            revert RecoveryInProcess();
        }
        _;
    }

    /**
     * @dev Modifier to check if the given address is a configured guardian
     * for an account. Assumes msg.sender is the account
     * @param guardian The address of the guardian to check
     */
    modifier onlyAccountForGuardian(address guardian) {
        bool isGuardian = guardiansStorage[msg.sender].get(guardian).status != GuardianStatus.NONE;
        if (!isGuardian) {
            revert UnauthorizedAccountForGuardian();
        }
        _;
    }
}
