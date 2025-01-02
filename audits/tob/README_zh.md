译文：
以下内容包含了Trail of Bits编写的属性。

- [使用Echidna进行端到端测试](#end-to-end-testing-with-echidna)
- [使用Manticore进行验证](#verification-with-manticore)

# 使用Echidna进行端到端测试

我们已为Uniswap V3 Core池合约实现了端到端属性。

## 安装

为了运行此程序，您需要安装[echidna 1.7.0](https://github.com/crytic/echidna/releases/tag/v1.7.0)。

## 运行

假设您在存储库的根目录中

```
echidna-test contracts/crytic/echidna/E2E_swap.sol --config contracts/crytic/echidna/E2E_swap.config.yaml --contract E2E_swap

echidna-test contracts/crytic/echidna/E2E_mint_burn.sol --config contracts/crytic/echidna/E2E_mint_burn.config.yaml --contract E2E_mint_burn

echidna-test contracts/crytic/echidna/Other.sol --config contracts/crytic/echidna/Other.config.yaml --contract Other
```

## 随机但有效的池初始化、创建位置和价格限制

为了帮助Echidna获得良好的覆盖率，我们使用多个辅助函数来：

- 在进行交换或铸造/销毁之前，创建随机但有效的池初始化参数（费用、tickSpacing、初始价格）[链接](./E2E_mint_burn.sol#L303-L337) [链接](./E2E_swap.sol#L196-L230)
- 在测试交换之前，创建一个随机数量的随机但有效的位置[链接](./E2E_swap.sol#L233-L283)
- 在进行交换时创建一个随机但有效的价格限制[链接](./E2E_swap.sol#L68-L80)
- 在进行铸造时创建随机但有效的位置参数[链接](./E2E_mint_burn.sol#L102-L130)

通过上述方法，Echidna将能够测试我们想要测试的实际属性，而不是使用无效的价格限制或无效的位置参数。上述方法还允许在执行交换之前创建动态数量的随机位置，而不是使用静态列表。

为了实现上述随机但有效的结果，我们使用`uint128 _amount`作为交换/铸造/销毁的种子，在辅助函数中创建随机性。这也意味着检索所使用参数并不是非常直接。但是，通过结合hardhat `console.sol`和编写一个小的js单元测试，可以检索每次（一组）调用的确切使用参数。

## 调整 hardhat.config.ts

由于构造函数中包含所有调用，Echidna合约的部署成本过高。

调整 `hardhat.config.ts` 为：

```json
hardhat: {
    allowUnlimitedContractSize: true,
    gas: 950000000,
    blockGasLimit: 950000000,
    gasPrice: 1,
},
```

### E2E_swap：检索池初始化参数和创建的位置

池初始化和创建的位置是确定性的，有一个`view`函数会返回一个特定 `_amount`（用作 `_seed`）将创建的内容。

编写一个js单元测试：

```js
console.log(await E2E_swap.viewRandomInit('<第一个交换调用的 _amount>'))
```

### E2E_swap：检索交换的使用价格限制

价格限制取决于池合约的状态，因此最容易通过使用hardhat的 `console.sol` 来检索。

取消注释以下行：

- 在 `E2E_swap.sol` 的顶部：`// import 'hardhat/console.sol';`
- 在交换函数内部：`// console.log('sqrtPriceLimitX96 = %s', sqrtPriceLimitX96); `

假设Echidna报告两次交换调用，第二次调用导致断言失败。

```js
// 获取池参数 + 创建的位置
console.log(await E2E_swap.viewRandomInit('<第一个交换调用的 _amount>'))

// 执行交换，这将创建上述内容并将使用的价格限制记录到控制台
await E2E_swap.test_swap_exactOut_oneForZero('<第一个交换调用的 _amount>')

// 执行交换，将价格限制记录到控制台
await E2E_swap.test_swap_exactIn_oneForZero('<第二个交换调用的 _amount>')
```

### E2E_mint_burn：检索池初始化参数

池初始化参数的创建是确定性的，有一个 `view` 函数将返回一个特定 `_amount`（用作 `_seed`）将创建的内容。

编写一个js单元测试：

```js
console.log(await E2E_mint_burn.viewInitRandomPoolParams('<第一个铸造调用的 _amount>'))
```

### E2E_mint_burn：检索铸造创建的随机位置

```js
const poolInitParams = await E2E_mint_burn.viewInitRandomPoolParams('<第一个铸造调用的 _amount>')

const positionParams = await E2E_mint_burn.viewMintRandomNewPosition(
  '<第一个铸造调用的 _amount>',
  poolInitParams.tickSpacing,
  poolInitParams.tickCount,
  poolInitParams.maxTick
)

console.log(positionParams)
```

### E2E_mint_burn：检索销毁的使用位置

取消注释以下行：

- 在 `E2E_mint_burn.sol` 的顶部：`// import 'hardhat/console.sol';`
- 在特定销毁函数内部：`// console.log('burn posIdx = %s', posIdx);`
- 如果这是部分销毁，还要查看被销毁的金额。在 `test_burn_partial` 函数内部：`// console.log('burn amount = %s', burnAmount);`

然后在js测试中执行销毁。

```js
// 显示池初始化参数
const poolInitParams = await E2E_mint_burn.viewInitRandomPoolParams('<第一个铸造调用的 _amount>')
console.log(positionParams)

// 显示池铸造位置参数
const positionParams = await E2E_mint_burn.viewMintRandomNewPosition(
  '<第一个铸造调用的 _amount>',
  poolInitParams.tickSpacing,
  poolInitParams.tickCount,
  poolInitParams.maxTick
)
console.log(positionParams)

// 执行第一个铸造
await E2E_mint_burn.test_mint('<第一个铸造调用的 _amount>')

// 执行销毁
await E2E_mint_burn.test_burn_partial('<第一个 test_burn_partial 调用的 _amount>')
// 这应该在控制台记录被销毁的位置索引和金额
// 结合上述输出，应清楚显示被销毁的确切位置和金额

# 使用Manticore进行验证

验证是使用实验分支[dev-evm-experiments](https://github.com/trailofbits/manticore/tree/dev-evm-experiments)执行的，其中包含新的优化并且仍在进行中。Trail of Bits 将确保在分支稳定并包含在Manticore发布中后，以下属性仍然成立。

为了方便起见，我们遵循了“如果有可达路径，则有错误”的模式。

要验证属性，请运行：

```
manticore . --contract CONTRACT_NAME --txlimit 1 --smt.solver all --quick-mode --lazy-evaluation --core.procs 1
```

> 一旦 `dev-evm-experiments` 稳定下来，命令可能会更改

Manticore 将创建一个 `mcore_X` 目录。如果没有生成 `X.tx` 文件，这意味着Manticore没有找到违反属性的路径。

| ID  | 描述                                                                                          | 合约                                                              | 状态   |
| --- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | -------- |
| 01  | `BitMath.mostSignificantBit 返回一个值 x >= 2**msb && (msb == 255 or x < 2**(msb+1)).`       | [`VerifyBitMathMsb`](./contracts/crytic/manticore/001