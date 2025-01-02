// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 具有可变状态的池状态
/// @notice 这些方法构成了池的状态，并且可以在任何频率下更改，包括每笔交易中多次更改
interface IUniswapV3PoolState {
    /// @notice 池中的第0个存储槽存储许多值，并且作为单个方法暴露以节省gas
    /// 当外部访问时。
    /// @return sqrtPriceX96 池的当前价格，作为sqrt(token1/token0) Q64.96值
    /// tick 池的当前tick，即最后运行的tick过渡所指示的值。
    /// 如果价格在tick边界上，则此值可能并不总是等于SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96)。
    /// observationIndex 写入的最后一个oracle观察的索引，
    /// observationCardinality 池中存储的当前最大观察数量，
    /// observationCardinalityNext 下一个要更新的最大观察数量，当观察被更新时。
    /// feeProtocol 池中两个token的协议费用。
    /// 编码为两个4位值，其中token1的协议费用向左移动4位，token0的协议费用是较低的4位。
    /// 作为交易费用分数的分母，例如，4表示交易费用的1/4。
    /// unlocked 池当前是否被锁定以避免递归调用
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    /// @notice 作为Q128.128的fee增长，表示池的整个生命周期中每单位流动性收集的token0的费用
    /// @dev 此值可以溢出uint256
    function feeGrowthGlobal0X128() external view returns (uint256);

    /// @notice 作为Q128.128的fee增长，表示池的整个生命周期中每单位流动性收集的token1的费用
    /// @dev 此值可以溢出uint256
    function feeGrowthGlobal1X128() external view returns (uint256);

    /// @notice 应支付给协议的token0和token1的金额
    /// @dev 协议费用在任一token中永远不会超过uint128的最大值
    function protocolFees() external view returns (uint128 token0, uint128 token1);

    /// @notice 池中当前可用的流动性
    /// @dev 此值与所有tick中的总流动性无关
    function liquidity() external view returns (uint128);

    /// @notice 查找池中特定tick的信息
    /// @param tick 要查找的tick
    /// @return liquidityGross 使用池作为tick下限或tick上限的所有仓位流动性的总量，
    /// liquidityNet 当池价格穿过tick时流动性的变化量，
    /// feeGrowthOutside0X128 在当前tick的另一侧从tick边界开始的token0上的fee增长，
    /// feeGrowthOutside1X128 在当前tick的另一侧从tick边界开始的token1上的fee增长，
    /// tickCumulativeOutside 在当前tick的另一侧tick的累积值，
    /// secondsPerLiquidityOutsideX128 在当前tick的另一侧的每单位流动性花费的秒数，
    /// secondsOutside 在当前tick的另一侧花费的秒数，
    /// initialized 如果tick已初始化，则设置为true，即liquidityGross大于0，否则等于false。
    /// 只有在tick初始化后（即liquidityGross大于0）才能使用外部值。
    /// 此外，这些值仅相对，必须仅与特定仓位以前的快照进行比较使用。
    function ticks(
        int24 tick
    )
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        );

    /// @notice 返回256个打包的tick初始化布尔值。有关更多信息，请参阅TickBitmap
    function tickBitmap(int16 wordPosition) external view returns (uint256);

    /// @notice 根据仓位的key返回有关仓位的信息
    /// @param key 仓位的key是由所有者、tick下限和tick上限组成的预影像的哈希
    /// @return _liquidity 仓位中的流动性量，
    /// 返回feeGrowthInside0LastX128 tick范围内token0的最后一个铸造/燃烧/poke时的费用增长，
    /// 返回feeGrowthInside1LastX128 tick范围内token1的最后一个铸造/燃烧/poke时的费用增长，
    /// 返回tokensOwed0 根据最后一个铸造/燃烧/poke时计算的应支付给该仓位的token0量，
    /// 返回tokensOwed1 根据最后一个铸造/燃烧/poke时计算的应支付给该仓位的token1量
    function positions(
        bytes32 key
    )
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    /// @notice 根据特定观察索引返回有关观察的数据
    /// @param index 要获取的observations数组的元素
    /// @dev 您可能更倾向于使用#observe()而不是此方法，以获取特定时间点（而不是在数组中特定索引处）的观察值。
    /// @return blockTimestamp 观察的时间戳，
    /// 返回tickCumulative 观察时池的tick乘以经过的秒数的累积值，
    /// 返回secondsPerLiquidityCumulativeX128 池中在观察时间戳处的每单位流动性的累积秒数，
    /// 返回initialized 观察是否已初始化，且值可安全使用
    function observations(
        uint256 index
    )
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        );
}
