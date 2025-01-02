
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 用于流动性的数学库
library LiquidityMath {
    /// @notice 将一个有符号流动性增量添加到流动性中，并在溢出或下溢时回滚
    /// @param x 更改前的流动性
    /// @param y 应更改流动性的增量
    /// @return z 流动性增量
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        if (y < 0) {
            require((z = x - uint128(-y)) < x, 'LS');
        } else {
            require((z = x + uint128(y)) >= x, 'LA');
        }
    }
}