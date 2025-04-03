// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {JackpotCashback} from "../src/megapot.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AllTestsScript is Script {
    // Number of test accounts to create
    uint256 constant BATCH_ACCOUNTS = 101;
    uint256 constant SUBSCRIPTION_ACCOUNTS = 100;
    
    // Amount of USDC to transfer to each account
    uint256 constant BATCH_USDC_AMOUNT = 1e6; // 1 USDC (assuming 6 decimals)
    uint256 constant SUB_USDC_AMOUNT = 35e6; // 35 USDC for subscriptions
    
    // Amount of ETH to transfer to each account for gas
    uint256 constant ETH_AMOUNT = 0.00001 ether;
    
    // Subscription parameters
    uint256 constant TICKETS_PER_DAY = 5;
    uint256 constant DAYS_COUNT = 7;
    
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
        
        console2.log("=== Starting All Tests ===");
        console2.log("Using deployer address:", deployer);
        console2.log("USDC address:", usdcAddress);
        console2.log("JackpotCashback address:", jackpotCashbackAddress);
        
        // First run the batch purchase test
        runBatchPurchaseTest(deployerPrivateKey, jackpotCashback, usdc, deployer);
        
        // Then run the subscription test
        runSubscriptionTest(deployerPrivateKey, jackpotCashback, usdc, deployer);
        
        console2.log("=== All Tests Completed ===");
    }
    
    function runBatchPurchaseTest(
        uint256 deployerPrivateKey, 
        JackpotCashback jackpotCashback, 
        IERC20 usdc,
        address deployer
    ) internal {
        console2.log("\n=== BATCH PURCHASE TEST ===");
        console2.log("Creating and funding", BATCH_ACCOUNTS, "accounts");
        
        // Start broadcasting transactions from the deployer
        vm.startBroadcast(deployerPrivateKey);
        
        // Create test accounts and fund them
        address[] memory testAccounts = new address[](BATCH_ACCOUNTS);
        
        for (uint256 i = 0; i < BATCH_ACCOUNTS; i++) {
            // Generate a private key based on i (this is deterministic)
            uint256 privateKey = uint256(keccak256(abi.encode(i, block.timestamp, deployer)));
            address testAccount = vm.addr(privateKey);
            testAccounts[i] = testAccount;
            
            // Transfer ETH for gas
            payable(testAccount).transfer(ETH_AMOUNT);
            
            // Transfer USDC
            usdc.transfer(testAccount, BATCH_USDC_AMOUNT);
            
            // Log the test account creation
            if (i % 10 == 0) { // Only log every 10th account to reduce output
                console2.log("Created and funded batch test account", i, ":", testAccount);
            }
        }
        
        vm.stopBroadcast();
        
        // For each test account, approve and buy tickets
        for (uint256 i = 0; i < BATCH_ACCOUNTS; i++) {
            uint256 privateKey = uint256(keccak256(abi.encode(i, block.timestamp, deployer)));
            
            vm.startBroadcast(privateKey);
            
            // Approve USDC spending
            usdc.approve(jackpotCashbackAddress, BATCH_USDC_AMOUNT);
            
            // Purchase tickets with cashback
            try jackpotCashback.purchaseTicketsWithCashback(BATCH_USDC_AMOUNT) {
                if (i % 10 == 0) { // Only log every 10th purchase to reduce output
                    console2.log("Account", i, "purchased tickets successfully");
                }
            } catch (bytes memory reason) {
                console2.log("Account", i, "failed to purchase tickets");
                console2.logBytes(reason);
            }
            
            vm.stopBroadcast();
        }
        
        console2.log("Batch purchase test completed");
    }
    
    function runSubscriptionTest(
        uint256 deployerPrivateKey, 
        JackpotCashback jackpotCashback, 
        IERC20 usdc,
        address deployer
    ) internal {
        console2.log("\n=== SUBSCRIPTION TEST ===");
        console2.log("Creating and funding", SUBSCRIPTION_ACCOUNTS, "subscription accounts");
        
        // Start broadcasting transactions from the deployer
        vm.startBroadcast(deployerPrivateKey);
        
        // Create test accounts and fund them
        address[] memory testAccounts = new address[](SUBSCRIPTION_ACCOUNTS);
        
        for (uint256 i = 0; i < SUBSCRIPTION_ACCOUNTS; i++) {
            // Generate a private key based on i (this is deterministic but different from BatchTest)
            uint256 privateKey = uint256(keccak256(abi.encode("subscription", i, block.timestamp, deployer)));
            address testAccount = vm.addr(privateKey);
            testAccounts[i] = testAccount;
            
            // Transfer ETH for gas
            payable(testAccount).transfer(ETH_AMOUNT);
            
            // Transfer USDC
            usdc.transfer(testAccount, SUB_USDC_AMOUNT);
            
            // Log the test account creation
            if (i % 10 == 0) { // Only log every 10th account to reduce output
                console2.log("Created and funded subscription account", i, ":", testAccount);
            }
        }
        
        vm.stopBroadcast();
        
        // For each test account, create a subscription
        for (uint256 i = 0; i < SUBSCRIPTION_ACCOUNTS; i++) {
            uint256 privateKey = uint256(keccak256(abi.encode("subscription", i, block.timestamp, deployer)));
            
            vm.startBroadcast(privateKey);
            
            // Approve USDC spending
            usdc.approve(jackpotCashbackAddress, SUB_USDC_AMOUNT);
            
            // Create subscription
            try jackpotCashback.createSubscription(TICKETS_PER_DAY, DAYS_COUNT) {
                if (i % 10 == 0) { // Only log every 10th subscription to reduce output
                    console2.log("Account", i, "created subscription successfully");
                }
            } catch (bytes memory reason) {
                console2.log("Account", i, "failed to create subscription");
                console2.logBytes(reason);
            }
            
            vm.stopBroadcast();
        }
        
        // At the end, process the first batch of subscriptions
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