# TEST-22 · DMA 真实搬运（hardware-gated）

| 项 | 值 |
| --- | --- |
| 模块 | test（PH-67-R4） |
| 类型 | 测试缺口：只验了寄存器面 |
| 严重度 | Medium |
| 状态 | deferred |
| 处置证据 | **deferred**（真板门控；触发：STM32F4 真板到位，或 REQ-HW-020 参考工程先落地；owner DEV） |
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

## 处置（2026-11-22，REV/REQ）

**结论：`deferred`（真板门控）。** 验收要的是「字节真的被搬走」：EN 置 1、USART2_TX 发出固定
字节、串口侧比对、覆盖 TCIF 与错误路径。这需要真实 STM32F4 板卡加一个可观测的 USART2 对端；
Renode 的 DMA 模型不保证数据流，本机也没有真板，因此**不是本仓库能自证的**——按 §5.4 记
`deferred` 并写死触发条件，比长期挂 `open` 更准确（`open` 会让台账读成「随时可做」）。

- owner：DEV（测试线）；触发后由 REV 复核。
- 触发条件（任一即启动，先到先用）：
  1. **真板到位**：STM32F4 Discovery 或等价板 + 可编程 USART2 对端 + 厂商 HAL 能配
     DMA1 Stream6（即 [REQ-HW-020](../../docs/planning/hardware-readiness-requirements.md)
     的参考工程条件）；届时按下文「触发条件」三步落地，证据含串口原始字节与 TCIF 计数；
  2. **REQ-HW-020 参考工程先落地**：本条并入该工程的 E2E 用例，不再单列（届时转
     `superseded` 并指到参考工程的用例 id）。
- 在此之前：`test/ast/p67_dma.sh` 的寄存器面证据保持有效（EN 保持 0，只验 PAR/M0AR/NDTR/CR
  写入与回读，**不声称任何字节被搬走**），本条不并入任何「已验证」结论。

已核对的现状（离线可复核）：

```console
$ grep -n 'hardware-gated\|never claims bytes moved' test/ast/p67_dma.sh
4:# hardware-gated (registered separately), so this probe only checks the
5:# descriptor contract, never claims bytes moved.
$ grep -n 'CreateFileBackend' test/baremetal-renode/run.sh
105:        -e "sysbus.usart2 CreateFileBackend @$work/out/uart.txt" \
119:        -e "sysbus.usart2 CreateFileBackend @/w/uart.txt" \
129:        -e "sysbus.usart2 CreateFileBackend @$work/out/uart.txt" \
```

三处 `CreateFileBackend` 都只把 **USART2** 写到文件，run.sh 里没有任何 DMA 数据流断言——
「DMA 真搬运」在这一层确实无从验证，defer 的边界即在此。
