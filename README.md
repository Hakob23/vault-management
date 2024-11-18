

# Vault Smart Contract Documentation

## Overview
The Vault contract is an upgradeable ERC4626-compliant vault that integrates with AMMs (like Uniswap) and lending protocols (like Aave). It features role-based access control, fee management, and price feed integration.

## Key Features
- ERC4626 compliant vault functionality
- AMM integration for token swaps
- Aave integration for lending/borrowing
- Chainlink price feed integration
- Fee management system
- Role-based access control
- Upgradeable design

## Core Roles
- `OWNER_ROLE`: Can perform administrative actions
- `STRATEGY_ROLE`: Can execute strategy-related functions
- `DEFAULT_ADMIN_ROLE`: Can manage roles

## Main Functions

### Initialization
```solidity
function initialize(
    address asset_,
    address ammRouter_,
    address lendingPool_,
    address dataProvider_,
    address priceFeed_,
    address strategy_
) public initializer
```

### Core Vault Operations
- `deposit(uint256 assets, address receiver)`: Deposit assets and receive shares
- `withdraw(uint256 assets, address receiver, address owner)`: Withdraw assets by burning shares
- `mint(uint256 shares, address receiver)`: Mint exact shares by depositing assets
- `redeem(uint256 shares, address receiver, address owner)`: Redeem shares for assets

### AMM Operations
```solidity
function swapTokensOnAMM(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    uint256 deadline
) external
```

### Aave Operations
```solidity
function depositToAave(uint256 amount) external
function withdrawFromAave(uint256 amount) external
function borrowFromAave(address assetToBorrow, uint256 amount, uint256 interestRateMode) external
function repayToAave(address assetToRepay, uint256 amount, uint256 interestRateMode) external
```

### Fee Management
```solidity
function updateFeeBasisPoints(uint256 newEntryFeeBasisPoints, uint256 newExitFeeBasisPoints) external
function updateFeeRecipients(address newEntryFeeRecipient, address newExitFeeRecipient) external
```
