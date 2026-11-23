# CI-18 · 多单元 build 下 Box 实例的 `Drop_drop` static 原型未定义（gcc 告警）

| 项 | 值 |
| --- | --- |
| 模块 | ci / selfhost（发射器） |
| 定性 | CI 缺陷（gcc `-Wunused-function`） |
| 严重度 | P1 |
| 锚点 | v0.88.3（2026-11-23） |
| 依据 | CI run 45186937586（`ubuntu-gcc`，`examples/52_box_new`） |
| 状态 | verified |

## 现象

SH-116 后 `ct build` 会发射 `Box.c`；`Box.h` 对 `Box_<T>_Drop_drop` 仍发 `static` 原型，
而定义只在 owner 单元，消费单元 gcc 报 `declared 'static' but never defined`。

## 处置（DEV，2026-11-23）

多单元 build 下，泛型实例的 drop 原型改为：owner 单元发非 static 定义/原型，其它单元发
`extern`；compile 模式保持原 static 对。`examples/52` build + `-Wall -Wextra` 零告警，
`sh116_build_box` 12/0，goldens 25/25。

## 验收

`ubuntu-gcc` 的 warning-free 段转绿；本机 check-all 12 门绿。


## 复核（REV，2026-11-24）

CI `45211587896` 三 job 全绿；`examples/52` build + `-Wall -Wextra` 零告警；`sh116_build_box` 12/0；
本机 check-all 12 门绿。
