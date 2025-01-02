
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Uniswap V3工厂接口
/// @notice Uniswap V3工厂用于创建Uniswap V3池并控制协议费用
interface IUniswapV3Factory {
    /// @notice 当工厂的所有者更改时触发
    /// @param oldOwner 所有者在所有者更改之前的地址
    /// @param newOwner 所有者在所有者更改之后的地址
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    /// @notice 当创建一个池时触发
    /// @param token0 池中的第一个令牌按地址排序
    /// @param token1 池中的第二个令牌按地址排序
    /// @param fee 池中每次交换收取的费用，以百分之一的bip为单位
    /// @param tickSpacing 初始化标记之间的最小标记数
    /// @param pool 创建的池的地址
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint24 indexed fee,
        int24 tickSpacing,
        address pool
    );

    /// @notice 当启用新的费用金额用于通过工厂创建池时触发
    /// @param fee 启用的费用，以百分之一的bip为单位
    /// @param tickSpacing 使用给定费用创建的池中初始化标记之间的最小标记数
    event FeeAmountEnabled(uint24 indexed fee, int24 indexed tickSpacing);

    /// @notice 返回工厂的当前所有者
    /// @dev 可通过setOwner方法由当前所有者更改
    /// @return 工厂所有者的地址
    function owner() external view returns (address);

    /// @notice 返回给定费用金额的标记间距（如果已启用），否则返回0
    /// @dev 费用金额永远不会被删除，因此这个值应该在调用上下文中被硬编码或缓存
    /// @param fee 启用的费用，以百分之一的bip为单位。如果费用未启用，则返回0
    /// @return 标记间距
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    /// @notice 返回给定令牌对和费用的池地址，如果不存在则返回地址0
    /// @dev 令牌A和令牌B可以传递在token0/token1或token1/token0顺序
    /// @param tokenA 池中的token0或token1合约地址
    /// @param tokenB 另一个令牌的合约地址
    /// @param fee 池中每次交换收取的费用，以百分之一的bip为单位
    /// @return pool 池地址
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    /// @notice 为给定的两个令牌和费用创建一个池
    /// @param tokenA 所需池中的两个令牌中的一个
    /// @param tokenB 所需池中的另一个令牌
    /// @param fee 池的期望费用
    /// @dev 可以按任何顺序传递tokenA和tokenB：token0/token1或token1/token0。tickSpacing从费用中检索
    /// 如果池已经存在、费用无效或令牌参数无效，则调用将失败。
    /// @return pool 新创建的池的地址
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);

    /// @notice 更新工厂的所有者
    /// @dev 必须由当前所有者调用
    /// @param _owner 工厂的新所有者
    function setOwner(address _owner) external;

    /// @notice 启用具有给定tickSpacing的费用金额
    /// @dev 一旦启用，费用金额永远不会被删除
    /// @param fee 要启用的费用金额，以百分之一的bip为单位（即1e-6）
    /// @param tickSpacing 对于所有使用给定费用金额创建的池，要强制执行的ticks之间的间距
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}