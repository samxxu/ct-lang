# PKG-11 · `ct get` 只打印 `installed N package(s)`

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` 的人类输出） |
| 定性 | **可用性缺陷**：结果没有请求、版本、来源、store、digest、动作与依赖 |
| 严重度 | **Medium** |
| 优先级 | **P1**（包线 patch） |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV） |
| 锚点 | `v0.63.3`；修复在 `v0.63.4` |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)：`get`、`fetch_git`、`get_one` |

## 现象

```console
$ ct get json
installed 1 package(s)
```

无法判断：请求的是哪个 spec、解析到哪个版本/tag/commit、来自 registry/index/URL/dir、
是新装还是复用、落在哪、digest 是什么、有没有依赖。

## 期望

- 默认：逐包输出 `requested/resolved/source/tag/commit/store/digest/action` 与汇总；
- `-q` / `--quiet`：每包一行 `name version url`；
- `--json`：`requested`、`packages[]`、`summary` 的机器可读对象；
- 不影响 `ct install/verify/update` 的现有输出。

## 验收

| # | 输入 | 期望 |
| --- | --- | --- |
| A1 | `ct get gutil` | 含 `resolved ct/gutil 0.2.0`、`source git`、`action installed` |
| A2 | `ct get -q gutil` | 一行 `ct/gutil 0.2.0 <url>` |
| A3 | `ct get --json gutil` | 含 `"version":"0.2.0"`、`"action":"reused"` |
| A4 | 回归 | `test/pkg` 全绿；`ct install/verify/update` 不变 |

## 处置

- `Pkg` 保存本次解析记录（name/version/publisher/source/url/tag/commit/store/digest/action）；
- `get` 按 quiet/json/default 输出；
- 版本 `v0.63.4`；`test/pkg` 147/0。

## 处置（2026-11-20，DEV · 复跑）

- 结论：v0.63.4 的修复仍在 HEAD（提交 `fbb63562`）；fix tag `v0.63.4`
  缺失见 CI-12。只记录证据，不改 `status`。
- 命令/输出（`test/pkg/run.sh` 由 `check-all` 门 7 运行）：

```console
$ bash test/pkg/run.sh
  ok    default get reports resolved package, source and action
  ok    quiet get reports name, version and url
  ok    json get reports the resolved package
...
== summary: 147 passed, 0 failed ==
```

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举后跑 `test/pkg/run.sh`：

```console
$ bash test/pkg/run.sh
  ok    default get reports resolved package, source and action
  ok    quiet get reports name, version and url
  ok    json get reports the resolved package
...
== summary: 147 passed, 0 failed ==
$ echo $?
0
```

修复提交 `fbb63562` 为 HEAD 祖先；fix tag `v0.63.4` 已回补（见 CI-12 复核段）。
