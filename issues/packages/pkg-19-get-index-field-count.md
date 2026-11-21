# PKG-19 · A1：`ct get` 索引行字段数未对齐六字段（bugfix）

| 项 | 值 |
| --- | --- |
| 模块 | packages / 消费侧索引读取 |
| 定性 | **bugfix**（对齐已成文契约；冻结期允许） |
| 严重度 | Medium |
| 锚点 | v0.84.1（2026-11-21） |
| 依据 | [对齐清单 A1](../planning/ct-pkg-index-alignment.md)、[契约 §3.2](../planning/ct-pkg-get-contract.md#32-索引行)、[D-014](../decisions/D-014.md) 第 5 条 |
| 状态 | verified |
| 处置证据 | **verified（REV 独立复核，2026-11-22，HEAD `7061aa22`）：归档自举 + 24/24 探针绿 + 基线 `38cd4ae4` 的 10 条红证复跑；见 §复核通过** |

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

## 处置（DEV，v0.88.3，2026-11-22）：fixed

`status` 保持 `open`（5.4：`fixed` 只写正文，由 REV 复核后改 `verified`）。

- **修复**：`pkg_index_lookup` 与 `pkg_index_verify` 现在共用 `index_row_parse`（逐行切字段）
  与 `index_row_check`（字段数 / legacy / name / publisher / version / tag / digest）。
  `ct get` 对**被选中**的行执行同一校验：七字段行在返回前报
  `line 1: field-count: index row has 7 fields; six are required`，不再进入 `git clone`。
- **不变量**：五字段行走 `index_row_check` 的 legacy 分支，文案
  `index row for '<spec> <ver>' is legacy (five fields); a six-field row is required` 不变；
  六字段合法行的选择、锁行、digest 不变；未选中坏行不阻塞（不做全文件扫描）。
- **失败原子性**：探针把测试替身 `git` 放在 PATH 首位；失败请求不留下调用标记，
  `ct.lock` 与 `~/.ct/pkg/<publisher>/<name>` 均不出现。
- **测试**：新增 `test/ast/pkg19_20_rows.sh` 并接入 `selfhost/check-ast.sh`（`p83_probe rows`），
  覆盖七字段、badtag、badpub、badname、badver、合法六字段行、未选中坏行、verify 全文件扫描。
- **红证**：baseline `38cd4ae4`（`git archive 38cd4ae4 | tar -x` 后按 L0→L1→L2→ct-ast 链构建），
  `sh test/ast/pkg19_20_rows.sh <baseline ct-ast>` → exit 1；七字段行的 `ct get` 进入
  `git clone`，缺 `line 1: field-count:`，10 条断言红（test 提交 `8f3d051b`）：
  ```console
  FAIL pkg19_20: a seven-field row get
    rc=1 ctc: git clone of 'file:///.../nope' failed
    cause: the package cache is corrupt
  FAIL pkg19_20: a seven-field row no git
    the resolver reached git
  ```
- **绿证**（实现后，`ct-ast v0.88.3`）：
  ```console
  $ sh test/ast/pkg19_20_rows.sh <ct-ast>
  ok   a seven-field row: verify reports field-count
  ok   a seven-field row: get reports field-count before fetch
  ok   a seven-field row: get does not invoke git
  ok   a seven-field row: get leaves ct.lock and store untouched
  ok   a tag that is not v<version>: verify reports tag-version
  ok   a tag that is not v<version>: get reports tag-version before fetch
  ok   a tag that is not v<version>: get does not invoke git
  ok   a tag that is not v<version>: get leaves ct.lock and store untouched
  ok   publisher = local: verify reports identity
  ok   publisher = local: get reports identity before fetch
  ok   publisher = local: get does not invoke git
  ok   publisher = local: get leaves ct.lock and store untouched
  ok   a name outside [a-z0-9][a-z0-9-]*: verify reports identity
  ok   a name outside [a-z0-9][a-z0-9-]*: get reports identity before fetch
  ok   a name outside [a-z0-9][a-z0-9-]*: get does not invoke git
  ok   a name outside [a-z0-9][a-z0-9-]*: get leaves ct.lock and store untouched
  ok   a version that is not x.y.z: verify reports identity
  ok   a version that is not x.y.z: get reports identity before fetch
  ok   a version that is not x.y.z: get does not invoke git
  ok   a version that is not x.y.z: get leaves ct.lock and store untouched
  ok   a legal six-field row still installs with the same lock row and digest
  ok   verify still accepts the legal six-field row
  ok   an unselected seven-field row does not block a legal request
  ok   verify still scans the whole file and reports the unselected bad row
  pkg19_20: OK
  ```
- **同提交验证**：`p83_legacy` / `p83_verify` / conformance 19/0 / `p87_dogfood` / `p88_metrics`
  9/0 / check-all 11 门（见提交正文）。
- **版本/文档**：v0.88.3（PATCH，V-3）；五处 `CTC_VERSION` + 51 golden/p39 ABI banner +
  README / docs/README / AGENTS / test/README + p80/p81/p82 断言；`differences.md` D2 标记已消除。
- **未覆盖**：字段数 < 5 的行仍由 `ct get` 跳过（缺 url/tag/digest，无法成为候选），
  `ct index verify` 仍按全文件报 `field-count`；不做 `ct get` 全文件预检（非目标，转 v1.1）。
  PKG-19 与 PKG-20 共用同一次 fix（v0.88.3），未拆两个实现提交（用户本轮口径）。

## §复核通过（REV，2026-11-22，HEAD `7061aa22`）

独立复核，不复用工作树产物：从 `git archive 7061aa22` 自举整条链，红绿双向复跑。
PKG-19 置 `verified`。

### 1. 归档与自举

```console
$ mkdir -p /tmp/rev-pkg3/src && git archive 7061aa22 | tar -x -C /tmp/rev-pkg3/src
$ gcc -Wall -Wextra -Wno-format-truncation -Wno-implicit-fallthrough -std=c99 \
      selfhost/l0/ctc.c -o /tmp/rev-pkg3/ctc-l0
$ /tmp/rev-pkg3/ctc-l0 selfhost/l1/ctc.ct -o /tmp/rev-pkg3/l1.c
$ gcc -Wall -Wextra -std=c99 /tmp/rev-pkg3/l1.c -o /tmp/rev-pkg3/ctc-l1
$ /tmp/rev-pkg3/ctc-l1 build selfhost/l2/driver.ct -o /tmp/rev-pkg3/l2
$ gcc -Wall -Wextra -std=c99 /tmp/rev-pkg3/l2/*.c -o /tmp/rev-pkg3/ctc-l2
$ /tmp/rev-pkg3/ctc-l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev-pkg3/ast
$ gcc -Wall -Wextra -std=c99 /tmp/rev-pkg3/ast/*.c -o /tmp/rev-pkg3/ct-ast
$ /tmp/rev-pkg3/ct-ast --version
ct-ast v0.88.3
```

归档 sha 核对（`shasum -a 256`）：

| 对象 | sha256 |
| --- | --- |
| 归档内 `selfhost/ct-ast/tool/pkg/Pkg.h.ct` | `6faa0ef08638fb5e77696cc805f55727fbe74ca027de584f443db6f2f3e4218f` |
| 归档内 `test/ast/pkg19_20_rows.sh` | `02c1d95e11d2f5580e66bb6441c3eaa4437b3d67b3097a9b24cd502a6fe365c3` |
| 自举产物 `ct-ast` | `2aa21806076d58caea22f3ed3a0fb60d2245f3bd488780cd7c612401ed6dcdcd` |

### 2. 绿证（HEAD `7061aa22`）

```console
$ sh test/ast/pkg19_20_rows.sh /tmp/rev-pkg3/ct-ast
ok   a seven-field row: verify reports field-count
ok   a seven-field row: get reports field-count before fetch
ok   a seven-field row: get does not invoke git
ok   a seven-field row: get leaves ct.lock and store untouched
ok   a tag that is not v<version>: verify reports tag-version
ok   a tag that is not v<version>: get reports tag-version before fetch
ok   a tag that is not v<version>: get does not invoke git
ok   a tag that is not v<version>: get leaves ct.lock and store untouched
ok   publisher = local: verify reports identity
ok   publisher = local: get reports identity before fetch
ok   publisher = local: get does not invoke git
ok   publisher = local: get leaves ct.lock and store untouched
ok   a name outside [a-z0-9][a-z0-9-]*: verify reports identity
ok   a name outside [a-z0-9][a-z0-9-]*: get reports identity before fetch
ok   a name outside [a-z0-9][a-z0-9-]*: get does not invoke git
ok   a name outside [a-z0-9][a-z0-9-]*: get leaves ct.lock and store untouched
ok   a version that is not x.y.z: verify reports identity
ok   a version that is not x.y.z: get reports identity before fetch
ok   a version that is not x.y.z: get does not invoke git
ok   a version that is not x.y.z: get leaves ct.lock and store untouched
ok   a legal six-field row still installs with the same lock row and digest
ok   verify still accepts the legal six-field row
ok   an unselected seven-field row does not block a legal request
ok   verify still scans the whole file and reports the unselected bad row
pkg19_20: OK                                        # exit 0
```

### 3. 红证复跑（证明探针非空转）

基线 `38cd4ae4` 归档后按同一 L0→L1→L2→ct-ast 链构建（`ct-ast v0.88.2`），把 `8f3d051b` 的探针放到同一路径跑：

```console
$ sh test/ast/pkg19_20_rows.sh /tmp/rev-pkg3/base/ct-ast
ok   a seven-field row: verify reports field-count
FAIL pkg19_20: a seven-field row get
  rc=1 ctc: git clone of 'file:///…/nope' failed
  cause: the package cache is corrupt
FAIL pkg19_20: a seven-field row no git
  the resolver reached git
…（badtag / badpub / badname / badver 同形）
FAIL pkg19_20: a version that is not x.y.z no git
  the resolver reached git
                                                     # exit 1（5 类 × 2 条 = 10 条红，未打印 OK）
```

### 4. 回归三件套（同一归档构建）

```console
$ sh test/ast/p83_legacy.sh /tmp/rev-pkg3/ct-ast
p83_legacy: OK                                       # exit 0
$ sh test/ast/p83_verify.sh /tmp/rev-pkg3/ct-ast
p83_verify: OK                                       # exit 0
$ sh test/conformance/pkg/run.sh --ct /tmp/rev-pkg3/ct-ast
conformance: 19 passed, 0 failed (data: v1)          # exit 0
```

### 5. 逐条对照

| 卡内期望 | 复核结果 |
| --- | --- |
| `ntok != 6`（五字段除外）报 `field-count`，文案同 verify | 成立：`index_row_parse` → `index_row_check` 是唯一判定点，lookup 与 verify 都调用；`line 1: field-count: index row has 7 fields; six are required` 两边逐字一致 |
| 五字段行仍 legacy、文案不变 | 成立：`index_row_check` 先判 `ntok == 5` 走 `index_legacy_msg`；`p83_legacy` OK |
| 失败先于 `git clone` / store / lock | 成立：lookup 在 `best_bad` 分支返回前不取回；替身 `git` 未留下调用标记；`ct.lock` 与 `~/.ct/pkg/pub/foo` 均未出现 |
| 只改 lookup 与测试，不改索引格式 | 成立：`git show 7061aa22` 的 Pkg 改动只在行解析/校验，索引读写格式未变；六字段合法行的锁行与 digest 不变 |
| 未选中坏行不阻塞 | 成立：`mixed.index` 选合法行成功，verify 仍按全文件报 `line 2: field-count:` |

结论：修复与验收在归档自举上独立复现，无回归、无漏项；`open` → `verified`。
