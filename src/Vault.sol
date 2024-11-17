// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC4626Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@uniswap/interfaces/IUniswapV2Router02.sol";

import {IPool} from "@aave-v3-core/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";

import {AggregatorV3Interface} from "@chainlink/interfaces/feeds/AggregatorV3Interface.sol";

import "./IStrategy.sol";

contract Vault is
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    // Fee Basis Points. E.g. 1% fee is 100
    uint256 private _entryFeeBasisPoints;
    uint256 private _exitFeeBasisPoints;

    // AMM Router (e.g., Uniswap V2)
    IUniswapV2Router02 public ammRouter;

    // Aave Lending Pool
    IPool public lendingPool;
    IPoolAddressesProvider public dataProvider;

    // Chainlink Price Feed
    AggregatorV3Interface public priceFeed;

    IStrategy public strategy;

    // Fee Recipinets
    address private _entryFeeRecipient;
    address private _exitFeeRecipient;

    // IERC20 Token managed by the vault
    address public token0; // Asset token

    error ZeroAddress();
    error InvalidPathLength();
    error NoSharesMinted();
    error AccessDenied();

    // Events
    event TokensSwapped(
        address indexed caller,
        uint256 amountIn,
        uint256 amountOut
    );
    event TokensDepositedToAave(address indexed caller, uint256 amount);
    event TokensWithdrawnFromAave(address indexed caller, uint256 amount);
    event TokensBorrowedFromAave(
        address indexed caller,
        address assetToBorrow,
        uint256 amount
    );
    event TokensRepaidToAave(
        address indexed caller,
        address assetToRepay,
        uint256 amount
    );
    event VaultRebalanced(address indexed caller);
    event AMMRouterUpdated(address indexed caller, address newRouter);
    event LendingPoolUpdated(address indexed caller, address newLendingPool);
    event PriceFeedUpdated(address indexed caller, address newPriceFeed);
    event FeeRecipientsUpdated(
        address indexed caller,
        address newEntryFeeRecipient,
        address newExitFeeRecipient
    );
    event FeeBasisPointsUpdated(
        address indexed caller,
        uint256 newEntryFeeBasisPoints,
        uint256 newExitFeeBasisPoints
    );

    // Health Factor variable
    uint256 private _targetHealthFactor;

    /// @notice Initializes the vault with the necessary parameters.
    /// @param asset_ The address of the ERC20 asset managed by the vault.
    /// @param ammRouter_ The address of the AMM router (e.g., Uniswap V2 router).
    /// @param lendingPool_ The address of the Aave lending pool.
    /// @param dataProvider_ The address of the Aave protocol data provider.
    /// @param priceFeed_ The address of the Chainlink price feed.
    function initialize(
        address asset_,
        address ammRouter_,
        address lendingPool_,
        address dataProvider_,
        address priceFeed_,
        address strategy_
    ) public initializer {
        __ERC4626_init(IERC20(asset_));
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);

        ammRouter = IUniswapV2Router02(ammRouter_);
        lendingPool = IPool(lendingPool_);
        dataProvider = IPoolAddressesProvider(dataProvider_);
        priceFeed = AggregatorV3Interface(priceFeed_);

        token0 = asset_;

        strategy = IStrategy(strategy_);

        _entryFeeRecipient = address(this); // Fees are collected by the vault itself
        _exitFeeRecipient = address(this); // Fees are collected by the vault itself

        _targetHealthFactor = 1e18; // Initialize health factor to 1_000

        // Grant the strategy role to the strategy contract
        _grantRole(STRATEGY_ROLE, strategy_);
    }

    modifier onlyRoles() {
        if (
            !hasRole(OWNER_ROLE, msg.sender) ||
            !hasRole(STRATEGY_ROLE, msg.sender)
        ) {
            revert AccessDenied();
        }
        _;
    }

    // === Vault Core Functions ===

    // The deposit and withdraw functions are inherited from ERC4626Upgradeable.
    // Users can deposit tokens and receive shares, withdraw based on share value.

    // === Owner-Controlled Actions ===

    /// @notice Swaps tokens on an AMM. Callable by the owner or strategy.
    /// @param amountIn The amount of input tokens to swap.
    /// @param amountOutMin The minimum amount of output tokens expected.
    /// @param path The swap path.
    /// @param deadline The deadline timestamp by which the swap must be completed.
    function swapTokensOnAMM(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external onlyRoles nonReentrant {
        if (path.length < 2) {
            revert InvalidPathLength();
        }
        IERC20(path[0]).approve(address(ammRouter), amountIn);

        ammRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );
        emit TokensSwapped(msg.sender, amountIn, amountOutMin);
    }

    /// @notice Deposits tokens into Aave lending pool. Callable by the owner or strategy.
    /// @param amount The amount of tokens to deposit.
    function depositToAave(uint256 amount) external onlyRoles nonReentrant {
        IERC20(asset()).approve(address(lendingPool), amount);
        lendingPool.deposit(asset(), amount, address(this), 0);
        emit TokensDepositedToAave(msg.sender, amount);
    }

    /// @notice Withdraws tokens from Aave lending pool. Callable by the owner or strategy.
    /// @param amount The amount of tokens to withdraw.
    function withdrawFromAave(uint256 amount) external onlyRoles nonReentrant {
        lendingPool.withdraw(asset(), amount, address(this));
        emit TokensWithdrawnFromAave(msg.sender, amount);
    }

    /// @notice Borrows tokens from Aave lending pool. Callable by the owner or strategy.
    /// @param assetToBorrow The address of the asset to borrow.
    /// @param amount The amount to borrow.
    /// @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable).
    function borrowFromAave(
        address assetToBorrow,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyRoles nonReentrant {
        lendingPool.borrow(
            assetToBorrow,
            amount,
            interestRateMode,
            0, // referral code
            address(this)
        );
        emit TokensBorrowedFromAave(msg.sender, assetToBorrow, amount);
    }

    /// @notice Repays borrowed tokens to Aave lending pool. Callable by the owner or strategy.
    /// @param assetToRepay The address of the asset to repay.
    /// @param amount The amount to repay.
    /// @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable).
    function repayToAave(
        address assetToRepay,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyRoles nonReentrant {
        IERC20(assetToRepay).approve(address(lendingPool), amount);
        lendingPool.repay(
            assetToRepay,
            amount,
            interestRateMode,
            address(this)
        );
        emit TokensRepaidToAave(msg.sender, assetToRepay, amount);
    }

    /// @notice Rebalances the vault's asset allocation. Only callable by the owner.
    /// @dev This is a placeholder function for rebalancing logic.
    function rebalance() external onlyRole(OWNER_ROLE) nonReentrant {
        // TODO
        emit VaultRebalanced(msg.sender);
    }

    /// @notice Updates the strategy contract address. Callable by the owner only.
    /// @param newStrategy The address of the new strategy contract.
    function updateStrategy(
        address newStrategy
    ) external onlyRole(OWNER_ROLE) zeroAddress(newStrategy) {
        // Revoke the old strategy role if it exists
        if (address(strategy) != address(0)) {
            _revokeRole(STRATEGY_ROLE, address(strategy));
        }

        strategy = IStrategy(newStrategy); // Update the strategy contract address
        _grantRole(STRATEGY_ROLE, newStrategy); // Grant the strategy role to the new strategy contract
    }

    // === Price Feed Functions ===

    /// @notice Gets the latest price from the Chainlink price feed.
    /// @return The latest price.
    function getLatestPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    // === Overrides for Fee Logic ===

    /// @dev Preview taking an entry fee on deposit. See {IERC4626-previewDeposit}.
    function previewDeposit(
        uint256 assets
    ) public view virtual override returns (uint256) {
        uint256 fee = _feeOnTotal(assets, entryFeeBasisPoints());
        return super.previewDeposit(assets - fee);
    }

    /// @dev Preview adding an entry fee on mint. See {IERC4626-previewMint}.
    function previewMint(
        uint256 shares
    ) public view virtual override returns (uint256) {
        uint256 assets = super.previewMint(shares);
        return assets + _feeOnRaw(assets, entryFeeBasisPoints());
    }

    /// @dev Preview adding an exit fee on withdraw. See {IERC4626-previewWithdraw}.
    function previewWithdraw(
        uint256 assets
    ) public view virtual override returns (uint256) {
        uint256 fee = _feeOnRaw(assets, exitFeeBasisPoints());
        return super.previewWithdraw(assets + fee);
    }

    /// @dev Preview taking an exit fee on redeem. See {IERC4626-previewRedeem}.
    function previewRedeem(
        uint256 shares
    ) public view virtual override returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotal(assets, exitFeeBasisPoints());
    }

    /// @dev Send entry fee to {_entryFeeRecipient}. See {IERC4626-_deposit}.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        uint256 fee = _feeOnTotal(assets, entryFeeBasisPoints());
        address recipient = entryFeeRecipient();

        super._deposit(caller, receiver, assets - fee, shares);

        if (fee > 0 && recipient != address(this)) {
            IERC20(asset()).safeTransferFrom(caller, recipient, fee);
        }
    }

    /// @dev Send exit fee to {_exitFeeRecipient}. See {IERC4626-_withdraw}.
    function _withdraw(
        address caller,
        address receiver,
        address owner_,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        uint256 fee = _feeOnRaw(assets, exitFeeBasisPoints());
        address recipient = exitFeeRecipient();

        super._withdraw(caller, receiver, owner_, assets - fee, shares);

        if (fee > 0 && recipient != address(this)) {
            IERC20(asset()).safeTransfer(recipient, fee);
        }
    }

    // === Fee Configuration ===

    function entryFeeBasisPoints() internal view virtual returns (uint256) {
        return _entryFeeBasisPoints;
    }

    function exitFeeBasisPoints() internal view virtual returns (uint256) {
        return _exitFeeBasisPoints;
    }

    function entryFeeRecipient() internal view virtual returns (address) {
        return _entryFeeRecipient;
    }

    function exitFeeRecipient() internal view virtual returns (address) {
        return _exitFeeRecipient;
    }

    // === Fee Operations ===

    /// @dev Calculates the fees that should be added to an amount `assets` that does not already include fees.
    function _feeOnRaw(
        uint256 assets,
        uint256 feeBasisPoints
    ) private pure returns (uint256) {
        return
            assets.mulDiv(
                feeBasisPoints,
                _BASIS_POINT_SCALE,
                Math.Rounding.Ceil
            );
    }

    /// @dev Calculates the fee part of an amount `assets` that already includes fees.
    function _feeOnTotal(
        uint256 assets,
        uint256 feeBasisPoints
    ) private pure returns (uint256) {
        return
            assets.mulDiv(
                feeBasisPoints,
                feeBasisPoints + _BASIS_POINT_SCALE,
                Math.Rounding.Ceil
            );
    }

    // === Security Measures ===

    modifier zeroAddress(address _address) {
        if (_address == address(0)) {
            revert ZeroAddress();
        }
        _;
    }

    /// @notice Allows the owner to update the AMM router address.
    /// @param newRouter The address of the new AMM router.
    function updateAMMRouter(
        address newRouter
    ) external onlyRole(OWNER_ROLE) zeroAddress(newRouter) {
        ammRouter = IUniswapV2Router02(newRouter);
        emit AMMRouterUpdated(msg.sender, newRouter);
    }

    /// @notice Allows the owner to update the Aave lending pool address.
    /// @param newLendingPool The address of the new lending pool.
    function updateLendingPool(
        address newLendingPool
    ) external onlyRole(OWNER_ROLE) zeroAddress(newLendingPool) {
        lendingPool = IPool(newLendingPool);
        emit LendingPoolUpdated(msg.sender, newLendingPool);
    }

    /// @notice Allows the owner to update the Chainlink price feed address.
    /// @param newPriceFeed The address of the new price feed.
    function updatePriceFeed(
        address newPriceFeed
    ) external onlyRole(OWNER_ROLE) zeroAddress(newPriceFeed) {
        priceFeed = AggregatorV3Interface(newPriceFeed);
        emit PriceFeedUpdated(msg.sender, newPriceFeed);
    }

    /// @notice Allows the owner to update the fee recipients.
    /// @param newEntryFeeRecipient The address of the new entry fee recipient.
    /// @param newExitFeeRecipient The address of the new exit fee recipient.
    function updateFeeRecipients(
        address newEntryFeeRecipient,
        address newExitFeeRecipient
    ) external onlyRole(OWNER_ROLE) {
        _entryFeeRecipient = newEntryFeeRecipient;
        _exitFeeRecipient = newExitFeeRecipient;
        emit FeeRecipientsUpdated(
            msg.sender,
            newEntryFeeRecipient,
            newExitFeeRecipient
        );
    }

    /// @notice Allows the owner to update the fee recipients.
    /// @param newEntryFeeBasisPoints The amount of the new entry fee.
    /// @param newExitFeeBasisPoints The amount of the new exit fee.
    function updateFeeBasisPoints(
        uint256 newEntryFeeBasisPoints,
        uint256 newExitFeeBasisPoints
    ) external onlyRole(OWNER_ROLE) {
        _entryFeeBasisPoints = newEntryFeeBasisPoints;
        _exitFeeBasisPoints = newExitFeeBasisPoints;
        emit FeeBasisPointsUpdated(
            msg.sender,
            newEntryFeeBasisPoints,
            newExitFeeBasisPoints
        );
    }

    /// @notice Allows the owner to update the health factor.
    /// @param newHealthFactor The new health factor value.
    function updateHealthFactor(
        uint256 newHealthFactor
    ) external onlyRole(OWNER_ROLE) {
        _targetHealthFactor = newHealthFactor;
    }

    /// @dev Converts assets to shares, factoring in the health factor.
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        // Include _targetHealthFactor in the calculation
        uint256 adjustedAssets = (assets * _targetHealthFactor) / 1e18; // Assuming _targetHealthFactor is scaled by 1e18
        return super._convertToShares(adjustedAssets, rounding);
    }

    /// @dev Converts shares to assets, factoring in the health factor.
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual override returns (uint256) {
        // Include _targetHealthFactor in the calculation
        uint256 adjustedShares = (shares * 1e18) / _targetHealthFactor; // Assuming _targetHealthFactor is scaled by 1e18
        return super._convertToAssets(adjustedShares, rounding);
    }

    /// @notice Returns the current health factor.
    /// @return The current health factor.
    function targetHealthFactor() external view returns (uint256) {
        return _targetHealthFactor;
    }

    /// @notice Calculates the real health factor.
    /// @return The calculated real health factor.
    function realHealthFactor() public view returns (uint256) {
        uint256 totalSharesMinted = totalSupply();

        // Avoid division by zero
        if (totalSharesMinted == 0) {
            revert NoSharesMinted();
        }

        // Get the latest price of the asset
        uint256 assetPrice = uint256(getLatestPrice());

        // Calculate the real health factor
        return assetPrice.mulDiv(totalAssets(), totalSharesMinted);
    }
}
