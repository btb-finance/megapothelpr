// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {JackpotCashback} from "../src/megapot.sol";

contract JackpotCashbackTest is Test {
    JackpotCashback public jackpotCashback;
    address public usdcAddress = address(0xA4253E7C13525287C56550b8708100f93E60509f);
    address public jackpotAddress = address(0x6f03c7BCaDAdBf5E6F5900DA3d56AdD8FbDac5De);
    address public referralAddress = address(0x44D4F5694Ba6A9F138F41C3cD74C8af1DE83a002);
    uint256 public cashbackPercentage = 10;

    function setUp() public {
        jackpotCashback = new JackpotCashback(jackpotAddress, usdcAddress, referralAddress, cashbackPercentage);
    }

    function test_Constructor() public {
        assertEq(address(jackpotCashback.token()), usdcAddress);
        assertEq(address(jackpotCashback.jackpotContract()), jackpotAddress);
        assertEq(jackpotCashback.referrer(), referralAddress);
        assertEq(jackpotCashback.immediatePurchaseCashbackPercentage(), cashbackPercentage);
    }
}
