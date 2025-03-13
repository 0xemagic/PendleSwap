// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {PendleSwap} from "../src/PendleSwap.sol";

contract PendleSwapTest is Test {
    PendleSwap public pendleSwap;

    function setUp() public {
        pendleSwap = new PendleSwap();
    }

    function test_PendleSwap() public view {
        console.log("PendleSwap");
    }
}
