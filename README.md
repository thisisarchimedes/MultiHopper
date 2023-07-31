# Multipool Hopper [![Open in Gitpod][gitpod-badge]][gitpod] [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry]

[gitpod]: https://gitpod.io/#https://github.com/PaulRBerg/foundry-template
[gitpod-badge]: https://img.shields.io/badge/Gitpod-Open%20in%20Gitpod-FFB45B?logo=gitpod
[gha]: https://github.com/PaulRBerg/foundry-template/actions
[gha-badge]: https://github.com/PaulRBerg/foundry-template/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Context

This is the smart contract infrastructure for automated AMM pool swapping. 

User deposit base asset (we also call it “underlying asset”) like ETH, USDC, WBTC and selects “strategy”. Each strategy has a predefined list of AMM pools (across one or more AMM) and offers few services: 
* *Auto compounding:* We use LiFi for swap quota (which requires off chain API all)
* *APY optimizer:* Swapping pools based on APY
* *Guardrails:* Limits how much to deposit in each pool, and withdraw funds from pools, when they starting to be “unhealthy”*

### “Unhealthy” 
There are different definitions of “unhealthy”, depending on the pool. The project attempts to ensure the user can withdraw the base asset (user isn’t locked in a pool or left holding some synthetic asset), and the user takes relatively low slippage with withdrawing.

For example: For a strategy that optimize across all ETH / pegged ETH assets we might define “healthy” as
* Pool maintain a balance of at least 40% ETH.
* The strategy amount of deposited ETH is never more than 30% of the total amount of ETH (not the pegged asset) currently in the pool.

## Main Components

### Strategy

[MultiPoolStrategy.sol]

Both users and Admin interact primarily with strategy contracts:
* Handles deposit and withdrawal of user funds
* Handles “Monitor” “adjust” in and out pools

When a user deposits an asset (Like: ETH or USDC), strategy keeps it idle within the strategy contract. "Monitor" periodically calls “adjust” to distribute any idle fund to AMM pools. When user withdrawals, strategy takes out idle funds first and then withdraw from AMM pools (strategy always save a small amount idle to facilitate small withdrawals).

“Monitor” is a privileged role, monitoring all pools' health off-chain, and instructs the contract to adjust pool balance. “Monitor” runs an off chain logic to determine how to re-adjust pools. 

“Monitor” calls adjust with a list of pools (see "adapters" below) to adjust and how much to withdraw from each pool (keeping it idle on the strategy), and how much to add to each pool (from the idle funds kept on the strategy).

Strategy can support one of more pools. We call a strategy that supports only one pool “Single Pool Strategy”.

Strategy only supports one underlying asset (e.g.: WETH or USDC). So in order for users to deposit and withdraw ETH or USDT (as an example) we are building zappers.

### Adaptors

[*Adapter.sol]

Each AMM has its own interface. There is also variation between different types of pool implementation of the same AMM. Therefore, Strategy interacts with adapter layers that abstract and standardize the AMM.

We currently support Convex (Curve booster) and several Aura (Balancer booster) pools.

### Factory
[MultiPoolStrategyFactory.sol]

We use factory architecture. Factory is deployed once and generates Adopters and Strategy by demand. 

## High Level Architecture

<img width="6000" alt="MultiPoolDrawing" src="https://github.com/thisisarchimedes/MultiHopper/assets/98904111/030b6daa-e6dd-4b29-9b83-15dc9186772c">


# Boilerplate Instructions

## What's Inside

- [Forge](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, format, and deploy smart
  contracts
- [PRBTest](https://github.com/PaulRBerg/prb-test): modern collection of testing assertions and logging utilities
- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and cheatcodes for testing
- [Solhint](https://github.com/protofire/solhint): linter for Solidity code
- [Prettier Plugin Solidity](https://github.com/prettier-solidity/prettier-plugin-solidity): code formatter for
  non-Solidity files

## Getting Started

Click the [`Use this template`](https://github.com/PaulRBerg/foundry-template/generate) button at the top of the page to
create a new repository with this repo as the initial state.

Or, if you prefer to install the template manually:

```sh
forge init my-project --template https://github.com/PaulRBerg/foundry-template
cd my-project
pnpm install # install Solhint, Prettier, and other Node.js deps
```

If this is your first time with Foundry, check out the
[installation](https://github.com/foundry-rs/foundry#installation) instructions.

## Features

This template builds upon the frameworks and libraries mentioned above, so for details about their specific features,
please consult their respective documentation.

For example, if you're interested in exploring Foundry in more detail, you should look at the
[Foundry Book](https://book.getfoundry.sh/). In particular, you may be interested in reading the
[Writing Tests](https://book.getfoundry.sh/forge/writing-tests.html) tutorial.

### Sensible Defaults

This template comes with a set of sensible default configurations for you to use. These defaults can be found in the
following files:

```text
├── .editorconfig
├── .gitignore
├── .prettierignore
├── .prettierrc.yml
├── .solhint.json
├── foundry.toml
└── remappings.txt
```

### VSCode Integration

This template is IDE agnostic, but for the best user experience, you may want to use it in VSCode alongside Nomic
Foundation's [Solidity extension](https://marketplace.visualstudio.com/items?itemName=NomicFoundation.hardhat-solidity).

For guidance on how to integrate a Foundry project in VSCode, please refer to this
[guide](https://book.getfoundry.sh/config/vscode).

### GitHub Actions

This template comes with GitHub Actions pre-configured. Your contracts will be linted and tested on every push and pull
request made to the `main` branch.

You can edit the CI script in [.github/workflows/ci.yml](./.github/workflows/ci.yml).

## Writing Tests

To write a new test contract, you start by importing [PRBTest](https://github.com/PaulRBerg/prb-test) and inherit from
it in your test contract. PRBTest comes with a pre-instantiated [cheatcodes](https://book.getfoundry.sh/cheatcodes/)
environment accessible via the `vm` property. If you would like to view the logs in the terminal output you can add the
`-vvv` flag and use [console.log](https://book.getfoundry.sh/faq?highlight=console.log#how-do-i-use-consolelog).

This template comes with an example test contract [Foo.t.sol](./test/Foo.t.sol)

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ pnpm lint
```

### Test

Run the tests:

```sh
$ forge test
```

## Notes

1. Foundry uses [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) to manage dependencies. For
   detailed instructions on working with dependencies, please refer to the
   [guide](https://book.getfoundry.sh/projects/dependencies.html) in the book
2. You don't have to create a `.env` file, but filling in the environment variables may be useful when debugging and
   testing against a fork.

## Related Efforts

- [abigger87/femplate](https://github.com/abigger87/femplate)
- [cleanunicorn/ethereum-smartcontract-template](https://github.com/cleanunicorn/ethereum-smartcontract-template)
- [foundry-rs/forge-template](https://github.com/foundry-rs/forge-template)
- [FrankieIsLost/forge-template](https://github.com/FrankieIsLost/forge-template)

## License

This project is licensed under Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International Public License.
