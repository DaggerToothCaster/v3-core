// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Factory.sol';

import './UniswapV3PoolDeployer.sol';
import './NoDelegateCall.sol';

import './UniswapV3Pool.sol';

/// @title Canonical Uniswap V3 工厂
/// @notice 部署 Uniswap V3 矿池并管理矿池协议费用的所有权和控制权
contract UniswapV3Factory is IUniswapV3Factory, UniswapV3PoolDeployer, NoDelegateCall {
    /// @inheritdoc IUniswapV3Factory
    address public override owner;

    /// @inheritdoc IUniswapV3Factory
    // 状态变量：feeAmountTickSpacing
    // 合约：UniswapV3Factory
    /// @inheritdoc IUniswapV3Factory
    /// @notice 返回给定费用金额的标记间距（如果已启用），否则返回0
    /// @dev 费用金额永远不会被删除，因此这个值应该在调用上下文中被硬编码或缓存
    /// @param fee 启用的费用，以百分之一的bip为单位。如果费用未启用，则返回0
    /// @return 标记间距
    mapping(uint24 => int24) public override feeAmountTickSpacing;

    /// @inheritdoc IUniswapV3Factory
    /// @notice 返回给定令牌对和费用的池地址，如果不存在则返回地址0
    /// @dev 令牌A和令牌B可以传递在token0/token1或token1/token0顺序
    /// @param tokenA 池中的token0或token1合约地址
    /// @param tokenB 另一个令牌的合约地址
    /// @param fee 池中每次交换收取的费用，以百分之一的bip为单位
    /// @return pool 池地址
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);

        feeAmountTickSpacing[500] = 10;
        emit FeeAmountEnabled(500, 10);
        feeAmountTickSpacing[3000] = 60;
        emit FeeAmountEnabled(3000, 60);
        feeAmountTickSpacing[10000] = 200;
        emit FeeAmountEnabled(10000, 200);
    }

    /// @inheritdoc IUniswapV3Factory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        require(tokenA != tokenB);
        // 对token 进行排序
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // 校验token0是否为0地址
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        // 保证指定的费用金额已启用
        require(tickSpacing != 0);
        // 校验池是否已经存在
        require(getPool[token0][token1][fee] == address(0));
        // 创建池
        pool = deploy(address(this), token0, token1, fee, tickSpacing);
        // 设置池信息
        getPool[token0][token1][fee] = pool;
        // 反向设置池信息
        getPool[token1][token0][fee] = pool;
        // 触发事件
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }

    /// @inheritdoc IUniswapV3Factory
    function setOwner(address _owner) external override {
        // 校验调用者是否为合约所有者
        require(msg.sender == owner);
        // 触发事件
        emit OwnerChanged(owner, _owner);
        // 转让合约所有者
        owner = _owner;
    }

    /// @inheritdoc IUniswapV3Factory
    /// @notice 启用一个新的手续费级别（fee amount）和对应的 tick 间距（tick spacing）。
    /// @dev 这个函数只能由合约所有者调用，用于动态添加新的手续费选项。
    function enableFeeAmount(uint24 fee, int24 tickSpacing) public override {
        // 确保函数调用者是合约所有者
        // 只有合约所有者才有权限启用新的手续费选项
        require(msg.sender == owner, 'Caller is not the owner');

        // 验证手续费值是否小于 1000000（百万分之一级别的最大值）
        // 这是为了确保手续费值在合理范围内
        require(fee < 1000000, 'Fee must be less than 1000000');

        // 验证 tick 间距是否在合理范围内
        // tick 间距的最大值被限制为 16384，这是为了避免在计算过程中出现溢出
        // 如果 tick 间距过大，`TickBitmap#nextInitializedTickWithinOneWord` 方法可能会导致 int24 类型的溢出
        // 最大值 16384 对应于 1 bips（1 基点）情况下的 >5 倍价格变化，这已足够覆盖绝大部分场景
        require(tickSpacing > 0 && tickSpacing < 16384, 'Tick spacing must be >0 and <16384');

        // 确保当前的手续费级别尚未启用
        // 如果 `feeAmountTickSpacing[fee]` 不为 0，说明这个手续费级别已经存在
        require(feeAmountTickSpacing[fee] == 0, 'Fee amount already enabled');

        // 将 tick 间距与对应的手续费值关联
        // 在 `feeAmountTickSpacing` 映射中存储 fee -> tickSpacing 的映射关系
        feeAmountTickSpacing[fee] = tickSpacing;

        // 触发事件通知外部，新的手续费级别已被启用
        emit FeeAmountEnabled(fee, tickSpacing);
    }
}
