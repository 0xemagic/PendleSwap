// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {PendleSwap} from "../src/PendleSwap.sol";

contract PendleSwapScript is Script {
    PendleSwap public pendleSwap;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        pendleSwap = new PendleSwap();

        vm.stopBroadcast();
    }
}
