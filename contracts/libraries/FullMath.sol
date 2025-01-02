// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.8.0;

/// @title 包含512位数学函数
/// @notice 便于实现乘法和除法，可以在中间值溢出但不会损失精度的情况下进行
/// @dev 处理“幻影溢出”，即允许乘法和除法中出现中间值溢出256位
library FullMath {
    /// @notice 使用全精度计算floor(a×b÷denominator)。 如果结果溢出uint256或分母== 0，则引发错误
    /// @param a 乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result 256位结果
    /// @dev 归功于Remco Bloemen，根据MIT许可证https://xn--2-umb.com/21/muldiv
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // 512位乘法 [prod1 prod0] = a * b
        // 计算模2**256和模2**256-1的乘积
        // 然后使用中国剩余定理重构512位结果。 将结果存储在两个256位变量中，使得product = prod1 * 2**256 + prod0
        uint256 prod0; // 产品的最低有效256位
        uint256 prod1; // 产品的最高有效256位
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // 处理非溢出情况，256位除法
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // 确保结果小于2**256。
        // 同时防止分母为0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512位至256位的除法。
        ///////////////////////////////////////////////

        // 通过从[prod1 prod0]减去余数使除法精确
        // 使用mulmod计算余数
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // 从512位数中减去256位数
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // 将除数中的两的幂因子分解
        // 计算除数的最大的二的幂因子。
        // 总是>= 1。
        uint256 twos = -denominator & denominator;
        // 通过二的幂因子除以除数
        assembly {
            denominator := div(denominator, twos)
        }

        // 由于结果小于2**256，因此不需要再计算高位的结果，prod1也不再需要。
        result = prod0 * inv;
        return result;
    }

    /// @notice 使用全精度计算ceil(a×b÷denominator)。 如果结果溢出uint256或分母== 0，则引发错误
    /// @param a 乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return 结果 256位结果
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }
}
