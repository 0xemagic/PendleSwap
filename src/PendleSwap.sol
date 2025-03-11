// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PendleSwap is Ownable, ReentrancyGuard {
    address constant pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;

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
    mapping(address => AssetType) public userAssets;

    event Deposited(address indexed user, address assetType, uint256 amount);

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
        userAssets[inputToken] = inputTokenType;
        emit Deposited(msg.sender, inputToken, amount);
    }

    function convert(
        address inputToken,
        AssetType toAssetType
    ) public returns (uint256) {
        AssetType fromTokenType = userAssets[inputToken];
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
                // data = abi.encode(inputToken, msg.sender, userBalances[msg.sender][inputToken],);
            } else if (
                toAssetType == AssetType.PT || toAssetType == AssetType.YT
            ) {
                selector = _getSelector(
                    "mintPyFromToken(address,address,uint256,TokenInput)"
                );
                // data = abi.encode(inputToken, msg.sender, userBalances[msg.sender][inputToken],);
            } else if (toAssetType == AssetType.LP) {
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

        pendleRouter.call(abi.encodePacked(selector, functionData));
        return 0;
        // bytes4 selector = _getSelector("swapExactTokenForPt(address,address,uint256)");
    }

    function swap(
        address inputToken,
        AssetType toAssetType,
        uint256 amount
    ) public returns (uint256) {
        AssetType fromTokenType = userAssets[inputToken];
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
                selector = _getSelector("mintSyFromToken(address,address,uint256,TokenInput)");
            } else if (toAssetType == AssetType.PT || toAssetType == AssetType.YT) {
                selector = _getSelector("mintPyFromToken(address,address,uint256,TokenInput)");
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector("addLiquiditySingleToken(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)");
            }
        } else if (fromTokenType == AssetType.SY) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector("redeemSyToToken(address,address,uint256, TokenOutput)");
            } else if (toAssetType == AssetType.PT || toAssetType == AssetType.YT) {
                selector = _getSelector("mintPyFromSy(address,address,uint256,uint256)");
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector("addLiquiditySingleSy(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)");
            }
        } else if (fromTokenType == AssetType.LP) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector("removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)");
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector("removeLiquiditySingleToken(address,address,uint256,ApproxParams,TokenOutput,LimitOrderData)");
            } else if (toAssetType == AssetType.PT || toAssetType == AssetType.YT) {
                selector = _getSelector("mintPyFromToken(address,address,uint256,TokenInput)");
            }
        } else if (fromTokenType == AssetType.PT) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector("redeemPyToToken(address,address,uint256, TokenOutput)");
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector("redeemPyToSy(address,address,uint256,uint256)");
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector("addLiquiditySinglePt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)");
            }
        } else if (fromTokenType == AssetType.YT) {
            if (toAssetType == AssetType.UNDERLYING) {
                selector = _getSelector("redeemPyToToken(address,address,uint256, TokenOutput)");
            } else if (toAssetType == AssetType.SY) {
                selector = _getSelector("redeemYtToSy(address,address,uint256,uint256)");
            } else if (toAssetType == AssetType.LP) {
                selector = _getSelector("addLiquiditySingleYt(address,address,uint256,ApproxParams,TokenInput,LimitOrderData)");
            }
        }

        pendleRouter.call(abi.encodePacked(selector, functionData));
        return 0;

    }

    function _getSelector(
        string memory funcSignature
    ) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(funcSignature)));
    }
}
