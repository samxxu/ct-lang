# Phase 83 — 包管理契约 v1 与索引校验

> **状态：实施中（准备；施工入口未过）**（2026-11-20 立项并开卡；`v0.83.0`）。
> **签收：EDITOR 2026-11-20**（主编统一签收；卡作者 REQ）。
> **施工闸门**：PH-82 未收口；未过前只做契约、设计与夹具，不落实现代码。
> **前置**：PH-82 收口；[PKG-12](../../issues/packages/pkg-12-contract-v1-doc-gaps.md) 判据矩阵
> 至少覆盖 `verify` 所需条目；index 仓确认产物消费方式。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase83.md`。
> **依据**：[D-014](../decisions/D-014.md)、[契约 v1](../planning/ct-pkg-get-contract.md)、
> [提案评估](../reviews/2026-11-20-pkg-contract-proposal-eval.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-83（legacy 文件 `phase83.md`） |
| 目标 | 把包管理契约收敛为单一 v1 文本，并提供只读索引校验与 CI 可用的分发产物 |
| 范围 | 契约 v1 维护、判据归属矩阵、只读 `ct index verify`、conformance 数据/runner、Linux x64 产物 |
| 非目标 | `ct pkg release`、`ct index build|refresh`、全量 PK/R/S 进 CT、多索引并存、签名/pin、宿主平台建仓 |
| 交付物 | 契约 v1、`ct index verify`、conformance、`ct-linux-x64.tar.gz` + sha256 |
| 任务清单 | §2（S83a–S83d） |
| 退出判据 | E83-1…E83-8（§3） |
| version-minor | 83（PH-83，`d=0`） |
| 已知风险 | R83-1…R83-5（§4） |

## 1 需求与边界

```sh
ct index verify ./index                 # 只读：字段/摘要/tag/可安装性
ct index verify ./index --json          # 供 CI 解析
```

- `ct index verify` 只读：不联网、不写 store、不写 lock、不推索引；
- 五字段旧行按行硬错（D-014 第 5 条），与 `ct get` 判定一致；
- 发布/索引生成仍在 `ct-pkg/index` 的 CI；CT 只提供契约与固定版本二进制；
- 每 MINOR 发布 `ct-linux-x64.tar.gz` + `.sha256`，GitHub Release 稳定 URL；
- 单索引：`--index` > `CT_INDEX` > `$CT_HOME/index/index`，不承诺多索引并存。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S83a 契约/矩阵 | 契约 v1 补齐、判据归属矩阵定稿 | 无代码前置（本卡前已完成草案） |
| S83b 只读校验 | `ct index verify` 与五字段按行硬错 | PH-82 收口；PKG-12 覆盖 verify 条目 |
| S83c conformance | 数据 + runner；digest 三向量 | S83a |
| S83d 分发 | Linux x64 产物、sha256、稳定 URL、版本钉法 | S83b；index 仓确认消费方式 |

### 1.2 准备态可做（不落实现代码）

| # | 项 | 通过方式 |
| --- | --- | --- |
| P83-pre-1 | 判据原文与归属矩阵补齐 | PKG-12；index 仓提供原文 |
| P83-pre-2 | 五字段硬错的发布顺序与 index 仓对齐 | PKG-13/PKG-16；书面时间点 |
| P83-pre-3 | `verify` 的只读边界与输出格式评审 | 设计审读：零网络/零 store/零 lock |
| P83-pre-4 | 产物命名、glibc 基线与 URL 规则 | 发布工程评审 |
| P83-pre-5 | conformance 数据格式与 runner 接口 | 与 shell 侧对照基准对齐 |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S83a 契约/矩阵 | 契约 v1（digest 向量、spec、单索引、MVS、归属矩阵） | `p83_contract`（no-test，REVIEW 签字） | S |
| S83b 只读校验 | `ct index verify`；五字段按行硬错 | `p83_verify` / `p83_legacy` | M |
| S83c conformance | 版本化数据 + runner；三向量 | `p83_conformance` | M |
| S83d 分发 | `ct-linux-x64.tar.gz` + sha256 + 稳定 URL | `p83_dist`（发布工程） | M |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S83a 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E83-1 | 契约 v1 有 digest 伪代码与 3 组实测向量；spec 语法、单索引、MVS、判据归属矩阵齐全（无 TBD） |
| E83-2 | 五字段旧行按行硬错，与 `ct get` 判定一致；其余六字段行不受影响；发布前置已由 index 仓确认 |
| E83-3 | `ct index verify` 零网络、零子进程、零 store/lock 写入；坏行给行号与非零退出码 |
| E83-4 | `--json` 输出稳定，CI 可解析；退出码 0/1/2 语义与契约 §7 一致 |
| E83-5 | conformance 数据覆盖合法/非法清单、索引行与 digest 三向量；shell 与 CT 共用且差异显式登记 |
| E83-6 | `ct-linux-x64.tar.gz` 可下载、sha256 匹配、解包即可运行 `ct -v`；版本与 tag 一致 |
| E83-7 | 旧 golden/既有门禁不变；`check-all` 通过；`v0.83.0` 五处版本号与文档同步 |
| E83-8 | 单卡回滚：撤回 `ct index verify` 与产物不影响 `ct get`/发布路径 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R83-1 | 五字段硬错先于 index 仓清零，存量包集体不可装 | 发布前置 + 过渡版本；PKG-13 |
| R83-2 | 范围蔓延成 release/index 生成 | 本卡非目标写死；复开需覆盖 D-014 第 1 条 |
| R83-3 | Linux 产物不可复现或 glibc 基线不清 | 固定构建环境、发 sha256、写清基线 |
| R83-4 | shell 与 CT 判定再次漂移 | conformance 共用数据；差异显式登记 |
| R83-5 | 版本钉法冲突（index CI 钉旧版） | 每 MINOR 稳定 URL；契约写清“谁钉谁” |

回滚：单卡回滚；`ct index verify` 与产物同退，发布/消费路径不受影响。
