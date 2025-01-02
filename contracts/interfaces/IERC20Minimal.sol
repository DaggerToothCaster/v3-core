
// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 用于Uniswap的最小ERC20接口
/// @notice 包含Uniswap V3中使用的完整ERC20接口的子集
interface IERC20Minimal {
    /// @notice 返回代币的余额
    /// @param account 要查找其代币数量（即余额）的账户
    /// @return 账户持有的代币数量
    function balanceOf(address account) external view returns (uint256);

    /// @notice 将代币金额从`msg.sender`转移到接收方
    /// @param recipient 将接收转移金额的账户
    /// @param amount 从发送方发送到接收方的代币数量
    /// @return 转移成功返回true，失败返回false
    function transfer(address recipient, uint256 amount) external returns (bool);

    /// @notice 返回所有者授予给支出者的当前授权额度
    /// @param owner 代币所有者的账户
    /// @param spender 代币支出者的账户
    /// @return 所有者授予给支出者的当前授权额度
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice 将`msg.sender`给定的支出者的授权额度设置为`amount`
    /// @param spender 将被允许花费所有者代币的账户
    /// @param amount 允许`spender`使用的代币数量
    /// @return 授权成功返回true，失败返回false
    function approve(address spender, uint256 amount) external returns (bool);

    /// @notice 将`sender`到`recipient`之间的`amount`代币数量根据`msg.sender`给出的授权额度进行转移
    /// @param sender 进行转账的账户
    /// @param recipient 转账的接收方
    /// @param amount 转账的数量
    /// @return 转账成功返回true，失败返回false
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /// @notice 当代币从一个地址传输到另一个地址时发出的事件，无论是通过`#transfer`还是`#transferFrom`。
    /// @param from 发送代币的账户，即余额减少的账户
    /// @param to 接收代币的账户，即余额增加的账户
    /// @param value 被传输的代币数量
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice 当给定所有者代币的支出者的授权额度发生变化时发出的事件。
    /// @param owner 批准花费其代币的账户
    /// @param spender 修改了支出者的花费授权额度的账户
    /// @param value 所有者授予给支出者的新授权额度
    event Approval(address indexed owner, address indexed spender, uint256 value);
}