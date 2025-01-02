// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';

import './TickMath.sol';
import './LiquidityMath.sol';


/// @title Tick
/// @notice 包含用于管理ticks流程和相关计算的函数
library Tick {
    using LowGasSafeMath for int256;
    using SafeCast for int256;

    // 存储每个初始化的单个tick的信息
    struct Info {
        // 引用此tick的总头寸流动性
        uint128 liquidityGross;
        // 当从左到右（从右到左）穿过tick时添加（减去）的净流动性量
        int128 liquidityNet;
        // 在此tick的_另一侧_每单位流动性的手续费增长（相对于当前tick）
        // 仅具有相关含义，不是绝对值 — 该值取决于何时初始化tick
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        // 此tick的另一侧的累积tick值
        int56 tickCumulativeOutside;
        // 在_tick初始化时的_另一侧_每单位流动性的秒数
        // 仅具有相关含义，不是绝对值 — 该值取决于何时初始化tick
        uint160 secondsPerLiquidityOutsideX128;
        // 在_tick的另一侧度过的秒数（相对于当前tick）
        // 仅具有相关含义，不是绝对值 — 该值取决于何时初始化tick
        uint32 secondsOutside;
        // 如果tick已初始化，则为true，即值与表达式liquidityGross != 0完全相同
        // 设置这8位是为了在跨越新初始化的ticks时防止新的sstores
        bool initialized;
    }

    /// @notice 根据给定的tick间隔导出每个tick的最大流动性
    /// @dev 在池构造函数内执行
    /// @param tickSpacing 所需tick间隔的数量，以`tickSpacing`的倍数实现
    ///     例如，tickSpacing为3表示每第3个tick需初始化，即，..., -6, -3, 0, 3, 6, ...
    /// @return 每个tick的最大流动性
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        return type(uint128).max / numTicks;
    }
}

    /// @notice 检索费用增长数据
    /// @param self 包含所有已初始化刻度信息的映射
    /// @param tickLower 位置的下限刻度边界
    /// @param tickUpper 位置的上限刻度边界
    /// @param tickCurrent 当前刻度
    /// @param feeGrowthGlobal0X128 代币0中所有时间的全局费用增长，每单位流动性
    /// @param feeGrowthGlobal1X128 代币1中所有时间的全局费用增长，每单位流动性 返回值
    /// @return feeGrowthInside0X128 刻度边界内代币0的全局费用增长，每单位流动性
    /// @return feeGrowthInside1X128 刻度边界内代币1的全局费用增长，每单位流动性
    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        // 计算下方的费用增长
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
        }

        // 计算上方的费用增长
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

   /// @notice 更新一个tick并返回true，如果该tick从已初始化变为未初始化，或者反之
    /// @param self 包含所有已初始化tick信息的映射
    /// @param tick 将要被更新的tick
    /// @param tickCurrent 当前的tick
    /// @param liquidityDelta 当tick从左向右(从右向左)越过时要添加(减去)的新流动性数量
    /// @param feeGrowthGlobal0X128 token0中每单位流动性的全局费用增长
    /// @param feeGrowthGlobal1X128 token1中每单位流动性的全局费用增长
    /// @param secondsPerLiquidityCumulativeX128 池中每个最大(1，流动性)的历史秒数
    /// @param tickCumulative tick * 自池初始化以来经过的时间
    /// @param time 当前块时间戳转换为uint32
    /// @param upper 如果要更新头部tick的位置，则为true；如果要更新底部tick的位置，则为false
    /// @param maxLiquidity 单个tick的最大流动性分配
    /// @return flipped 如果tick从初始化变为未初始化，或者反之，则为true
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        Tick.Info storage info = self[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, 'LO');

        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        if (liquidityGrossBefore == 0) {
            // 根据惯例，我们假设tick初始化之前的所有增长发生在tick下方
            if (tick <= tickCurrent) {
                info.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
                info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128;
                info.tickCumulativeOutside = tickCumulative;
                info.secondsOutside = time;
            }
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // 当下界(上界)tick从左向右(从右向左)越过时，必须添加(删除)流动性
        info.liquidityNet = upper
            ? int256(info.liquidityNet).sub(liquidityDelta).toInt128()
            : int256(info.liquidityNet).add(liquidityDelta).toInt128();
    }

    /// @notice 清除tick数据
    /// @param self 包含所有已初始化tick信息的映射
    /// @param tick 将要被清除的tick
    function clear(mapping(int24 => Tick.Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    /// @notice 根据价格变动的需要，转到下一个tick
    /// @param self 包含所有已初始化tick信息的映射
    /// @param tick 转换的目标tick
    /// @param feeGrowthGlobal0X128 token0中每单位流动性的全局费用增长
    /// @param feeGrowthGlobal1X128 token1中每单位流动性的全局费用增长
    /// @param secondsPerLiquidityCumulativeX128 当前每单位流动性的秒数
    /// @param tickCumulative tick * 自池初始化以来经过的时间
    /// @param time 当前块时间戳
    /// @return liquidityNet 当tick从左向右(从右向左)越过时添加(减去)的流动性数量
    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time
    ) internal returns (int128 liquidityNet) {
        Tick.Info storage info = self[tick];
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128 - info.secondsPerLiquidityOutsideX128;
        info.tickCumulativeOutside = tickCumulative - info.tickCumulativeOutside;
        info.secondsOutside = time - info.secondsOutside;
        liquidityNet = info.liquidityNet;
    }
}
