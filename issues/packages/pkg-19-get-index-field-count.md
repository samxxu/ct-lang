# PKG-19 · A1：`ct get` 索引行字段数未对齐六字段（bugfix）

| 项 | 值 |
| --- | --- |
| 模块 | packages / 消费侧索引读取 |
| 定性 | **bugfix**（对齐已成文契约；冻结期允许） |
| 严重度 | Medium |
| 锚点 | v0.84.1（2026-11-21） |
| 依据 | [对齐清单 A1](../planning/ct-pkg-index-alignment.md)、[契约 §3.2](../planning/ct-pkg-get-contract.md#32-索引行)、[D-014](../decisions/D-014.md) 第 5 条 |
| 状态 | open |
| 处置证据 | **open（REV 复核仍复现，2026-11-22，HEAD `38cd4ae4`；A1 未实现）** |

## 现象

七字段索引行（六字段 + 多余列）在 `ct index verify` 被拒，但在 `ct get --index` 被接受，
直接进入 `git clone`；两处判定不一致。

```console
$ ct index verify /tmp/ct-idx-probe/idx7
line 1: field-count: index row has 7 fields; six are required
index verify: FAIL (1 invalid of 1 rows)          # exit 1

$ ct get --index /tmp/ct-idx-probe/idx7 pub/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed       # 没有先报字段数
```

`idx7` 内容：

```text
foo 0.1.0 pub file:///tmp/nope v0.1.0 sha256:<64 个 0> EXTRA
```

## 根因

`pkg_index_lookup` 收集最多 8 个 token，只按 `legacy = (ntok < 6)` 分类，`>6` 静默忽略
（[Pkg.h.ct:2412-2440](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2412-L2440)）；
`pkg_index_verify` 要求 `ntok == 6`
（[Pkg.h.ct:2666-2679](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2666-L2679)）。

## 期望

- `pkg_index_lookup` 对 `ntok != 6`（且非五字段 legacy）报 `field-count`，文案与 verify 一致：
  `index row has <n> fields; six are required`；
- 五字段行保持现有 legacy 判定与文案（`index row ... is legacy (five fields)`）；
- 失败发生在任何 `git clone` / store / lock 写入之前；
- 只改 `pkg_index_lookup` 与对应测试，不改索引格式。

## 兼容断言

| 用例 | 断言 |
| --- | --- |
| 六字段合法行 | 与现状一致，`ct get` / `ct install` 正常 |
| 五字段旧行 | 仍按 legacy 硬错，文案不变 |
| 七字段行 | `ct get` 与 `ct index verify` 均失败，且 `ct get` 不发起 git |
| 未选中坏行 | 不影响选中好行的 `ct get`（与 verify 的全文件扫描区分） |

## 验收与门禁

1. 先提 `test(pkg): PKG-19 A1 红`（baseline 见提交说明），覆盖七字段负例；
2. 实现后转绿；`ct index verify` 的既有探针不变；
3. 双 job：host + Linux x64，跑 `ct get → ct index verify → ct install → 运行比对`；
4. 单提交回滚；不夹带 A2 或 B/C 改动。

## 非目标

- `ct get` 全文件预检（契约外新行为，转 v1.1）；
- 原生 `ct index refresh`（[PKG-18](pkg-18-native-ct-index-refresh.md)）；
- index 仓脚本修复。

## 关联

- [PKG-21](pkg-21-ct-pkg-index-refactor-ruling.md)（总跟踪）
- [对齐清单](../planning/ct-pkg-index-alignment.md)
- [PKG-20](pkg-20-get-index-row-identity.md)（A2，独立提交）

## §复核（REV，2026-11-22，HEAD `38cd4ae4`）

A1 在 HEAD **未实现**，仍按卡内现象复现。源码现状：

- `pkg_index_lookup` 仍把 `char *tok[8]` 收满 8 个 token（`Pkg.h.ct:2680`），
  随后 `legacy = (ntok < 6)`（`Pkg.h.ct:2693`），`>6` 的多余列静默忽略；
- `pkg_index_verify` 仍要求 `ntok == 6`（`Pkg.h.ct:2937`），`ntok == 5` 走 legacy（`:2930`）。

复现（HEAD 构建的 `ct-ast v0.88.2`；`seven.index` 为六字段 + `EXTRA`，隔离 `HOME`/`CT_HOME`）：

```console
$ ct index verify seven.index
line 1: field-count: index row has 7 fields; six are required
index verify: FAIL (1 invalid of 1 rows)             # exit 1
$ ct get --index seven.index pub/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed           # 先进入取回，没有先报字段数
  git said (last 4 line(s); credentials redacted):
    fatal: '/tmp/nope' does not appear to be a git repository
    ...
                                                      # exit 1
```

未写 `ct.lock` / store（失败点仍在 clone 之后，但不符合“失败先于任何取回”的期望）。

最小下一步（DEV，P2，冻结期允许的 bugfix）：

1. 先提 `test(pkg): PKG-19 A1 红`（baseline = 本卡复核时的 `38cd4ae4`），覆盖七字段负例；
2. `pkg_index_lookup` 对 `ntok != 6`（五字段 legacy 除外）在选中后、返回前报
   `index row has <n> fields; six are required`，与 verify 同文案；
3. 跑 `sh test/ast/p83_legacy.sh`、`sh test/ast/p83_verify.sh`、`bash test/conformance/pkg/run.sh`，
   并同步 `test/conformance/pkg/differences.md` 的 D2（该表当前明确记着 `>6` 未收紧）。

本卡不做全文件预检（非目标），不夹带 A2。
