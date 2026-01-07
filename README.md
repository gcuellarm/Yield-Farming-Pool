# 🌾 Yield Farming Pool (Foundry)

A minimal yield farming example built with **Solidity + Foundry**.

This repository contains:

- **`YieldFarmingPool.sol`**: Multi-pool staking contract that accrues rewards over time.
- **`MockToken.sol`**: Simple ERC-20 token with owner-only mint + public burn, used for testing.
- **`YieldFarmingPool.t.sol`**: Extensive Forge test suite covering core flows, edge cases and reverts.

---

## 🧭 Quick Start

### Requirements

- Foundry (Forge)
- Git submodules initialized (`forge-std`, `openzeppelin-contracts`)

### Install / Setup

```bash
git submodule update --init --recursive
```

### Build
```bash
forge build
```

### Run tests

```bash
forge test -vvv
```

### Coverage

```bash
forge coverage
```

### Format
```bash
forge fmt
```

---
## 🏗️ Contracts

### 🌾 `YieldFarmingPool.sol`

#### High-level idea

The contract supports **multiple staking pools**. Each pool has:

- a staking token (`pool.token`)
- a reward rate (`pool.rewardRate`) expressed as **reward tokens per second**

Users stake tokens in a pool and earn rewards over time.

#### Core storage

- `rewardToken`: ERC-20 token used to pay rewards.
- `pools[poolId] => Pool`: pool configuration and accounting.
- `userInfo[poolId][user] => UserInfo`: per-user staking amounts and reward tracking.
- `activePools[]`: list of created pool IDs.

#### Pool ID generation

`createPool()` generates a unique `poolId` using:

```solidity
keccak256(abi.encodePacked(token, rewardRate, block.timestamp, block.chainid))
```

This means:

- Pool IDs are deterministic for the exact same input tuple.
- If you call it twice in the **same block timestamp** with same token and rate, it will revert with `"Pool already exists"`.

---

## 📣 Events

- `PoolCreated(poolId, token, rewardRate)`
- `Staked(poolId, user, amount)`
- `Withdrawn(poolId, user, amount)`
- `RewardClaimed(poolId, user, amount)`
- `PoolUpdated(poolId, newRewardRate)`

---

## 🧩 Public / External Functions (Detailed)

### 🧪 `constructor(address _rewardToken)`

- **Purpose**: Initializes the reward token.
- **Reverts**: `"Invalid Reward Token"` if `_rewardToken == address(0)`.

### 🏊 `createPool(address token, uint256 rewardRate) external onlyOwner returns (bytes32 poolId)`

- **Purpose**: Creates a new staking pool.
- **Reverts**:
  - `"Invalid Token"` if `token == address(0)`
  - `"Reward Rate must be positive"` if `rewardRate == 0`
  - `"Pool already exists"` if the computed `poolId` is already used
- **Side effects**:
  - Stores pool in `pools`
  - Appends poolId to `activePools`
  - Emits `PoolCreated`

### `stake(bytes32 poolId, uint256 amount) external nonReentrant`

- **Purpose**: Stake `amount` of the pool’s staking token.
- **Important**: Uses `safeTransferFrom(msg.sender, address(this), amount)`.
  - User must `approve()` the contract beforehand.
- **Reverts**:
  - `"Pool is not active"` if pool is inactive / does not exist
  - `"Amount must be positive"` if `amount == 0`
- **Reward behavior**:
  - Updates pool accounting (`_updatePool`)
  - If user already had stake, it computes pending rewards and transfers them
  - Then increases `user.amount`, updates `rewardDebt`, sets `lastClaimTime`
- **Emits**:
  - `RewardClaimed` (only when the user had previous stake AND pending > 0)
  - `Staked`

### 🧾 `withdraw(bytes32 poolId, uint256 amount) external nonReentrant`

- **Purpose**: Withdraw staked tokens from the pool.
- **Reverts**:
  - `"Pool is not active"` if pool is inactive / does not exist
  - `"Amount must be positive"` if `amount == 0`
  - `"Insufficient staked amount"` if user tries to withdraw more than staked
- **Behavior**:
  - Updates pool (`_updatePool`)
  - Transfers pending rewards (if any)
  - Decreases `user.amount`, updates `rewardDebt`
  - Transfers staking tokens back to the user
- **Emits**:
  - `RewardClaimed` (only if pending > 0)
  - `Withdrawn`

### 🎁 `claimRewards(bytes32 poolId) external nonReentrant`

- **Purpose**: Claim pending rewards without changing stake amount.
- **Reverts**:
  - `"No rewards to claim"` if `pending == 0`
- **Behavior**:
  - Updates pool
  - Computes pending rewards
  - Updates user accounting (`rewardDebt`, `lastClaimTime`)
  - Transfers rewards via `_safeRewardTransfer`
- **Emits**:
  - `RewardClaimed`

### 🛠️ `updatePoolRewardRate(bytes32 poolId, uint256 newRewardRate) external onlyOwner`

- **Purpose**: Update pool rewards emission rate.
- **Reverts**:
  - `"Pool is not active"` if pool is inactive / does not exist
- **Behavior**:
  - Calls `_updatePool` before changing `rewardRate`
  - Sets `pool.rewardRate = newRewardRate`
- **Emits**:
  - `PoolUpdated`

### ⏳ `pendingRewards(bytes32 poolId, address user) external view returns (uint256)`

- **Purpose**: View helper to compute pending rewards using current timestamp.
- **Note**: Simulates a “fresh” rewardPerToken value by taking `timeElapsed` into account.

### 🧬 `getPoolEncodedData(bytes32 poolId) external view returns (bytes memory)`

- **Purpose**: Returns an `abi.encodePacked(...)` blob containing pool fields.
- **Use case**: Demo / external tooling.

### 🧾 `getUserHash(bytes32 poolId, address user) external pure returns (bytes32)`

- **Purpose**: Deterministic, unique hash for `(poolId, user)`.
- **Hash salt**: includes the string `"YIELD_FARMING_USER"`.

### 📋 `getActivePoolsCount() external view returns (uint256)`

- **Purpose**: Returns number of created pools.

### 📦 `getActivePools() external view returns (bytes32[] memory)`

- **Purpose**: Returns the full list of active pool IDs.

### 🚨 `emergencyWithdraw(address token, uint256 amount) external onlyOwner`

- **Purpose**: Allows the owner to recover tokens from the contract.
- **Warning**: In production systems this function must be carefully governed.

---

## 🧠 Internal Functions (How the Math Works)

### 🔄 `_updatePool(bytes32 poolId)`

- Updates `rewardPerTokenStored` when `totalStaked > 0`.
- Updates `lastUpdateTime` always.

### 🧯 `_safeRewardTransfer(address to, uint256 amount)`

- Reads reward token balance of the contract.
- If `amount > rewardBalance`, it caps to `rewardBalance`.
- If final `amount == 0`, it does not transfer.

### 🧮 `_calculatePendingRewards(bytes32 poolId, address user)`

- Computes pending rewards using the pool’s stored accounting and “simulated” extra rewards since last update.

---

## 🪙 `MockToken.sol`

`MockToken` is an ERC-20 used in tests.

- `constructor(name, symbol, initialSupply)` mints an initial supply to the deployer.
- `mint(to, amount)` is **onlyOwner**.
- `burn(amount)` burns from `msg.sender`.

---

## ✅ Test Suite (Deep Dive)

All tests live in `test/YieldFarmingPool.t.sol` and are written with Forge.

### 🧰 Test helpers

- `_deployFreshPool(rewardTokenFunding)`
  - Deploys a brand new `YieldFarmingPool`, a reward token, and a staking token.
  - Optionally funds the pool with a small amount of reward tokens (useful for testing reward caps).

- `_setPoolActive(poolId, active)`
  - Uses `StdStorage` to modify `pools(poolId).isActive` directly.
  - This is required because the contract has no public “deactivate pool” method.
  - The helper also asserts the change actually happened.

### 🧪 Pool creation & ID behavior

- `testCreatePool()`
  - Validates that pools were created with expected token + reward rate.

- `testPoolIdUniqueness()`
  - Confirms pool IDs differ across time (timestamp contributes).

- `test_RevertWhen_ConstructorInvalidRewardToken()`
  - Constructor reverts on zero address.

- `test_RevertWhen_CreatePoolInvalidToken()`
  - `createPool` reverts on zero token.

- `test_RevertWhen_CreatePoolRewardRateZero()`
  - `createPool` reverts on `rewardRate == 0`.

- `test_RevertWhen_CreatePoolAlreadyExistsSameTimestamp()`
  - Creates the same pool twice at a fixed timestamp to trigger `"Pool already exists"`.

### Staking / rewards / withdraw flows

- `testStake()`
  - User stakes and state updates (user.amount, pool.totalStaked).

- `testStakeAndRewards()`
  - Stakes, warps time, checks pending rewards, then claims.

- `testWithdraw()`
  - Stakes, warps, withdraws, verifies balances and accounting.

- `testMultipleUsers()`
  - Two users stake different amounts; verifies both have rewards and bigger stake earns more.

### 🔍 View helpers

- `testPendingRewardsNoStakeReturnsZero()`
  - Ensures pending rewards is zero when user never staked.

- `testGetPoolEncodedData()`
  - Verifies encoded pool data is non-empty.

- `testGetUserHash()`
  - Confirms hash changes across users and across pools.

- `testGetActivePools()`
  - Verifies list and count of active pools.

### 🛡️ Owner-only & emergency logic

- `testUpdatePoolRewardRate()`
  - Owner updates reward rate successfully.

- `testEmergencyWithdraw()`
  - Owner recovers tokens sent to the pool.

- `test_RevertWhen_UpdatePoolRewardRateNotOwner()`
  - Non-owner cannot update reward rate.

- `test_RevertWhen_EmergencyWithdrawNotOwner()`
  - Non-owner cannot emergency withdraw.

### ❌ Revert & edge-case coverage

- `test_RevertWhen_StakeAmountZero()`
  - Staking zero must revert.

- `test_RevertWhen_WithdrawAmountZero()`
  - Withdrawing zero must revert.

- `test_RevertWhen_WithdrawMoreThanStaked()`
  - User cannot withdraw more than staked.

- `test_RevertWhen_ClaimNoRewards()`
  - Claiming with no rewards must revert.

- `test_RevertWhen_StakeNonexistentPool()`
  - Using a random poolId should revert because `isActive == false` by default.

- `test_RevertWhen_StakeInactivePool()`
  - Forces `isActive=false` via storage write, then staking must revert.

- `test_RevertWhen_WithdrawInactivePool()`
  - Stakes first, disables pool via storage, then withdraw must revert.

- `test_RevertWhen_UpdatePoolRewardRateInactivePool()`
  - Disables pool and checks owner update reverts.

### 💸 Reward transfer edge cases

- `testClaimRewardsCapsToRewardBalance()`
  - Funds the pool with a tiny reward balance and ensures claim is capped (no underflow / no revert).

- `testClaimRewardsWithZeroRewardBalanceTransfersNothing()`
  - Ensures claim does not transfer when pool has zero reward balance.

### MockToken coverage

- `testMockTokenMintAndBurn()`
  - Owner mints, then user burns.

- `test_RevertWhen_MockTokenMintNotOwner()`
  - Non-owner mint reverts.

---

## ⚠️ Notes & Limitations

- This is a learning-oriented implementation.
- There is no public pool deactivation function; tests use `StdStorage` to simulate inactive pools.
- Reward accounting is simplified and intended for demonstration.

---

## 📚 References

- Foundry Book: https://book.getfoundry.sh/
- OpenZeppelin Contracts: https://github.com/OpenZeppelin/openzeppelin-contracts
