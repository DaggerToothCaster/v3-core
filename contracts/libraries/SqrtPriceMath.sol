// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';

import './FullMath.sol';
import './UnsafeMath.sol';
import './FixedPoint96.sol';

/// @title 基于Q64.96平方根价格和流动性的函数
/// @notice 包含使用价格的平方根作为Q64.96和流动性来计算增量的数学方法
library SqrtPriceMath {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;

    /// @notice 获取给定token0变化量的下一个平方根价格
    /// @dev 总是向上取整，因为在精确输出情况下（价格增加），我们需要将价格至少移动到足够远的地方以获得所需的输出金额，
    /// 而在精确输入情况下（价格下降），我们需要移动的价格较少，以便不发送太多输出。
    /// 计算这个最精确的公式是 liquidity * sqrtPX96 / (liquidity +- amount * sqrtPX96),
    /// 如果因为溢出而不可能完成，我们计算 liquidity / (liquidity / sqrtPX96 +- amount)。
    /// @param sqrtPX96 起始价格，即考虑token0变化之前的价格
    /// @param liquidity 可用流动性量
    /// @param amount 要从虚拟储备中增加或减少的token0数量
    /// @param add 是否增加或减少token0的数量
    /// @return 添加或移除数量后的价格，取决于add
    function getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // 我们快速处理 amount == 0，因为否则结果不能保证等于输入价格
        if (amount == 0) return sqrtPX96;
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;

        if (add) {
            uint256 product;
            if ((product = amount * sqrtPX96) / amount == sqrtPX96) {
                uint256 denominator = numerator1 + product;
                if (denominator >= numerator1)
                    // 总是适应于160位
                    return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
            }

            return uint160(UnsafeMath.divRoundingUp(numerator1, (numerator1 / sqrtPX96).add(amount)));
        } else {
            uint256 product;
            // 如果乘积溢出，我们知道分母下溢
            // 另外，我们必须检查分母不会下溢
            require((product = amount * sqrtPX96) / amount == sqrtPX96 && numerator1 > product);
            uint256 denominator = numerator1 - product;
            return FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator).toUint160();
        }
    }

   译文："/// @title 基于Q64.96平方根价格和流动性的函数
/// @notice 包含使用Q64.96平方根价格和流动性计算增量的数学方法
library SqrtPriceMath {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;

    /// @notice 在给定token1的增量的情况下获取下一个平方根价格
    /// @dev 始终向下舍入，因为在精确输出情况下（价格下降），我们需要至少移动价格到足够远以获得期望的输出量，在精确输入情况下（价格增加），我们需要移动更少的价格以避免发送太多输出
    /// 我们计算的公式与无损版本相差小于1 wei：sqrtPX96 +- amount / liquidity
    /// @param sqrtPX96 起始价格，即在考虑token1增量之前
    /// @param liquidity 可用流动性的数量
    /// @param amount 要添加或移除的token1数量
    /// @param add 是否添加或移除token1的数量
    /// @return 添加或移除`amount`后的价格
    function getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // 如果我们在添加（减去），向下舍入需要向下（向上）舍入商
        // 在这两种情况下，避免大多数输入的mulDiv
        if (add) {
            uint256 quotient =
                (
                    amount <= type(uint160).max
                        ? (amount << FixedPoint96.RESOLUTION) / liquidity
                        : FullMath.mulDiv(amount, FixedPoint96.Q96, liquidity)
                );

            return uint256(sqrtPX96).add(quotient).toUint160();
        } else {
            uint256 quotient =
                (
                    amount <= type(uint160).max
                        ? UnsafeMath.divRoundingUp(amount << FixedPoint96.RESOLUTION, liquidity)
                        : FullMath.mulDivRoundingUp(amount, FixedPoint96.Q96, liquidity)
                );

            require(sqrtPX96 > quotient);
            // 总是符合160位
            return uint160(sqrtPX96 - quotient);
        }
    }

    /// @notice 获取给定token0或token1的输入量后的下一个平方根价格
    /// @dev 如果价格或流动性为0，或者下一个价格超出范围，则抛出异常
    /// @param sqrtPX96 起始价格，在考虑输入量之前
    /// @param liquidity 可用流动性的数量
    /// @param amountIn 被交换的token0或token1的数量
    /// @param zeroForOne 是否输入量为token0或token1
    /// @return 添加输入量到token0或token1后的价格
    function getNextSqrtPriceFromInput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

        // 舍入以确保我们不超过目标价格
        return
            zeroForOne
                ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountIn, true)
                : getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountIn, true);
    }

    /// @notice 获取给定token0或token1的输出量后的下一个平方根价格
    /// @dev 如果价格或流动性为0，或者下一个价格超出范围，则抛出异常
    /// @param sqrtPX96 去除输出量之前的起始价格
    /// @param liquidity 可用流动性的数量
    /// @param amountOut 将被交换出的token0或token1的数量
    /// @param zeroForOne 输出量为token0或token1
    /// @return 删除token0或token1的输出量后的价格
    function getNextSqrtPriceFromOutput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

        // 舍入以确保我们超过目标价格
        return
            zeroForOne
                ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false)
                : getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
    }
   译文：/// @notice 获取两个价格之间的amount0增量
    /// @dev 计算流动性/ sqrt(lower) - 流动性/ sqrt(upper),
    /// 即流动性*（sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    /// @param sqrtRatioAX96 一个sqrt价格
    /// @param sqrtRatioBX96 另一个sqrt价格
    /// @param 流动性 可用流动性的数量
    /// @param roundUp 是否向上或向下舍入
    /// @return amount0 要覆盖两个传递价格之间的大小流动性的头寸所需的token0数量
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0);

        return
            roundUp
                ? UnsafeMath.divRoundingUp(
                    FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                    sqrtRatioAX96
                )
                : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    /// @notice 获取两个价格之间的amount1增量
    /// @dev 计算流动性*（sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 一个sqrt价格
    /// @param sqrtRatioBX96 另一个sqrt价格
    /// @param 流动性 可用流动性的数量
    /// @param roundUp 是否向上或向下舍入
    /// @return amount1 要覆盖两个传递价格之间的大小流动性的头寸需要的token1数量
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
            roundUp
                ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
                : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice 获取有符号的token0增量的辅助函数
    /// @param sqrtRatioAX96 一个sqrt价格
    /// @param sqrtRatioBX96 另一个sqrt价格
    /// @param liquidity 要计算amount0增量的流动性变化
    /// @return amount0 对应于两个价格之间传递的流动性变化的token0数量
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount0) {
        return
            liquidity < 0
                ? -getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                : getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
    }

    /// @notice 获取有符号的token1增量的辅助函数
    /// @param sqrtRatioAX96 一个sqrt价格
    /// @param sqrtRatioBX96 另一个sqrt价格
    /// @param liquidity 要计算amount1增量的流动性变化
    /// @return amount1 对应于两个价格之间传递的流动性变化的token1数量
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount1) {
        return
            liquidity < 0
                ? -getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
                : getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
    }
}
