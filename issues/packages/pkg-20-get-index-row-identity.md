# PKG-20 · A2：`ct get` 选中索引行未校验 name/publisher/version/tag（bugfix）

| 项 | 值 |
| --- | --- |
| 模块 | packages / 消费侧索引读取 |
| 定性 | **bugfix**（对齐已成文契约；冻结期允许） |
| 严重度 | Medium |
| 锚点 | v0.84.1（2026-11-21） |
| 依据 | [对齐清单 A2](../planning/ct-pkg-index-alignment.md)、[契约 §4.4](../planning/ct-pkg-get-contract.md#44-ct-index-verify只读ct-lang-负责)、[D-014](../decisions/D-014.md) |
| 状态 | verified |
| 处置证据 | **verified（REV 独立复核，2026-11-22，HEAD `7061aa22`）：与 PKG-19 同一归档自举，四类身份负例在取回前 exit 1、对应 12 条断言绿，基线 8 条身份红证复跑；见 §复核通过** |

## 现象

`ct index verify` 会拒绝非法 name / publisher / version / tag；但 `ct get --index` 命中同一行时
不校验，直接进入 `git clone`。实测（v0.84.1）：

```console
$ ct index verify /tmp/ct-idx-probe/idx_badtag
line 1: tag-version: index tag 'v9.9.9' must be 'v0.1.0'
index verify: FAIL

$ ct get --index /tmp/ct-idx-probe/idx_badtag pub/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed       # 没有先报 tag 错

$ ct index verify /tmp/ct-idx-probe/idx_badpub
line 1: identity: index publisher 'local' must be non-empty, not 'local', without '/'
index verify: FAIL

$ ct get --index /tmp/ct-idx-probe/idx_badpub local/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed       # 没有先报 publisher 错
```

## 根因

`pkg_index_lookup` 只做 `name` / `publisher` 匹配与 digest 拼写检查
（[Pkg.h.ct:2441-2471](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2441-L2471)）；
`pkg_index_verify` 才做 name / publisher / version / tag / digest 全套校验
（[Pkg.h.ct:2680-2715](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2680-L2715)）。

`index_name_ok` / `index_version_ok` 已是 `PkgIndex.h.ct` 的 `pub` 函数
（[PkgIndex.h.ct:32-33](../../selfhost/ct-ast/tool/pkg/PkgIndex.h.ct#L32-L33)），可直接复用。

## 期望

对**被选中**的六字段行，在返回成功前执行与 verify 相同的校验：

- `index_name_ok(tok[0])`；
- publisher 非空、非 `local`、无 `/`；
- `index_version_ok(tok[1])`；
- `tag == 'v' + version`；
- digest 保持现有 `sha256:<64 lowercase>` 检查（已存在）。

错误文案与 verify 一致；失败发生在任何 `git clone` / store / lock 写入之前。
**不做** `ct get` 全文件扫描（未选中坏行仍不阻塞）。

## 兼容断言

| 用例 | 断言 |
| --- | --- |
| 六字段合法行 | 与现状一致，`ct get` / `ct install` 正常 |
| 五字段旧行 | 仍按 legacy 硬错，文案不变 |
| 选中行 name 非法 | `ct get` 硬错，文案同 verify |
| 选中行 `publisher = local` | `ct get` 硬错，文案同 verify |
| 选中行 `version` 非 `x.y.z` | `ct get` 硬错，文案同 verify |
| 选中行 tag 非 `v<version>` | `ct get` 硬错，文案同 verify |
| 未选中坏行 | 不影响选中好行的 `ct get` |

## 验收与门禁

1. 先提 `test(pkg): PKG-20 A2 红`（baseline 见提交说明），覆盖上述负例；
2. 实现后转绿；`ct index verify` 既有探针不变；
3. 双 job：host + Linux x64，跑 `ct get → ct index verify → ct install → 运行比对`；
4. 单提交回滚；不夹带 A1（若 A1 未合入，先 rebase）或 B/C 改动。

## 非目标

- `ct get` 全文件校验 / duplicate 检测（verify 的职责；全文件预检属 v1.1）；
- 原生 `ct index refresh`（[PKG-18](pkg-18-native-ct-index-refresh.md)）；
- index 仓脚本修复。

## 关联

- [PKG-21](pkg-21-ct-pkg-index-refactor-ruling.md)（总跟踪）
- [对齐清单](../planning/ct-pkg-index-alignment.md)
- [PKG-19](pkg-19-get-index-field-count.md)（A1，独立提交）

## §复核（REV，2026-11-22，HEAD `38cd4ae4`）

A2 在 HEAD **未实现**，仍按卡内现象复现。源码现状：

- `pkg_index_lookup`（`Pkg.h.ct:2630-2780`）只做 `name` / `publisher` 匹配与 digest 拼写检查
  （`sha_hex_ok`），返回前没有 `index_name_ok`、publisher 字符集、`index_version_ok` 或
  `tag == 'v' + version` 校验；
- 这些 helper 仍是 `PkgIndex.h.ct` 的 `pub` 函数（声明 `:32-33`，定义 `:120`/`:136`），可直接复用。

复现（HEAD 构建的 `ct-ast v0.88.2`；隔离 `HOME`/`CT_HOME`）：

```console
$ ct index verify badtag.index
line 1: tag-version: index tag 'v9.9.9' must be 'v0.1.0'
index verify: FAIL (1 invalid of 1 rows)             # exit 1
$ ct get --index badtag.index pub/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed           # 没有先报 tag 错
                                                      # exit 1

$ ct index verify badpub.index
line 1: identity: index publisher 'local' must be non-empty, not 'local', without '/'
index verify: FAIL (1 invalid of 1 rows)             # exit 1
$ ct get --index badpub.index local/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed           # 没有先报 publisher 错
                                                      # exit 1
```

最小下一步（DEV，P2，冻结期允许的 bugfix）：

1. 先提 `test(pkg): PKG-20 A2 红`（baseline = 本卡复核时的 `38cd4ae4`），覆盖 name /
   publisher=`local` / version 形状 / tag 四类负例；
2. 在 `pkg_index_lookup` 返回成功前，对**被选中**的六字段行执行与 verify 相同的校验：
   `index_name_ok(tok[0])`、publisher 非空/非 `local`/无 `/`、`index_version_ok(tok[1])`、
   `tag == 'v' + version`；失败在 clone / store / lock 之前；
3. 不做全文件扫描（未选中坏行不阻塞），不夹带 A1；跑 `p83_legacy` / `p83_verify` /
   conformance 三件套并同步 `differences.md`（D1 措辞、D2 字段数边界）。

## 处置（DEV，v0.88.3，2026-11-22）：fixed

`status` 保持 `open`（5.4：`fixed` 只写正文，由 REV 复核后改 `verified`）。

- **修复**：`pkg_index_lookup` 与 `pkg_index_verify` 共用 `index_row_parse` +
  `index_row_check`。`ct get` 在返回成功前对**被选中**的六字段行执行与 verify 相同的校验：
  `index_name_ok(tok[0])`、publisher 非空 / 非 `local` / 无 `/`、`index_version_ok(tok[1])`、
  `tag == 'v' + version`、`sha256:<64 lowercase>`；诊断带行号与类别（`identity` /
  `tag-version` / `digest`），文案与 verify 逐字相同。
- **失败原子性**：校验在 `git clone` / store / lock 之前；探针用测试替身 `git` 证明未调用，
  失败请求不写 `ct.lock` 与 `~/.ct/pkg/<publisher>/<name>`。
- **范围**：只校验**选中行**；未选中坏行不阻塞（不做 `ct get` 全文件扫描，与 verify 区分）。
- **测试**：新增 `test/ast/pkg19_20_rows.sh` 并接入 `selfhost/check-ast.sh`；覆盖
  badtag / badpub / badname / badver 四类选中行负例，以及合法六字段行与未选中坏行。
- **红证**：baseline `38cd4ae4`（`git archive 38cd4ae4 | tar -x` 后按 L0→L1→L2→ct-ast 链构建），
  `sh test/ast/pkg19_20_rows.sh <baseline ct-ast>` → exit 1；四类 `ct get` 均进入 `git clone`，
  缺 `line 1: identity:` / `line 1: tag-version:`（test 提交 `8f3d051b`）：
  ```console
  FAIL pkg19_20: a tag that is not v<version> get
    rc=1 ctc: git clone of 'file:///.../nope' failed
  FAIL pkg19_20: a tag that is not v<version> no git
    the resolver reached git
  FAIL pkg19_20: publisher = local get
    rc=1 ctc: git clone of 'file:///.../nope' failed
  FAIL pkg19_20: publisher = local no git
    the resolver reached git
  ```
- **绿证**（实现后，`ct-ast v0.88.3`，节选；完整 24 条见 PKG-19 处置）：
  ```console
  ok   a tag that is not v<version>: verify reports tag-version
  ok   a tag that is not v<version>: get reports tag-version before fetch
  ok   a tag that is not v<version>: get does not invoke git
  ok   a tag that is not v<version>: get leaves ct.lock and store untouched
  ok   publisher = local: verify reports identity
  ok   publisher = local: get reports identity before fetch
  ok   publisher = local: get does not invoke git
  ok   publisher = local: get leaves ct.lock and store untouched
  ok   a name outside [a-z0-9][a-z0-9-]*: get reports identity before fetch
  ok   a version that is not x.y.z: get reports identity before fetch
  ok   a legal six-field row still installs with the same lock row and digest
  ok   an unselected seven-field row does not block a legal request
  pkg19_20: OK
  ```
- **同提交验证**：`p83_legacy` / `p83_verify` / conformance 19/0 / `p87_dogfood` / `p88_metrics`
  9/0 / check-all 11 门（见提交正文）。
- **版本/文档**：v0.88.3（PATCH，V-3）；五处 `CTC_VERSION` + 51 golden/p39 ABI banner +
  README / docs/README / AGENTS / test/README + p80/p81/p82 断言；`differences.md` D2 标记已消除。
- **未覆盖**：digest 仍沿用既有 `sha_hex_ok`（被选中行在候选阶段即排除坏 digest，
  错误不新增行号）；不做全文件扫描与 duplicate 检测（verify 的职责，全文件预检转 v1.1）。
  PKG-20 与 PKG-19 共用同一次 fix（v0.88.3），未拆两个实现提交（用户本轮口径）。

## §复核通过（REV，2026-11-22，HEAD `7061aa22`）

与 PKG-19 共用同一次归档自举（`git archive 7061aa22` → L0→L1→L2→ct-ast，
`ct-ast v0.88.3`，产物 sha256 `2aa21806076d58caea22f3ed3a0fb60d2245f3bd488780cd7c612401ed6dcdcd`；
探针 sha256 `02c1d95e11d2f5580e66bb6441c3eaa4437b3d67b3097a9b24cd502a6fe365c3`）。
完整自举命令、24 条绿证与回归命令见 [PKG-19](pkg-19-get-index-field-count.md) 的 §复核通过，本节只列 A2 相关断言。

### 绿证（A2 四类选中行）

```console
$ sh test/ast/pkg19_20_rows.sh /tmp/rev-pkg3/ct-ast
ok   a tag that is not v<version>: get reports tag-version before fetch
ok   a tag that is not v<version>: get does not invoke git
ok   a tag that is not v<version>: get leaves ct.lock and store untouched
ok   publisher = local: get reports identity before fetch
ok   publisher = local: get does not invoke git
ok   publisher = local: get leaves ct.lock and store untouched
ok   a name outside [a-z0-9][a-z0-9-]*: get reports identity before fetch
ok   a version that is not x.y.z: get reports identity before fetch
ok   a legal six-field row still installs with the same lock row and digest
ok   an unselected seven-field row does not block a legal request
pkg19_20: OK                                        # exit 0
```

诊断原文（与 verify 同文案、同 `line 1` 行号）：

```console
line 1: tag-version: index tag 'v9.9.9' must be 'v0.1.0'
line 1: identity: index publisher 'local' must be non-empty, not 'local', without '/'
line 1: identity: index package name 'Foo' must match [a-z0-9][a-z0-9-]*
line 1: identity: index version '1.0' must be x.y.z
```

### 红证复跑

基线 `38cd4ae4`（`ct-ast v0.88.2`）上，四类 `ct get` 全部进入 `git clone`、缺对应诊断；
`pkg19_20` exit 1、10 条断言红（七字段 1 类 + 身份 4 类，各 `get` + `no git`；其中身份 8 条），
与 DEV 记录一致，证明探针覆盖本次修复而非空转。

### 逐条对照

| 卡内期望 | 复核结果 |
| --- | --- |
| `index_name_ok(tok[0])` | 成立：`index_row_check` 统一执行，错误类别 `identity` |
| publisher 非空 / 非 `local` / 无 `/` | 成立：同一函数，文案与 verify 逐字相同 |
| `index_version_ok(tok[1])` | 成立：同上 |
| `tag == 'v' + version` | 成立：类别 `tag-version`，`line 1` 行号来自 lookup 的 `lineno` |
| digest 保持既有检查 | 成立：`sha_hex_ok(tok[5])` 仍在同一校验点；被选中行坏 digest 仍由候选阶段排除（卡内「未覆盖」） |
| 失败先于 clone / store / lock | 成立：`best_bad` 在返回前 `return -1`；替身 `git` 无调用标记、lock/store 未写 |
| 未选中坏行不阻塞 | 成立：`ct get` 只校验选中行，verify 仍全文件扫描 |
| 合法六字段行不变 | 成立：锁行 `acme/util 1.1.0 git … <digest>` 与基线一致，verify `OK (1 rows)` |

结论：PKG-20 的修复与验收在归档自举上独立复现；`open` → `verified`。
