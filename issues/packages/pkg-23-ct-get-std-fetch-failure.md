---
id: PKG-23
title: "ct get std 官方 pin 的 git fetch 失败只报通用错误，无法区分网络/认证/tag/缓存"
status: open
area: packages
severity: P1
opened: 2026-11-21
confirmed-by: REQ-review-v077-1
---

# PKG-23 · `ct get std` fetch 失败不可诊断

## 复现

```console
$ ct get std
ctc: git fetch of 'https://github.com/ct-pkg/std' failed
```

## 已核事实

- 官方 pin 表：`std` → `0.19.0`、`https://github.com/ct-pkg/std`、`v0.19.0`、`sha256:432086f0…`（[Pkg.h.ct:2037](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2037)）；
- 远端 `v0.19.0` tag 存在（GitHub API 2026-11-21 返回，commit `ae8dd94f…`）；
- 失败点在 `fetch_git` 的 `git -C <cache> fetch --quiet --tags --force`（[Pkg.h.ct:1008](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1008)）；
- `git_run` 的 stderr/stdout 在 `--quiet` 下被丢弃，只留下通用错误；
- 同一路径可能的原因：网络不可达、代理/凭据、远端拒绝、缓存 `.git` 损坏、tag/对象缺失；当前无法区分。

## 定性

**不是**官方 pin 身份或 URL 配错；`std` 的解析是对的。  
这是 `ct get` 的**失败可诊断性/恢复性**缺陷：用户看到“fetch failed”无法判断该重试、清缓存、检查代理，还是报 pin 错。

## 期望

1. 保留 git stderr 的最后 N 行（脱敏）或 `--no-quiet` 捕获，错误里给原因类别；
2. 分类提示：网络/代理、认证、远端无 tag、缓存损坏；给对应动作（重试 / 清缓存 / `ct get ct/std@0.19.0`）；
3. 缓存 `.git` 损坏或 origin 不符时，提供 `--refresh` 或明确“remove <cache> and retry”；
4. 干净 HOME + 可达网络：`ct get std` 必须成功；不可达时也必须给出可操作诊断，而不是通用失败。

## 验收

- 模拟网络不可达：错误含“network/proxy”类原因与重试建议；
- 模拟缓存损坏：错误指到具体 cache 路径与清理动作；
- 干净 HOME：`ct get std` 成功，锁行 `ct/std 0.19.0`，store 为 `~/.ct/pkg/ct/std/0.19.0`；
- 不改变官方 pin 版本，除非另行确认 pin/tag 不一致。

## 范围

P1；`ct get` 引导命令。修法在 Pkg/Driver；本 issue 只落库，不改代码。

## 处理（REQ，2026-11-21）

- 状态：`open`（P1）
- owner：DEV
- next：保留 git stderr/分类网络/缓存，提供 refresh；不先改 pin
- 不能关闭：`ct get std` 仍只报通用 fetch failed
