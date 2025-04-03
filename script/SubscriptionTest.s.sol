// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {JackpotCashback} from "../src/megapot.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SubscriptionTestScript is Script {
    // Use the same 5 test accounts from BatchTest
    uint256 constant NUM_ACCOUNTS = 5;
    
    // Seed for deterministic account generation
    bytes32 constant PRIVATE_KEY_SEED = bytes32(uint256(1234567890));
    
    // Environment variables
    address usdcAddress;
    address jackpotCashbackAddress;
    
    function setUp() public {
        // Load addresses from environment
        usdcAddress = vm.envAddress("usdc_address");
        jackpotCashbackAddress = vm.envAddress("jackpotcashback_address");
    }

    function run() public {
        // Read deployer's private key
        uint256 deployerPrivateKey = vm.envUint("private_key");
        address deployer = vm.addr(deployerPrivateKey);
        
        JackpotCashback jackpotCashback = JackpotCashback(jackpotCashbackAddress);
        IERC20 usdc = IERC20(usdcAddress);
        
        console2.log("Starting subscription test with generated accounts");
        console2.log("Using deployer address:", deployer);
        console2.log("USDC address:", usdcAddress);
        console2.log("JackpotCashback address:", jackpotCashbackAddress);
        
        // Generate deterministic private keys and addresses
        uint256[] memory privateKeys = new uint256[](NUM_ACCOUNTS);
        address[] memory testAccounts = new address[](NUM_ACCOUNTS);
        
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Generate a deterministic private key
            privateKeys[i] = uint256(keccak256(abi.encode(PRIVATE_KEY_SEED, i)));
            testAccounts[i] = vm.addr(privateKeys[i]);
            console2.log("Generated account", i, "address:", testAccounts[i]);
            console2.log("With private key:", privateKeys[i]);
        }
        
        // Start broadcasting transactions from the deployer
        vm.startBroadcast(deployerPrivateKey);
        
        // Check USDC balances before
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 balance = usdc.balanceOf(testAccounts[i]);
            console2.log("Account", i, "initial USDC balance:", balance);
        }
        
        // Fund each account with USDC for subscriptions
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Calculate subscription parameters for this account
            uint256 ticketsPerDay = i + 1; // 1, 2, 3, 4, 5 tickets per day
            uint256 daysCount = (i + 1) * 2; // 2, 4, 6, 8, 10 days
            uint256 ticketPrice = 1e6; // Assuming 1 USDC per ticket (6 decimals)
            uint256 requiredAmount = ticketsPerDay * daysCount * ticketPrice;
            
            // Transfer the exact amount needed plus a little extra
            usdc.transfer(testAccounts[i], requiredAmount + 1e6);
            console2.log("Funded account", i, "with USDC:", requiredAmount + 1e6);
            
            // Also transfer some ETH for gas
            payable(testAccounts[i]).transfer(0.00001 ether);
            console2.log("Funded account", i, "with ETH for gas");
        }
        
        // Check USDC balances after funding
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 balance = usdc.balanceOf(testAccounts[i]);
            console2.log("Account", i, "new USDC balance:", balance);
        }
        
        vm.stopBroadcast();
        
        // For each test account, broadcast using its private key to create a subscription
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Different subscription parameters for each account
            uint256 ticketsPerDay = i + 1; // 1, 2, 3, 4, 5 tickets per day
            uint256 daysCount = (i + 1) * 2; // 2, 4, 6, 8, 10 days
            uint256 ticketPrice = 1e6; // Assuming 1 USDC per ticket (6 decimals)
            uint256 requiredAmount = ticketsPerDay * daysCount * ticketPrice;
            
            // Start broadcasting with the test account's private key
            vm.startBroadcast(privateKeys[i]);
            
            console2.log("Creating subscription from account", i, ":", testAccounts[i]);
            
            // Approve USDC spending
            usdc.approve(jackpotCashbackAddress, requiredAmount);
            console2.log("Approved USDC spending:", requiredAmount);
            
            // Create subscription with different parameters
            try jackpotCashback.createSubscription(ticketsPerDay, daysCount) {
                console2.log("Account", i, "created subscription successfully");
                console2.log("Tickets per day:", ticketsPerDay);
                console2.log("Days count:", daysCount);
            } catch (bytes memory reason) {
                console2.log("Account", i, "failed to create subscription");
                console2.logBytes(reason);
            }
            
            vm.stopBroadcast();
        }
        
        // Process the first batch of subscriptions as the deployer
        vm.startBroadcast(deployerPrivateKey);
        try jackpotCashback.processDailyBatch(0) {
            console2.log("Successfully processed batch 0");
        } catch (bytes memory reason) {
            console2.log("Failed to process batch 0");
            console2.logBytes(reason);
        }
        vm.stopBroadcast();
        
        console2.log("Subscription test completed");
    }
} 