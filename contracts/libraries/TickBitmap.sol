// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './BitMath.sol';

/// @title 压缩的tick初始化状态库
/// @notice 存储将tick索引与其初始化状态打包映射
/// @dev 该映射使用int16作为键，因为ticks表示为int24，每个字有256（2^8）个值。
library TickBitmap {
    /// @notice 计算存储tick初始化位的映射中的位置
    /// @param tick 要计算位置的tick
    /// @return wordPos 包含存储标志的字的映射键
    /// @return bitPos 字中标志存储的位位置
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(tick % 256);
    }

    /// @notice 将给定tick的初始化状态从false翻转为true，反之亦然
    /// @param self 要翻转tick的映射
    /// @param tick 要翻转的tick
    /// @param tickSpacing 可用tick之间的间距
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0); // 确保tick有间距
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    /// @notice 返回在与给定tick相同的字中（或相邻字中）包含的下一个初始化tick，其要么
    /// 在给定tick的左侧（小于或等于）或右侧（大于）上
    /// @param self 计算下一个初始化tick的映射
    /// @param tick 起始tick
    /// @param tickSpacing 可用tick之间的间距
    /// @param lte 是否搜索左侧（小于或等于起始tick）的下一个初始化tick
    /// @return next 下一个初始化或未初始化的tick，距离当前tick最多256个tick
    /// @return initialized 下一个tick是否已初始化，因为函数仅在最多搜索256个tick内
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // 向负无穷大舍入

        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // 当前bitPos上或右侧的所有1
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            // 如果在当前tick的右侧或在当前tick处没有初始化tick，则返回字中的最右边一个
            initialized = masked != 0;
            // 溢出/下溢是可能的，但外部通过限制tickSpacing和tick来防止
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // 从下一个tick的字开始，因为当前tick状态不重要
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // 当前bitPos上或左侧的所有1
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            // 如果在当前tick的左侧或在当前tick处没有初始化tick，则返回字中的最左边一个
            initialized = masked != 0;
            // 溢出/下溢是可能的，但外部通过限制tickSpacing和tick来防止
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }
}