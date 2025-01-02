// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Pool.sol';

import './NoDelegateCall.sol';

import './libraries/LowGasSafeMath.sol';
import './libraries/SafeCast.sol';
import './libraries/Tick.sol';
import './libraries/TickBitmap.sol';
import './libraries/Position.sol';
import './libraries/Oracle.sol';

import './libraries/FullMath.sol';
import './libraries/FixedPoint128.sol';
import './libraries/TransferHelper.sol';
import './libraries/TickMath.sol';
import './libraries/LiquidityMath.sol';
import './libraries/SqrtPriceMath.sol';
import './libraries/SwapMath.sol';

import './interfaces/IUniswapV3PoolDeployer.sol';
import './interfaces/IUniswapV3Factory.sol';
import './interfaces/IERC20Minimal.sol';
import './interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/callback/IUniswapV3SwapCallback.sol';
import './interfaces/callback/IUniswapV3FlashCallback.sol';

contract UniswapV3Pool is IUniswapV3Pool, NoDelegateCall {
    // 引入LowGasSafeMath库，用于安全的uint256数学操作
    using LowGasSafeMath for uint256;
    // 引入LowGasSafeMath库，用于安全的int256数学操作
    using LowGasSafeMath for int256;
    // 引入SafeCast库，用于类型安全的转换
    using SafeCast for uint256;
    using SafeCast for int256;
    // 引入Tick库，为映射(int24 => Tick.Info)添加辅助方法
    using Tick for mapping(int24 => Tick.Info);
    // 引入TickBitmap库，为映射(int16 => uint256)添加辅助方法
    using TickBitmap for mapping(int16 => uint256);
    // 引入Position库，为映射(bytes32 => Position.Info)添加辅助方法
    using Position for mapping(bytes32 => Position.Info);
    // 引入Position库，为Position.Info结构体添加辅助方法
    using Position for Position.Info;
    // 引入Oracle库，为长度为65535的Oracle.Observation数组添加辅助方法
    using Oracle for Oracle.Observation[65535];

    /// @inheritdoc IUniswapV3PoolImmutables
    // Uniswap V3池的工厂合约地址，不可变
    address public immutable override factory;
    /// @inheritdoc IUniswapV3PoolImmutables
    // 池中第一个代币的地址，不可变
    address public immutable override token0;
    /// @inheritdoc IUniswapV3PoolImmutables
    // 池中第二个代币的地址，不可变
    address public immutable override token1;
    /// @inheritdoc IUniswapV3PoolImmutables
    // 池中交易手续费，不可变
    uint24 public immutable override fee;

    /// @inheritdoc IUniswapV3PoolImmutables
    // 池中的最小刻度间隔，不可变
    int24 public immutable override tickSpacing;

    /// @inheritdoc IUniswapV3PoolImmutables
    // 每个刻度的最大流动性，不可变
    uint128 public immutable override maxLiquidityPerTick;

    // slot0结构体，存储池的主要状态信息
    struct Slot0 {
        // 当前价格的平方根，使用Q64.96定点数表示
        uint160 sqrtPriceX96;
        // 当前刻度
        int24 tick;
        // 观测数组的最新更新索引
        uint16 observationIndex;
        // 当前存储的最大观测值数量
        uint16 observationCardinality;
        // 下一个要存储的最大观测值数量
        uint16 observationCardinalityNext;
        // 协议费占手续费的比例，表示为1/x
        uint8 feeProtocol;
        // 池是否被锁定
        bool unlocked;
    }
    /// @inheritdoc IUniswapV3PoolState
    // 当前池的主要状态
    Slot0 public override slot0;

    /// @inheritdoc IUniswapV3PoolState
    // 全局累计手续费增长量（代币0）
    uint256 public override feeGrowthGlobal0X128;
    /// @inheritdoc IUniswapV3PoolState
    // 全局累计手续费增长量（代币1）
    uint256 public override feeGrowthGlobal1X128;

    // 协议费用结构体，记录协议累计的代币0和代币1的费用
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }
    /// @inheritdoc IUniswapV3PoolState
    // 协议累计费用
    ProtocolFees public override protocolFees;

    /// @inheritdoc IUniswapV3PoolState
    // 当前池的流动性
    uint128 public override liquidity;

    /// @inheritdoc IUniswapV3PoolState
    // 每个刻度的信息
    mapping(int24 => Tick.Info) public override ticks;
    /// @inheritdoc IUniswapV3PoolState
    // 刻度位图，标识哪些刻度已初始化
    mapping(int16 => uint256) public override tickBitmap;
    /// @inheritdoc IUniswapV3PoolState
    // 每个地址或位置的流动性信息
    mapping(bytes32 => Position.Info) public override positions;
    /// @inheritdoc IUniswapV3PoolState
    // 观测值数组，用于计算时间加权平均价格
    Oracle.Observation[65535] public override observations;

    /// @dev 互斥的重入保护，防止在池未初始化或调用方法时发生重入
    modifier lock() {
        require(slot0.unlocked, 'LOK'); // 检查池是否已解锁
        slot0.unlocked = false; // 锁定池
        _; // 执行函数主体
        slot0.unlocked = true; // 解锁池
    }

    /// @dev 限制函数只能由工厂合约的所有者调用
    modifier onlyFactoryOwner() {
        require(msg.sender == IUniswapV3Factory(factory).owner(), 'Not owner');
        _;
    }

    constructor() {
        int24 _tickSpacing;
        // 从部署者合约中获取池的初始化参数
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing; // 设置刻度间隔

        // 根据刻度间隔计算每个刻度的最大流动性
        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    /// @dev 通用的刻度输入验证
    /// @param tickLower 下限刻度
    /// @param tickUpper 上限刻度
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        require(tickLower < tickUpper, 'TLU'); // 下限刻度必须小于上限刻度
        require(tickLower >= TickMath.MIN_TICK, 'TLM'); // 下限刻度必须大于等于最小刻度
        require(tickUpper <= TickMath.MAX_TICK, 'TUM'); // 上限刻度必须小于等于最大刻度
    }

    /// @dev 返回当前区块时间的32位截断值，即 mod 2**32
    /// 该方法在测试中可以被覆盖
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // 32位截断
    }

    /// @dev 获取池中代币0的余额
    /// 此函数进行了gas优化，避免了冗余的`extcodesize`检查
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) = token0.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32); // 确保调用成功并返回足够的数据
        return abi.decode(data, (uint256)); // 解码并返回余额
    }

    /// @dev 获取池中代币1的余额
    /// 此函数进行了gas优化，避免了冗余的`extcodesize`检查
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) = token1.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32); // 确保调用成功并返回足够的数据
        return abi.decode(data, (uint256)); // 解码并返回余额
    }

    /// @inheritdoc IUniswapV3PoolDerivedState
    /// 返回两个刻度之间的累积快照数据
    /// @param tickLower 下限刻度
    /// @param tickUpper 上限刻度
    function snapshotCumulativesInside(
        int24 tickLower,
        int24 tickUpper
    )
        external
        view
        override
        noDelegateCall
        returns (int56 tickCumulativeInside, uint160 secondsPerLiquidityInsideX128, uint32 secondsInside)
    {
        checkTicks(tickLower, tickUpper); // 验证刻度输入

        // 定义变量存储下限和上限刻度的数据
        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            Tick.Info storage lower = ticks[tickLower]; // 获取下限刻度信息
            Tick.Info storage upper = ticks[tickUpper]; // 获取上限刻度信息
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower); // 确保下限刻度已初始化

            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
            require(initializedUpper); // 确保上限刻度已初始化
        }

        Slot0 memory _slot0 = slot0; // 读取当前池的状态

        // 根据当前刻度位置返回相应的累积值
        if (_slot0.tick < tickLower) {
            return (
                tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128,
                secondsOutsideLower - secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            uint32 time = _blockTimestamp(); // 获取当前时间
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time,
                0,
                _slot0.tick,
                _slot0.observationIndex,
                liquidity,
                _slot0.observationCardinality
            );
            return (
                tickCumulative - tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityCumulativeX128 -
                    secondsPerLiquidityOutsideLowerX128 -
                    secondsPerLiquidityOutsideUpperX128,
                time - secondsOutsideLower - secondsOutsideUpper
            );
        } else {
            return (
                tickCumulativeUpper - tickCumulativeLower,
                secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128,
                secondsOutsideUpper - secondsOutsideLower
            );
        }
    }

    /// @inheritdoc IUniswapV3PoolDerivedState
    /// @dev 观察并返回给定时间范围的累积数据
    /// @param secondsAgos 一个时间戳数组，表示从当前时间起的过去时间点
    /// @return tickCumulatives 累积的价格变化（tick）数组
    /// @return secondsPerLiquidityCumulativeX128s 每单位流动性累积的时间数组
    function observe(
        uint32[] calldata secondsAgos
    )
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        // 调用 observations 合约的 observe 方法获取数据
        return
            observations.observe(
                _blockTimestamp(), // 当前区块时间戳
                secondsAgos, // 过去的时间点
                slot0.tick, // 当前价格的 tick
                slot0.observationIndex, // 当前观察索引
                liquidity, // 当前流动性
                slot0.observationCardinality // 最大观测数量
            );
    }

    /// @inheritdoc IUniswapV3PoolActions
    /// @dev 增加 observationCardinalityNext 的值，以支持更多的历史观测点
    /// @param observationCardinalityNext 新的目标观测点数量
    function increaseObservationCardinalityNext(
        uint16 observationCardinalityNext
    ) external override lock noDelegateCall {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext; // 记录旧值用于事件
        // 调用 observations 合约的 grow 方法更新目标观测点数量
        uint16 observationCardinalityNextNew = observations.grow(
            observationCardinalityNextOld,
            observationCardinalityNext
        );
        // 更新 slot0 中的 observationCardinalityNext
        slot0.observationCardinalityNext = observationCardinalityNextNew;
        // 如果新旧值不同，触发事件
        if (observationCardinalityNextOld != observationCardinalityNextNew)
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }

    /// @inheritdoc IUniswapV3PoolActions
    /// @dev 初始化池子的状态（不锁定，因为它是在解锁状态下初始化）
    /// @param sqrtPriceX96 初始的平方根价格
    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, 'AI'); // 确保池子尚未初始化

        // 根据初始价格计算对应的 tick
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        // 初始化观察点
        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        // 设置池子的初始状态
        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

        // 触发初始化事件
        emit Initialize(sqrtPriceX96, tick);
    }

    /// @dev 定义一个修改头寸的参数结构体
    struct ModifyPositionParams {
        address owner; // 持有该头寸的地址
        int24 tickLower; // 头寸的下限 tick
        int24 tickUpper; // 头寸的上限 tick
        int128 liquidityDelta; // 流动性的变化量
    }

    /// @dev 修改头寸并更新相关数据
    /// @param params 包含头寸细节和流动性变化的参数
    /// @return position 指向所修改头寸的存储指针
    /// @return amount0 池子需要支付或接收的 token0 数量
    /// @return amount1 池子需要支付或接收的 token1 数量
    function _modifyPosition(
        ModifyPositionParams memory params
    ) private noDelegateCall returns (Position.Info storage position, int256 amount0, int256 amount1) {
        checkTicks(params.tickLower, params.tickUpper); // 检查传入的刻度是否有效

        Slot0 memory _slot0 = slot0; // 加载 slot0 数据以优化 gas 使用

        // 更新头寸信息
        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick
        );

        // 如果流动性有变化，则计算影响的金额
        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // 当前 tick 在范围左侧
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                // 当前 tick 在范围内
                uint128 liquidityBefore = liquidity; // 读取当前流动性

                // 写入观察点数据
                (slot0.observationIndex, slot0.observationCardinality) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                // 计算影响的 token0 和 token1 数量
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                // 更新流动性
                liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
            } else {
                // 当前 tick 在范围右侧
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    /// @dev 获取并更新头寸的流动性变化
    /// @param owner 持有该头寸的地址
    /// @param tickLower 头寸的下限 tick
    /// @param tickUpper 头寸的上限 tick
    /// @param tick 当前的 tick 值，用于优化 gas 使用
    /// @param liquidityDelta 流动性的变化量
    /// @return position 更新后的头寸信息存储指针
    function _updatePosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tick
    ) private returns (Position.Info storage position) {
        position = positions.get(owner, tickLower, tickUpper); // 获取头寸信息

        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128; // 全局 fee 增长（token0）
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128; // 全局 fee 增长（token1）

        // 如果需要更新 tick，则进行更新
        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            uint32 time = _blockTimestamp(); // 当前时间戳
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                time,
                0,
                slot0.tick,
                slot0.observationIndex,
                liquidity,
                slot0.observationCardinality
            );

            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                false,
                maxLiquidityPerTick
            );
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                true,
                maxLiquidityPerTick
            );

            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing); // 翻转位图以反映 tick 的状态变化
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing); // 翻转位图以反映 tick 的状态变化
            }
        }

        // 获取头寸范围内的 fee 增长
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks.getFeeGrowthInside(
            tickLower,
            tickUpper,
            tick,
            _feeGrowthGlobal0X128,
            _feeGrowthGlobal1X128
        );

        // 更新头寸的流动性和 fee 信息
        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        // 如果流动性减少，清除不再需要的 tick 数据
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    /// @inheritdoc IUniswapV3PoolActions
    /// @dev 通过 `_modifyPosition` 间接应用 `noDelegateCall`，禁止委托调用。
    function mint(
        address recipient, // 接收新增流动性的地址
        int24 tickLower, // 流动性范围的下界价格刻度
        int24 tickUpper, // 流动性范围的上界价格刻度
        uint128 amount, // 添加的流动性数量
        bytes calldata data // 额外数据，用于回调函数传递参数
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0); // 确保流动性数量大于 0

        // 修改指定范围内的头寸信息，返回调整后需转移的两种代币数量
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: recipient, // 头寸的所有者
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(amount).toInt128() // 流动性变化量
            })
        );

        // 将返回的 int256 类型代币数量转换为 uint256 类型
        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before; // 记录当前合约中 token0 的余额
        uint256 balance1Before; // 记录当前合约中 token1 的余额
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        // 触发回调函数以从调用者接收代币
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);

        // 确保合约余额增加的代币量与预期一致
        if (amount0 > 0) require(balance0Before.add(amount0) <= balance0(), 'M0');
        if (amount1 > 0) require(balance1Before.add(amount1) <= balance1(), 'M1');

        // 触发 Mint 事件，记录操作细节
        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    /// @inheritdoc IUniswapV3PoolActions
    function collect(
        address recipient, // 接收代币的地址
        int24 tickLower, // 头寸范围的下界价格刻度
        int24 tickUpper, // 头寸范围的上界价格刻度
        uint128 amount0Requested, // 请求提取的 token0 数量
        uint128 amount1Requested // 请求提取的 token1 数量
    ) external override lock returns (uint128 amount0, uint128 amount1) {
        // 获取指定头寸的信息
        Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);

        // 确定实际可以提取的代币数量
        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        // 如果提取的 token0 数量大于 0，则更新头寸状态并转移代币
        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        // 如果提取的 token1 数量大于 0，则更新头寸状态并转移代币
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        // 触发 Collect 事件，记录操作细节
        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }

    /// @inheritdoc IUniswapV3PoolActions
    /// @dev 通过 `_modifyPosition` 间接应用 `noDelegateCall`，禁止委托调用。
    function burn(
        int24 tickLower, // 要移除流动性的范围下界
        int24 tickUpper, // 要移除流动性的范围上界
        uint128 amount // 要移除的流动性数量
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 修改头寸，移除指定范围内的流动性，返回需要减少的代币数量
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender, // 头寸所有者
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -int256(amount).toInt128() // 流动性减少量
            })
        );

        // 将返回的负数转换为正数，表示实际减少的代币数量
        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        // 更新头寸的应得代币数量
        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        // 触发 Burn 事件，记录操作细节
        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    struct SwapCache {
        // 输入代币的协议费用（单位：百分比）
        uint8 feeProtocol;
        // 交换开始时的流动性
        uint128 liquidityStart;
        // 当前区块的时间戳
        uint32 blockTimestamp;
        // 当前价格区间的 tick 累计值（仅在跨过初始化的 tick 时计算）
        int56 tickCumulative;
        // 每单位流动性的秒数累计值（仅在跨过初始化的 tick 时计算）
        uint160 secondsPerLiquidityCumulativeX128;
        // 是否已计算并缓存上述两个累积值
        bool computedLatestObservation;
    }

    struct SwapState {
        // 剩余待交换的输入/输出资产数量
        int256 amountSpecifiedRemaining;
        // 已交换的输出/输入资产数量
        int256 amountCalculated;
        // 当前平方根价格（以 Q96 格式表示）
        uint160 sqrtPriceX96;
        // 与当前价格对应的 tick 值
        int24 tick;
        // 输入代币的全局费用增长值
        uint256 feeGrowthGlobalX128;
        // 协议费用中支付的输入代币数量
        uint128 protocolFee;
        // 当前价格范围内的流动性
        uint128 liquidity;
    }

    struct StepComputations {
        // 当前步骤开始时的平方根价格
        uint160 sqrtPriceStartX96;
        // 交换方向的下一个 tick
        int24 tickNext;
        // 下一个 tick 是否已初始化
        bool initialized;
        // 下一个 tick 的平方根价格
        uint160 sqrtPriceNextX96;
        // 当前步骤中交换的输入数量
        uint256 amountIn;
        // 当前步骤中交换的输出数量
        uint256 amountOut;
        // 当前步骤中支付的费用
        uint256 feeAmount;
    }

    function swap(
        address recipient, // 接收交换结果的地址
        bool zeroForOne, // 交换方向：true 表示从 token0 到 token1，false 反之
        int256 amountSpecified, // 交换的输入或输出数量（正值表示输入，负值表示输出）
        uint160 sqrtPriceLimitX96, // 允许的最小或最大平方根价格（根据方向判断）
        bytes calldata data // 交换回调时的附加数据
    ) external override noDelegateCall returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, 'AS'); // 确保交换数量不为 0

        Slot0 memory slot0Start = slot0; // 记录交换开始时的状态

        require(slot0Start.unlocked, 'LOK'); // 确保池子未被锁定
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            'SPL' // 确保价格限制在有效范围内
        );

        slot0.unlocked = false; // 锁定池子，防止重入攻击

        SwapCache memory cache = SwapCache({
            liquidityStart: liquidity, // 记录初始流动性
            blockTimestamp: _blockTimestamp(), // 记录当前区块时间戳
            feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
            secondsPerLiquidityCumulativeX128: 0,
            tickCumulative: 0,
            computedLatestObservation: false
        });

        bool exactInput = amountSpecified > 0; // 判断是精确输入还是精确输出

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified, // 剩余交换数量
            amountCalculated: 0, // 已交换数量初始化为 0
            sqrtPriceX96: slot0Start.sqrtPriceX96, // 初始价格
            tick: slot0Start.tick, // 初始 tick
            feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            protocolFee: 0,
            liquidity: cache.liquidityStart
        });

        // 持续交换，直到用完输入/输出数量或达到价格限制
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96; // 记录步骤开始时的价格

            // 获取下一 tick 及其初始化状态
            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                tickSpacing,
                zeroForOne
            );

            // 确保 tick 不超过最小/最大限制
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // 计算下一 tick 的价格
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // 计算步骤内的交换结果
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee
            );

            // 根据精确输入/输出更新状态
            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

            // 处理协议费用
            if (cache.feeProtocol > 0) {
                uint256 delta = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // 更新全局费用增长
            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);

            // 如果达到下一价格点，可能需要移动 tick
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    int128 liquidityNet = ticks.cross(
                        step.tickNext,
                        (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                        (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                        cache.secondsPerLiquidityCumulativeX128,
                        cache.tickCumulative,
                        cache.blockTimestamp
                    );
                    if (zeroForOne) liquidityNet = -liquidityNet;
                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // 根据交换结果更新池子状态
        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = observations.write(
                slot0Start.observationIndex,
                cache.blockTimestamp,
                slot0Start.tick,
                cache.liquidityStart,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
                state.sqrtPriceX96,
                state.tick,
                observationIndex,
                observationCardinality
            );
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;

        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token0 += state.protocolFee;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token1 += state.protocolFee;
        }

        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        // 进行资产转账和支付
        if (zeroForOne) {
            if (amount1 < 0) TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));
            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance0Before.add(uint256(amount0)) <= balance0(), 'IIA');
        } else {
            if (amount0 < 0) TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));
            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance1Before.add(uint256(amount1)) <= balance1(), 'IIA');
        }

        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        slot0.unlocked = true; // 解锁池子
    }

    /// @inheritdoc IUniswapV3PoolActions
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external override lock noDelegateCall {
        uint128 _liquidity = liquidity;
        require(_liquidity > 0, 'L');

        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        require(balance0Before.add(fee0) <= balance0After, 'F0');
        require(balance1Before.add(fee1) <= balance1After, 'F1');

        // sub is safe because we know balanceAfter is gt balanceBefore by at least fee
        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (uint128(fees0) > 0) protocolFees.token0 += uint128(fees0);
            feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity);
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (uint128(fees1) > 0) protocolFees.token1 += uint128(fees1);
            feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity);
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    /// @inheritdoc IUniswapV3PoolOwnerActions
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactoryOwner {
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) &&
                (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        uint8 feeProtocolOld = slot0.feeProtocol;
        slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    /// @inheritdoc IUniswapV3PoolOwnerActions
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock onlyFactoryOwner returns (uint128 amount0, uint128 amount1) {
        amount0 = amount0Requested > protocolFees.token0 ? protocolFees.token0 : amount0Requested;
        amount1 = amount1Requested > protocolFees.token1 ? protocolFees.token1 : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == protocolFees.token0) amount0--; // ensure that the slot is not cleared, for gas savings
            protocolFees.token0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == protocolFees.token1) amount1--; // ensure that the slot is not cleared, for gas savings
            protocolFees.token1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}
