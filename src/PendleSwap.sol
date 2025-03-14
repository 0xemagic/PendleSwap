// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console2} from "forge-std/Test.sol";

import {IPAllActionV3} from "pendle-core-v2-public/contracts/interfaces/IPAllActionV3.sol";
import {IPMarket} from "pendle-core-v2-public/contracts/interfaces/IPMarket.sol";
import {IStandardizedYield} from "pendle-core-v2-public/contracts/interfaces/IStandardizedYield.sol";
import {IPPrincipalToken} from "pendle-core-v2-public/contracts/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "pendle-core-v2-public/contracts/interfaces/IPYieldToken.sol";
import {IPMarketFactoryV3} from "pendle-core-v2-public/contracts/interfaces/IPMarketFactoryV3.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "pendle-core-v2-public/contracts/interfaces/IPAllActionTypeV3.sol";


contract PendleSwap is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IPAllActionV3 pendleRouter =
        IPAllActionV3(0x888888888889758F76e7103c6CbF23ABbF58F946);
    IPMarketFactoryV3 pendleMarketFactoryV3 =
        IPMarketFactoryV3(0x1A6fCc85557BC4fB7B534ed835a03EF056552D52);

    /// @notice Supported assets in
    enum TokenType {
        UNDERLYING,
        SY,
        PT,
        YT,
        LP
    }
    error UnsupportedMarket();
    error UnsupportedAsset();
    error InvalidDepositAmount();
    error InsufficientBalance();
    error InvalidSwap();

    constructor() Ownable(msg.sender) {}

    /// @notice User balances
    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => TokenType) public supportedAssetTypes;
    mapping(address => address) public supportedMarkets;
    mapping(address => mapping(TokenType => address)) public marketToken;

    event Deposited(address indexed user, address assetType, uint256 amount);

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

    /// @notice Deposits a supported asset
    /// @param inputToken The asset to deposit
    /// @param amount The amount to deposit
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
        emit Deposited(msg.sender, inputToken, amount);
    }

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
        // emit Withdrawn(msg.sender, withdrawToken, userBalances[msg.sender][withdrawToken]);
    }

    function convert(address inputToken, TokenType toAssetType) public {
        TokenType fromTokenType = supportedAssetTypes[inputToken];
        address market = supportedMarkets[inputToken];
        uint256 syAmount;
        require(inputToken != address(0), UnsupportedAsset());
        require(market != address(0), UnsupportedMarket());
        require(
            userBalances[msg.sender][inputToken] > 0,
            InsufficientBalance()
        );
        IERC20(inputToken).forceApprove(
            address(pendleRouter),
            userBalances[msg.sender][inputToken]
        );
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
        IERC20( marketToken[market][TokenType.SY]).forceApprove(
            address(pendleRouter),
            syAmount
        );
        if (toAssetType == TokenType.UNDERLYING) {
            (, address assetAddress, ) = IStandardizedYield(marketToken[market][TokenType.SY]).assetInfo();
            uint256 netTokenOut = pendleRouter.redeemSyToToken(
                address(this),
                marketToken[market][TokenType.SY],
                syAmount,
                createTokenOutputSimple(assetAddress, 0)
            );
            userBalances[msg.sender][assetAddress] += netTokenOut;
        } else if (toAssetType == TokenType.SY) {
            userBalances[msg.sender][marketToken[market][TokenType.SY]] += syAmount;
        } else if (toAssetType == TokenType.PT) {
            (uint256 netPtOut, ) = pendleRouter.swapExactSyForPt(
                address(this),
                supportedMarkets[inputToken],
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][marketToken[market][TokenType.PT]] += netPtOut;
        } else if (toAssetType == TokenType.YT) {
            (uint256 netYtOut, ) = pendleRouter.swapExactSyForYt(
                address(this),
                supportedMarkets[inputToken],
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][marketToken[market][TokenType.YT]] += netYtOut;
        } else if (toAssetType == TokenType.LP) {
            (uint256 netLpOut, ) = pendleRouter.addLiquiditySingleSy(
                address(this),
                market,
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][market] += netLpOut;
        }
        userBalances[msg.sender][inputToken] = 0;
    }



    function swap(
        address inputToken,
        TokenType toAssetType,
        uint256 amount
    ) public {
        deposit(inputToken, amount);
        convert(inputToken, toAssetType);
        withdraw(marketToken[supportedMarkets[inputToken]][toAssetType]);
    }
}
