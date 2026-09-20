// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TokenVestingVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error ZeroAddress();
    error InvalidAmount();
    error InvalidStart();
    error InvalidDuration();
    error InvalidCliff();
    error ScheduleNotFound(uint256 scheduleId);
    error NotBeneficiary(address caller, address beneficiary);
    error NothingToClaim(uint256 scheduleId);
    error NotRevocable(uint256 scheduleId);
    error AlreadyRevoked(uint256 scheduleId);
    error FundingMismatch(uint256 expected, uint256 received);

    struct Schedule {
        address token;
        address beneficiary;
        uint256 totalAmount;
        uint64 start;
        uint64 cliffDuration;
        uint64 duration;
        uint256 claimed;
        bool revocable;
        bool revoked;
        uint64 revokedAt;
    }

    mapping(uint256 => Schedule) private _schedules;
    uint256 public nextScheduleId;

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

    constructor(address initialOwner) Ownable(initialOwner) {}

    function createVesting(
        address token,
        address beneficiary,
        uint256 totalAmount,
        uint64 start,
        uint64 cliffDuration,
        uint64 duration,
        bool revocable
    ) external onlyOwner nonReentrant returns (uint256 scheduleId) {
        if (token == address(0) || beneficiary == address(0)) revert ZeroAddress();
        if (totalAmount == 0) revert InvalidAmount();
        if (start == 0) revert InvalidStart();
        if (duration == 0) revert InvalidDuration();
        if (cliffDuration > duration) revert InvalidCliff();

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 received = balanceAfter - balanceBefore;
        if (received != totalAmount) revert FundingMismatch(totalAmount, received);

        scheduleId = nextScheduleId++;
        _schedules[scheduleId] = Schedule({
            token: token,
            beneficiary: beneficiary,
            totalAmount: totalAmount,
            start: start,
            cliffDuration: cliffDuration,
            duration: duration,
            claimed: 0,
            revocable: revocable,
            revoked: false,
            revokedAt: 0
        });

        emit VestingCreated(scheduleId, token, beneficiary, totalAmount, start, cliffDuration, duration, revocable);
    }

    function getSchedule(uint256 scheduleId) external view returns (Schedule memory) {
        Schedule storage schedule = _schedule(scheduleId);
        return schedule;
    }

    function vestedAmount(uint256 scheduleId) public view returns (uint256) {
        Schedule storage schedule = _schedule(scheduleId);
        return _vestedAmount(schedule);
    }

    function claimableAmount(uint256 scheduleId) public view returns (uint256) {
        Schedule storage schedule = _schedule(scheduleId);
        uint256 vested = _vestedAmount(schedule);
        return _releasableAmount(vested, schedule.claimed);
    }

    function claim(uint256 scheduleId) external nonReentrant returns (uint256 amount) {
        Schedule storage schedule = _schedule(scheduleId);
        if (msg.sender != schedule.beneficiary) {
            revert NotBeneficiary(msg.sender, schedule.beneficiary);
        }

        amount = _releasableAmount(_vestedAmount(schedule), schedule.claimed);
        if (amount == 0) revert NothingToClaim(scheduleId);

        schedule.claimed += amount;

        IERC20(schedule.token).safeTransfer(schedule.beneficiary, amount);
        emit TokensClaimed(scheduleId, schedule.beneficiary, amount, schedule.claimed);
    }

    function revoke(uint256 scheduleId) external onlyOwner nonReentrant {
        Schedule storage schedule = _schedule(scheduleId);
        if (schedule.revoked) revert AlreadyRevoked(scheduleId);
        if (!schedule.revocable) revert NotRevocable(scheduleId);

        uint256 vested = _vestedAmountAt(schedule, block.timestamp);
        uint256 unvested = schedule.totalAmount - vested;

        schedule.revoked = true;
        schedule.revokedAt = uint64(block.timestamp);

        address recipient = owner();
        if (unvested != 0) {
            IERC20(schedule.token).safeTransfer(recipient, unvested);
        }

        emit VestingRevoked(scheduleId, schedule.revokedAt, vested, unvested, recipient);
    }

    function _schedule(uint256 scheduleId) internal view returns (Schedule storage schedule) {
        schedule = _schedules[scheduleId];
        if (schedule.token == address(0)) revert ScheduleNotFound(scheduleId);
    }

    function _vestedAmount(Schedule storage schedule) internal view returns (uint256) {
        uint256 effectiveTime = schedule.revoked ? schedule.revokedAt : block.timestamp;
        return _vestedAmountAt(schedule, effectiveTime);
    }

    function _vestedAmountAt(Schedule storage schedule, uint256 timestamp) internal view returns (uint256) {
        uint256 startTime = uint256(schedule.start);
        uint256 cliffTime = startTime + uint256(schedule.cliffDuration);
        uint256 endTime = startTime + uint256(schedule.duration);

        if (timestamp < cliffTime) return 0;
        if (timestamp >= endTime) return schedule.totalAmount;

        uint256 elapsed = timestamp - startTime;
        uint256 vestingDuration = uint256(schedule.duration);

        // Split the calculation to avoid overflowing totalAmount * elapsed.
        uint256 wholeUnits = schedule.totalAmount / vestingDuration;
        uint256 remainder = schedule.totalAmount % vestingDuration;
        return (wholeUnits * elapsed) + (remainder * elapsed) / vestingDuration;
    }

    function _releasableAmount(uint256 vested, uint256 claimed) private pure returns (uint256) {
        if (vested <= claimed) return 0;
        return vested - claimed;
    }
}
