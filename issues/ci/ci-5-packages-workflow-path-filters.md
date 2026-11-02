# CI-5 · `packages.yml` 的 push / PR 路径过滤不覆盖包工具与包相关改动

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | Low |
| 锚点 | commit `553d300`（2026-11-02，工作树 `v0.18.0`） |
| 文件 | [.github/workflows/packages.yml](../../.github/workflows/packages.yml#L1-L20) |
| 状态 | 已修（2026-11-02，`v0.18.0`）：push / PR 过滤补上 `selfhost/ct-ast/tool/pkg/**` 与 `test/pkg/**`（采纳方案 1；外部仓库仍由 nightly 覆盖） |

## 现象

`packages.yml` 的触发条件只列了 demo 与工作流自身：

```yaml
on:
  push:
    paths:
      - 'examples/wave1-demo/**'
      - '.github/workflows/packages.yml'
  pull_request:
    paths:
      - 'examples/wave1-demo/**'
      - '.github/workflows/packages.yml'
```

而 Phase 18 计划 §18.2 写的是「在 push / PR（**触及包或索引相关文件**）与 nightly 运行」。

## 证据

- 包与索引本体在外部仓库（`ct-pkg/{hal,hal-posix,clib,index}`），本仓库 push 天然触发不到；
  这部分只能靠 nightly（`0 19 * * *`）覆盖，属已接受的限制。
- 但**本仓库内的包工具**不在过滤里：`selfhost/ct-ast/tool/pkg/**`（`Pkg.h.ct` 的
  `get` / `update` / `verify` / `install`）改动不会触发包门禁；`test/pkg/**` 同理。
  这类改动恰好是最容易把 Wave 1 端到端弄坏的改动。
- 结果是 PR 阶段看不到 `ct get → ct update → ct verify → ct install → 运行 → diff` 这条链的回归。

## 影响

包工具的回归被推迟到 nightly 才暴露；若 nightly 连续失败而无人看，Wave 1 的「端到端绿」
会长期失真。计划文本与实际过滤也不一致。

## 修复建议

二选一，并在计划里写明：

1. **补过滤**（推荐）：`selfhost/ct-ast/tool/pkg/**`、`test/pkg/**`、`examples/wave1-demo/**`、
   `.github/workflows/packages.yml`；
2. 维持现状，但在 `docs/design/phase18.md` §18.2 把「触及包或索引相关文件」改成
   「触及 demo 或本工作流；包工具与外部仓库改动由 nightly 覆盖」。

## 验证

改 `selfhost/ct-ast/tool/pkg/Pkg.h.ct` 并推送（或 `act` 本地跑 workflow），观察 `packages` 工作流
是否被触发；补过滤前不会触发。
