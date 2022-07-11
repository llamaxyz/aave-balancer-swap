// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

// testing libraries
import "@ds/test.sol";
import "@std/console.sol";
import {stdCheats} from "@std/stdlib.sol";
import {Vm} from "@std/Vm.sol";
import {DSTestPlus} from "@solmate/test/utils/DSTestPlus.sol";

// contract dependencies
import "../external/aave/IAaveGovernanceV2.sol";
import "../external/aave/IExecutorWithTimelock.sol";
import "../ProposalPayload.sol";
import "../OtcEscrowApprovals.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProposalPayloadTest is DSTestPlus, stdCheats {
    event Swap(uint256 balAmount, uint256 aaveAmount);

    Vm private vm = Vm(HEVM_ADDRESS);

    address public constant aaveTokenAddress = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address public constant balancerTokenAddress = 0xba100000625a3754423978a60c9317c58a424e3D;

    address public constant aaveEcosystemReserve = 0x25F2226B597E8F9514B3F68F00f494cF4f286491;
    address public constant balancerTreasury = 0x10A19e7eE7d7F8a52822f6817de8ea18204F2e4f;

    uint256 public constant aaveAmount = 1737755e16;
    uint256 public constant balancerAmount = 200000e18;

    address private aaveGovernanceAddress = 0xEC568fffba86c094cf06b22134B23074DFE2252c;
    address private aaveGovernanceShortExecutor = 0xEE56e2B3D491590B5b31738cC34d5232F378a8D5;

    IAaveGovernanceV2 private aaveGovernanceV2 = IAaveGovernanceV2(aaveGovernanceAddress);
    IExecutorWithTimelock private shortExecutor = IExecutorWithTimelock(aaveGovernanceShortExecutor);

    address[] private aaveWhales;

    address private proposalPayloadAddress;
    address private otcEscrowApprovalsAddress;

    address[] private targets;
    uint256[] private values;
    string[] private signatures;
    bytes[] private calldatas;
    bool[] private withDelegatecalls;
    bytes32 private ipfsHash = 0x0;

    uint256 private proposalId;

    OtcEscrowApprovals public otcEscrowApprovals;
    ProposalPayload public proposalPayload;

    function setUp() public {
        // aave whales may need to be updated based on the block being used
        // these are sometimes exchange accounts or whale who move their funds

        // select large holders here: https://etherscan.io/token/0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9#balances
        aaveWhales.push(0xBE0eB53F46cd790Cd13851d5EFf43D12404d33E8);
        aaveWhales.push(0x26a78D5b6d7a7acEEDD1e6eE3229b372A624d8b7);
        aaveWhales.push(0x2FAF487A4414Fe77e2327F0bf4AE2a264a776AD2);

        // Deploying OTC Escrow Approvals contract
        otcEscrowApprovals = new OtcEscrowApprovals(balancerAmount, aaveAmount);
        otcEscrowApprovalsAddress = address(otcEscrowApprovals);
        vm.label(otcEscrowApprovalsAddress, "OtcEscrowApprovals");

        // Deploying Proposal Payload contract
        proposalPayload = new ProposalPayload(otcEscrowApprovals, aaveAmount);
        proposalPayloadAddress = address(proposalPayload);
        vm.label(proposalPayloadAddress, "ProposalPayload");

        vm.label(aaveTokenAddress, "aaveTokenAddress");
        vm.label(balancerTokenAddress, "balancerTokenAddress");
        vm.label(aaveEcosystemReserve, "aaveEcosystemReserve");
        vm.label(balancerTreasury, "balancerTreasury");
        vm.label(aaveGovernanceAddress, "aaveGovernance");
        vm.label(aaveGovernanceShortExecutor, "aaveGovernanceShortExecutor");

        // Balancer Treasury approving spend of balancer amount to OTC Escrow Approvals contract
        vm.prank(balancerTreasury);
        IERC20(balancerTokenAddress).approve(otcEscrowApprovalsAddress, balancerAmount);

        // create proposal is configured to call execute() as a delegatecall
        // most proposals can use this format - you likely will not have to update this
        _createProposal();

        // these are generic steps for all proposals - no updates required
        _voteOnProposal();
        _skipVotingPeriod();
        _queueProposal();
        _skipQueuePeriod();
    }

    function testExecute() public {
        // Check that Balancer Treasury has approved OTC Escrow Approvals contract to transfer balancer amount of tokens
        assertEq(IERC20(balancerTokenAddress).allowance(balancerTreasury, otcEscrowApprovalsAddress), balancerAmount);

        uint256 initialAaveEcosystemReserveAaveBalance = IERC20(aaveTokenAddress).balanceOf(aaveEcosystemReserve);
        uint256 initialAaveEcosystemReserveBalancerBalance = IERC20(balancerTokenAddress).balanceOf(
            aaveEcosystemReserve
        );
        uint256 initialBalancerTreasuryAaveBalance = IERC20(aaveTokenAddress).balanceOf(balancerTreasury);
        uint256 initialBalancerTreasuryBalancerBalance = IERC20(balancerTokenAddress).balanceOf(balancerTreasury);

        vm.expectEmit(false, false, false, true);
        emit Swap(balancerAmount, aaveAmount);
        _executeProposal();

        // Checking final post execution balances
        assertEq(
            initialAaveEcosystemReserveAaveBalance - aaveAmount,
            IERC20(aaveTokenAddress).balanceOf(aaveEcosystemReserve)
        );
        assertEq(
            initialAaveEcosystemReserveBalancerBalance + balancerAmount,
            IERC20(balancerTokenAddress).balanceOf(aaveEcosystemReserve)
        );
        assertEq(initialBalancerTreasuryAaveBalance + aaveAmount, IERC20(aaveTokenAddress).balanceOf(balancerTreasury));
        assertEq(
            initialBalancerTreasuryBalancerBalance - balancerAmount,
            IERC20(balancerTokenAddress).balanceOf(balancerTreasury)
        );
    }

    function testSecondSwap() public {
        _executeProposal();

        vm.expectRevert(OtcEscrowApprovals.SwapAlreadyOccured.selector);
        otcEscrowApprovals.swap();
    }

    function _executeProposal() public {
        // execute proposal
        aaveGovernanceV2.execute(proposalId);

        // confirm state after
        IAaveGovernanceV2.ProposalState state = aaveGovernanceV2.getProposalState(proposalId);
        assertEq(uint256(state), uint256(IAaveGovernanceV2.ProposalState.Executed), "PROPOSAL_NOT_IN_EXPECTED_STATE");
    }

    /*******************************************************************************/
    /******************     Aave Gov Process - Create Proposal     *****************/
    /*******************************************************************************/

    function _createProposal() public {
        bytes memory emptyBytes;

        targets.push(proposalPayloadAddress);
        values.push(0);
        signatures.push("execute()");
        calldatas.push(emptyBytes);
        withDelegatecalls.push(true);

        vm.prank(aaveWhales[0]);
        aaveGovernanceV2.create(shortExecutor, targets, values, signatures, calldatas, withDelegatecalls, ipfsHash);
        proposalId = aaveGovernanceV2.getProposalsCount() - 1;
    }

    /*******************************************************************************/
    /***************     Aave Gov Process - No Updates Required      ***************/
    /*******************************************************************************/

    function _voteOnProposal() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        vm.roll(proposal.startBlock + 1);
        for (uint256 i; i < aaveWhales.length; i++) {
            vm.prank(aaveWhales[i]);
            aaveGovernanceV2.submitVote(proposalId, true);
        }
    }

    function _skipVotingPeriod() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        vm.roll(proposal.endBlock + 1);
    }

    function _queueProposal() public {
        aaveGovernanceV2.queue(proposalId);
    }

    function _skipQueuePeriod() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        vm.warp(proposal.executionTime + 1);
    }

    function testSetup() public {
        IAaveGovernanceV2.ProposalWithoutVotes memory proposal = aaveGovernanceV2.getProposalById(proposalId);
        assertEq(proposalPayloadAddress, proposal.targets[0], "TARGET_IS_NOT_PAYLOAD");

        IAaveGovernanceV2.ProposalState state = aaveGovernanceV2.getProposalState(proposalId);
        assertEq(uint256(state), uint256(IAaveGovernanceV2.ProposalState.Queued), "PROPOSAL_NOT_IN_EXPECTED_STATE");
    }
}
