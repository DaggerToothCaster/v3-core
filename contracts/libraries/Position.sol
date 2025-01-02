// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './FixedPoint128.sol';
import './LiquidityMath.sol';

/// @title Position
/// @notice 位置表示所有者地址在较低和较高tick边界之间的流动性
/// @dev 位置存储额外状态以跟踪欠位置所有者的费用
library Position {
    // 每个用户位置存储的信息
    struct Info {
        // 该位置拥有的流动性数量
        uint128 liquidity;
        // 截至到最后一次更新流动性或应付费用时，每单位流动性的费用增长
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // 应付给位置所有者的费用，以token0/token1表示
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @notice 给定所有者和位置边界，返回一个位置的Info结构
    /// @param self 包含所有用户位置的映射
    /// @param owner 位置所有者的地址
    /// @param tickLower 位置的下限tick边界
    /// @param tickUpper 位置的上限tick边界
    /// @return 位置 给定所有者位置的位置信息结构
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
    }

    /// @notice 将累积的费用记入用户的位置
    /// @param self 要更新的个别位置
    /// @param liquidityDelta 由于位置更新而导致的流动性变化
    /// @param feeGrowthInside0X128 在位置的tick边界内，token0的全部时间费用增长，每单位流动性
    /// @param feeGrowthInside1X128 在位置的tick边界内，token1的全部时间费用增长，每单位流动性
    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        Info memory _self = self;

        uint128 liquidityNext;
        if (liquidityDelta == 0) {
            require(_self.liquidity > 0, 'NP'); // 不允许对流动性为0的位置进行操作
            liquidityNext = _self.liquidity;
        } else {
            liquidityNext = LiquidityMath.addDelta(_self.liquidity, liquidityDelta);
        }

        // 计算累积费用
        uint128 tokensOwed0 =
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0X128 - _self.feeGrowthInside0LastX128,
                    _self.liquidity,
                    FixedPoint128.Q128
                )
            );
        uint128 tokensOwed1 =
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1X128 - _self.feeGrowthInside1LastX128,
                    _self.liquidity,
                    FixedPoint128.Q128
                )
            );

        // 更新位置
        if (liquidityDelta != 0) self.liquidity = liquidityNext;
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            // 溢出是可接受的，必须在达到type(uint128).max费用之前提取
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }
}