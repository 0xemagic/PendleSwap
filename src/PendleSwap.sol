// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PendleRouterV4} from "pendle-core-v2-public/contracts/Router/PendleRouterV4.sol";
import "pendle-core-v2-public/contracts/Interfaces/IPAllActionTypeV3.sol";
import {IPMarketV3} from "pendle-core-v2-public/contracts/Interfaces/IPMarketV3.sol";

contract PendleSwap is Ownable, ReentrancyGuard {
    PendleRouterV4 pendleRouter =
        PendleRouterV4(0x888888888889758F76e7103c6CbF23ABbF58F946);

    /// @notice Supported assets in
    enum AssetType {
        UNDERLYING,
        SY,
        PT,
        YT,
        LP
    }

    constructor() Ownable(msg.sender) {}

    /// @notice User balances
    mapping(address => mapping(address => uint256)) public userBalances;
    mapping(address => AssetType) public supportedAssetTypes;
    mapping(address => address) public supportedMarkets;

    event Deposited(address indexed user, address assetType, uint256 amount);

    function setSupportedAsset(
        address asset,
        address market,
        AssetType assetType
    ) external onlyOwner {
        supportedMarkets[asset] = market;
        require(
            IPMarketV3(market).readTokens() != (address(0), address(0)),
            "Invalid market"
        );
        supportedAssetTypes[asset] = assetType;
    }

    /// @notice Deposits a supported asset
    /// @param inputToken The asset to deposit
    /// @param inputTokenType The type of asset to deposit
    /// @param amount The amount to deposit
    function deposit(
        address inputToken,
        AssetType inputTokenType,
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
        AssetType toAssetType
    ) public returns (uint256) {
        AssetType fromTokenType = supportedAssetTypes[inputToken];
        bytes4 selector;
        bytes memory functionData;
        require(
            fromTokenType != toAssetType,
            "Input and output asset types cannot be the same"
        );
        require(inputToken == address(0), "Token address cannot be 0");
        require(
            userBalances[msg.sender][inputToken] > 0,
            "Amount in must be greater than 0"
        );
        if (fromTokenType == AssetType.UNDERLYING) {
            if (toAssetType == AssetType.SY) {
                (_SY, ) = IPMarketV3(supportedMarkets[inputToken]).readTokens();
                uint256 syAmount = pendleRouter.mintSyFromToken(
                    address(this),
                    address(_SY),
                    userBalances[msg.sender][inputToken],
                    createTokenInputSimple(
                        inputToken,
                        userBalances[msg.sender][inputToken]
                    )
                );
                userBalances[msg.sender][address(_SY)] += syAmount;
                userBalances[msg.sender][inputToken] = 0;
                supportedAssetTypes[address(_SY)] = AssetType.SY;
            } else if (toAssetType == AssetType.PT) {
                (uint256 netPtOut, ) = pendleRouter.swapExactTokenForPt(
                    address(this),
                    supportedMarkets[inputToken],
                    0,
                    createDefaultApproxParams(),
                    createTokenInputSimple(
                        inputToken,
                        userBalances[msg.sender][inputToken]
                    ),
                    createTokenInputSimple(USDC_ADDRESS, 1000e6),
                    createEmptyLimitOrderData()
                );
            } else if (toAssetType == AssetType.YT) {} else if (
                toAssetType == AssetType.LP
            ) {
                selector = _getSelector(
                    "addLiquiditySingleToken(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
                // data = abi.encode(inputToken, msg.sender, userBalances[msg.sender][inputToken],);
            }
        } else if (fromTokenType == AssetType.SY) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "redeemSyToToken(address,address,uint256, TokenOutput)"
                );
            } else if (
                toAssetType == AssetType.PT || toAssetType == AssetType.YT
            ) {
                selector = _getSelector(
                    "mintPyFromSy(address,address,uint256,uint256)"
                );
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector(
                    "addLiquiditySingleSy(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
            }
        } else if (fromTokenType == AssetType.LP) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)"
                );
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector(
                    "removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)"
                );
                // selector = _getSelector(
                //     "mintSyFromToken(address,address,uint256, TokenInput)"
                // );
            } else if (
                toAssetType == AssetType.PT || toAssetType == AssetType.YT
            ) {
                // selector = _getSelector(
                //     "removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)"
                // );
                selector = _getSelector(
                    "mintPyFromToken(address,address,uint256,TokenInput)"
                );
            }
        } else if (fromTokenType == AssetType.PT) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "redeemPyToToken(address,address,uint256, TokenOutput)"
                );
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector(
                    "redeemPyToSy(address,address,uint256,uint256)"
                );
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector(
                    "addLiquiditySinglePt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
            }
        } else if (fromTokenType == AssetType.YT) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "redeemPyToToken(address,address,uint256, TokenOutput)"
                );
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector(
                    "redeemYtToSy(address,address,uint256,uint256)"
                );
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector(
                    "addLiquiditySingleYt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
            }
        }

        PENDLE_ROUTER.call(abi.encodePacked(selector, functionData));
        return 0;
        // bytes4 selector = _getSelector("swapExactTokenForPt(address,address,uint256)");
    }

    function swap(
        address inputToken,
        AssetType toAssetType,
        uint256 amount
    ) public returns (uint256) {
        AssetType fromTokenType = supportedAssetTypes[inputToken];
        bytes4 selector;
        bytes memory functionData;
        require(
            fromTokenType != toAssetType,
            "Input and output asset types cannot be the same"
        );
        require(inputToken == address(0), "Token address cannot be 0");
        require(
            userBalances[msg.sender][inputToken] > 0,
            "Amount in must be greater than 0"
        );

        if (fromTokenType == AssetType.UNDERLYING) {
            if (toAssetType == AssetType.SY) {
                selector = _getSelector(
                    "mintSyFromToken(address,address,uint256,TokenInput)"
                );
            } else if (
                toAssetType == AssetType.PT || toAssetType == AssetType.YT
            ) {
                selector = _getSelector(
                    "mintPyFromToken(address,address,uint256,TokenInput)"
                );
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector(
                    "addLiquiditySingleToken(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
            }
        } else if (fromTokenType == AssetType.SY) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "redeemSyToToken(address,address,uint256, TokenOutput)"
                );
            } else if (
                toAssetType == AssetType.PT || toAssetType == AssetType.YT
            ) {
                selector = _getSelector(
                    "mintPyFromSy(address,address,uint256,uint256)"
                );
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector(
                    "addLiquiditySingleSy(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
            }
        } else if (fromTokenType == AssetType.LP) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)"
                );
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector(
                    "removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)"
                );
            } else if (
                toAssetType == AssetType.PT || toAssetType == AssetType.YT
            ) {
                selector = _getSelector(
                    "mintPyFromToken(address,address,uint256,TokenInput)"
                );
            }
        } else if (fromTokenType == AssetType.PT) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "redeemPyToToken(address,address,uint256, TokenOutput)"
                );
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector(
                    "redeemPyToSy(address,address,uint256,uint256)"
                );
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector(
                    "addLiquiditySinglePt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
            }
        } else if (fromTokenType == AssetType.YT) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector(
                    "redeemPyToToken(address,address,uint256, TokenOutput)"
                );
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector(
                    "redeemYtToSy(address,address,uint256,uint256)"
                );
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector(
                    "addLiquiditySingleYt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)"
                );
            }
        }

        PENDLE_ROUTER.call(abi.encodePacked(selector, functionData));
        return 0;
    }

    function _getSelector(
        string memory funcSignature
    ) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(funcSignature)));
    }
}
