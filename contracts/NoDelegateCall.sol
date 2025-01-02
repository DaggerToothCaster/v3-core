// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

/// @title 防止对合约的 delegatecall
/// @notice 提供一个基类合约，包含一个修饰器，用于防止对子合约方法的 delegatecall
abstract contract NoDelegateCall {
    /// @dev 存储合约的原始地址（即部署时的地址）
    ///      使用 `immutable` 修饰符，表示该变量的值只能在合约构造函数中初始化，并且在部署后不可更改。
    address private immutable original;

    /// @dev 构造函数，用于初始化合约的原始地址
    constructor() {
        // `immutable` 类型的变量在合约的初始化代码中计算，并直接嵌入到已部署的字节码中。
        // 这意味着部署后检查时，此变量的值不会发生变化。
        original = address(this);
    }

    /// @dev 检查当前调用是否为 delegatecall
    ///      使用 `private` 修饰符确保该函数仅在本合约内部调用。
    ///      不将逻辑直接内联到修饰器中的原因是：
    ///      1. 修饰器会被复制到每个被修饰的方法中。
    ///      2. 如果内联，`immutable` 变量的地址字节会被多次复制，导致效率降低。
    function checkNotDelegateCall() private view {
        // 检查当前合约地址是否与原始地址一致。
        // 如果发生 delegatecall，`address(this)` 将指向调用者的地址而非原始地址，从而触发 `require`。
        require(address(this) == original, "NoDelegateCall: delegatecall not allowed");
    }

    /// @notice 防止 delegatecall 调用被修饰的方法
    /// @dev 如果在被修饰的方法中发生 delegatecall，将抛出异常
    modifier noDelegateCall() {
        checkNotDelegateCall(); // 调用检查函数，确保当前调用未发生 delegatecall
        _; // 执行被修饰的函数逻辑
    }
}
