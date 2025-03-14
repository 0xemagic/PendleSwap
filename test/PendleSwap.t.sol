// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPMarket} from "pendle-core-v2-public/contracts/interfaces/IPMarket.sol";
import {IStandardizedYield} from "pendle-core-v2-public/contracts/interfaces/IStandardizedYield.sol";
import {IPPrincipalToken} from "pendle-core-v2-public/contracts/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "pendle-core-v2-public/contracts/interfaces/IPYieldToken.sol";
import {PendleSwap} from "../src/PendleSwap.sol";

/**
 * @title PendleSwapTest
 * @notice Foundry test suite for the PendleSwap contract
 */
contract PendleSwapTest is Test {
    PendleSwap public pendleSwap;

    address public Bob = 0xe2fF3c4a7b87df9a6Acabf3a848083198080a763;
    address public constant USDe = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant MARKET = 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25;
    address public constant SY = 0x4dB99b79361F98865230f5702de024C69f629fEC;
    address public constant PT = 0x8A47b431A7D947c6a3ED6E42d501803615a97EAa;
    address public constant YT = 0x4A8036EFA1307F1cA82d932C0895faa18dB0c9eE;
    address public constant LP = 0xB451A36c8B6b2EAc77AD0737BA732818143A0E25;
    uint256 public constant DEPOSIT_AMOUNT = 1_000e18;

    mapping(PendleSwap.TokenType => address) public tokenAddresses;

    /**
     * @notice Set up the test environment
     */
    function setUp() public {
        pendleSwap = new PendleSwap();

        // Register supported assets
        pendleSwap.setSupportedMarket(USDe, MARKET);

        // Fund test contract with tokens
        deal(USDe, address(this), 10000000 * 10 ** 18); // 1M USDC
        deal(SY, address(this), 10000000 * 10 ** 18);
        deal(PT, address(this), 10000000 * 10 ** 18);
        deal(YT, address(this), 10000000 * 10 ** 18);
        deal(LP, address(this), 10000000 * 10 ** 18);

        // Approve PendleSwap to spend tokens
        IERC20(USDe).approve(address(pendleSwap), type(uint256).max);
        IERC20(SY).approve(address(pendleSwap), type(uint256).max);
        IERC20(PT).approve(address(pendleSwap), type(uint256).max);
        IERC20(YT).approve(address(pendleSwap), type(uint256).max);
        IERC20(LP).approve(address(pendleSwap), type(uint256).max);

        // Map token types to addresses
        tokenAddresses[PendleSwap.TokenType.UNDERLYING] = USDe;
        tokenAddresses[PendleSwap.TokenType.SY] = SY;
        tokenAddresses[PendleSwap.TokenType.PT] = PT;
        tokenAddresses[PendleSwap.TokenType.YT] = YT;
        tokenAddresses[PendleSwap.TokenType.LP] = LP;
    }

    /**
     * @notice Test setting a supported market
     */
    function test_setSupportedMarket() public {
        vm.expectRevert(PendleSwap.UnsupportedAsset.selector);
        pendleSwap.setSupportedMarket(address(0), MARKET);

        assertEq(pendleSwap.supportedMarkets(USDe), MARKET);
        assertEq(pendleSwap.supportedMarkets(SY), MARKET);
        assertEq(pendleSwap.supportedMarkets(PT), MARKET);
        assertEq(pendleSwap.supportedMarkets(YT), MARKET);
        assertEq(pendleSwap.supportedMarkets(LP), MARKET);

        vm.prank(Bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                Bob
            )
        );
        pendleSwap.setSupportedMarket(address(USDe), MARKET);
    }

    /**
     * @notice Test deposit functionality
     */
    function test_Deposit() public {
        uint256 beforeBalance = IERC20(USDe).balanceOf(address(this));
        pendleSwap.deposit(USDe, DEPOSIT_AMOUNT);
        uint256 afterBalance = IERC20(USDe).balanceOf(address(this));
        uint256 balance = pendleSwap.userBalances(address(this), USDe);
        assertEq(afterBalance, beforeBalance - DEPOSIT_AMOUNT);
        assertEq(balance, DEPOSIT_AMOUNT);

        vm.expectRevert(PendleSwap.InvalidDepositAmount.selector);
        pendleSwap.deposit(USDe, 0);

        vm.expectRevert(PendleSwap.UnsupportedMarket.selector);
        pendleSwap.deposit(address(0), DEPOSIT_AMOUNT);
    }

    /**
     * @notice Test withdrawal functionality
     */
    function testFuzz_Withdraw(uint8 tokenType) public {
        address ioToken = tokenAddresses[PendleSwap.TokenType(tokenType % 5)];
        uint256 beforeBalance = IERC20(ioToken).balanceOf(address(this));
        pendleSwap.deposit(ioToken, DEPOSIT_AMOUNT);
        pendleSwap.withdraw(ioToken);
        uint256 afterBalance = IERC20(ioToken).balanceOf(address(this));
        uint256 balance = pendleSwap.userBalances(address(this), ioToken);
        assertEq(afterBalance, beforeBalance);
        assertEq(balance, 0);

        vm.expectRevert(PendleSwap.InsufficientBalance.selector);
        pendleSwap.withdraw(ioToken);

        vm.expectRevert(PendleSwap.UnsupportedAsset.selector);
        pendleSwap.withdraw(address(0));

        vm.expectRevert(PendleSwap.UnsupportedMarket.selector);
        pendleSwap.withdraw(Bob);
    }

    /**
     * @notice Test fuzzing conversion between asset types
     */
    function testFuzz_Convert(uint8 from, uint8 to) public {
        PendleSwap.TokenType fromTokenType = PendleSwap.TokenType(from % 5);
        PendleSwap.TokenType toTokenType = PendleSwap.TokenType(to % 5);
        vm.assume(fromTokenType != toTokenType);
        vm.assume(fromTokenType <= PendleSwap.TokenType.LP);
        vm.assume(toTokenType <= PendleSwap.TokenType.LP);

        pendleSwap.deposit(tokenAddresses[fromTokenType], DEPOSIT_AMOUNT);
        pendleSwap.convert(tokenAddresses[fromTokenType], toTokenType);
        assertEq(
            pendleSwap.userBalances(
                address(this),
                tokenAddresses[fromTokenType]
            ),
            0
        );
        assertGt(
            pendleSwap.userBalances(address(this), tokenAddresses[toTokenType]),
            0
        );

        vm.expectRevert(PendleSwap.UnsupportedAsset.selector);
        pendleSwap.convert(address(0), toTokenType);

        vm.expectRevert(PendleSwap.UnsupportedMarket.selector);
        pendleSwap.convert(Bob, toTokenType);
    }

    /**
     * @notice Test fuzzing swap functionality
     */
    function testFuzz_Swap(uint8 from, uint8 to) public {
        PendleSwap.TokenType fromTokenType = PendleSwap.TokenType(from % 5);
        PendleSwap.TokenType toTokenType = PendleSwap.TokenType(to % 5);
        vm.assume(fromTokenType != toTokenType);

        pendleSwap.swap(
            tokenAddresses[fromTokenType],
            toTokenType,
            DEPOSIT_AMOUNT
        );
        assertGt(
            IERC20(tokenAddresses[toTokenType]).balanceOf(address(this)),
            0
        );
    }
}
