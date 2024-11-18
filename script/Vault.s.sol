// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Vault} from "../src/Vault.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address asset_;
    address ammRouter_;
    address lendingPool_;
    address dataProvider_;
    address priceFeed_;
    uint256 deployer;

    function run() external returns (Vault, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!

        (
            asset_,
            ammRouter_,
            lendingPool_,
            dataProvider_,
            priceFeed_,
            deployer
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployer);
        Vault vault = new Vault();
        vault.initialize(
            asset_,
            ammRouter_,
            lendingPool_,
            dataProvider_,
            priceFeed_
        );
        vm.stopBroadcast();
        return (vault, helperConfig);
    }
}
