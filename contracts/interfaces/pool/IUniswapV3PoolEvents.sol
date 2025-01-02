
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 由池发出的事件
/// @notice 包含池发出的所有事件
interface IUniswapV3PoolEvents {
    /// @notice 当池首次调用#initialize时，池会发出一次
    /// @dev 在初始化之前，池不能发出Mint/Burn/Swap
    /// @param sqrtPriceX96 池的初始平方根价格，作为Q64.96
    /// @param tick 池的初始刻度，即池起始价格的log base 1.0001
    event Initialize(uint160 sqrtPriceX96, int24 tick);

    /// @notice 当为特定位置铸币时发出
    /// @param sender 铸造流动性的地址
    /// @param owner 位置的所有者和任何铸币流动性的接收者
    /// @param tickLower 位置的下限刻度
    /// @param tickUpper 位置的上限刻度
    /// @param amount 铸币到位置范围的流动性量
    /// @param amount0 铸造流动性所需的token0数量
    /// @param amount1 铸造流动性所需的token1数量
    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice 位置所有者收取费用时发出
    /// @dev 当调用者选择不收取费用时，收取事件可能会发出零amount0和amount1
    /// @param owner 收取费用的位置所有者
    /// @param tickLower 位置的下限刻度
    /// @param tickUpper 位置的上限刻度
    /// @param amount0 收取的token0费用数量
    /// @param amount1 收取的token1费用数量
    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount0,
        uint128 amount1
    );

    /// @notice 当移除位置的流动性时发出
    /// @dev 不会提取流动性位置赚取的任何费用，必须通过#collect提取
    /// @param owner 移除流动性的位置所有者
    /// @param tickLower 位置的下限刻度
    /// @param tickUpper 位置的上限刻度
    /// @param amount 要移除的流动性量
    /// @param amount0 提取的token0数量
    /// @param amount1 提取的token1数量
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice 由池发出的任何token0和token1之间的交换
    /// @param sender 启动交换调用并接收回调的地址
    /// @param recipient 接收交换输出的地址
    /// @param amount0 池的token0余额变化量
    /// @param amount1 池的token1余额变化量
    /// @param sqrtPriceX96 交换后池的sqrt(price)，作为Q64.96
    /// @param liquidity 交换后池的流动性
    /// @param tick 交换后池价格的log base 1.0001
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    /// @notice 由池发出的任何token0/token1的闪光
    /// @param sender 启动交换调用并接收回调的地址
    /// @param recipient 接收闪光中的代币的地址
    /// @param amount0 闪光的token0数量
    /// @param amount1 闪光的token1数量
    /// @param paid0 用于闪光的token0金额，可以超过amount0加上费用
    /// @param paid1 用于闪光的token1金额，可以超过amount1加上费用
    event Flash(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 paid0,
        uint256 paid1
    );

    /// @notice 由池发出的可存储的观察次数增加
    /// @dev observationCardinalityNext不是观察次数，直到在mint/swap/burn之前写入观察
    /// @param observationCardinalityNextOld 下一个观察次数的先前值
    /// @param observationCardinalityNextNew 下一个观察次数的更新值
    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld,
        uint16 observationCardinalityNextNew
    );

    /// @notice 当池更改协议费时发出
    /// @param feeProtocol0Old token0协议费的先前值
    /// @param feeProtocol1Old token1协议费的先前值
    /// @param feeProtocol0New token0协议费的更新值
    /// @param feeProtocol1New token1协议费的更新值
    event SetFeeProtocol(uint8 feeProtocol0Old, uint8 feeProtocol1Old, uint8 feeProtocol0New, uint8 feeProtocol1New);

    /// @notice 工厂所有者提取已收取的协议费时发出
    /// @param sender 收取协议费的地址
    /// @param recipient 收到已收取的协议费的地址
    /// @param amount0 提取的token0协议费数量
    /// @param amount0 提取的token1协议费数量
    event CollectProtocol(address indexed sender, address indexed recipient, uint128 amount0, uint128 amount1);
}