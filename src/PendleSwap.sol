// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPAllActionV3} from "pendle-core-v2-public/contracts/interfaces/IPAllActionV3.sol";
import "pendle-core-v2-public/contracts/interfaces/IPAllActionTypeV3.sol";
import {IPMarket} from "pendle-core-v2-public/contracts/interfaces/IPMarket.sol";
import {IStandardizedYield} from "pendle-core-v2-public/contracts/interfaces/IStandardizedYield.sol";
import {IPPrincipalToken} from "pendle-core-v2-public/contracts/interfaces/IPPrincipalToken.sol";
import {IPYieldToken} from "pendle-core-v2-public/contracts/interfaces/IPYieldToken.sol";

contract PendleSwap is Ownable, ReentrancyGuard {
    IPAllActionV3 pendleRouter =
        IPAllActionV3(0x888888888889758F76e7103c6CbF23ABbF58F946);

    /// @notice Supported assets in
    enum TokenType {
        UNDERLYING,
        SY,
        PT,
        YT,
        LP
    }

    constructor() Ownable(msg.sender) {}

    /// @notice User balances
    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => TokenType) public supportedAssetTypes;
    mapping(address => address) public supportedMarkets;

    event Deposited(address indexed user, address assetType, uint256 amount);

    function setSupportedAsset(
        address asset,
        address market,
        TokenType assetType
    ) external onlyOwner {
        (
            IStandardizedYield _SY,
            IPPrincipalToken _PT,
            IPYieldToken _YT
        ) = IPMarket(supportedMarkets[market]).readTokens();
        supportedMarkets[address(_SY)] = market;
        supportedAssetTypes[address(_SY)] = TokenType.SY;
        supportedMarkets[address(_PT)] = market;
        supportedAssetTypes[address(_PT)] = TokenType.PT;
        supportedMarkets[address(_YT)] = market;
        supportedAssetTypes[address(_YT)] = TokenType.YT;
        if (assetType == TokenType.UNDERLYING) {
            supportedMarkets[asset] = market;
            supportedAssetTypes[asset] = TokenType.UNDERLYING;
        }
    }

    /// @notice Deposits a supported asset
    /// @param inputToken The asset to deposit
    /// @param inputTokenType The type of asset to deposit
    /// @param amount The amount to deposit
    function deposit(
        address inputToken,
        TokenType inputTokenType,
        uint256 amount
    ) external nonReentrant {
        require(amount > 0, "Invalid deposit amount");
        require(
            IERC20(inputToken).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        userBalances[msg.sender][inputToken] += amount;
        supportedAssetTypes[inputToken] = inputTokenType;
        emit Deposited(msg.sender, inputToken, amount);
    }

    function convert(
        address inputToken,
        TokenType toAssetType
    ) public returns (uint256) {
        (
            IStandardizedYield _SY,
            IPPrincipalToken _PT,
            IPYieldToken _YT
        ) = IPMarket(supportedMarkets[inputToken]).readTokens();
        TokenType fromTokenType = supportedAssetTypes[inputToken];
        uint256 syAmount;
        require(
            fromTokenType != toAssetType,
            "Input and output asset types cannot be the same"
        );
        require(inputToken == address(0), "Token address cannot be 0");
        require(
            userBalances[msg.sender][inputToken] > 0,
            "Amount in must be greater than 0"
        );
        if (fromTokenType == TokenType.UNDERLYING) {
            uint256 netSyOut = pendleRouter.mintSyFromToken(
                address(this),
                address(_SY),
                0,
                createTokenInputSimple(
                    inputToken,
                    userBalances[msg.sender][inputToken]
                )
            );
            syAmount = netSyOut;
        } else if (fromTokenType == TokenType.LP) {
            (uint256 netSYOut, ) = pendleRouter.removeLiquiditySingleSy(
                address(this),
                supportedMarkets[inputToken],
                userBalances[msg.sender][inputToken],
                0,
                createEmptyLimitOrderData()
            );
            syAmount = netSYOut;
        } else if (fromTokenType == TokenType.SY) {
            syAmount = userBalances[msg.sender][inputToken];
        } else if (fromTokenType == TokenType.PT) {
            (uint256 netSYOut, ) = pendleRouter.swapExactPtForSy(
                address(this),
                supportedMarkets[inputToken],
                userBalances[msg.sender][inputToken],
                0,
                createEmptyLimitOrderData()
            );
            syAmount = netSYOut;
        } else if (fromTokenType == TokenType.YT) {
            (uint256 netSYOut, ) = pendleRouter.swapExactYtForSy(
                address(this),
                supportedMarkets[inputToken],
                userBalances[msg.sender][inputToken],
                0,
                createEmptyLimitOrderData()
            );
            syAmount = netSYOut;
        }

        if (toAssetType == TokenType.UNDERLYING) {
            (, address assetAddress,) = _SY.assetInfo();
            uint256 netTokenOut = pendleRouter.redeemSyToToken(
                address(this),
                address(_SY),
                syAmount,
                createTokenOutputSimple(assetAddress, 0)
            );
            userBalances[msg.sender][assetAddress] += netTokenOut;
        } else if (toAssetType == TokenType.SY) {
            userBalances[msg.sender][address(_SY)] += syAmount;
        } else if (toAssetType == TokenType.PT) {
            (uint256 netPtOut, ) = pendleRouter.swapExactSyForPt(
                address(this),
                supportedMarkets[inputToken],
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][address(_PT)] += netPtOut;
        } else if (toAssetType == TokenType.YT) {
            (uint256 netYtOut, ) = pendleRouter.swapExactSyForYt(
                address(this),
                supportedMarkets[inputToken],
                syAmount,
                0,
                createDefaultApproxParams(),
                createEmptyLimitOrderData()
            );
            userBalances[msg.sender][address(_YT)] += netYtOut;
        }
        userBalances[msg.sender][inputToken] = 0;
        return 0;
    }

    // function swap(
    //     address inputToken,
    //     AssetType toAssetType,
    //     uint256 amount
    // ) public returns (uint256) {
    //     AssetType fromTokenType = supportedAssetTypes[inputToken];
    //     bytes4 selector;
    //     bytes memory functionData;
    //     require(
    //         fromTokenType != toAssetType,
    //         "Input and output asset types cannot be the same"
    //     );
    //     require(inputToken == address(0), "Token address cannot be 0");
    //     require(
    //         userBalances[msg.sender][inputToken] > 0,
    //         "Amount in must be greater than 0"
    //     );

    //     if (fromTokenType == AssetType.UNDERLYING) {
    //         if (toAssetType == AssetType.SY) {
    //             selector = _getSelector(
    //                 "mintSyFromToken(address,address,uint256,TokenInput)"
    //             );
    //         } else if (
    //             toAssetType == AssetType.PT || toAssetType == AssetType.YT
    //         ) {
    //             selector = _getSelector(
    //                 "mintPyFromToken(address,address,uint256,TokenInput)"
    //             );
    //         } else if (toAssetType == AssetType.LP) {
    //             selector = _getSelector(
    //                 "addLiquiditySingleToken(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
    //             );
    //         }
    //     } else if (fromTokenType == AssetType.SY) {
    //         if (toAssetType == AssetType.UNDERLYING) {
    //             selector = _getSelector(
    //                 "redeemSyToToken(address,address,uint256,TokenOutput)"
    //             );
    //         } else if (
    //             toAssetType == AssetType.PT || toAssetType == AssetType.YT
    //         ) {
    //             selector = _getSelector(
    //                 "mintPyFromSy(address,address,uint256,uint256)"
    //             );
    //         } else if (toAssetType == AssetType.LP) {
    //             selector = _getSelector(
    //                 "addLiquiditySingleSy(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
    //             );
    //         }
    //     } else if (fromTokenType == AssetType.LP) {
    //         if (toAssetType == AssetType.UNDERLYING) {
    //             selector = _getSelector(
    //                 "removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)"
    //             );
    //         } else if (toAssetType == AssetType.SY) {
    //             selector = _getSelector(
    //                 "removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)"
    //             );
    //         } else if (
    //             toAssetType == AssetType.PT || toAssetType == AssetType.YT
    //         ) {
    //             selector = _getSelector(
    //                 "mintPyFromToken(address,address,uint256,TokenInput)"
    //             );
    //         }
    //     } else if (fromTokenType == AssetType.PT) {
    //         if (toAssetType == AssetType.UNDERLYING) {
    //             selector = _getSelector(
    //                 "redeemPyToToken(address,address,uint256, TokenOutput)"
    //             );
    //         } else if (toAssetType == AssetType.SY) {
    //             selector = _getSelector(
    //                 "redeemPyToSy(address,address,uint256,uint256)"
    //             );
    //         } else if (toAssetType == AssetType.LP) {
    //             selector = _getSelector(
    //                 "addLiquiditySinglePt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
    //             );
    //         }
    //     } else if (fromTokenType == AssetType.YT) {
    //         if (toAssetType == AssetType.UNDERLYING) {
    //             selector = _getSelector(
    //                 "redeemPyToToken(address,address,uint256, TokenOutput)"
    //             );
    //         } else if (toAssetType == AssetType.SY) {
    //             selector = _getSelector(
    //                 "redeemYtToSy(address,address,uint256,uint256)"
    //             );
    //         } else if (toAssetType == AssetType.LP) {
    //             selector = _getSelector(
    //                 "addLiquiditySingleYt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
    //             );
    //         }
    //     }

    //     PENDLE_ROUTER.call(abi.encodePacked(selector, functionData));
    //     return 0;
    // }
}
