// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {JackpotCashback} from "../src/megapot.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ProcessBatchScript is Script {
    // Environment variables
    address usdcAddress;
    address jackpotCashbackAddress;
    
    // Number of test users to create
    uint256 constant NUM_USERS = 20;
    
    // Seed for deterministic account generation
    bytes32 constant PRIVATE_KEY_SEED = bytes32(uint256(7654321));

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

        console2.log("Creating subscriptions for multiple users");
        console2.log("Using deployer:", deployer);
        console2.log("USDC address:", usdcAddress);
        console2.log("JackpotCashback address:", jackpotCashbackAddress);
        
        // Get ticket price
        uint256 ticketPrice;
        try jackpotCashback.jackpotContract().ticketPrice() returns (uint256 price) {
            ticketPrice = price;
            console2.log("Ticket price:", ticketPrice);
        } catch {
            // Default to 1 USDC if we can't get the price
            ticketPrice = 1e6; 
            console2.log("Failed to get ticket price, using default:", ticketPrice);
        }

        // Generate deterministic private keys and addresses
        uint256[] memory privateKeys = new uint256[](NUM_USERS);
        address[] memory users = new address[](NUM_USERS);

        for (uint256 i = 0; i < NUM_USERS; i++) {
            // Generate a deterministic private key
            privateKeys[i] = uint256(keccak256(abi.encode(PRIVATE_KEY_SEED, i)));
            users[i] = vm.addr(privateKeys[i]);
            console2.log("Generated user", i);
        }

        // Start broadcasting from deployer - fund the users
        vm.startBroadcast(deployerPrivateKey);
        
        // Check deployer's USDC balance
        uint256 deployerBalance = usdc.balanceOf(deployer);
        console2.log("Deployer USDC balance:", deployerBalance);

        // Fund each user with different USDC amounts and ETH
        for (uint256 i = 0; i < NUM_USERS; i++) {
            // Vary the parameters for each user
            uint256 ticketsPerDay = (i % 3) + 1; // 1-3 tickets per day
            uint256 daysCount = (i % 5) + 1; // 1-5 days
            
            // Calculate how much USDC they need
            uint256 requiredAmount = ticketsPerDay * daysCount * ticketPrice;
            // Add 10% buffer
            uint256 fundAmount = requiredAmount * 11 / 10;
            
            // Transfer USDC
            usdc.transfer(users[i], fundAmount);
            console2.log("Funded user", i);
            
            // Transfer some ETH for gas
            payable(users[i]).transfer(0.00001 ether);
        }
        
        vm.stopBroadcast();

        // Create subscriptions for each user with staggered timing
        for (uint256 i = 0; i < NUM_USERS; i++) {
            vm.startBroadcast(privateKeys[i]);
            
            // Vary the parameters for each user
            uint256 ticketsPerDay = (i % 3) + 1; // 1-3 tickets per day
            uint256 daysCount = (i % 5) + 1; // 1-5 days
            
            // Calculate required amount
            uint256 requiredAmount = ticketsPerDay * daysCount * ticketPrice;
            
            // Check user balance
            uint256 userBalance = usdc.balanceOf(users[i]);
            if (userBalance < requiredAmount) {
                console2.log("User", i, "has insufficient USDC");
                vm.stopBroadcast();
                continue;
            }
            
            // Approve USDC spending
            usdc.approve(jackpotCashbackAddress, requiredAmount);
            
            console2.log("Creating subscription for user", i);
            console2.log("  Tickets per day:", ticketsPerDay);
            console2.log("  Days count:", daysCount);
            
            try jackpotCashback.createSubscription(ticketsPerDay, daysCount) {
                console2.log("  Subscription created successfully");
            } catch (bytes memory reason) {
                console2.log("  Failed to create subscription");
                console2.logBytes(reason);
            }
            
            vm.stopBroadcast();
            
            // Simulate time difference between users creating subscriptions
            if (i < NUM_USERS - 1) {
                uint256 sleepTime = 2; // Sleep 2 seconds between users
                vm.sleep(sleepTime * 1000); // vm.sleep takes milliseconds
                console2.log("  Waiting", sleepTime, "seconds");
            }
        }
        
        // Process batch after all subscriptions are created
        vm.startBroadcast(deployerPrivateKey);
        
        // Get updated state
        uint256 currentDay = jackpotCashback.currentBatchDay();
        uint256 lastBatchTime = jackpotCashback.lastBatchTimestamp();
        uint256 currentTime = block.timestamp;
        uint256 subscriberCount = jackpotCashback.getSubscriberCount();
        uint256 totalBatches = jackpotCashback.getNumberOfBatches();
        
        console2.log("Current batch day:", currentDay);
        console2.log("Last batch timestamp:", lastBatchTime);
        console2.log("Current timestamp:", currentTime);
        console2.log("Time elapsed since last batch:", currentTime - lastBatchTime, "seconds");
        console2.log("Total subscriber count:", subscriberCount);
        console2.log("Total batches needed:", totalBatches);
        
        // Check if we can process batch 0
        if (subscriberCount > 0) {
            // Check if enough time has passed
            if (currentTime >= lastBatchTime + jackpotCashback.PROCESSING_INTERVAL()) {
                console2.log("Processing batch 0...");
                try jackpotCashback.processDailyBatch(0) {
                    console2.log("Successfully processed batch 0");
                    
                    // Check new batch day
                    currentDay = jackpotCashback.currentBatchDay();
                    console2.log("New batch day after processing:", currentDay);
                } catch (bytes memory reason) {
                    console2.log("Failed to process batch 0");
                    console2.logBytes(reason);
                }
            } else {
                console2.log("Not enough time elapsed since last batch");
                console2.log("Need to wait more seconds");
            }
        } else {
            console2.log("No subscribers to process");
        }
        
        vm.stopBroadcast();
        
        console2.log("Batch subscription test completed");
    }
} 