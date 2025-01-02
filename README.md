译文：""
# Uniswap V3

[![Lint](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/lint.yml/badge.svg)](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/lint.yml)
[![Tests](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/tests.yml/badge.svg)](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/tests.yml)
[![Fuzz Testing](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/fuzz-testing.yml/badge.svg)](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/fuzz-testing.yml)
[![Mythx](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/mythx.yml/badge.svg)](https://github.com/Uniswap/uniswap-v3-core/actions/workflows/mythx.yml)
[![npm version](https://img.shields.io/npm/v/@uniswap/v3-core/latest.svg)](https://www.npmjs.com/package/@uniswap/v3-core/v/latest)

本存储库包含Uniswap V3协议的核心智能合约。
要查看更高级别的合约，请参阅[uniswap-v3-periphery](https://github.com/Uniswap/uniswap-v3-periphery)
存储库。

## 漏洞赏金

本存储库受Uniswap V3漏洞赏金计划约束，详细条款请参阅[此处](./bug-bounty.md)。

## 本地部署

为了将该代码部署到本地测试网络，您应安装npm包
`@uniswap/v3-core`
并导入位于
`@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json` 的工厂字节码。
例如：

```typescript
import {
  abi as FACTORY_ABI,
  bytecode as FACTORY_BYTECODE,
} from '@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json'

// 部署字节码
```

这将确保您测试与部署到主网和公共测试网络的相同字节码，并且所有Uniswap代码将正确与您的本地部署互操作。

## 使用solidity接口

Uniswap v3接口可通过npm工件`@uniswap/v3-core`导入solidity智能合约，例如：

```solidity
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

contract MyContract {
  IUniswapV3Pool pool;

  function doSomethingWithPool() {
    // pool.swap(...);
  }
}

```

## 许可

Uniswap V3 Core的主要许可是商业源代码许可1.1 (`BUSL-1.1`), 参见 [`LICENSE`](./LICENSE)。但是，某些文件也采用`GPL-2.0或更高版本`双许可：

- `contracts/interfaces/` 中的所有文件也可能受 `GPL-2.0-or-later` 许可 (如其SPDX头部中指示的那样)，请参见 [`contracts/interfaces/LICENSE`](./contracts/interfaces/LICENSE)
- `contracts/libraries/` 中的几个文件也可能受 `GPL-2.0-or-later` 许可 (如其SPDX头部中指示的那样)，请参见 [`contracts/libraries/LICENSE`](contracts/libraries/LICENSE)

### 其他例外

- `contracts/libraries/FullMath.sol` 受 `MIT` 许可，(如其SPDX头部中指示的那样)，请参见 [`contracts/libraries/LICENSE_MIT`](contracts/libraries/LICENSE_MIT)
- `contracts/test` 中的所有文件保持未授权 (如其SPDX头部中指示的那样)。