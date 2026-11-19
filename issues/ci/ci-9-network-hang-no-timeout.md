---
id: CI-9
title: "check-all 可被 ct get 的 git 子进程无限挂起：无超时、无禁交互"
status: open
area: ci
severity: P1
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# CI-9 · check-all 可被 `ct get` 的 git 子进程挂起

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §2 / P1-1；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 现象

- `Pkg.h.ct` 的 `git_run()` 唯一实现是 `system(full)`（[:770](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L770)）；
- clone/fetch 走它（[:944](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L944)、[:951](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L951)）；
- `p77_external.sh` 与 `check-ast.sh:994` 无外层 `timeout`；
- 反向验证：`10.255.255.1` 黑洞 75s 会 TCP 失败；但“接受连接、不响应”的 stalled server 可无限等待（20s/90s 两次均被外部 timeout 杀掉）。

**限定**：不是“所有网络黑洞都无限等待”；是“git 子进程无内在超时/无禁交互，特定网络状态可无限挂起”。

## 期望

1. `ct get` 的 git 子进程有可配置超时（默认合理，例如 60s），超时后 kill 并返回非零；
2. 设置 `GIT_TERMINAL_PROMPT=0`，凭据提示不得挂起；
3. `p77_external` 外层加 `timeout`，超时返回 77（skip）或红，行为明确；
4. 补一条 stalled server 负例：N 秒内返回，不无限挂起。

## 验收

- 模拟 stalled server：`ct get` 在限定时间内退出，非 0；
- `check-all` 不再被该探针挂起；
- 正例（可达网络）仍成功；
- 负例进入 `test/ast` 或 `test/pkg`，命令/原始输出入库。

## 范围

P1；fix/task，不占 phase。DEV 负责；CI 入口与 Pkg 同改。

## 处置（2026-11-20，DEV）

**结论：fixed（待 REV 复核）。** 红证提交 `5e9e53ce`，实现提交 `1fa773a8`。

已核实（基线 `5b13fef4`）：`git_run` 只有裸 `system("... 2>/dev/null")`；本地
“accept 后不响应”的 HTTP git 服务让 `ct get` 越过 40s 仍不返回。

改法（`selfhost/ct-ast/tool/pkg/Pkg.h.ct`）：

- `GIT_TERMINAL_PROMPT=0` + `GIT_ASKPASS=true` 关闭凭据提示；
- 每条 git 命令插入 `-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60`，
  无 `timeout` 的平台（macOS）也能中止停滞传输；
- 有 `timeout` 时包一层 `timeout ${CT_GIT_TIMEOUT:-180}`（只接受数字），
  无 `timeout` 时退化为 git 自身配置；
- 插入点固定在 `git ` 之后，所有 caller 的 `-C`/子命令参数不变。

探针：`test/ast/p77_net_timeout.sh`（python3 起 accept-不响应 server；
无 `timeout` 平台 `exit 77` skip），已接入 `selfhost/check-ast.sh`。

验证（实现后，本轮重建的 ct-ast）：

```console
$ bash test/ast/p77_net_timeout.sh /tmp/ci9-sh93-build/ct-ast
OK p77/net-timeout (ct get failed in 5s, rc=1)
```

正例不回归：`test/pkg/run.sh` 的本地 `file://` 与本地 git 仓取包仍 147/0
（见 `selfhost/check-all.sh` 门 7，2026-11-20 本轮复跑）。
