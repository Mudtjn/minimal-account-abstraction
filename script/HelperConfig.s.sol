// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ZKSYNC_CHAIN_ID = 300;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    address public constant BURNER_WALLET = 0x6E1aafc110855e553e378d57533dD90C140366a4;
    address public constant ANVIL_DEFAULT_WALLET = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public localNetworkConfig;
    mapping(uint256 => NetworkConfig) chainIdToNetworkConfig;

    constructor() {
        chainIdToNetworkConfig[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        chainIdToNetworkConfig[ZKSYNC_CHAIN_ID] = getZkSyncConfig();
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public returns (NetworkConfig memory) {
        if (chainId == LOCAL_CHAIN_ID) {
            return getAnvilEthConfig();
        } else if (chainIdToNetworkConfig[chainId].entryPoint != address(0)) {
            return chainIdToNetworkConfig[chainId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789, account: BURNER_WALLET});
    }

    function getZkSyncConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({entryPoint: address(0), account: BURNER_WALLET});
    }

    function getAnvilEthConfig() public returns (NetworkConfig memory) {
        if (localNetworkConfig.account != address(0)) return localNetworkConfig;
        // deploy mock entrypoint
        console2.log("deploying mocks");

        vm.startBroadcast(ANVIL_DEFAULT_WALLET);
        EntryPoint entrypoint = new EntryPoint();
        vm.stopBroadcast();

        localNetworkConfig = NetworkConfig({entryPoint: address(entrypoint), account: ANVIL_DEFAULT_WALLET});
        return localNetworkConfig;
    }
}
