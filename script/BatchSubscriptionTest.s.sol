// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {JackpotCashback} from "../src/megapot.sol";

contract BatchSubscriptionTestScript is Script {
    // Number of test accounts to create
    uint256 constant NUM_ACCOUNTS = 20;
    
    // Seed for deterministic account generation (different from the previous test)
    bytes32 constant PRIVATE_KEY_SEED = bytes32(uint256(9876543210));
    
    // Environment variables
    address usdcAddress;
    address jackpotCashbackAddress;
    
    // Struct to store account data
    struct AccountData {
        address addr;
        uint256 privateKey;
        uint256 ticketsPerDay;
        uint256 daysCount;
    }
    
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
        
        console2.log("Starting batch subscription test with 20 accounts");
        console2.log("Using deployer address:", deployer);
        console2.log("USDC address:", usdcAddress);
        console2.log("JackpotCashback address:", jackpotCashbackAddress);
        
        // Generate deterministic private keys, addresses, and subscription parameters
        AccountData[] memory accounts = new AccountData[](NUM_ACCOUNTS);
        
        // Generate accounts with varying subscription parameters
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Generate a deterministic private key
            uint256 privateKey = uint256(keccak256(abi.encode(PRIVATE_KEY_SEED, i)));
            address addr = vm.addr(privateKey);
            
            // Generate varying subscription parameters
            // Tickets per day: 1-10 (based on account index)
            // Days count: 1-30 (based on a pattern)
            uint256 ticketsPerDay = (i % 10) + 1;
            uint256 daysCount = (i % 30) + 1;
            
            // Store the account data
            accounts[i] = AccountData({
                addr: addr,
                privateKey: privateKey,
                ticketsPerDay: ticketsPerDay,
                daysCount: daysCount
            });
            
            // Log each account's details instead of every 10th account
            console2.log("Generated account", i, "address:", addr);
            console2.log("  Private key:", privateKey);
            console2.log("  Tickets per day:", ticketsPerDay);
            console2.log("  Days count:", daysCount);
        }
        
        // Start broadcasting transactions from the deployer to fund accounts
        vm.startBroadcast(deployerPrivateKey);
        
        // Fund each account with USDC for subscriptions
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Calculate required amount based on subscription parameters
            uint256 ticketPrice = 1e6; // Assuming 1 USDC per ticket (6 decimals)
            uint256 requiredAmount = accounts[i].ticketsPerDay * accounts[i].daysCount * ticketPrice;
            
            // Transfer the exact amount needed plus a little extra
            usdc.transfer(accounts[i].addr, requiredAmount + 1e6);
            
            // Also transfer some ETH for gas
            payable(accounts[i].addr).transfer(0.00001 ether);
            
            // Fix the funding log
            console2.log("Funded account", i, "with USDC and ETH");
            console2.log("  USDC amount:", requiredAmount + 1e6);
        }
        
        vm.stopBroadcast();
        
        // Create subscriptions for each account
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Calculate required amount based on subscription parameters
            uint256 ticketPrice = 1e6; // Assuming 1 USDC per ticket (6 decimals)
            uint256 requiredAmount = accounts[i].ticketsPerDay * accounts[i].daysCount * ticketPrice;
            
            // Start broadcasting with the test account's private key
            vm.startBroadcast(accounts[i].privateKey);
            
            // Approve USDC spending
            usdc.approve(jackpotCashbackAddress, requiredAmount);
            
            // Create subscription with account-specific parameters
            try jackpotCashback.createSubscription(accounts[i].ticketsPerDay, accounts[i].daysCount) {
                // Log only every 10th subscription to reduce output
                console2.log("Account", i, "created subscription successfully");
                console2.log("  Tickets per day:", accounts[i].ticketsPerDay);
                console2.log("  Days count:", accounts[i].daysCount);
            } catch (bytes memory reason) {
                console2.log("Account", i, "failed to create subscription");
                console2.logBytes(reason);
            }
            
            vm.stopBroadcast();
        }
        
        // Save all accounts to a log file for later reference
        saveAccountsToCSV(accounts);
        
        console2.log("Batch subscription test completed");
    }

    function saveAccountsToCSV(AccountData[] memory accounts) private {
        console2.log("=== ACCOUNT DETAILS ===");
        console2.log("FORMAT: index, address, private key, tickets/day, days");
        
        for (uint i = 0; i < accounts.length; i++) {
            console2.log(
                string.concat(
                    "ACCOUNT_", 
                    vm.toString(i), ": ",
                    vm.toString(accounts[i].addr), ", ",
                    vm.toString(uint256(accounts[i].privateKey)), ", ",
                    vm.toString(accounts[i].ticketsPerDay), ", ",
                    vm.toString(accounts[i].daysCount)
                )
            );
        }
        
        console2.log("=== END ACCOUNT DETAILS ===");
    }
} 