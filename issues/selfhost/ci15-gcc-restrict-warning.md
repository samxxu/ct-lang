---
id: CI-15
title: "Ubuntu gcc 的 ct-tour 因 -Wrestrict 告警失败（字段表 memmove 前）"
status: open
area: selfhost
severity: P1
opened: 2026-11-21
confirmed-by: CI-44823947267
---

# CI-15 gcc -Wrestrict 告警

## 现象

v0.83.2 的 CI `ubuntu-gcc` 在 `ct-tour` 报 `FAIL: ct-ast did not build warning-free`：

```
Emitter.h.ct:1075: warning: 'snprintf' argument 4 overlaps destination object 'g_sb' [-Wrestrict]
Emitter.h.ct:5663: warning: 'snprintf' argument 4 overlaps destination object 'g_sb' [-Wrestrict]
```

即使 `j != i`，gcc 仍认为同一 `g_sb` 对象的两个数组可能重叠。

## 期望

`-Wall -Wextra` 零告警；字段表压缩行为不变（Linux/macOS）。

## 处置

把两处 `snprintf(dst, MAX_TEXT, "%s", src)` 改为 `memmove(..., MAX_TEXT)`（同对象、允许重叠、完整复制 NUL）；补跑 p80_retain/p83_verify 与 check-all。

## 处理（REQ，2026-11-21）

- 状态：`open`（P1，CI 红）
- owner：DEV
- next：按处置段改 `memmove`，补跑 p80_retain/p83_verify/check-all
- 不能关闭：v0.83.2 ubuntu-gcc 仍红
