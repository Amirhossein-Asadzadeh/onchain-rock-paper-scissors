// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {RockPaperScissors} from "../src/RockPaperScissors.sol";

/// @notice Deploys RockPaperScissors to whichever network is selected.
///
/// Usage (Sepolia):
///   forge script script/Deploy.s.sol \
///     --rpc-url sepolia \
///     --broadcast \
///     --verify \
///     -vvvv
///
/// Required env vars (in .env, never committed):
///   PRIVATE_KEY         — deployer wallet private key (throwaway only)
///   SEPOLIA_RPC_URL     — HTTP RPC endpoint
///   ETHERSCAN_API_KEY   — for --verify
contract Deploy is Script {
    function run() external returns (RockPaperScissors rps) {
        // vm.envUint reads PRIVATE_KEY from the environment and converts it
        // to a uint256 that Foundry uses as the signing key.  The key itself
        // never appears in compiled bytecode or broadcast files.
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Everything between startBroadcast / stopBroadcast is signed and
        // submitted as a real transaction when --broadcast is passed.
        // Without --broadcast, forge runs a dry-run simulation only.
        vm.startBroadcast(deployerKey);
        rps = new RockPaperScissors();
        vm.stopBroadcast();

        console.log("RockPaperScissors deployed at:", address(rps));
    }
}
