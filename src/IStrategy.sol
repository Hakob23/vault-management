// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IStrategy {
    
    /// @notice executes certain instructions based on the current and target health factors
    function execute(uint256 currentHealthFactor, uint256 targetHealthFactor) external;
}