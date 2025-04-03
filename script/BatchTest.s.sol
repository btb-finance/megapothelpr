// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {JackpotCashback} from "../src/megapot.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BatchTestScript is Script {
    // Number of test accounts to create
    uint256 constant NUM_ACCOUNTS = 5; // Reduced from 101 for quicker testing
    
    // Amount of USDC to transfer to each account
    uint256 constant USDC_AMOUNT = 1e6; // 1 USDC (assuming 6 decimals)
    
    // Amount of ETH to transfer to each account for gas
    uint256 constant ETH_AMOUNT = 0.00001 ether;
    
    // Environment variables
    address usdcAddress;
    address jackpotCashbackAddress;
    
    function setUp() public {
        // Load addresses from environment
        usdcAddress = vm.envAddress("usdc_address");
        jackpotCashbackAddress = vm.envAddress("jackpotcashback_address"); // Use the correct env var
    }

    function run() public {
        // Read deployer's private key
        uint256 deployerPrivateKey = vm.envUint("private_key");
        address deployer = vm.addr(deployerPrivateKey);
        
        JackpotCashback jackpotCashback = JackpotCashback(jackpotCashbackAddress);
        IERC20 usdc = IERC20(usdcAddress);
        
        console2.log("Starting batch test with", NUM_ACCOUNTS, "accounts");
        console2.log("Using deployer address:", deployer);
        console2.log("USDC address:", usdcAddress);
        console2.log("JackpotCashback address:", jackpotCashbackAddress);
        
        // Start broadcasting transactions from the deployer
        vm.startBroadcast(deployerPrivateKey);
        
        // Create test accounts and fund them
        address[] memory testAccounts = new address[](NUM_ACCOUNTS);
        
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            // Generate a private key based on i (this is deterministic)
            uint256 privateKey = uint256(keccak256(abi.encode(i, block.timestamp, deployer)));
            address testAccount = vm.addr(privateKey);
            testAccounts[i] = testAccount;
            
            // Transfer ETH for gas
            payable(testAccount).transfer(ETH_AMOUNT);
            
            // Transfer USDC
            usdc.transfer(testAccount, USDC_AMOUNT);
            
            // Log the test account creation
            console2.log("Created and funded test account", i, ":", testAccount);
        }
        
        vm.stopBroadcast();
        
        // For each test account, approve and buy tickets
        for (uint256 i = 0; i < NUM_ACCOUNTS; i++) {
            uint256 privateKey = uint256(keccak256(abi.encode(i, block.timestamp, deployer)));
            
            vm.startBroadcast(privateKey);
            
            // Approve USDC spending
            usdc.approve(jackpotCashbackAddress, USDC_AMOUNT);
            
            // Purchase tickets with cashback
            try jackpotCashback.purchaseTicketsWithCashback(USDC_AMOUNT) {
                console2.log("Account", i, "purchased tickets successfully");
            } catch (bytes memory reason) {
                console2.log("Account", i, "failed to purchase tickets");
                console2.logBytes(reason);
            }
            
            vm.stopBroadcast();
        }
        
        console2.log("Batch test completed");
    }
} 