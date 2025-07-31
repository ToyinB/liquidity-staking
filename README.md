# Liquidity Staking Contract

A Clarity smart contract for Stacks blockchain that implements liquidity provision and staking mechanics with reward distribution for decentralized finance (DeFi) applications.

## Overview

This contract allows users to provide liquidity by depositing pairs of fungible tokens (Token A and Token B) into a liquidity pool. In return, liquidity providers receive shares and earn rewards based on their stake duration and pool participation.

## Key Features

- **Dual Token Liquidity**: Support for Token A and Token B pairs
- **Staking Rewards**: Time-based reward calculation with configurable multipliers
- **Lock Period**: 24-hour minimum staking period (144 blocks)
- **Pool Management**: Administrative controls for pool parameters
- **Fee Accumulation**: Built-in 0.3% fee mechanism
- **Minimum Liquidity**: 100,000 minimum token requirement for deposits

## Contract Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MINIMUM-LIQUIDITY` | 100,000 | Minimum tokens required for liquidity provision |
| `LOCK_PERIOD` | 144 blocks | ~24 hours lock period for staked tokens |
| `REWARD_MULTIPLIER` | 100 | Base reward multiplier (1.00x) |
| `FEE_PERCENTAGE` | 30 | Pool fee percentage (0.3%) |

## Main Functions

### Public Functions

#### `add-liquidity`
```
(add-liquidity (token-a <ft-trait>) (token-b <ft-trait>) (token-a-amount uint) (token-b-amount uint))
```
- Adds liquidity to the pool by depositing Token A and Token B
- Returns liquidity shares proportional to deposit
- Enforces minimum liquidity requirements
- Prevents duplicate liquidity provision per address

#### `remove-liquidity`
```
(remove-liquidity (token-a <ft-trait>) (token-b <ft-trait>))
```
- Removes all liquidity from the pool
- Returns original tokens plus accumulated rewards
- Enforces lock period before withdrawal
- Automatically calculates and distributes rewards

#### Administrative Functions

- `set-owner`: Transfer contract ownership (with validation)
- `update-reward-multiplier`: Modify reward calculation parameters
- `toggle-pool-status`: Enable/disable pool operations

### Read-Only Functions

- `get-provider-info`: View liquidity provider details
- `get-pool-info`: View pool statistics and balances
- `calculate-liquidity-share`: Preview share calculation for deposits

## Data Structures

### Liquidity Provider Record
```
{
    token-a: uint,           // Amount of Token A deposited
    token-b: uint,           // Amount of Token B deposited
    liquidity-tokens: uint,  // Share tokens received
    start-block: uint,       // Block when liquidity was added
    last-reward-claim: uint, // Last reward calculation block
    locked-until: uint       // Block when tokens can be withdrawn
}
```

### Pool Information
```
{
    token-a-balance: uint,   // Total Token A in pool
    token-b-balance: uint,   // Total Token B in pool
    total-shares: uint,      // Total liquidity shares issued
    fee-accumulated: uint    // Accumulated pool fees
}
```

## Reward Calculation

Rewards are calculated based on:
- **Staking Duration**: Blocks since last reward claim
- **Share Proportion**: User's share of total pool liquidity
- **Reward Multiplier**: Configurable rate parameter

Formula: `(shares × blocks_staked × reward_multiplier) ÷ 10,000`

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u1 | ERR-NOT-AUTHORIZED | Caller lacks required permissions |
| u2 | ERR-INSUFFICIENT-LIQUIDITY | Pool lacks sufficient liquidity |
| u3 | ERR-ALREADY-PROVIDED | Address already has active liquidity |
| u4 | ERR-NO-LIQUIDITY | No liquidity found for address |
| u5 | ERR-MINIMUM-AMOUNT | Deposit below minimum requirement |
| u6 | ERR-LOCKED-PERIOD | Tokens still in lock period |
| u7 | ERR-INVALID-PAIR | Invalid token pair provided |
| u8 | ERR-CALCULATION-ERROR | Mathematical calculation failed |
| u9 | ERR-INVALID-OWNER | Invalid owner address |
| u10 | ERR-OWNER-VALIDATION | Owner validation failed |

## Usage Example

```clarity
;; Add liquidity to the pool
(contract-call? .liquidity-staking add-liquidity 
    .token-a 
    .token-b 
    u1000000  ;; 1M Token A
    u1000000) ;; 1M Token B

;; Wait for lock period (144 blocks)

;; Remove liquidity and claim rewards
(contract-call? .liquidity-staking remove-liquidity 
    .token-a 
    .token-b)
```

## Security Features

- **Owner Validation**: Multi-step owner transfer with liquidity requirements
- **Lock Period Enforcement**: Prevents immediate withdrawal manipulation
- **Minimum Liquidity**: Protects against dust attacks
- **Token Pair Validation**: Ensures only supported tokens are used
- **Zero Address Protection**: Prevents invalid owner assignments

## Deployment Requirements

1. Deploy Token A contract
2. Deploy Token B contract  
3. Deploy liquidity staking contract
4. Update token principal constants
5. Initialize pool with `pool-id: u1`

## Dependencies

- Fungible Token Trait (ft-trait)
- Token A contract implementation
- Token B contract implementation
- Stacks blockchain environment
