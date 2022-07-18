// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import './Convert.sol';
import './Call.sol';

import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract OuroborusRouter {
    using SafeMath for uint256;
    using Convert for uint256;
    using Call for address;

    event Log(bytes);

    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public constant PART_DENOMINATOR = 100;

    bytes32 private constant META_TRANSACTION_TYPEHASH = keccak256(
        bytes(
            "MetaTransaction(uint256 nonce,address from,bytes functionSignature)"
        )
    );

    mapping(address => uint256) nonces;

    struct MetaTransaction {
        uint256 nonce;
        address from;
        bytes functionSignature;
    }

    function hashMetaTransaction(MetaTransaction metaTx)
        internal
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encode(
                    META_TRANSACTION_TYPEHASH,
                    metaTx.nonce,
                    metaTx.from,
                    keccak256(metaTx.functionSignature)
                )
            );
    }

    function getNonce(address user) public view returns (uint256 nonce) {
        nonce = nonces[user];
    }

    function verify(
        address signer,
        MetaTransaction metaTx,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV
    ) internal view returns (bool) {
        require(signer != address(0), "NativeMetaTransaction: INVALID_SIGNER");
        return
            signer ==
            ecrecover(
                toTypedMessageHash(hashMetaTransaction(metaTx)),
                sigV,
                sigR,
                sigS
            );
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 swapFee
    ) internal pure returns (uint256) {
        // todo: reverse fee
        amountIn = amountIn.mul(FEE_DENOMINATOR.sub(swapFee));
        uint256 numerator = reserveOut.mul(amountIn);
        uint256 denominator = reserveIn.mul(FEE_DENOMINATOR).add(amountIn);
        return numerator.div(denominator);
    }

    function _quote(uint256 amountIn, uint256[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](path.length);
        for (uint256 i; i < path.length; i++) {
            uint256 swapFee = path[i].swapFee();
            if (swapFee != 0) {
                (uint256 reserveIn, uint256 reserveOut) = path[i]
                    .addr()
                    .getReserves();

                if (path[i].rev()) {
                    (reserveIn, reserveOut) = (reserveOut, reserveIn);
                }

                uint256 part = path[i].part();
                uint256 src = path[i].src();
                amounts[i] = getAmountOut(
                    amounts[src].mul(part).div(PART_DENOMINATOR),
                    reserveIn,
                    reserveOut,
                    swapFee
                );

                uint256 tokenFee = path[i].tokenFee();
                amountIn += amounts[i].mul(tokenFee).div(FEE_DENOMINATOR);
            } else {
                // reverse fee
                amounts[i] = amountIn;
                amountIn = 0;
            }
        }
    }

    function _swap(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] memory path,
        address to,
        uint256 comissionPrecentage
    ) internal returns (uint256[] memory amounts) {
        amounts = _quote(amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            'OuroborusRouter: insufficient amount'
        );

        //comission problem
        require(amountIn % 100 == 0);
        uint256 protocol_fee = (amountIn * comissionPrecentage) / 100;
        amountIn -= protocol_fee;
        payable(msg.sender).transfer(amountIn);
        payable(to).transfer(protocol_fee);

        path[0].addr().transferFrom(to, address(this), amountIn);
        uint256 preBalance = path[path.length - 1].addr().balanceOf(to);

        for (uint256 i; i < path.length; i++) {
            if (path[i].swapFee() != 0) {
                uint256 src = path[i].src();
                path[src].addr().transfer(
                    address(uint160(path[i])),
                    amounts[src].mul(path[i].part()).div(PART_DENOMINATOR)
                );
                uint256 amount0Out;
                uint256 amount1Out = amounts[i];
                if (path[i].rev()) {
                    (amount0Out, amount1Out) = (amount1Out, amount0Out);
                }
                path[i].addr().swap(
                    amount0Out,
                    amount1Out,
                    address(msg.sender),
                    hex''
                );
            }
        }

        emit Log(
            abi.encode(
                path[path.length - 1].addr().balanceOf(address(msg.sender)),
                amounts[amounts.length - 1]
            )
        );
    }

    function MetaSwap(
        address userAddress,
        bytes functionSignature,
        bytes32 sigR,
        bytes32 sigS,
        uint8 sigV,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] memory path,
        uint256 comissionPrecentage
    ) public payable returns (bytes) {
        _swap(amountIn,amountOutMin,path,userAddress, comissionPrecentage);
        MetaTransaction metaTx = MetaTransaction({
            nonce: nonces[userAddress],
            from: userAddress,
            protocol_fee: comission,
            functionSignature: functionSignature
        });
        
        require(
            verify(userAddress, metaTx, sigR, sigS, sigV),
            "Signer and signature do not match"
        );

        nonces[userAddress] = nonces[userAddress] + 1;

        (bool success, bytes returnData) = address(this).call(
            abi.encodePacked(functionSignature, userAddress)
        );
        require(success, "Function call not successful");

        return returnData;
    }

    function swap(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] memory path,
        address to
    ) external returns (uint256[] memory amounts) {
        _swap(amountIn, amountOutMin, path, msg.sender);
    }

    function quote(uint256 amountIn, uint256[] memory path)
        external
        view
        returns (uint256[] memory)
    {
        return _quote(amountIn, path);
    }
}