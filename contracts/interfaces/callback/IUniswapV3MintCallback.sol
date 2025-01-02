// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IUniswapV3PoolActions#mint的回调
/// @notice 任何调用IUniswapV3PoolActions#mint的合约必须实现此接口
interface IUniswapV3MintCallback {
    /// @notice 在从IUniswapV3Pool#mint向仓位铸造流动性后调用`msg.sender`
    /// @dev 在实现中，您必须支付铸造流动性所欠的代币给池子。
    /// 必须检查调用此方法的调用者是否为由规范UniswapV3Factory部署的UniswapV3Pool。
    /// @param amount0Owed 铸造流动性所欠给池子的token0数量
    /// @param amount1Owed 铸造流动性所欠给池子的token1数量
    /// @param data 通过IUniswapV3PoolActions#mint调用者传递的任何数据
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}