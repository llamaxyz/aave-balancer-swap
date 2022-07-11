// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {OtcEscrowApprovals} from "./OtcEscrowApprovals.sol";
import {IEcosystemReserveController} from "./external/aave/IEcosystemReserveController.sol";

/// @title Payload to approve and execute BAL <> AAVE Swap
/// @author Llama
/// @notice Provides an execute function for Aave governance to approve and execute the BAL <> AAVE Swap
contract ProposalPayload {
    /********************************
     *   CONSTANTS AND IMMUTABLES   *
     ********************************/

    IEcosystemReserveController public constant AAVE_ECOSYSTEM_RESERVE_CONTROLLER =
        IEcosystemReserveController(0x3d569673dAa0575c936c7c67c4E6AedA69CC630C);

    address public constant AAVE_ECOSYSTEM_RESERVE = 0x25F2226B597E8F9514B3F68F00f494cF4f286491;

    address public constant AAVE_TOKEN = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    uint256 public constant AAVE_AMOUNT = 1690728e16;

    OtcEscrowApprovals public immutable otcEscrowApprovals;

    /*******************
     *   CONSTRUCTOR   *
     *******************/

    constructor(OtcEscrowApprovals _otcEscrowApprovals) {
        otcEscrowApprovals = _otcEscrowApprovals;
    }

    /*****************
     *   FUNCTIONS   *
     *****************/

    /// @notice The AAVE governance executor calls this function to implement the proposal.
    function execute() external {
        // Approve the OTC Escrow Approvals contract to transfer pre-defined amount of AAVE tokens
        AAVE_ECOSYSTEM_RESERVE_CONTROLLER.approve(
            AAVE_ECOSYSTEM_RESERVE,
            AAVE_TOKEN,
            address(otcEscrowApprovals),
            AAVE_AMOUNT
        );
        // Execute the OTC Escrow Approvals swap
        otcEscrowApprovals.swap();
    }
}
