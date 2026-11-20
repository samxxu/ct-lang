---
id: SH-103
title: "p80_retain 在 Ubuntu clang/gcc 的 sanitizer 段失败（macOS 绿）"
status: open
area: selfhost
severity: P1
opened: 2026-11-21
confirmed-by: CI-44804723025
---

# SH-103 p80_retain Linux sanitizer 段失败

## 现象

v0.82.0 起 CI `ubuntu-clang-smoke` 与 `ubuntu-gcc` 的 AST 套件报：
`FAIL PH-80-SH-102 retain (D-013 §3 automatic retain trace, ASan/UBSan, escapes)`；
探针输出停在 `ok struct_lit -fsanitize=address`，无最终 `p80_retain: OK`；
macOS clang 同版本全绿。常规运行、UBSan 的 retain/jump/field_reassign 均 ok。

## 复现

CI run `44804723025`；本地 macOS `sh test/ast/p80_retain.sh <ct-ast>` 绿。

## 期望

两平台 `p80_retain: OK`；若 Linux 触发真实 ASan/UBSan 报告，应修产品代码而不是跳过。

## 处置

待查：在 Linux 容器/CI 上取 `struct_lit` sanitizer 完整 stderr；`test/ast/p80_retain.sh`
现已输出完整 stderr（commit 8dfb34c7 的诊断改动）。修复前 PH-82 tag 的 CI 为红。
