// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title 无需许可的池操作
/// @notice 包含任何人都可以调用的池方法
interface IUniswapV3PoolActions {
    /// @notice 设置池的初始价格
    /// @dev 价格以sqrt(amountToken1/amountToken0) Q64.96值表示
    /// @param sqrtPriceX96 池的初始sqrt价格，以Q64.96表示
    function initialize(uint160 sqrtPriceX96) external;

    /// @notice 为给定的recipient/tickLower/tickUpper位置增加流动性
    /// @dev 调用此方法的调用者会接收一个回调，形式为IUniswapV3MintCallback#uniswapV3MintCallback
    /// 在回调中，他们必须支付任何流动性所欠的token0或token1。所欠的token0/token1的金额取决于tickLower、tickUpper、流动性量和当前价格。
    /// @param recipient 将创建流动性的地址
    /// @param tickLower 要添加流动性的位置的较低tick
    /// @param tickUpper 要添加流动性的位置的较高tick
    /// @param amount 要铸造的流动性量
    /// @param data 应传递到回调的任何数据
    /// @return amount0 支付以铸造给定流动性量所需的token0量。与回调中的值匹配
    /// @return amount1 支付以铸造给定流动性量所需的token1量。与回调中的值匹配
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice 收集应付给位置的代币
    /// @dev 不重新计算已赚取的费用，必须通过任意数量的流动性的铸造或销毁来执行。
    /// 收集必须由位置所有者调用。若要仅提取token0或仅提取token1，amount0Requested或amount1Requested可以设置为零。
    /// 要提取所有应付的代币，调用者可以传递大于实际应付代币的任何值，例如type(uint128).max。应付的代币可能来自累积的交换费或销毁的流动性。
    /// @param recipient 应收取收集费用的地址
    /// @param tickLower 要收集费用的位置的较低tick
    /// @param tickUpper 要收集费用的位置的较高tick
    /// @param amount0Requested 应从应付费用中提取的token0数量
    /// @param amount1Requested 应从应付费用中提取的token1数量
    /// @return amount0 提取的token0的费用量
    /// @return amount1 提取的token1的费用量
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    /// @notice 从发送方销毁流动性并为位置的代币应付利息
    /// @dev 可用于通过以数量为0调用触发对位置的应付费用的重新计算
    /// @dev 费用必须通过调用#collect单独收取
    /// @param tickLower 要销毁流动性的位置的较低tick
    /// @param tickUpper 要销毁流动性的位置的较高tick
    /// @param amount 要销毁的流动性量
    /// @return amount0 发送给收件人的token0量
    /// @return amount1 发送给收件人的token1量
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice 将token0兑换为token1，或将token1兑换为token0
    /// @dev 调用此方法的调用者会接收一个回调，形式为IUniswapV3SwapCallback#uniswapV3SwapCallback
    /// @param recipient 接收兑换输出的地址
    /// @param zeroForOne 兑换的方向，对于token0到token1为true，对于token1到token0为false
    /// @param amountSpecified 兑换的数量，隐式配置为精确输入（正数），或精确输出（负数）
    /// @param sqrtPriceLimitX96 Q64.96平方根价格限制。如果为零为one，则兑换后的价格不得低于这个值。
    /// 如果为one为zero，则兑换后的价格不得高于这个值。
    /// @param data 应传递到回调的任何数据
    /// @return amount0 池子的token0余额的变化量，负数时为精确，正数时为最小值
    /// @return amount1 池子的token1余额的变化量，负数时为精确，正数时为最小值
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice 接收token0和/或token1，并在回调中支付它们以及手续费
    /// @dev 调用此方法的调用者会接收一个回调，形式为IUniswapV3FlashCallback#uniswapV3FlashCallback
    /// @dev 可通过以0数量{0,1}调用，从回调中发送捐赠的底层代币按比例分配给当前在范围内的流动性提供者
    /// @param recipient 将接收token0和token1量的地址
    /// @param amount0 要发送的token0量
    /// @param amount1 要发送的token1量
    /// @param data 应传递到回调的任何数据
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    /// @notice 增加此池将存储的价格和流动性观察次数的最大数量
    /// @dev 如果池已经具有大于或等于输入observationCardinalityNext的observationCardinalityNext，则此方法无效。
    /// @param observationCardinalityNext 池应存储的最小观察次数
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}