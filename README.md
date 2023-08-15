# Multipool Hopper [![Open in Gitpod][gitpod-badge]][gitpod] [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry]

[gitpod]: https://gitpod.io/#https://github.com/PaulRBerg/foundry-template
[gitpod-badge]: https://img.shields.io/badge/Gitpod-Open%20in%20Gitpod-FFB45B?logo=gitpod
[gha]: https://github.com/PaulRBerg/foundry-template/actions
[gha-badge]: https://github.com/PaulRBerg/foundry-template/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Context

This is the smart contract infrastructure for automated AMM pool swapping.

User deposit base asset (we also call it “underlying asset”) like ETH, USDC, WBTC and selects “strategy”. Each strategy
has a predefined list of AMM pools (across one or more AMM) and offers few services:

- _Auto compounding:_ We use LiFi for swap quota (which requires off chain API all)
- _APY optimizer:_ Swapping pools based on APY
- _Guardrails:_ Limits how much to deposit in each pool, and withdraw funds from pools, when they starting to be
  “unhealthy”\*

### “Unhealthy”

There are different definitions of “unhealthy”, depending on the pool. The project attempts to ensure the user can
withdraw the base asset (user isn’t locked in a pool or left holding some synthetic asset), and the user takes
relatively low slippage with withdrawing.

For example: For a strategy that optimize across all ETH / pegged ETH assets we might define “healthy” as

- Pool maintain a balance of at least 40% ETH.
- The strategy amount of deposited ETH is never more than 30% of the total amount of ETH (not the pegged asset)
  currently in the pool.

## Main Components

### Strategy

[MultiPoolStrategy.sol]

Both users and Admin interact primarily with strategy contracts:

- Handles deposit and withdrawal of user funds
- Handles “Monitor” “adjust” in and out pools

When a user deposits an asset (Like: ETH or USDC), strategy keeps it idle within the strategy contract. "Monitor"
periodically calls “adjust” to distribute any idle fund to AMM pools. When user withdrawals, strategy takes out idle
funds first and then withdraw from AMM pools (strategy always save a small amount idle to facilitate small withdrawals).

“Monitor” is a privileged role, monitoring all pools' health off-chain, and instructs the contract to adjust pool
balance. “Monitor” runs an off chain logic to determine how to re-adjust pools.

“Monitor” calls adjust with a list of pools (see "adapters" below) to adjust and how much to withdraw from each pool
(keeping it idle on the strategy), and how much to add to each pool (from the idle funds kept on the strategy).

Strategy can support one of more pools. We call a strategy that supports only one pool “Single Pool Strategy”.

Strategy only supports one ERC-20 as underlying asset (e.g.: WETH or USDC). So in order for users to deposit and
withdraw ETH or USDT (as an example) we are building zappers.

### Adaptors

[*Adapter.sol]

Each AMM has its own interface. There is also variation between different types of pool implementation of the same AMM.
Therefore, Strategy interacts with adapter layers that abstract and standardize the AMM.

We currently support Convex (Curve booster) and several Aura (Balancer booster) pools.

- Curve/Convex pools
- Balancer/Aura Composable Stable Pool
- Balancer/Aura Stable Pool
- Balancer/Aura Weighted Pool

### Factory

[MultiPoolStrategyFactory.sol]

We use factory architecture. Factory is deployed once and generates Adopters and Strategy by demand.

### Zapper

- ETHZapper: Support ETH deposit and withdraw with WETH strategies

## High Level Architecture

<img width="6000" alt="MultiPoolDrawing" src="https://github.com/thisisarchimedes/MultiHopper/assets/98904111/030b6daa-e6dd-4b29-9b83-15dc9186772c">

# Troubleshooting

## Python virtual enviornment

Make sure you set up a python virtual environment and install the requirements.txt file.

`pip install -r requirements.txt`

# License

This project is licensed under Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International Public
License.
