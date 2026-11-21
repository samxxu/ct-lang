---
id: PKG-23
title: "ct get std 官方 pin 的 git fetch 失败只报通用错误，无法区分网络/认证/tag/缓存"
status: reopened
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

- 状态：`open`（P1；2026-11-22 REV 复核后转 `reopened`，见文末）
- owner：DEV
- next：保留 git stderr/分类网络/缓存，提供 refresh；不先改 pin
- 不能关闭：`ct get std` 仍只报通用 fetch failed

## 处置（DEV，v0.88.1，2026-11-21）：fixed

- **修复**：`git_run` 在 `ct get` 的 git 阶段把 stderr 落到
  `$HOME/.cache/ct-pkg/.ct-pkg.err`（`umask 077`，读完即删）；失败时读最后 8 行、把 URL
  userinfo 脱敏为 `***@`，再按 git 原文归类并给动作：
  `network/proxy unreachable`（重试、查 `https_proxy`/`ALL_PROXY`/DNS）、
  `authentication/permission denied`（查凭据/SSH key；`GIT_TERMINAL_PROMPT=0` 不交互）、
  `remote tag/object missing`（核对 pin/tag 或先发布）、
  `package cache is corrupt`（给 cache 路径、`rm -rf '<cache>'`、`ct get --refresh <spec>`）、
  未分类兜底。`git checkout` / `rev-parse` 失败同样走这套分类。
- **`--refresh`**：`ct get --refresh <spec>` 只在该次调用丢弃对应 git 缓存并重新 clone；
  未带该标志时缓存照旧复用（不破坏正常缓存）。origin 不符/缓存 `.git` 不可读时，错误里同时
  给 recorded/expected origin、cache 路径与清理/refresh 动作。
- **不变项**：官方 pin 的版本 `0.19.0`、URL `https://github.com/ct-pkg/std`、tag `v0.19.0`、
  digest `sha256:432086f0…` 未改；成功路径与 v2 锁行格式未改；失败仍发生在写 `ct.lock` 之前。
- **测试**：新增 `test/ast/pkg23_git_diag.sh` 并接入 `selfhost/check-ast.sh`。离线覆盖
  关闭的 loopback 端口、`.git` 损坏缓存、远端缺 pinned tag、认证失败（git 测试替身，含
  凭据脱敏）、`--refresh` 重建缓存；每类断言新诊断文本。
- **红证**：`baseline: 4edc70e9`（test 提交 `600e6595` 的父提交），
  `sh test/ast/pkg23_git_diag.sh /tmp/p23-baseline/ct-ast` → exit 1：
  ```console
  FAIL pkg23: network diagnostic
    ctc: git fetch of 'https://github.com/ct-pkg/std' failed
  FAIL pkg23: corrupt-cache diagnostic
    ctc: cache for 'ct/std' has a different origin; remove '.../.cache/ct-pkg/ct/std' and retry
  FAIL pkg23: missing-tag diagnostic
    ctc: git checkout of 'v0.19.0' failed
  FAIL pkg23: authentication diagnostic
    ctc: git fetch of 'https://github.com/ct-pkg/std' failed
  FAIL pkg23: --refresh diagnostic
    ctc: unknown option '--refresh'
  ```
- **绿证**（实现后）：
  ```console
  $ sh test/ast/pkg23_git_diag.sh <ct-ast>
  ok   an unreachable remote names network/proxy and gives a retry action
  ok   a corrupt cache names the cache path, rm -rf and --refresh
  ok   a missing pinned tag is classified as remote tag/object missing
  ok   an authentication failure is classified and credentials are redacted
  ok   --refresh discards the corrupt cache and fetches the pin again
  OK pkg23 (network, corrupt cache, missing tag, auth, refresh)
  ```
- **版本/文档**：`v0.88.1`（PATCH，V-3）；五处 `CTC_VERSION`、51 个
  `test/cases`/`test/modules` golden banner、`README.md` / `docs/README.md` / `AGENTS.md`
  当前版本、`docs/package-guide.md` §4/§6、`docs/history/phase-log.md` 同步。
- **夹具跟进**：`test/probes/p87_dogfood.tsv` 的 10 条 warning 行号随 `Pkg.h.ct` 增行重算；
  `docs/history/p88_metrics.md` 的 `emitted_after` 按 v0.88.1 复测（48870）。
- **状态**：front-matter 仍为 `open`（状态词归 REV/REQ）；DEV 主张 `fixed`，等待 REV 复核。
- **未覆盖**：认证分支用 git 测试替身（未起真实 401 HTTP 服务）；`proxy`/TLS 归类按 git
  原文匹配，未逐一构造真实代理隧道；未 pin 的第三方 range 走 `git_pick_tag` 失败时仍报
  `no tag ... satisfies`（不在本 issue 的官方 pin 路径内）。

## 复核（REV，2026-11-22）：**reopened**

功能面通过。`git archive 00eb6df1` 同链自举 ct-ast v0.88.1，
`test/ast/pkg23_git_diag.sh` 5/5（network / corrupt cache / missing tag / auth /
refresh）；基线 `4edc70e9` 上 5 类全红；干净 HOME 成功路径 `ct/std 0.19.0`、
digest `sha256:432086f0…`、`ct.lock` 与 v0.88.0 基线逐字相同；失败不写锁、无
`.ct-pkg.err` 残留；`--refresh` 只删目标包并保留同根 sibling。

**但提交独立性不成立（T-4，blocking）**：`00eb6df1` 的 `selfhost/check-ast.sh:1330`
把 SH-106 的钩子一起带进了本提交，而 `test/ast/p106_str_escape.sh` 到 `c1b54d2f`
才存在。`git archive 00eb6df1` 跑 `selfhost/check-ast.sh`：

```console
  FAIL  SH-106 Str view escape: sh: test/ast/p106_str_escape.sh: No such file or directory
== summary: 1570 passed, 7 failed, 5 skipped ==
EXIT=1
```

`git revert c1b54d2f` 后同一行仍指向已删除文件（exit 127）。最小复现与最小修法见
[2026-11-22-pkg23-sh106-rev-verdict.md](../../docs/reviews/2026-11-22-pkg23-sh106-rev-verdict.md)
§2.4/§4：一次本地 rebase，把该 11 行钩子从 `00eb6df1` 移到 `c1b54d2f`；两提交均未
push/tag，无外部影响。另 `--refresh` 的 `.`/`..` 目标依赖 `rm` 兜底（未观察到越界
删除，建议补 name 校验，见复核 §2.5）。

`status` 置 `reopened`；功能修复本身无需改动，重写历史后按新 sha 重跑
`pkg23_git_diag.sh` 与 `check-ast` 即可转 `verified`。
