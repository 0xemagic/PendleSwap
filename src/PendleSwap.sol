// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PendleSwap is Ownable {
    uint256 public number;

    address constant pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;

    constructor() Ownable(msg.sender) {}

    function setNumber(uint256 newNumber) public onlyOwner {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
