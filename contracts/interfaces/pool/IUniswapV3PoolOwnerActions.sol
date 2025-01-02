// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 具有权限的池操作
/// @notice 包含只能由工厂所有者调用的池方法
interface IUniswapV3PoolOwnerActions {
    /// @notice 设置协议在费用中的%份额的分母
    /// @param feeProtocol0 池中token0的协议费用的新值
    /// @param feeProtocol1 池中token1的协议费用的新值
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;

    /// @notice 收取池中应计的协议费用
    /// @param recipient 应将收集的协议费用发送到的地址
    /// @param amount0Requested 要发送的token0的最大金额，可以为0以仅收集token1的费用
    /// @param amount1Requested 要发送的token1的最大金额，可以为0以仅收集token0的费用
    /// @return amount0 收集的token0中的协议费用
    /// @return amount1 收集的token1中的协议费用
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}
