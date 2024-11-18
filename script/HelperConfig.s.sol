// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.12;

import {Script} from "lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address asset_;
        address ammRouter_;
        address lendingPool_;
        address dataProvider_;
        address priceFeed_;
        uint256 deployer;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    function getSepoliaConfig() private view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                asset_: vm.envAddress("ASSET_ADDRESS"),
                ammRouter_: vm.envAddress("AMM_ROUTER_ADDRESS"),
                lendingPool_: vm.envAddress("LENDING_POOL_ADDRESS"),
                dataProvider_: vm.envAddress("DATA_PROVIDER_ADDRESS"),
                priceFeed_: vm.envAddress("PRICE_FEED_ADDRESS"),
                deployer: vm.envUint("PRIVATE_KEY")
            });
    }

    function getAnvilConfig() private returns (NetworkConfig memory) {
        vm.startBroadcast();
        ERC20Mock weth = new ERC20Mock();
        MockV3Aggregator wethPriceFeed = new MockV3Aggregator(8, 4_000e8);

        vm.stopBroadcast();
        return
            NetworkConfig({
                asset_: address(weth),
                ammRouter_: address(0),
                lendingPool_: address(0),
                dataProvider_: address(0),
                priceFeed_: address(wethPriceFeed),
                deployer: vm.envUint("DEFAULT_PRIVATE_KEY")
            });
    }
}
