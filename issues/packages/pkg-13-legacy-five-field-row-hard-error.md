# PKG-13 · 五字段旧索引行改为按行硬错

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` 索引解析） |
| 定性 | 破坏性契约变更（推翻契约 I12 的“只读兼容”） |
| 严重度 | High（存量包会立即不可安装） |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [ct-pkg-get-contract.md](../../docs/planning/ct-pkg-get-contract.md) §3.2/§8、[ct-pkg-index.md](../../docs/ct-pkg-index.md) |
| 状态 | verified |
| 处置证据 | **verified（REV 复核，2026-11-22，HEAD `38cd4ae4`；`ct-ast` v0.88.2）** |

## 裁定

[D-014](../../docs/decisions/D-014.md) 第 5 条：五字段旧行**按行立即硬错**——请求的 spec 命中五字段行即失败；
索引中其余六字段行照常可用。契约 I12 已同步改写。

## 影响

- `ct/hal` 等仍是五字段旧行的包会立即不可安装；
- 官方 pin 表（`std`）不受影响，因为走编译期常量；
- index 仓必须先清零五字段行，再发布带硬错的 `ct` 版本。

## 期望行为

```text
$ ct get --index old.index acme/util@1.0.0
ctc: index row for 'acme/util 1.0.0' is legacy (five fields); a six-field row is required
```

- 请求命中旧行：退出码 1，不写 store、不写 lock；
- 请求命中六字段行：行为不变；
- 错误信息给出六字段形态示例。

## 发布前置（必须与 index 仓协同）

1. index 仓刷新全部行为六字段，并给出清零证明；
2. 本仓再发布硬错版本；或在硬错版本前先发“逻辑存在但默认关闭”的过渡版本；
3. 旧行清零后，方可删除兼容分支。

## 验收

- 新增夹具：旧行命中硬错、六字段行正常、混合索引按行判定；
- 契约 §9 验收第 4 条与实现一致；
- 发布说明写明破坏性变更与迁移步骤。

## 关联

- [D-014](../../docs/decisions/D-014.md)、[PKG-12](pkg-12-contract-v1-doc-gaps.md)
- [ct-pkg-index.md](../../docs/ct-pkg-index.md) §2/§3 需同步旧行为描述

## 处置（DEV，PH-83 S83b，2026-11-21）

- 实现：`ct get` 的索引解析在**请求解析命中**五字段行时硬错（`tool/pkg/Pkg.h.ct` 的
  `pkg_index_lookup`），消息为
  `ctc: index row for '<spec> <version>' is legacy (five fields); a six-field row is required`；
  同一文件里的六字段行照常安装；MVS/latest 选中旧行时同样失败；失败不写 store、不写 lock。
- `ct index verify` 扫描整份索引，逐行报 `legacy-five-field` 与其余坏行（契约 v1 §4.4）。
- 提交：`d22a5077`（红，探针）+ `b5873c40`（实现）。
- 证据：`test/ast/p83_legacy.sh` 9 条 ok（旧行命中、六字段不受影响、逐行判定、MVS、
  latest、verify 全量、lock 不变）；`test/ast/p83_verify.sh` 19 条 ok。
- 跨仓登记（不代改）：`ct-pkg/index@0cdb132` 的 `tools/verify-index.sh` 仍把五字段行当作
  `publisher = "-"` 回放（`:70-80`），与本仓“按行硬错”不一致；该脚本需由 index 仓自行
  更新（先清零旧行，再让回放失败）。本仓只登记，不改对方工作树。

## §复核（REV，2026-11-22，HEAD `38cd4ae4`）

在 HEAD 重新构建 `ct-ast`（`sh .temp/build-ct-ast.sh . .temp/rev-pkg-head`），二进制自报
`v0.88.2`；以下输出均来自该二进制。

```console
$ .temp/rev-pkg-head/ct-ast --version
ct-ast v0.88.2
$ sh test/ast/p83_legacy.sh .temp/rev-pkg-head/ct-ast
ok   a requested legacy row exits 1 with the contract message
ok   the legacy failure writes neither ct.lock nor store
ok   a six-field row installs even when the file has legacy rows
ok   the same package rejects @1.0.0 (legacy) while accepting @1.1.0
ok   MVS skips the lower legacy row for a range that excludes it
ok   MVS selects the lowest satisfying row and rejects it when legacy
ok   no range selects the highest row and rejects it when legacy
ok   verify reports every legacy row by line and skips the six-field row
ok   a failed legacy request leaves ct.lock byte-identical
p83_legacy: OK
$ sh test/ast/p83_verify.sh .temp/rev-pkg-head/ct-ast | tail -2
ok   comments and blank lines are not rows
p83_verify: OK
```

手工夹具（隔离 `HOME` / `CT_HOME`，`five.index` 恰为五字段；`six.index` 为同内容六字段）：

```console
$ ct index verify five.index
line 1: legacy-five-field: index row for 'oldutil 1.0.0' is legacy (five fields); a six-field row is required
index verify: FAIL (1 invalid of 1 rows)          # exit 1
$ ct index verify six.index
index verify: OK (1 rows)                          # exit 0
$ ct get --index five.index acme/oldutil@1.0.0
ctc: index row for 'acme/oldutil 1.0.0' is legacy (five fields); a six-field row is required
# exit 1；临时 cwd 内无 ct.lock，$HOME/.ct 下无 store
```

发布前置（旧行清零）的现状核对：2026-11-22 取到的官方索引 5 行全部为六字段
（`awk 'NF{print NF}' | sort | uniq -c` → `5 6`），本仓 `ct index verify` 对该索引退出 0
（`index verify: OK (5 rows)`）。**index 仓的书面时间表/确认**仍由
[PKG-16](pkg-16-external-baseline-and-schedule.md)（`deferred`）跟踪，不阻塞本卡的行为验收。

逐条对照验收：

- 旧行命中硬错、六字段行正常、混合索引按行判定：`p83_legacy` 9/9；
- 契约 §9 验收第 4 条（五字段命中即硬错、其余六字段仍可安装）：同上第 1/3 条；
- 发布说明/迁移口径：`docs/package-guide.md` §4 与 `docs/ct-pkg-index.md` §2 已写硬错与
  “index 仓先清零”的前置，`docs/history/phase-log.md` v0.83.0 条记录该行为。

结论：`verified`。
