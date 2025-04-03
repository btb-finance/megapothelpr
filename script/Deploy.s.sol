// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {JackpotCashback} from "../src/megapot.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        // Read environment variables
        uint256 deployerPrivateKey = vm.envUint("private_key");
        address usdcAddress = vm.envAddress("usdc_address");
        address jackpotAddress = vm.envAddress("jackpot_address");
        address referralAddress = vm.envAddress("referral_address");
        uint256 cashbackPercentage = vm.envUint("cashback_percentage");
        
        console2.log("Deploying JackpotCashback with the following parameters:");
        console2.log("USDC Address:", usdcAddress);
        console2.log("Jackpot Address:", jackpotAddress);
        console2.log("Referral Address:", referralAddress);
        console2.log("Cashback Percentage:", cashbackPercentage);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy JackpotCashback contract
        JackpotCashback jackpotCashback = new JackpotCashback(
            jackpotAddress,
            usdcAddress,
            referralAddress,
            cashbackPercentage
        );
        
        // Log the deployed contract address
        console2.log("JackpotCashback deployed at:", address(jackpotCashback));
        
        vm.stopBroadcast();
    }
} 