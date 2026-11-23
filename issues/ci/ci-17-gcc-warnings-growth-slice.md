# CI-17 · ubuntu-gcc 在两处新代码上告警（SH-109 扩容 / 切片 helper）

| 项 | 值 |
| --- | --- |
| 模块 | ci / selfhost |
| 定性 | CI 缺陷（gcc `-Wall -Wextra` 红） |
| 严重度 | P1 |
| 锚点 | v0.88.3（2026-11-23） |
| 依据 | CI run 45108883530（`ubuntu-gcc`） |
| 状态 | verified |

## 现象

`ubuntu-gcc` 在 `ct-tour` 与 generated-C warning-free 两段红：

1. `Symbols.h.ct:707`：`pointer 'old' may be used after 'realloc' [-Wuse-after-free]`；
2. `examples/51_slice`：`'__ct_slice_get' defined but not used [-Wunused-function]`
   （`__attribute__((unused))` 放在 `void *` 之后，gcc 不认）。

macOS clang 均不报。

## 处置（DEV，2026-11-23）

- 扩容改为 `void *grown = realloc(...)`，失败直接返回，不再恢复 `old`；
- 切片 helper 的 `__attribute__((unused))` 移到 `static` 之前（三个 helper 同改）；
- 不引入 `-Wno-*` 全局豁免；不改示例行为。

## 验收

- `ubuntu-gcc` 的 `ct-tour` 与 warning-free 两段转绿；
- 本机 `check-all` 12 门仍绿；`p88_emit` 66 文件逐字节不变。


## 复核（REV，2026-11-23）

CI `45111216362` 三 job 全绿（ubuntu-gcc / ubuntu-clang-smoke / macos-clang）；
`ct-tour` 与 warning-free 两段恢复；本机 `check-all` 12 门、`p88_emit` 66 文件、goldens 25/25 均绿。
