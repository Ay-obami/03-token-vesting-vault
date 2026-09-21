# Token Vesting Vault Design

## Goal
Build a self-contained Solidity `^0.8.20` vesting vault that manages multiple fully-funded ERC-20 vesting schedules by ID for employees, investors, and grants.

## Project conventions
- `src/TokenVestingVault.sol` is one self-contained production file with zero imports.
- Foundry tests use standard `forge-std/Test.sol` and separate test mocks.
- Foundry deployment script uses standard `forge-std/Script.sol`.
- No TypeScript, Hardhat, frontend, private keys, or committed RPC/API secrets.
- Production code uses custom errors, events, owner access control, safe token transfers, and reentrancy protection.

## Schedule model
Each schedule stores token, beneficiary, total amount, start timestamp, cliff duration, vesting duration, claimed amount, revocability, revocation state, and revocation timestamp.

Schedules are fully funded at creation. The vault measures its token balance before and after `transferFrom` and rejects any token that delivers fewer tokens than the declared allocation.

## Vesting math
- Before `start + cliffDuration`, vested amount is zero.
- At and after the cliff, vesting is linear from `start` through `start + duration`.
- At and after `start + duration`, the full allocation is vested.
- If revoked, vesting is permanently evaluated at `revokedAt` rather than the current time.

This means a cliff delays release but does not restart the linear clock: at the cliff boundary the beneficiary receives the portion accrued since `start`.

## Claims
Only the schedule beneficiary may call `claim(scheduleId)`. A claim transfers the entire currently vested-but-unclaimed amount and increments `claimed` before the token transfer. A claim with zero available amount reverts.

## Revocation
Only the owner may revoke a schedule, and only when `revocable == true` and it has not already been revoked. Revocation freezes vesting at the current timestamp, preserves all vested-but-unclaimed tokens for the beneficiary, and returns exactly the unvested amount to the current owner. Fully vested schedules may still be revoked; in that case the returned amount is zero.

## Validation
Creation rejects zero token or beneficiary addresses, zero allocations, zero start timestamps, zero durations, and cliffs greater than the total duration. Schedule IDs must exist for all schedule-specific operations.

## Security
All functions that perform ERC-20 transfers are non-reentrant. Token calls use a safe-transfer library that accepts standard no-return tokens but rejects explicit `false` return values or failed calls. State is updated before external transfers on claims and revocations.

## Events
- `VestingCreated`
- `TokensClaimed`
- `VestingRevoked`
- `OwnershipTransferred`

## Foundry proof
Tests cover creation and funding, invalid schedules, pre-cliff behavior, exact cliff boundary, partial and full vesting, repeated claims, cumulative claims, unauthorized claims and revocations, non-revocable schedules, revocation before the cliff, partial-vesting revocation, full-vesting revocation, duplicate revocation, fee-on-transfer/false-return tokens, conservation accounting, timing/allocation fuzzing, and reentrancy attempts.
