# TEST-22 · DMA 真实搬运（hardware-gated）

| 项 | 值 |
| --- | --- |
| 模块 | test（PH-67-R4） |
| 类型 | 测试缺口：只验了寄存器面 |
| 严重度 | Medium |
| 状态 | `open`（hardware-gated，等真板） |
| 承诺出处 | [PH-67 卡](../../docs/design/phase67.md) R4 / E67-4 |

## 现状

`test/ast/p67_dma.sh` 只证明 DMA1 Stream6 的 PAR/M0AR/NDTR/CR 描述符写入与
回读一致（EN 保持 0，故意不触发搬运）。Renode 的 DMA 模型不保证真实数据流，
因此**没有**声称任何字节被搬走。

## 触发条件

拿到真实 STM32F4 板卡后：

1. 把 `dma_setup_tx` 的 EN 置 1，用 USART2_TX 发一段固定字节；
2. 串口侧对比收到内容；
3. 覆盖 DMA 传输完成中断（TCIF）与错误路径。

在此之前本项保持 `open`，不并入任何"已验证"结论。
