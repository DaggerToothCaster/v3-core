// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import '../interfaces/IERC20Minimal.sol';

/// @title TransferHelper
/// @notice 包含用于与不一致返回true/false的ERC20代币互动的辅助方法
library TransferHelper {
    /// @notice 从msg.sender转移代币到接收者
    /// @dev 在代币合约上调用transfer，如果转移失败则抛出错误
    /// @param token 将要转移的代币的合约地址
    /// @param to 转移的接收者
    /// @param value 转移的价值

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TF');
    }
}
