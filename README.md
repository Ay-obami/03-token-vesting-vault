# 03 · Token Vesting Vault

A Foundry project for creating and managing fully funded ERC-20 vesting schedules.
It uses Solidity `^0.8.20` and OpenZeppelin Contracts v5.3.0.

## Project structure

- `src/TokenVestingVault.sol` contains schedule creation, vesting calculations,
  claims, and revocation.
- `test/TokenVestingVault.t.sol` contains the Foundry test suite.
- `test/mocks/MockERC20.sol` contains the test tokens.
- `script/DeployTokenVestingVault.s.sol` contains the deployment script.

## Vesting rules

Vesting accrues linearly from `start`, but no tokens can be claimed before the
cliff. At the cliff, the beneficiary can claim everything accrued since the
start time. The full allocation is vested at `start + duration`.

Revocation freezes vesting at the revocation time. Unvested tokens return to
the current owner, while vested and unclaimed tokens remain available to the
beneficiary.

## Install dependencies

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.3.0 --no-git
forge install foundry-rs/forge-std --no-git
```

## Test

```bash
forge test -vvv
```

## Deploy

Set the initial owner and provide the RPC URL and signing options at runtime:

```bash
export INITIAL_OWNER=0xYourOwnerAddress
forge script script/DeployTokenVestingVault.s.sol:DeployTokenVestingVault \
    --rpc-url "$RPC_URL" \
    --broadcast
```

Keep RPC URLs and signing credentials outside the repository.
