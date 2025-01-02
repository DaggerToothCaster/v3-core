// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 不存储的池状态
/// @notice 包含视图函数，用于提供有关池的信息，这些信息是计算而不是存储在区块链上的。这里的函数可能具有可变的gas成本。
interface IUniswapV3PoolDerivedState {
    /// @notice 返回每个时间戳`secondsAgo`时的累积tick和流动性
    /// @dev 要获得时间加权平均tick或范围内流动性，必须使用两个值调用此函数，一个代表
    /// 期间的开始，另一个代表期间的结束。例如，要获得最后一小时的时间加权平均tick，
    /// 您必须使用secondsAgos = [3600, 0]调用它。
    /// @dev 时间加权平均tick代表池的几何时间加权平均价格，在上下文中为log基sqrt(1.0001)的token1/token0。可以使用TickMath库将tick值转换为比率。
    /// @param secondsAgos 应返回每个`secondsAgos`从当前区块时间戳的累积tick和流动性值
    /// @return tickCumulatives 每个`secondsAgos`从当前区块时间戳的累积tick值
    /// @return secondsPerLiquidityCumulativeX128s 每个`secondsAgos`从当前区块时间戳的累积范围内流动性的秒数
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    /// @notice 返回tick累积、每流动性秒数和范围内秒数的快照
    /// @dev 快照只能与其他快照比较，每当持有仓位时，都应在此期间采取快照。
    /// 也就是说，如果仓位在第一个快照被获取和第二个快照被获取之间的整个时间段内不存在，则无法比较快照。
    /// @param tickLower 范围的较低tick
    /// @param tickUpper 范围的较高tick
    /// @return tickCumulativeInside 范围内tick累加器的快照
    /// @return secondsPerLiquidityInsideX128 范围内每流动性秒数的快照
    /// @return secondsInside 范围内每流动性秒数的快照
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        );
}