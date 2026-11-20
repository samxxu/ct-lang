# PKG-14 · PH-83 开卡需求：只读 `ct index verify` 与 Linux x64 产物

| 项 | 值 |
| --- | --- |
| 模块 | packages / 发布工程 |
| 定性 | 需求（新 phase 开卡） |
| 严重度 | Medium |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [契约 v1](../../docs/planning/ct-pkg-get-contract.md)、[D-014](../../docs/decisions/D-014.md)、[评估](../../docs/reviews/2026-11-20-pkg-contract-proposal-eval.md) |
| 状态 | **reopened**（2026-11-21，REV；契约 §9 验收项 7「不可读退出 2」未过，对应 PH-83 卡 E83-4；见下方复核段） |

## 背景

外部提案要求把发布/索引生成收进 CT。需求方裁定（D-014 第 1、6、7 条）：维持 B′，只新增
**只读** `ct index verify`，并提供 CI 友好的 Linux x64 产物；发布与索引生成仍留在 index CI。

## 范围

1. `ct index verify <file>`：只读回放索引行——字段数、digest 拼写、行内 tag/版本一致性、
   store 可安装性；不联网、不写 store、不写 lock、不推索引；
2. 五字段旧行调用本命令时的行为与 [PKG-13](pkg-13-legacy-five-field-row-hard-error.md) 一致；
3. 每个 MINOR 发布 `ct-linux-x64.tar.gz` + `.sha256`，GitHub Release 稳定 URL；
4. 版本节奏：`vX.Y.Z`；index CI 按 tag 钉版本。

## 非目标

- `ct pkg release`、`ct index build|refresh`；
- 全量 PK/R/S 校验；
- 多索引并存、签名/pin 基础设施；
- 宿主平台建仓。

## 退出判据（建议）

| ID | 断言 |
| --- | --- |
| E83-1 | `ct index verify` 对合法索引返回 0，对坏行返回非零并给行号 |
| E83-2 | 命令零网络、零子进程、零 store/lock 写入 |
| E83-3 | 五字段行按行硬错，与 `ct get` 判定一致 |
| E83-4 | Linux x64 产物可下载、sha256 匹配、可直接运行 `ct -v` |
| E83-5 | 产物版本与 tag 一致；旧 golden 与既有门禁不变 |
| E83-6 | 契约 §9 的 CT 侧验收项全绿 |

## 施工前置

- PH-82 收口；
- [PKG-12](pkg-12-contract-v1-doc-gaps.md) 的判据归属矩阵定稿（至少完成 `verify` 所需条目）；
- index 仓确认消费该产物的方式。

## 关联

- [PH-83 roadmap 条目](../../docs/roadmap.md)、[D-014](../../docs/decisions/D-014.md)

## 复核（REV，2026-11-21）：**reopened**

PKG-14 的 E83-6（契约 §9 CT 侧验收项；对应 PH-83 卡 E83-4）未过：PH-83 收口复核
（`5378850e`）发现 `ct index verify` 对非普通文件输入不返回契约要求的
退出码 2：目录、`/dev/null`、指向目录的 symlink、`CT_INDEX` 指向目录、
`$CT_HOME/index/index` 为目录时均输出 `index verify: OK (0 rows)` 并 exit 0，`--json`
输出 `"ok":true`；FIFO 阻塞；GitHub Release 的 Linux 产物对 `/` 同判。最小复现：

```console
$ mkdir -p /tmp/p83-dir.index
$ ct index verify /tmp/p83-dir.index
index: /tmp/p83-dir.index
index verify: OK (0 rows)
$ echo $?
0
```

契约 §4.4 要求“用法错误/索引不可读 → 退出码 2”。代码 `selfhost/ct-ast/tool/pkg/Pkg.h.ct:2674`
只 `fopen`，`:2803` 直接 `fclose`，无 `stat`/`S_ISREG`、无 `ferror` 检查。期望：非普通文件
与读错误均 exit 2；`--json` 不得在 exit 2 时给 `ok:true`；`p83_verify` 补目录/FIFO 负例。

证据：[REV verdict](../../docs/reviews/2026-11-21-phase83-rev-verdict.md) §5.2。修复前
PH-83 不写 `REV: 通过`。
