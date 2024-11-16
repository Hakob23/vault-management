// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

contract Vault is
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 private constant _BASIS_POINT_SCALE = 1e4;
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    // AMM Router (e.g., Uniswap V2)
    IUniswapV2Router02 public ammRouter;

    // Aave Lending Pool
    IPool public lendingPool;
    IPoolAddressesProvider public dataProvider;

    // Chainlink Price Feed
    AggregatorV3Interface public priceFeed;

    // Tokens managed by the vault
    address public token0; // Asset token
    address public token1; // Secondary token for swapping

    /// @notice Initializes the vault with the necessary parameters.
    /// @param asset_ The address of the ERC20 asset managed by the vault.
    /// @param ammRouter_ The address of the AMM router (e.g., Uniswap V2 router).
    /// @param lendingPool_ The address of the Aave lending pool.
    /// @param dataProvider_ The address of the Aave protocol data provider.
    /// @param priceFeed_ The address of the Chainlink price feed.
    /// @param token1_ The address of the secondary token for swaps.
    function initialize(
        address asset_,
        address ammRouter_,
        address lendingPool_,
        address dataProvider_,
        address priceFeed_,
        address token1_
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
        token1 = token1_;
    }

    // === Vault Core Functions ===

    // The deposit and withdraw functions are inherited from ERC4626Upgradeable.
    // Users can deposit tokens and receive shares, withdraw based on share value.

    // === Owner-Controlled Actions ===

    /// @notice Swaps tokens on an AMM. Only callable by the owner.
    /// @param amountIn The amount of input tokens to swap.
    /// @param amountOutMin The minimum amount of output tokens expected.
    /// @param path The swap path.
    /// @param deadline The deadline timestamp by which the swap must be completed.
    function swapTokensOnAMM(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external onlyRole(OWNER_ROLE) nonReentrant {
        require(path.length >= 2, "Vault: Invalid swap path");
        IERC20(path[0]).approve(address(ammRouter), amountIn);

        ammRouter.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );
    }

    /// @notice Deposits tokens into Aave lending pool. Only callable by the owner.
    /// @param amount The amount of tokens to deposit.
    function depositToAave(
        uint256 amount
    ) external onlyRole(OWNER_ROLE) nonReentrant {
        IERC20(asset()).approve(address(lendingPool), amount);
        lendingPool.deposit(asset(), amount, address(this), 0);
    }

    /// @notice Withdraws tokens from Aave lending pool. Only callable by the owner.
    /// @param amount The amount of tokens to withdraw.
    function withdrawFromAave(
        uint256 amount
    ) external onlyRole(OWNER_ROLE) nonReentrant {
        lendingPool.withdraw(asset(), amount, address(this));
    }

    /// @notice Borrows tokens from Aave lending pool. Only callable by the owner.
    /// @param assetToBorrow The address of the asset to borrow.
    /// @param amount The amount to borrow.
    /// @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable).
    function borrowFromAave(
        address assetToBorrow,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyRole(OWNER_ROLE) nonReentrant {
        lendingPool.borrow(
            assetToBorrow,
            amount,
            interestRateMode,
            0, // referral code
            address(this)
        );
    }

    /// @notice Repays borrowed tokens to Aave lending pool. Only callable by the owner.
    /// @param assetToRepay The address of the asset to repay.
    /// @param amount The amount to repay.
    /// @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable).
    function repayToAave(
        address assetToRepay,
        uint256 amount,
        uint256 interestRateMode
    ) external onlyRole(OWNER_ROLE) nonReentrant {
        IERC20(assetToRepay).approve(address(lendingPool), amount);
        lendingPool.repay(
            assetToRepay,
            amount,
            interestRateMode,
            address(this)
        );
    }

    /// @notice Rebalances the vault's asset allocation. Only callable by the owner.
    /// @dev This is a placeholder function for rebalancing logic.
    function rebalance() external onlyRole(OWNER_ROLE) nonReentrant {
        // TODO
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
        uint256 fee = _feeOnTotal(assets, _entryFeeBasisPoints());
        return super.previewDeposit(assets - fee);
    }

    /// @dev Preview adding an entry fee on mint. See {IERC4626-previewMint}.
    function previewMint(
        uint256 shares
    ) public view virtual override returns (uint256) {
        uint256 assets = super.previewMint(shares);
        return assets + _feeOnRaw(assets, _entryFeeBasisPoints());
    }

    /// @dev Preview adding an exit fee on withdraw. See {IERC4626-previewWithdraw}.
    function previewWithdraw(
        uint256 assets
    ) public view virtual override returns (uint256) {
        uint256 fee = _feeOnRaw(assets, _exitFeeBasisPoints());
        return super.previewWithdraw(assets + fee);
    }

    /// @dev Preview taking an exit fee on redeem. See {IERC4626-previewRedeem}.
    function previewRedeem(
        uint256 shares
    ) public view virtual override returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        return assets - _feeOnTotal(assets, _exitFeeBasisPoints());
    }

    /// @dev Send entry fee to {_entryFeeRecipient}. See {IERC4626-_deposit}.
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        uint256 fee = _feeOnTotal(assets, _entryFeeBasisPoints());
        address recipient = _entryFeeRecipient();

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
        uint256 fee = _feeOnRaw(assets, _exitFeeBasisPoints());
        address recipient = _exitFeeRecipient();

        super._withdraw(caller, receiver, owner_, assets - fee, shares);

        if (fee > 0 && recipient != address(this)) {
            IERC20(asset()).safeTransfer(recipient, fee);
        }
    }

    // === Fee Configuration ===

    function _entryFeeBasisPoints() internal view virtual returns (uint256) {
        return 100; // 1% entry fee
    }

    function _exitFeeBasisPoints() internal view virtual returns (uint256) {
        return 50; // 0.5% exit fee
    }

    function _entryFeeRecipient() internal view virtual returns (address) {
        return address(this); // Fees are collected by the vault itself
    }

    function _exitFeeRecipient() internal view virtual returns (address) {
        return address(this); // Fees are collected by the vault itself
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

    /// @dev Ensures that only allowed tokens are accepted.
    modifier onlyAllowedTokens(address token) {
        require(token == token0 || token == token1, "Vault: Token not allowed");
        _;
    }

    /// @notice Allows the owner to update the AMM router address.
    /// @param newRouter The address of the new AMM router.
    function updateAMMRouter(address newRouter) external onlyRole(OWNER_ROLE) {
        require(newRouter != address(0), "Vault: Invalid router address");
        ammRouter = IUniswapV2Router02(newRouter);
    }

    /// @notice Allows the owner to update the Aave lending pool address.
    /// @param newLendingPool The address of the new lending pool.
    function updateLendingPool(
        address newLendingPool
    ) external onlyRole(OWNER_ROLE) {
        require(
            newLendingPool != address(0),
            "Vault: Invalid lending pool address"
        );
        lendingPool = IPool(newLendingPool);
    }

    /// @notice Allows the owner to update the Chainlink price feed address.
    /// @param newPriceFeed The address of the new price feed.
    function updatePriceFeed(
        address newPriceFeed
    ) external onlyRole(OWNER_ROLE) {
        require(
            newPriceFeed != address(0),
            "Vault: Invalid price feed address"
        );
        priceFeed = AggregatorV3Interface(newPriceFeed);
    }

    /// @notice Allows the owner to update the fee recipients.
    /// @param newEntryFeeRecipient The address of the new entry fee recipient.
    /// @param newExitFeeRecipient The address of the new exit fee recipient.
    function updateFeeRecipients(
        address newEntryFeeRecipient,
        address newExitFeeRecipient
    ) external onlyRole(OWNER_ROLE) {
        // TODO
    }
}
