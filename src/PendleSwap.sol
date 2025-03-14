// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPAllActionV3} from "pendle-core-v2-public/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket} from "pendle-core-v2-public/contracts/interfaces/IPMarket.sol";
import {IStandardizedYield} from "pendle-core-v2-public/contracts/interfaces/IStandardizedYield.sol";
import {IPPrincipalToken} from "pendle-core-v2-public/contracts/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "pendle-core-v2-public/contracts/interfaces/IPYieldToken.sol";
import {IPMarketFactoryV3} from "pendle-core-v2-public/contracts/interfaces/IPMarketFactoryV3.sol";
import "pendle-core-v2-public/contracts/interfaces/IPAllActionTypeV3.sol";

/**
 * @title PendleSwap
 * @notice A contract for swapping assets within the Pendle ecosystem.
 * @dev Provides functions for depositing, withdrawing, converting and swapping assets using the Pendle protocol.
 */
contract PendleSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Pendle router instance
    IPAllActionV3 pendleRouter =
        IPAllActionV3(0x888888888889758F76e7103c6CbF23ABbF58F946);

    /// @notice Enum representing different types of supported tokens
    enum TokenType {
        UNDERLYING,
        SY,
        PT,
        YT,
        LP
    }

    /// @notice Errors
    error UnsupportedMarket();
    error UnsupportedAsset();
    error InvalidDepositAmount();
    error InsufficientBalance();
    error InvalidSwap();


    /// @notice User balances mapping: user -> token -> balance
    mapping(address => mapping(address => uint256)) public userBalances;
    
    /// @notice Mapping to track supported asset types
    mapping(address => TokenType) public supportedAssetTypes;
    
    /// @notice Mapping to track supported markets
    mapping(address => address) public supportedMarkets;
    
    /// @notice Mapping to track market token relationships
    mapping(address => mapping(TokenType => address)) public marketToken;

    /**
     * @notice Constructor
     */
    constructor() Ownable(msg.sender) {}

    event Deposited(address indexed user, TokenType tokenType, uint256 amount);
    event Withdrawn(address indexed user, TokenType tokenType, uint256 amount);
    event Converted(address indexed user, TokenType fromTokenType, TokenType toTokenType, uint256 amount, uint256 outputAmount);
    event Swapped(address indexed user, TokenType fromTokenType, TokenType toTokenType);

    /**
     * @notice Sets a supported market for an asset
     * @param asset The asset to associate with a market
     * @param market The corresponding market address
     */
    function setSupportedMarket(
        address asset,
        address market
    ) external onlyOwner {
        require(asset != address(0), UnsupportedAsset());
        (
            IStandardizedYield _SY,
            IPPrincipalToken _PT,
            IPYieldToken _YT
        ) = IPMarket(market).readTokens();
        supportedMarkets[address(_SY)] = market;
        supportedAssetTypes[address(_SY)] = TokenType.SY;
        supportedMarkets[address(_PT)] = market;
        supportedAssetTypes[address(_PT)] = TokenType.PT;
        supportedMarkets[address(_YT)] = market;
        supportedAssetTypes[address(_YT)] = TokenType.YT;
        supportedMarkets[market] = market;
        supportedAssetTypes[market] = TokenType.LP;
        supportedMarkets[asset] = market;
        supportedAssetTypes[asset] = TokenType.UNDERLYING;
        marketToken[market][TokenType.UNDERLYING] = asset;
        marketToken[market][TokenType.SY] = address(_SY);
        marketToken[market][TokenType.PT] = address(_PT);
        marketToken[market][TokenType.YT] = address(_YT);
        marketToken[market][TokenType.LP] = market;
    }

    /**
     * @notice Deposits a supported asset
     * @param inputToken The asset to deposit
     * @param amount The amount to deposit
     */
    function deposit(address inputToken, uint256 amount) public nonReentrant {
        require(
            supportedMarkets[inputToken] != address(0),
            UnsupportedMarket()
        );
        require(amount > 0, InvalidDepositAmount());
        require(
            IERC20(inputToken).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        userBalances[msg.sender][inputToken] += amount;
        emit Deposited(msg.sender, supportedAssetTypes[inputToken], amount);
    }

    /**
     * @notice Withdraws a user's balance for a specific asset
     * @param withdrawToken The asset to withdraw
     */
    function withdraw(address withdrawToken) public nonReentrant {
        require(withdrawToken != address(0), UnsupportedAsset());
        require(
            supportedMarkets[withdrawToken] != address(0),
            UnsupportedMarket()
        );
        require(
            userBalances[msg.sender][withdrawToken] > 0,
            InsufficientBalance()
        );
        require(
            IERC20(withdrawToken).transfer(
                msg.sender,
                userBalances[msg.sender][withdrawToken]
            ),
            "Transfer failed"
        );

        userBalances[msg.sender][withdrawToken] = 0;
        emit Withdrawn(msg.sender, supportedAssetTypes[withdrawToken], userBalances[msg.sender][withdrawToken]);
    }

    /**
     * @notice Converts a user's balance from one asset type to another within the Pendle ecosystem
     * @param inputToken The asset to convert from
     * @param toAssetType The target asset type
     */
    function convert(address inputToken, TokenType toAssetType) public {
        TokenType fromTokenType = supportedAssetTypes[inputToken];
        address market = supportedMarkets[inputToken];
        uint256 syAmount;
        uint256 outputAmount;
        require(inputToken != address(0), UnsupportedAsset());
        require(market != address(0), UnsupportedMarket());
        require(
            userBalances[msg.sender][inputToken] > 0,
            InsufficientBalance()
        );
        //Approve tokens to router
        IERC20(inputToken).forceApprove(
            address(pendleRouter),
            userBalances[msg.sender][inputToken]
        );
        //Convert from tokens to SY
        if (fromTokenType == TokenType.UNDERLYING) {
            syAmount = pendleRouter.mintSyFromToken(
                address(this),
                marketToken[market][TokenType.SY],
                0,
                createTokenInputSimple(
                    inputToken,
                    userBalances[msg.sender][inputToken]
                )
            );
        } else if (fromTokenType == TokenType.LP) {
            (syAmount, ) = pendleRouter.removeLiquiditySingleSy(
                address(this),
                market,
                userBalances[msg.sender][inputToken],
                0,
                createEmptyLimitOrderData()
            );
        } else if (fromTokenType == TokenType.SY) {
            syAmount = userBalances[msg.sender][inputToken];
        } else if (fromTokenType == TokenType.PT) {
            (syAmount, ) = pendleRouter.swapExactPtForSy(
                address(this),
                supportedMarkets[inputToken],
                userBalances[msg.sender][inputToken],
                0,
                createEmptyLimitOrderData()
            );
        } else if (fromTokenType == TokenType.YT) {
            (syAmount, ) = pendleRouter.swapExactYtForSy(
                address(this),
                supportedMarkets[inputToken],
                userBalances[msg.sender][inputToken],
                0,
                createEmptyLimitOrderData()
            );
        }
        //Approve SY to router
        IERC20( marketToken[market][TokenType.SY]).forceApprove(
            address(pendleRouter),
            syAmount
        );
        //Convert from SY to destination tokens
        if (toAssetType == TokenType.UNDERLYING) {
            (, address assetAddress, ) = IStandardizedYield(marketToken[market][TokenType.SY]).assetInfo();
            outputAmount = pendleRouter.redeemSyToToken(
                address(this),
                marketToken[market][TokenType.SY],
                syAmount,
                createTokenOutputSimple(assetAddress, 0)
            );
            userBalances[msg.sender][assetAddress] += outputAmount;
        } else if (toAssetType == TokenType.SY) {
            userBalances[msg.sender][marketToken[market][TokenType.SY]] += syAmount;
        } else if (toAssetType == TokenType.PT) {
            (outputAmount, ) = pendleRouter.swapExactSyForPt(
                address(this),
                supportedMarkets[inputToken],
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][marketToken[market][TokenType.PT]] += outputAmount;
        } else if (toAssetType == TokenType.YT) {
            (outputAmount, ) = pendleRouter.swapExactSyForYt(
                address(this),
                supportedMarkets[inputToken],
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][marketToken[market][TokenType.YT]] += outputAmount;
        } else if (toAssetType == TokenType.LP) {
            (outputAmount, ) = pendleRouter.addLiquiditySingleSy(
                address(this),
                market,
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][market] += outputAmount;
        }
        userBalances[msg.sender][inputToken] = 0;
        emit Converted(msg.sender, fromTokenType, toAssetType, userBalances[msg.sender][inputToken], outputAmount);
    }


    /**
     * @notice Swaps an asset into another type using Pendle market
     * @param inputToken The asset to swap from
     * @param toAssetType The target asset type
     * @param amount The amount to swap
     */
    function swap(
        address inputToken,
        TokenType toAssetType,
        uint256 amount
    ) public {
        deposit(inputToken, amount);
        convert(inputToken, toAssetType);
        withdraw(marketToken[supportedMarkets[inputToken]][toAssetType]);
        emit Swapped(msg.sender, supportedAssetTypes[inputToken], toAssetType);
    }
}
