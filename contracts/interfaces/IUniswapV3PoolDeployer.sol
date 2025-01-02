// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 能够部署Uniswap V3池的合约接口
/// @notice 构建池的合约必须实现此接口以将参数传递给池
/// @dev 用于避免池合约中具有构造函数参数，导致池的初始代码哈希是恒定的，从而可以在链上便宜地计算池的CREATE2地址
interface IUniswapV3PoolDeployer {
    /// @notice 获取用于构建池的参数，在池创建期间临时设置。
    /// @dev 由池构造函数调用以获取池的参数
    /// Returns 工厂地址
    /// Returns 按地址排序顺序的池的第一个代币
    /// Returns 按地址排序顺序的池的第二个代币
    /// Returns 池中每次交换收取的费用，以一个bip的百分之一计价
    /// Returns 初始化的ticks之间的最小ticks数
    function parameters()
        external
        view
        returns (address factory, address token0, address token1, uint24 fee, int24 tickSpacing);
}
