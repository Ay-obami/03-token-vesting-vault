// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenVestingVault} from "../src/TokenVestingVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockERC20, FeeOnTransferToken, FalseReturnToken} from "./mocks/MockERC20.sol";

contract ReentrantVestingToken is MockERC20 {
    TokenVestingVault public vault;
    uint256 public scheduleId;
    bool public attackEnabled;
    bool public reentrySucceeded;

    constructor() MockERC20("Reentrant Token", "REENT") {}

    function configureAttack(TokenVestingVault vault_, uint256 scheduleId_) external {
        vault = vault_;
        scheduleId = scheduleId_;
        attackEnabled = true;
        reentrySucceeded = false;
    }

    function attackClaim() external {
        vault.claim(scheduleId);
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        if (attackEnabled && to == address(this)) {
            (bool ok,) = address(vault).call(abi.encodeCall(TokenVestingVault.claim, (scheduleId)));
            reentrySucceeded = ok;
        }
        return true;
    }
}

contract TokenVestingVaultTest is Test {
    uint256 internal constant TOTAL = 1_000 ether;
    uint64 internal constant CLIFF = 90 days;
    uint64 internal constant DURATION = 360 days;

    address internal constant BENEFICIARY = address(0xBEEF);
    address internal constant OTHER = address(0xCAFE);
    address internal constant NEW_OWNER = address(0xA11CE);

    TokenVestingVault internal vault;
    MockERC20 internal token;
    uint64 internal start;

    event VestingCreated(
        uint256 indexed scheduleId,
        address indexed token,
        address indexed beneficiary,
        uint256 totalAmount,
        uint64 start,
        uint64 cliffDuration,
        uint64 duration,
        bool revocable
    );
    event TokensClaimed(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount, uint256 totalClaimed);
    event VestingRevoked(
        uint256 indexed scheduleId,
        uint64 revokedAt,
        uint256 vestedAmount,
        uint256 returnedUnvested,
        address indexed recipient
    );

    function setUp() public {
        vm.warp(1_000_000);
        start = uint64(block.timestamp + 10 days);
        vault = new TokenVestingVault(address(this));
        token = new MockERC20("Vesting Token", "VEST");
        token.mint(address(this), 10_000 ether);
        token.approve(address(vault), type(uint256).max);
    }

    function testConstructorSetsOwner() public view {
        assertEq(vault.owner(), address(this));
        assertEq(vault.nextScheduleId(), 0);
    }

    function testConstructorRejectsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new TokenVestingVault(address(0));
    }

    function testCreateVestingStoresAndFundsSchedule() public {
        vm.expectEmit(true, true, true, true);
        emit VestingCreated(0, address(token), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);
        uint256 id = vault.createVesting(address(token), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);

        TokenVestingVault.Schedule memory s = vault.getSchedule(id);
        assertEq(id, 0);
        assertEq(s.token, address(token));
        assertEq(s.beneficiary, BENEFICIARY);
        assertEq(s.totalAmount, TOTAL);
        assertEq(s.start, start);
        assertEq(s.cliffDuration, CLIFF);
        assertEq(s.duration, DURATION);
        assertEq(s.claimed, 0);
        assertTrue(s.revocable);
        assertFalse(s.revoked);
        assertEq(s.revokedAt, 0);
        assertEq(token.balanceOf(address(vault)), TOTAL);
        assertEq(vault.nextScheduleId(), 1);
    }

    function testCreateVestingSupportsMultipleSchedules() public {
        uint256 id0 = _create(BENEFICIARY, TOTAL, true);
        uint256 id1 = _create(OTHER, 500 ether, false);
        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(token.balanceOf(address(vault)), 1_500 ether);
        assertEq(vault.getSchedule(id1).beneficiary, OTHER);
    }

    function testCreateVestingRejectsUnauthorizedCaller() public {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        vault.createVesting(address(token), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);
    }

    function testCreateVestingRejectsZeroToken() public {
        vm.expectRevert(TokenVestingVault.ZeroAddress.selector);
        vault.createVesting(address(0), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);
    }

    function testCreateVestingRejectsZeroBeneficiary() public {
        vm.expectRevert(TokenVestingVault.ZeroAddress.selector);
        vault.createVesting(address(token), address(0), TOTAL, start, CLIFF, DURATION, true);
    }

    function testCreateVestingRejectsZeroAmount() public {
        vm.expectRevert(TokenVestingVault.InvalidAmount.selector);
        vault.createVesting(address(token), BENEFICIARY, 0, start, CLIFF, DURATION, true);
    }

    function testCreateVestingRejectsZeroStart() public {
        vm.expectRevert(TokenVestingVault.InvalidStart.selector);
        vault.createVesting(address(token), BENEFICIARY, TOTAL, 0, CLIFF, DURATION, true);
    }

    function testCreateVestingRejectsZeroDuration() public {
        vm.expectRevert(TokenVestingVault.InvalidDuration.selector);
        vault.createVesting(address(token), BENEFICIARY, TOTAL, start, 0, 0, true);
    }

    function testCreateVestingRejectsCliffLongerThanDuration() public {
        vm.expectRevert(TokenVestingVault.InvalidCliff.selector);
        vault.createVesting(address(token), BENEFICIARY, TOTAL, start, DURATION + 1, DURATION, true);
    }

    function testCreateVestingRejectsFeeOnTransferFunding() public {
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        feeToken.mint(address(this), TOTAL);
        feeToken.approve(address(vault), TOTAL);

        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.FundingMismatch.selector, TOTAL, 900 ether));
        vault.createVesting(address(feeToken), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);
    }

    function testCreateVestingRejectsFalseReturnTransferFrom() public {
        FalseReturnToken falseToken = new FalseReturnToken();
        falseToken.mint(address(this), TOTAL);
        falseToken.approve(address(vault), TOTAL);
        falseToken.setFailTransferFrom(true);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        vault.createVesting(address(falseToken), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);
    }

    function testGetScheduleRejectsUnknownId() public {
        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.ScheduleNotFound.selector, 777));
        vault.getSchedule(777);
    }

    function testVestedAmountIsZeroBeforeStart() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(start - 1);
        assertEq(vault.vestedAmount(id), 0);
    }

    function testVestedAmountIsZeroAfterStartButBeforeCliff() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + CLIFF - 1);
        assertEq(vault.vestedAmount(id), 0);
    }

    function testExactCliffReleasesAccruedLinearAmount() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + CLIFF);
        assertEq(vault.vestedAmount(id), TOTAL * CLIFF / DURATION);
        assertEq(vault.claimableAmount(id), TOTAL * CLIFF / DURATION);
    }

    function testPartialVestingUsesElapsedTimeFromStart() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        uint256 elapsed = 180 days;
        vm.warp(uint256(start) + elapsed);
        assertEq(vault.vestedAmount(id), TOTAL * elapsed / DURATION);
    }

    function testFullVestingAtExactEnd() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + DURATION);
        assertEq(vault.vestedAmount(id), TOTAL);
    }

    function testFullVestingAfterEnd() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + DURATION + 365 days);
        assertEq(vault.vestedAmount(id), TOTAL);
    }

    function testClaimRejectsBeforeCliff() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + CLIFF - 1);
        vm.prank(BENEFICIARY);
        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.NothingToClaim.selector, id));
        vault.claim(id);
    }

    function testOnlyBeneficiaryCanClaim() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + 180 days);
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.NotBeneficiary.selector, OTHER, BENEFICIARY));
        vault.claim(id);
    }

    function testPartialClaimTransfersExactlyClaimableAmount() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + 180 days);
        uint256 expected = TOTAL / 2;

        vm.expectEmit(true, true, false, true);
        emit TokensClaimed(id, BENEFICIARY, expected, expected);
        vm.prank(BENEFICIARY);
        uint256 claimed = vault.claim(id);

        assertEq(claimed, expected);
        assertEq(token.balanceOf(BENEFICIARY), expected);
        assertEq(vault.getSchedule(id).claimed, expected);
        assertEq(vault.claimableAmount(id), 0);
    }

    function testRepeatedClaimWithoutMoreVestingReverts() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + 180 days);
        vm.prank(BENEFICIARY);
        vault.claim(id);

        vm.prank(BENEFICIARY);
        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.NothingToClaim.selector, id));
        vault.claim(id);
    }

    function testLaterClaimOnlyTransfersNewlyVestedTokens() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + 180 days);
        vm.prank(BENEFICIARY);
        vault.claim(id);

        vm.warp(uint256(start) + 270 days);
        uint256 additional = TOTAL * 90 days / DURATION;
        vm.prank(BENEFICIARY);
        uint256 claimed = vault.claim(id);

        assertEq(claimed, additional);
        assertEq(token.balanceOf(BENEFICIARY), TOTAL * 270 days / DURATION);
    }

    function testFullClaimCannotOverclaim() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + DURATION);
        vm.prank(BENEFICIARY);
        vault.claim(id);

        assertEq(token.balanceOf(BENEFICIARY), TOTAL);
        assertEq(token.balanceOf(address(vault)), 0);
        vm.prank(BENEFICIARY);
        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.NothingToClaim.selector, id));
        vault.claim(id);
    }

    function testClaimRevertsWhenTokenReturnsFalseAndPreservesAccounting() public {
        FalseReturnToken falseToken = new FalseReturnToken();
        falseToken.mint(address(this), TOTAL);
        falseToken.approve(address(vault), TOTAL);
        uint256 id = vault.createVesting(address(falseToken), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);
        vm.warp(uint256(start) + DURATION);
        falseToken.setFailTransfers(true);

        vm.prank(BENEFICIARY);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        vault.claim(id);

        assertEq(vault.getSchedule(id).claimed, 0);
        assertEq(falseToken.balanceOf(address(vault)), TOTAL);
    }

    function testRevokeRejectsUnauthorizedCaller() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        vault.revoke(id);
    }

    function testRevokeRejectsNonRevocableSchedule() public {
        uint256 id = _create(BENEFICIARY, TOTAL, false);
        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.NotRevocable.selector, id));
        vault.revoke(id);
    }

    function testRevokeBeforeCliffReturnsEntireAllocation() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        uint256 ownerBalanceBefore = token.balanceOf(address(this));
        vm.warp(uint256(start) + 1 days);

        vm.expectEmit(true, true, false, true);
        emit VestingRevoked(id, uint64(block.timestamp), 0, TOTAL, address(this));
        vault.revoke(id);

        TokenVestingVault.Schedule memory s = vault.getSchedule(id);
        assertTrue(s.revoked);
        assertEq(s.revokedAt, block.timestamp);
        assertEq(token.balanceOf(address(this)), ownerBalanceBefore + TOTAL);
        assertEq(token.balanceOf(address(vault)), 0);
        assertEq(vault.vestedAmount(id), 0);
    }

    function testRevokeAfterPartialVestingPreservesVestedClaim() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + 180 days);
        uint256 vested = TOTAL / 2;
        uint256 ownerBalanceBefore = token.balanceOf(address(this));

        vault.revoke(id);
        assertEq(token.balanceOf(address(this)), ownerBalanceBefore + (TOTAL - vested));
        assertEq(token.balanceOf(address(vault)), vested);
        assertEq(vault.vestedAmount(id), vested);
        assertEq(vault.claimableAmount(id), vested);

        vm.warp(block.timestamp + 500 days);
        assertEq(vault.vestedAmount(id), vested);
        vm.prank(BENEFICIARY);
        vault.claim(id);
        assertEq(token.balanceOf(BENEFICIARY), vested);
        assertEq(token.balanceOf(address(vault)), 0);
    }

    function testRevokeAfterEarlierClaimReturnsOnlyUnvestedAndPreservesNoDoubleClaim() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + 180 days);
        vm.prank(BENEFICIARY);
        vault.claim(id);

        vm.warp(uint256(start) + 270 days);
        uint256 vestedAtRevoke = TOTAL * 270 days / DURATION;
        vault.revoke(id);

        assertEq(vault.claimableAmount(id), vestedAtRevoke - TOTAL / 2);
        vm.prank(BENEFICIARY);
        vault.claim(id);
        assertEq(token.balanceOf(BENEFICIARY), vestedAtRevoke);
    }

    function testRevokeAfterFullVestingReturnsZero() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + DURATION);
        uint256 ownerBalanceBefore = token.balanceOf(address(this));
        vault.revoke(id);

        assertEq(token.balanceOf(address(this)), ownerBalanceBefore);
        assertEq(vault.vestedAmount(id), TOTAL);
        assertEq(vault.claimableAmount(id), TOTAL);
    }

    function testDuplicateRevocationReverts() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vm.warp(uint256(start) + 180 days);
        vault.revoke(id);
        vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.AlreadyRevoked.selector, id));
        vault.revoke(id);
    }

    function testRevocationTransferFailureRollsBackRevokedState() public {
        FalseReturnToken falseToken = new FalseReturnToken();
        falseToken.mint(address(this), TOTAL);
        falseToken.approve(address(vault), TOTAL);
        uint256 id = vault.createVesting(address(falseToken), BENEFICIARY, TOTAL, start, CLIFF, DURATION, true);
        vm.warp(uint256(start) + 180 days);
        falseToken.setFailTransfers(true);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        vault.revoke(id);
        TokenVestingVault.Schedule memory s = vault.getSchedule(id);
        assertFalse(s.revoked);
        assertEq(s.revokedAt, 0);
    }

    function testOwnershipTransferChangesAdministrativeAuthorityAndRevocationRecipient() public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        vault.transferOwnership(NEW_OWNER);
        assertEq(vault.owner(), NEW_OWNER);

        vm.warp(uint256(start) + 180 days);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.revoke(id);

        vm.prank(NEW_OWNER);
        vault.revoke(id);
        assertEq(token.balanceOf(NEW_OWNER), TOTAL / 2);
    }

    function testTransferOwnershipRejectsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        vault.transferOwnership(address(0));
    }

    function testAccountingConservationAcrossTwoSchedulesClaimAndRevoke() public {
        uint256 id0 = _create(BENEFICIARY, TOTAL, true);
        uint256 id1 = _create(OTHER, 500 ether, true);
        uint256 ownerAfterFunding = token.balanceOf(address(this));

        vm.warp(uint256(start) + 180 days);
        vm.prank(BENEFICIARY);
        vault.claim(id0); // 500
        vault.revoke(id1); // returns 250
        vm.prank(OTHER);
        vault.claim(id1); // 250

        assertEq(token.balanceOf(BENEFICIARY), 500 ether);
        assertEq(token.balanceOf(OTHER), 250 ether);
        assertEq(token.balanceOf(address(vault)), 500 ether);
        assertEq(token.balanceOf(address(this)), ownerAfterFunding + 250 ether);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(address(vault)) + token.balanceOf(BENEFICIARY)
                + token.balanceOf(OTHER),
            10_000 ether
        );
    }

    function testClaimBlocksTokenCallbackReentrancy() public {
        ReentrantVestingToken reentrant = new ReentrantVestingToken();
        reentrant.mint(address(this), TOTAL);
        reentrant.approve(address(vault), TOTAL);
        uint256 id = vault.createVesting(address(reentrant), address(reentrant), TOTAL, start, CLIFF, DURATION, true);
        reentrant.configureAttack(vault, id);
        vm.warp(uint256(start) + DURATION);

        reentrant.attackClaim();

        assertFalse(reentrant.reentrySucceeded());
        assertEq(reentrant.balanceOf(address(reentrant)), TOTAL);
        assertEq(vault.getSchedule(id).claimed, TOTAL);
    }

    function testFuzzVestedAmountMatchesLinearFormulaAfterCliff(uint64 elapsedSeed) public {
        uint256 id = _create(BENEFICIARY, TOTAL, true);
        uint256 elapsed = bound(uint256(elapsedSeed), CLIFF, DURATION);
        vm.warp(uint256(start) + elapsed);
        assertEq(vault.vestedAmount(id), TOTAL * elapsed / DURATION);
    }

    function testFuzzClaimNeverExceedsAllocation(uint96 amountSeed, uint64 elapsedSeed) public {
        uint256 amount = bound(uint256(amountSeed), 1, 1_000_000 ether);
        token.mint(address(this), amount);
        uint256 id = _create(BENEFICIARY, amount, true);
        uint256 elapsed = bound(uint256(elapsedSeed), CLIFF, DURATION + 365 days);
        vm.warp(uint256(start) + elapsed);

        uint256 claimable = vault.claimableAmount(id);
        if (claimable == 0) {
            vm.prank(BENEFICIARY);
            vm.expectRevert(abi.encodeWithSelector(TokenVestingVault.NothingToClaim.selector, id));
            vault.claim(id);
            assertEq(vault.getSchedule(id).claimed, 0);
        } else {
            vm.prank(BENEFICIARY);
            uint256 claimed = vault.claim(id);
            assertLe(claimed, amount);
            assertEq(vault.getSchedule(id).claimed, claimed);
        }
    }

    function _create(address beneficiary, uint256 amount, bool revocable) internal returns (uint256) {
        return vault.createVesting(address(token), beneficiary, amount, start, CLIFF, DURATION, revocable);
    }
}
