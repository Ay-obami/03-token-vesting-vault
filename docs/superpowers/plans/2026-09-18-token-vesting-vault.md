# Token Vesting Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and prove a fully-funded multi-schedule ERC-20 vesting vault with cliffs, linear vesting, claims, and revocation.

**Architecture:** One import-free production Solidity file contains the ERC-20 interfaces, safe transfer library, ownership module, reentrancy guard, and `TokenVestingVault`. Tests and deployment scripts use standard forge-std imports.

**Tech Stack:** Solidity `^0.8.20`, Foundry, `forge-std` for tests/scripts only.

**Spec:** `docs/superpowers/specs/2026-09-18-token-vesting-vault-design.md`

## Global Constraints
- Production contract must contain zero imports.
- Tests must use `forge-std/Test.sol`; do not reinvent TestBase or Vm.
- Script must use `forge-std/Script.sol`.
- No TypeScript, Hardhat, frontend, private keys, or committed RPC/API secrets.
- Use custom errors, events, access control, safe ERC-20 calls, and reentrancy protection.

---

### Task 1: Specify behavior in Foundry tests
**Files:** Create `test/TokenVestingVault.t.sol`, `test/mocks/MockERC20.sol`.

- [ ] Write tests for schedule creation, exact funding, invalid inputs, and ownership restrictions.
- [ ] Write `vm.warp` tests for before-cliff, exact-cliff, partial vesting, full vesting, and repeated claims.
- [ ] Write revocation tests for before-cliff, partial, full, non-revocable, unauthorized, and duplicate revocation cases.
- [ ] Add accounting, false-return/fee-on-transfer, reentrancy, and fuzz tests.
- [ ] Run `forge test --match-contract TokenVestingVaultTest -vvv` and confirm the suite fails because production behavior is not implemented.

### Task 2: Implement the self-contained vault
**Files:** Create `src/TokenVestingVault.sol`.

- [ ] Add `IERC20`, `SafeTransferLib`, `Ownable`, and `ReentrancyGuard` inside the same file.
- [ ] Add `Schedule`, schedule storage, custom errors, and lifecycle events.
- [ ] Implement `createVesting`, `vestedAmount`, `claimableAmount`, `claim`, and `revoke` exactly as the design specifies.
- [ ] Run `forge test --match-contract TokenVestingVaultTest -vvv` and resolve production defects without weakening tests.

### Task 3: Add the Foundry deployment script
**Files:** Create `script/DeployTokenVestingVault.s.sol`.

- [ ] Implement standard `Script` deployment with a zero-argument `run()`.
- [ ] Read only the non-secret initial owner from `INITIAL_OWNER`; broadcast credentials remain runtime/CLI concerns.
- [ ] Run `forge build`.

### Task 4: Full verification and packaging
**Files:** Create `README.md`, `foundry.toml`, `.gitignore`.

- [ ] Run `forge test -vvv`.
- [ ] Confirm `src/TokenVestingVault.sol` has zero import directives.
- [ ] Confirm no Hardhat/TypeScript/frontend or committed secret material exists.
- [ ] Package the assignment as `03-token-vesting-vault.zip`.
