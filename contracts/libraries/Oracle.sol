// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title Oracle
/// @notice 提供对各种系统设计有用的价格和流动性数据
/// @dev 存储的 Oracle 数据实例，即 "observations"，将被收集在 Oracle 数组中
/// 每个池都将初始化一个包含一个 Oracle 数组长度的数组。任何人都可以支付 SSTOREs 来增加 Oracle 数组的最大长度。当数组完全填满时，新的插槽将被添加。
/// 当 Oracle 数组的完整长度被填满时，观测将被覆盖。
/// 通过将 0 传递给 observe()，可以获取最近的观测结果，独立于 Oracle 数组的长度
library Oracle {
    struct Observation {
        // 观测的块时间戳
        uint32 blockTimestamp;
        // tick 累加器，即 tick * 自池首次初始化以来经过的时间
        int56 tickCumulative;
        // 流动性每秒，即自池首次初始化以来经过的秒数 / max(1, 流动性)
        uint160 secondsPerLiquidityCumulativeX128;
        // 观测是否已初始化
        bool initialized;
    }

    /// @notice 根据时间流逝和当前 tick 和流动性值，将之前的观测转换为新的观测
    /// @dev blockTimestamp _必须_按时间顺序等于或大于 last.blockTimestamp，安全地处理 0 或 1 溢出
    /// @param last 要转换的指定观测
    /// @param blockTimestamp 新观测的时间戳
    /// @param tick 新观测时的活跃 tick
    /// @param liquidity 新观测时的总范围内流动性
    /// @return Observation 新填充的观测
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity
    ) private pure returns (Observation memory) {
        uint32 delta = blockTimestamp - last.blockTimestamp;
        return
            Observation({
                blockTimestamp: blockTimestamp,
                tickCumulative: last.tickCumulative + int56(tick) * delta,
                secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 +
                    ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)),
                initialized: true
            });
    }

    /// @notice 通过写入第一个插槽来初始化 Oracle 数组。为观测数组的生命周期调用一次
    /// @param self 存储的 Oracle 数组
    /// @param time Oracle 初始化的时间，通过截断为 uint32 的 block.timestamp
    /// @return cardinality Oracle 数组中填充元素的数量
    /// @return cardinalityNext Oracle 数组的新长度，独立于填充情况
    function initialize(
        Observation[65535] storage self,
        uint32 time
    ) internal returns (uint16 cardinality, uint16 cardinalityNext) {
        self[0] = Observation({
            blockTimestamp: time,
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        return (1, 1);
    }

    /// @notice 将 oracle 观察写入数组
    /// @dev 每个区块最多写入一次。索引表示最近写入的元素。基数和索引必须在外部进行跟踪。
    /// 如果索引位于允许的数组长度末尾（根据基数），并且下一个基数
    /// 大于当前基数，则可以增加基数。此限制创建以保持排序。
    /// @param self 存储的 oracle 数组
    /// @param index 最近写入到观察数组的观察的索引
    /// @param blockTimestamp 新观察的时间戳
    /// @param tick 新观察时的活跃 tick
    /// @param liquidity 新观察时的总范围内流动性
    /// @param cardinality oracle 数组中填充元素的数量
    /// @param cardinalityNext oracle 数组的新长度，独立于填充
    /// @return indexUpdated oracle 数组中最近写入元素的新索引
    /// @return cardinalityUpdated oracle 数组的新基数
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];

        // 如果我们已经在此区块中写入了观察，则提前返回
        if (last.blockTimestamp == blockTimestamp) return (index, cardinality);

        // 如果条件合适，我们可以增加基数
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        indexUpdated = (index + 1) % cardinalityUpdated;
        self[indexUpdated] = transform(last, blockTimestamp, tick, liquidity);
    }

    /// @notice 准备 oracle 数组，以存储多达 `next` 个观察
    /// @param self 存储的 oracle 数组
    /// @param current oracle 数组的当前下一个基数
    /// @param next 将在 oracle 数组中填充的建议下一个基数
    /// @return next 将在 oracle 数组中填充的下一个基数
    function grow(Observation[65535] storage self, uint16 current, uint16 next) internal returns (uint16) {
        require(current > 0, 'I');
        // 如果传入的下一个值不大于当前的下一个值，则无操作
        if (next <= current) return current;
        // 在每个槽中存储，以防止在交换中出现新的 SSTORE 操作
        // 此数据将不会被使用，因为初始化的布尔值仍为 false
        for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
        return next;
    }

    /// @notice 用于 32 位时间戳的比较器
    /// @dev 安全执行 0 或 1 溢出，a 和 b _必须_在时间之前或等于时间
    /// @param time 截断为 32 位的时间戳
    /// @param a 用于确定 `time` 相对位置的比较时间戳
    /// @param b 用于确定 `time` 相对位置的时间戳
    /// @return bool `a` 是否按时间顺序 <= `b`
    function lte(uint32 time, uint32 a, uint32 b) private pure returns (bool) {
        // 如果没有溢出，无需调整
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2 ** 32;
        uint256 bAdjusted = b > time ? b : b + 2 ** 32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice 获取目标之前或之后以及在目标处的观察，即满足 [beforeOrAt, atOrAfter] 的观察。
    /// 结果可能是相同的观察，也可能是相邻的观察。
    /// @dev 答案必须包含在数组中，用于当目标位于存储的观察边界内时：早于最近的观察且晚于或等于最旧的观察
    /// @param self 存储的 oracle 数组
    /// @param time 当前区块时间戳
    /// @param target 应为保留观察结果的时间戳
    /// @param index 最近写入到观察数组的观察的索引
    /// @param cardinality oracle 数组中填充元素的数量
    /// @return beforeOrAt 记录在目标之前或在目标处的观察
    /// @return atOrAfter 记录在目标处或之后的观察
    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // 最老的观察
        uint256 r = l + cardinality - 1; // 最新的观察
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // 我们着陆在未初始化的 tick 上，继续向更高处搜索（更近）
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);

            // 检查是否找到答案！
            if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    /// @notice 获取给定目标前或等于和后或等于的观察结果，即满足[beforeOrAt，atOrAfter]的情况
    /// @dev 假定至少有1个初始化的观察结果。
    /// 由observeSingle()使用，以计算给定区块时间的反事实累加器值。
    /// @param self 存储的Oracle数组
    /// @param time 当前区块时间戳
    /// @param target 保留观察结果应为的时间戳
    /// @param tick 返回或模拟观察结果时的活跃tick
    /// @param index 最近写入观察结果数组的观察索引
    /// @param liquidity 调用时的总流动性
    /// @param cardinality Oracle数组中填充元素的数量
    /// @return beforeOrAt 发生在给定时间戳之前或等于之前发生的观察结果
    /// @return atOrAfter 发生在给定时间戳之后或等于之后发生的观察结果
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // 乐观地将before设置为最新的观察结果
        beforeOrAt = self[index];

        // 如果目标时间在最新的观察结果之后或等于之后，我们可以提前返回
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // 如果最新的观察结果等于目标时间，我们在同一个区块中，因此可以忽略atOrAfter
                return (beforeOrAt, atOrAfter);
            } else {
                // 否则，我们需要转换
                return (beforeOrAt, transform(beforeOrAt, target, tick, liquidity));
            }
        }

        // 现在，将before设置为最旧的观察结果
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // 确保目标时间在最旧的观察结果之后或等于之后
        require(lte(time, beforeOrAt.blockTimestamp, target), 'OLD');

        // 如果到达此点，我们必须进行二进制搜索
        return binarySearch(self, time, target, index, cardinality);
    }

    /// @dev 如果不存在与所需观察结果时间戳相同或之前的观察结果，则回滚。
    /// 可以将0作为`secondsAgo'传递以返回当前累积值。
    /// 如果在两个观察结果之间的时间戳调用，则返回恰好在两个观察结果之间的时间戳处的反事实累加器值。
    /// @param self 存储的Oracle数组
    /// @param time 当前区块时间戳
    /// @param secondsAgo 往回查找的时间量，以秒为单位，在哪个时间点返回一个观察结果
    /// @param tick 当前tick
    /// @param index 最近写入观察结果数组的观察索引
    /// @param liquidity 当前范围内的池流动性
    /// @param cardinality Oracle数组中填充元素的数量
    /// @return tickCumulative 自初始初始化池以来的tick * 已过时间，截至到`secondsAgo`
    /// @return secondsPerLiquidityCumulativeX128 自初始初始化池以来经过的时间/ max(1, liquidity)，截至到`secondsAgo`
    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity);
            return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
        }

        uint32 target = time - secondsAgo;

        (Observation memory beforeOrAt, Observation memory atOrAfter) = getSurroundingObservations(
            self,
            time,
            target,
            tick,
            index,
            liquidity,
            cardinality
        );

        if (target == beforeOrAt.blockTimestamp) {
            // 我们在左边界
            return (beforeOrAt.tickCumulative, beforeOrAt.secondsPerLiquidityCumulativeX128);
        } else if (target == atOrAfter.blockTimestamp) {
            // 我们在右边界
            return (atOrAfter.tickCumulative, atOrAfter.secondsPerLiquidityCumulativeX128);
        } else {
            // 我们在中间
            uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            return (
                beforeOrAt.tickCumulative +
                    ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / observationTimeDelta) *
                    targetDelta,
                beforeOrAt.secondsPerLiquidityCumulativeX128 +
                    uint160(
                        (uint256(
                            atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128
                        ) * targetDelta) / observationTimeDelta
                    )
            );
        }
    }

    /// @notice 返回每个时间点前几秒的累加器值
    /// @dev 如果`secondsAgos` > 最旧观察结果，则回滚
    /// @param self 存储的Oracle数组
    /// @param time 当前区块时间戳
    /// @param secondsAgos 要查看的时间量，以秒为单位，以返回一个观察结果的时间点
    /// @param tick 当前tick
    /// @param index 最近写入观察结果数组的观察索引
    /// @param liquidity 当前范围内的池流动性
    /// @param cardinality Oracle数组中填充元素的数量
    /// @return tickCumulatives 每个`secondsAgo`时的tick * 时间自初始化池以来经过
    /// @return secondsPerLiquidityCumulativeX128s 自初始化池以来经过的累积时间/ max(1, liquidity)，
    /// 每个`secondsAgo`时间点"
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        require(cardinality > 0, 'I');

        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(
                self,
                time,
                secondsAgos[i],
                tick,
                index,
                liquidity,
                cardinality
            );
        }
    }
}
