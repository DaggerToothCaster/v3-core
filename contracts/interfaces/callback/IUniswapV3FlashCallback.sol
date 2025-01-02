// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title IUniswapV3PoolActions#flash的回调
/// @notice 任何调用IUniswapV3PoolActions#flash的合约必须实现此接口
interface IUniswapV3FlashCallback {
    /// @notice 在从IUniswapV3Pool#flash转账给接收者后调用`msg.sender`
    /// @dev 在实现中，您必须偿还通过flash发送的代币以及计算的费用金额给池子。
    /// 必须检查调用此方法的调用者是否为由规范UniswapV3Factory部署的UniswapV3Pool。
    /// @param fee0 到flash结束时池子应支付的token0中的费用金额
    /// @param fee1 到flash结束时池子应支付的token1中的费用金额
    /// @param data 通过IUniswapV3PoolActions#flash调用者传递的任何数据
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external;
}