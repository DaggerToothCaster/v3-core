// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IUniswapV3PoolActions#swap的回调
/// @notice 任何调用IUniswapV3PoolActions#swap的合约必须实现此接口
interface IUniswapV3SwapCallback {
    /// @notice 在通过IUniswapV3Pool#swap执行交换后调用`msg.sender`
    /// @dev 在实现中，您必须支付交换所欠的池子代币。
    /// 必须检查调用此方法的调用者是否为由规范UniswapV3Factory部署的UniswapV3Pool。
    /// 如果没有代币被交换，amount0Delta和amount1Delta都可以是0。
    /// @param amount0Delta 通过交换发送（负数）或必须在交换结束时接收（正数）的token0数量。如果为正数，回调函数必须将该数量的token0发送给池子。
    /// @param amount1Delta 通过交换发送（负数）或必须在交换结束时接收（正数）的token1数量。如果为正数，回调函数必须将该数量的token1发送给池子。
    /// @param data 通过IUniswapV3PoolActions#swap调用者传递的任何数据
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}