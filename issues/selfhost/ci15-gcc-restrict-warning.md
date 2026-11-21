---
id: CI-15
title: "Ubuntu gcc 的 ct-tour 因 -Wrestrict 告警失败（字段表 memmove 前）"
status: verified
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

## 复核（CI-11 复验，2026-11-21，REV）

**结论：verified（源码 + tag 证据；本机无 GCC，`-Wrestrict` 未本地复跑）。**

```console
$ git show v0.83.3:selfhost/ct-ast/backend/emit/Emitter.h.ct | grep -n 'memmove(g_sb.fpath'
1075:        if (j != i) memmove(g_sb.fpath[j], g_sb.fpath[i], MAX_TEXT);
5663:                    if (j2 != i2) memmove(g_sb.fpath[j2], g_sb.fpath[i2], MAX_TEXT);
$ grep -rnE 'snprintf\(g_sb\.fpath\[[^]]+\], MAX_TEXT, "%s", g_sb\.fpath\[' selfhost/ct-ast | wc -l
0
$ git log --oneline v0.83.2..v0.83.3 -- selfhost/ct-ast/backend/emit/Emitter.h.ct
d5cca3b1 fix(ct-ast): CI-15 字段表压缩改用 memmove，消除 gcc -Wrestrict（v0.83.3）
$ cc -Wall -Wextra -std=c99 /tmp/ct-head/b/astsrc/*.c -o /tmp/ct-head/b/ct-ast && echo BUILD_OK
BUILD_OK
```

两处压缩点已由 `snprintf(dst, MAX_TEXT, "%s", src)`（GCC 视为 `restrict` 参数、同对象即
`-Wrestrict`）改为 `memmove(..., MAX_TEXT)`：`memmove` 明确允许重叠，且不再有自拷贝
`snprintf`（扫描 0 命中）。`v0.82.1` 的 SH-103 修复仍是 `if (j != i) snprintf(...)`，
GCC 仍可能告警；`v0.83.3` 的 `d5cca3b1` 才把它换成 `memmove`，两个 tag 均可在
`git tag --contains` 中追溯。

**证据边界**：本机只有 Apple clang 21（`/usr/bin/gcc` 是同一 clang shim），`-Wrestrict`
是 GCC 专有告警；Podman VM 在本沙箱不可启动，故未能本地复跑 GCC。上面的源码、tag 与
零告警重建证明修复已落地；GCC 侧的最终判据仍由 `ubuntu-gcc` CI 承担。
