## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

Hakob jan, here you go: 
Technical Task: Vault Contract with AMM or Aave Integration

Goal:
Develop a Vault smart contract where the owner manages strategy (AMM or Aave), rebalancing, and token swaps. Users can deposit and withdraw, receiving shares representing their stake.

Requirements:
Vault Core Functions:

Deposit/Withdraw: Users deposit tokens and receive shares, withdraw based on share value.
Share Calculation: Shares represent ownership of vault's total assets.
AMM Integration (e.g., Uniswap/Sushiswap) (Optional):

Owner can swap tokens on AMMs, manage slippage and price impact.
Aave Integration (Optional):

Owner can lend on Aave or borrow for leverage, maintaining healthy collateral.
Owner-Controlled Actions:

Rebalancing/Swapping: Only the vault owner can execute rebalancing, strategy switching, and token swaps.
Security & Best Practices:

Use oracles (e.g., Chainlink) for price feeds.
Upgradability.
Gas-optimized code, role-based access control.
Comprehensive tests and documentation.

Deliverables:
Solidity Vault contract
Test suite & documentation

On github, please invite @hirama to repo.