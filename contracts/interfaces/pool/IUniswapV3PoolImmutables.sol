// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 池状态永不更改
/// @notice 这些参数对于池来说是永久固定的，即，这些方法将永远返回相同的值
interface IUniswapV3PoolImmutables {
    /// @notice 部署池的合约，必须遵守IUniswapV3Factory接口
    /// @return 合约地址
    function factory() external view returns (address);

    /// @notice 池中两个代币中较小的一个，按地址排序
    /// @return 代币合约地址
    function token0() external view returns (address);

    /// @notice 池中两个代币中较大的一个，按地址排序
    /// @return 代币合约地址
    function token1() external view returns (address);

    /// @notice 池的费用，以百分之一bip为单位，即1e-6
    /// @return 费用
    function fee() external view returns (uint24);

    /// @notice 池刻度间隔
    /// @dev 刻度只能以此值的倍数使用，最小为1，始终为正值
    /// 例如：刻度间隔为3意味着刻度可以每3个刻度初始化一次，即，...，-6，-3，0，3，6，...
    /// 这个值是int24类型，以避免强制转换，尽管它始终为正值
    /// @return 刻度间隔
    function tickSpacing() external view returns (int24);

    /// @notice 每个范围内可以使用的位置流动性的最大数量
    /// @dev 此参数对于每个刻度进行了强制执行，以防止流动性在任何时候溢出uint128，并
    /// 也防止超出范围的流动性被使用，以防止向池中添加超范围内的流动性
    /// @return 每个刻度的最大流动性量
    function maxLiquidityPerTick() external view returns (uint128);
}
