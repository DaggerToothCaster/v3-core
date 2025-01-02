// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 安全转换方法
/// @notice 包含安全转换类型的方法
library SafeCast {
    /// @notice 将uint256转换为uint160，溢出时回滚
    /// @param y 要转换的uint256
    /// @return z 转换后的整数，现在是uint160类型
    function toUint160(uint256 y) internal pure returns (uint160 z) {
        require((z = uint160(y)) == y);
    }

    /// @notice 将int256转换为int128，溢出或下溢时回滚
    /// @param y 要转换的int256
    /// @return z 转换后的整数，现在是int128类型
    function toInt128(int256 y) internal pure returns (int128 z) {
        require((z = int128(y)) == y);
    }

    /// @notice 将uint256转换为int256，溢出时回滚
    /// @param y 要转换的uint256
    /// @return z 转换后的整数，现在是int256类型
    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2**255);
        z = int256(y);
    }
}