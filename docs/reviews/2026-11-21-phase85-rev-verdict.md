# PH-85（v0.85.0）REV 复核

> 复核席位：REV（`rev-ph85`） · 2026-11-21
> 对象：`e0b0c5616931567742f89124de98e2bbc1a2884d`（HEAD，未 push、未 tag）
> 环境：macOS arm64；Apple clang 21.0.0；Python 3.15.2
> 方法：`git archive e0b0c561` 解到 `/tmp/ph85rev`，按项目方式独立自举
> L0→L1→L2→ct-ast；四探针只用该归档产物 `/tmp/ph85rev/.temp/b/ct-ast`，未用工作树
> 二进制；另从 `git archive 10c23c77` 重建 M0 基线、从 `git archive e88561af` 复现
> M0 提交。未改实现；未 push、未 tag。
> 结论：**REV: 不通过（打回）**。E85-1/3/4/5/6 通过；E85-2 按字面“门通过”不成立；
> E85-7 因干净归档 `check-docs` 死链失败；E85-8 的 `git revert` 回滚不可单独完成。
> 另有两个阻断项：F1（提交树死链）、F2（M0 实现提交不能独立构建）。

## 0 结论摘要

- **F1（阻断，E85-7）**：`e0b0c561` 的 `docs/README.md:21` 链接
  `guide-for-c-programmers.md`，但该文件及其引用的 SH-106 都不在提交树里。
  干净归档 `check-docs` 红；工作树因未跟踪文件而绿。收口记录 `check-docs: OK
  (2295 links / 377 files)` 也是加 guide 行之前的旧数（复核当时工作树 2318/378；
  之后另一会话的 pkg 文档提交把它推到 2323/379，归档前提不变）。
- **F2（阻断，T-7/T-4）**：M0 实现提交 `e88561af` 不能独立构建。`Driver`/`Parser`/
  `TypeCheck` 调用的 3 个搬移函数没有 import，import 在下一个提交 `c7f8ed93`（S85d）
  才补上；该提交的“全链零警告/不动点”与 `842 functions / 11 S85d edits` 都是
  S85d 之后的数字。`p85_m0` 探针不构建当前树，因此在该提交上仍可 4/4，掩盖了问题。
- **F3（判据，E85-2）**：卡 §1.3 要求“完整等价重写”且“spike 通过才排 PH-86–88”，
  E85-2 又写“门通过”；但 DEV 的 spike 只做结构拆分（`next` 309→39 行），没有迁移
  `Str` 视图/`?`/`errdefer`/`match`，报告 §4 自己记“整子系统新语法等价重写：不通过”。
  R85-1 只说“不通过则退化”，不能把 E85-2 变成通过。卡 §7.3 标 `⚠️`、§8 写“门不通过”，
  但 `AGENTS.md:508` 与 `docs/history/phase-log.md:187` 写“E85-1…8 通过”，三处不一致。
- **F4（E85-8）**：`git revert e88561af` 在 HEAD 上 `CONFLICT (modify/delete)`：
  S85d 后来改过 `ModuleBoundary.h.ct`；即使解掉冲突，S85d 的
  `import frontend::sym::SymbolsTypeText` 仍指向被删单元，单卡回滚不能干净完成。
- 通过项：E85-1（27 单元/44,474 行/842 函数/0 环）；E85-3 的源码纯搬移与 0 新环；
  E85-4 的基线/映射（从 `10c23c77` 重算逐键相等）；E85-5 的 `off/warn/error`
  （默认 off、warn 产物不变、error 写产物前失败）；E85-6 的 66 文件逐字节；
  warnings 500/500、sanitizer 586/586、g0/g8 通过；版本五处 0.85.0。
- 新增反例（§5）：`--check-level=error` 不写产物（含既有产物 sentinel 不被覆盖）；
  `warn` 与 `off` 产物逐字节一致（含 66 语料）；M0 搬移函数跨单元调用在
  range/generic/map/index verify 上 pre/post 一致。

## 1 独立自举

```console
$ rm -rf /tmp/ph85rev && mkdir -p /tmp/ph85rev
$ git archive e0b0c561 | tar -x -C /tmp/ph85rev
$ cd /tmp/ph85rev && sh build-ct-ast.sh . .temp/b
...
built .temp/b/ct-ast
$ .temp/b/ct-ast -v
ct-ast v0.85.0
```

构建链 L0/L1/L2/ct-ast 各步退出码 0；生成的 C 零告警。以下 `$CT` 均指
`/tmp/ph85rev/.temp/b/ct-ast`。

## 2 E85-1…8 逐条

| ID | 结果 | 命令 / 原始输出 | 判定 |
| --- | --- | --- | --- |
| E85-1 | ✅ | `python3 tools/p85_inventory.py --root . check --doc docs/design/p85_inventory.md` → `p85_inventory: 27 units, 44474 lines, 842 functions, 0 import cycles, every row matches the tree`；`bash test/ast/p85_inventory.sh` → `p85inventory: 9 passed, 0 failed` | 覆盖/状态/导入图可重算，文档与树逐格一致 |
| E85-2 | ❌（字面） | `bash test/ast/p85_spike.sh $CT` → `p85spike: 14 passed, 0 failed`；`git apply --check test/probes/p85_spike_lexer.patch` → 0；但报告 §4 自记“整子系统新语法等价重写：不通过”；patch 只加方法拆分，无新语法 | 度量/逐字节/sharp edge 齐；**“门通过”不成立**，见 §3 |
| E85-3 | ✅（源码）/ ⚠️（提交） | `python3 tools/p85_inventory.py --root . m0` → `827 bodies, 842 functions, 6 moved units, 11 declared S85d edits, 26 products, 0 cycles`；`bash test/ast/p85_m0.sh $CT` → `p85m0: 4 passed, 0 failed`；从 `10c23c77` 重算 baseline 逐键相等；环 0→0 | HEAD 上纯搬移成立；**M0 提交本身不绿**，见 F2 |
| E85-4 | ✅ | `p85_m0_mapping.tsv` 6 行、两端存在；baseline 20 产物，HEAD 26；探针 §2/§3 通过 | 基线/映射入库，集合比对可跑 |
| E85-5 | ✅ | `bash test/ast/p85_a_wire.sh $CT` → `p85a: 9 passed, 0 failed`；新反例 §5 → 12/12；66 语料 `off` vs `warn` → 66/66；`error` 无产物 | 默认 off、warn 不改产物、error 写前失败 |
| E85-6 | ✅ | `p85_m0` 的 66 文件清单 diff 空；把 spike patch 应用到归档并重建后，`corpus-manifest` 与 `test/probes/p85_corpus_sha.tsv` diff 空（66 行） | 测试语料发射逐字节不变 |
| E85-7 | ❌ | 归档 `check-all` → gate 8 `1561 passed / 0 failed / 5 skipped`、gate 9 `check-warnings: 500 ok`、gate 10 `check-semantics: OK (23)`，**gate 11 `check-docs` 红**，最终 `check-all: FAIL`；`check-sanitizers: OK (586 checks)`；`g0: OK`、`g8: OK (9 legacy offsets)` | 干净归档不是 11/11，见 F1 |
| E85-8 | ❌ | 文档/证据在库；`git revert e88561af` → `CONFLICT (modify/delete)`，`error: could not revert`；未得到干净单卡回滚 | 回滚描述不可复现，见 F4；enum/switch 子句未单独证伪 |

### 2.1 四探针（独立归档产物）

```console
$ cd /tmp/ph85rev
$ bash test/ast/p85_inventory.sh
p85inventory: 9 passed, 0 failed
$ bash test/ast/p85_spike.sh .temp/b/ct-ast
p85spike: 14 passed, 0 failed
$ bash test/ast/p85_m0.sh .temp/b/ct-ast
p85m0: 4 passed, 0 failed
$ bash test/ast/p85_a_wire.sh .temp/b/ct-ast
p85a: 9 passed, 0 failed
```

## 3 §判据裁定：E85-2

### 3.1 冲突文本

| 位置 | 原文要点 | 对 E85-2 的作用 |
| --- | --- | --- |
| 卡 §1.3（`docs/design/phase85.md:39-41`） | “选一个子系统……做**完整等价重写**”；“**spike 通过才排 PH-86–88**；不通过则退化为按 inventory 逐项替换” | 门 = 能否整体重写；不通过是 R85-1 的降级分支 |
| 卡 §2（`:64`） | S85b “单切片等价重写与度量” | 允许单切片，但仍叫“等价重写” |
| E85-2（`:76`） | “spike 报告含……；**门通过**” | 字面要求门通过 |
| R85-1（`:88`） | “spike 不通过 → 退化为逐项替换；不进入整体重写” | 允许不通过后继续，但没把 E85-2 改成通过 |

### 3.2 事实

`test/probes/p85_spike_lexer.patch` 的 `next` 拆分确实是等价重构：

```console
$ grep -nE '^\+.*(void|int) (pp_line|ident|number|quoted|punct|lex_ident_start)' test/probes/p85_spike_lexer.patch
8:+    void pp_line(void);
9:+    void ident(void);
10:+    void number(void);
11:+    void quoted(int c);
12:+    void punct(int c);
22:+static int lex_ident_start(int c)
```

新增行里没有 `?`/`errdefer`/`match`/`Str` 视图的使用（`grep -E '\?|defer|match|Str'`
只命中注释里的 `=>`/`&&`/`||` 说明）。报告自己写：

```console
$ grep -n "结构等价\|不通过（未覆盖）\|门的含义" docs/design/p85_spike.md
70:| 结构等价（拆分、逐字节语料、不动点、零告警） | **通过**（§1/§2 原始输出） |
71:| 整子系统“新语法等价重写”（`Str` 视图 / `?` / `defer` / `match`） | **不通过（未覆盖）**：… |
72:| 门的含义（卡 §1.3 / R85-1） | **作为“PH-86 可以一次整体重写”的门：不通过。** 按 R85-1 退化为… |
```

### 3.3 裁定

**E85-2 按字面判“不通过”。** 理由：

1. E85-2 的断言是“门通过”，而报告、卡 §7.3、卡 §8 三处都承认门**没有**通过；
   结构等价 + 度量 + sharp edges 是 E85-2 的前半句，不是“门通过”的替代品。
2. R85-1 是**风险处置**，不是**判据改写**：它允许 PH-86–88 走逐项替换，但不把
   “门不通过”记成“E85-2 通过”。收口记录写“E85-1…8 通过”与卡面自相矛盾。
3. 因此 PH-85 可以按 R85-1 的**降级路径**继续，但必须由 EDITOR 签一条 decision
   明确“E85-2 的验收 = spike 已执行 + 度量/逐字节/sharp edges + 明确门结论”，
   并把整体新语法重写移交 PH-86 的 per-function 切片；不得在 decision 之前把
   E85-2 记成 ✅。

### 3.4 最小补做范围

- **推荐（无代码）**：一条签收 decision（`docs/decisions/D-<n>.md`），内容三项：
  ① E85-2 降级口径（spike 已执行 + 度量 + 逐字节 + sharp edges + 明确门结论）；
  ② 整子系统新语法重写按 R85-1 移交 PH-86，PH-86 卡按
  “punct → number → quoted/pp_line → `Str` 视图”拆，不承诺整体重写；
  ③ `AGENTS.md:508`、`docs/history/phase-log.md:187`、卡 §7.3 三处统一改写。
  这是最小补做，且与 R85-1 一致。
- **若坚持字面门**：补一次真正的完整新语法等价重写（至少一个完整子系统，含
  `Str` 视图/`?`/`defer`/`match` 中适用部分），以 66 语料逐字节、自举不动点、ASan
  为证。词法器的 sharp edge（`Str` 视图波及 Parser/Expr/Stmt、无错误通道）使它
  实质是 PH-86 的工作量；放在 PH-86 更符合卡 §2.3 的分段，不应回填 PH-85。

## 4 阻断项最小复现

### 4.1 F1：干净归档 `check-docs` 死链

```console
$ R=$(mktemp -d /tmp/ph85docs.XXXXXX); git archive e0b0c561 | tar -x -C "$R"
$ (cd "$R" && python3 test/docs/check-docs.py); echo rc=$?
FAIL: docs/README.md: dead link -> guide-for-c-programmers.md
spec pin: skipped (master spec draft 1.17.0)
check-docs: FAIL (1 problem(s))
rc=1
```

把工作树的未跟踪 guide 补进归档后，guide 又链到未入库的 SH-106：

```console
$ cp docs/guide-for-c-programmers.md "$R/docs/"
$ (cd "$R" && python3 test/docs/check-docs.py); echo rc=$?
FAIL: docs/guide-for-c-programmers.md: dead link -> ../issues/selfhost/sh106-str-view-escape-no-lint.md
check-docs: FAIL (1 problem(s))
rc=1
```

同一命令在工作树是绿的（未跟踪文件恰好存在；复核当时 2318/378，之后另一会话的
pkg 文档提交把工作树推到 2323/379，归档前提不变）：

```console
$ python3 test/docs/check-docs.py; echo rc=$?
check-docs: OK (2318 relative links in 378 files, v0.85.0, 11 hard gates, 12 phase status, 6 适用版本 header(s), 2 superseded link(s), 10 signoff(s))
rc=0
```

卡 §7.4 的 2295/377 是加 guide 行之前的数；加行后没有用归档重跑。
详见 [DOC-81](../../issues/docs/doc-81-phase85-clean-archive-dead-link.md)。

### 4.2 F2：M0 实现提交不能独立构建

```console
$ R=$(mktemp -d /tmp/ph85m0.XXXXXX); git archive e88561af | tar -x -C "$R"
$ cp .temp/build-ct-ast.sh "$R"/ && cd "$R" && sh build-ct-ast.sh . .temp/b; echo rc=$?
...
selfhost/ct-ast/tool/driver/Driver.h.ct:660:17: error: call to undeclared function 'frontend_module_ct_append_flags'; ...
selfhost/ct-ast/frontend/parse/Parser.h.ct:1282:13: error: call to undeclared function 'frontend_sym_ct_type_canon'; ...
selfhost/ct-ast/frontend/type/TypeCheck.h.ct:224:17: error: call to undeclared function 'frontend_sym_ct_generic_subst'; ...
selfhost/ct-ast/frontend/type/TypeCheck.h.ct:230:17: error: call to undeclared function 'frontend_sym_ct_generic_subst'; ...
rc=1
```

`c7f8ed93` 才补上 `import frontend::module::ModuleBoundary;` 与两处
`import frontend::sym::SymbolsTypeText;`。所以 `e88561af` 不是 T-7 意义上的“实现提交
随后转绿”；`p85_m0` 探针只验源码/映射/外部传入的 `<ct-ast>`，不构建当前树，故没抓到。
详见 [SH-107](../../issues/selfhost/sh107-m0-commit-not-buildable.md)。

### 4.3 F4：回滚冲突

```console
$ git revert --no-edit e88561af
Auto-merging selfhost/ct-ast/frontend/module/Module.h.ct
CONFLICT (modify/delete): selfhost/ct-ast/frontend/module/ModuleBoundary.h.ct deleted in parent of e88561af (...) and modified in HEAD.  Version HEAD of ... left in tree.
Auto-merging selfhost/ct-ast/frontend/parse/Expr.h.ct
error: could not revert e88561af...
```

即使解掉冲突，S85d 在 `Parser`/`TypeCheck` 留下的 `import frontend::sym::SymbolsTypeText`
仍指向被删单元，单卡回滚不成立。卡 §7.5 需要写成“M0 + 依赖 import 一起回退”，或给出
冲突解法与演练输出。

## 5 独立反例（新增，非四探针）

### 5.1 A：`error` 必须在写产物前失败（含既有产物不被覆盖）

```console
$ # 预置 out/src_mismatch.c = SENTINEL；`--check-level=error` 后
$ $CT build --emit-c --check-level=error mismatch.ct -o out
mismatch.ct:3:12: error: return: expected 'int', got 'char *'
ctc: 1 error(s) generated
rc=1
$ cat out/src_mismatch.c
SENTINEL
$ find out -type f
out/src_mismatch.c            # 没有新增/覆盖任何产物
```

编译模式（`-o out/prog`）与默认 `a.out` 也都在写产物前退出；合法程序在 `error`
档仍正常写 2 个产物 / 可执行文件。完整脚本 `/tmp/rev85/driver-a.sh` → 12/12。

### 5.2 A：`warn` 不得改产物

```console
$ bash /tmp/rev85/corpus-warn.sh
corpus warn: 66 passed, 0 failed
```

66 个 `test/cases/*.ct` + `examples/*/*.ct` 的 `off` vs `warn` 发射 C/头逐文件相同
（banner 归一化）；`default` vs `off` 也相同。定向用例还比较了编译模式的可执行文件
与 `.ctbuild` 产物，均相同；`warn` 只多一行 `warning: return: expected 'int', got 'char *'`。

### 5.3 M0：搬移函数在跨单元调用点行为一致

pre-M0 编译器 = `10c23c77` 归档构建（`ct-ast v0.84.1`），post = HEAD 归档
（`v0.85.0`）。用 3 个**新**输入（非语料）对比发射 C 与运行输出：

```console
$ bash /tmp/rev85/driver-m0.sh
ok  range_new: emitted C identical pre/post M0
ok  range_new: program output identical (rc 0)
ok  generic_new: emitted C identical pre/post M0
ok  generic_new: program output identical (rc 0)
ok  map_new: emitted C identical pre/post M0
ok  map_new: program output identical (rc 0)
M0 driver: 6 passed, 0 failed
```

另比 `ct index verify`（PkgIndex 的 6 个搬移函数）：

```console
$ $PRE index verify bad.index; echo rc=$?
...
line 3: legacy-five-field: index row for 'old 1.0.0' is legacy (five fields); ...
line 4: field-count: index row has 4 fields; six are required
line 5: digest: index digest must be sha256:<64 lowercase hex>
line 6: tag-version: index tag 'v2.0.0' must be 'v1.0.0'
line 7: duplicate: index row 'acme/util 1.0.0' appears more than once
index verify: FAIL (5 invalid of 6 rows)
rc=1
```

pre/post 的 stdout/stderr **逐字节相同**（`diff` 空）。这证明 HEAD 上 6 个新单元的
调用点行为一致；它不抵消 F2（M0 提交本身缺 import）。

## 6 门禁与版本原始输出

```console
$ cd /tmp/ph85rev && TMPDIR=/tmp/ph85tmp bash selfhost/check-all.sh
...
== summary: 1561 passed, 0 failed, 5 skipped ==      # check-ast
check-warnings: 500 ok, 0 failed
check-semantics: OK (23 assertions)
FAIL: docs/README.md: dead link -> guide-for-c-programmers.md
FAIL: 11) docs (links, version, gate count, phase status) (exit 1)
...
check-all: FAIL (at least one hard gate failed)
rc=1

$ TMPDIR=/tmp/ph85tmp bash selfhost/check-sanitizers.sh
check-sanitizers: OK (586 checks, no sanitizer report)
rc=0
```

`check-ast` 是 1561 passed / 5 skipped（卡 §7.4 记 1562 / 4；本机多 1 个 host 工具
skip，与 PH-84 复核时的差异同类）。四探针在 check-ast 内均为 `ok`
（`p85/inventory`、`p85/spike`、`p85/m0`、`p85/a-wire`）。

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
```

版本五处（`CTC_VERSION`）与 README/docs/AGENTS/phase-log：

```console
$ for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
>   printf '%-32s ' "$f"; grep -o 'CTC_VERSION "[0-9.]*"' "$f" | head -1; done
selfhost/l0/ctc.c                CTC_VERSION "0.85.0"
selfhost/l1/ctc.ct               CTC_VERSION "0.85.0"
selfhost/l2/core.ct              CTC_VERSION "0.85.0"
selfhost/l2/driver.ct            CTC_VERSION "0.85.0"
selfhost/ct-ast/main.ct          CTC_VERSION "0.85.0"
```

## 7 非阻断 / 说明

1. **E85-2 的度量/证据本身可信**：独立应用 `p85_spike_lexer.patch` 后重建，66 文件
   `corpus-manifest` 与 `p85_corpus_sha.tsv` diff 空；结构拆分（`next` 309→39）与
   报告一致。问题只在“门通过”的口径，不在 patch 的可应用性或语料一致性。
2. **E85-3 的源码纯搬移可信**：从 `10c23c77` 重算的 `p85_m0_baseline.json` 与入库
   文件逐键相等（827 body、20 产物、0 环、units/lines/functions 全等）；HEAD 上
   6 个新单元只含自由函数、不 import 宿主、0 新环；映射 6 行两端存在。
3. **A 的默认值/降级语义**：`off` 与 default 产物逐字节一致；`warn` 只改 stderr；
   `error` 在 `nsem` 检查处失败。编译模式的 `error` 会先创建空的 `.ctbuild/`
   目录（无文件），不构成产物写入；`--emit-c` 路径不创建。
4. **`ct check --types` 不变**：probe 7/8 与 §5 的定向用例均保持原错误文案；
   `ct check --check-level` 仍被拒。
5. **`p85_m0` 的探针缺口**：它接受外部 `<ct-ast>`，不构建当前树；建议把
   “用当前树构建的 ct-ast”作为前置，或由 check-ast 的构建段兜底（F2 的根因之一）。
6. **`p85_spike` 的探针缺口**：它只校验 patch 可应用、证据自洽、当前语料一致，
   不应用 patch 重建；本次复核已手工应用并验证 66 文件一致，但探针本身不能替代。
7. **工作树/归档差异**：复核时工作树含其他会话的未跟踪文件（`docs/guide-for-c-programmers.md`、
   `issues/selfhost/sh106-...`、`battle/ct-guide-1/**`、`docs/memory-guide.md` 改动）。
   本复核只以 `git archive e0b0c561` 为准；未把那些文件计入 PH-85 绿证。

## 8 证据限制

- 未 push、未 tag；F1/F2 的修复需要 DEV 在未 push 前处理（F2 可能要求重排 M0 提交）。
- 未运行 `enum`/`switch` 的专项回滚行为对比：F4 已证明回滚命令本身不干净，因此
  E85-8 的“单卡回滚”判据不成立；enum/switch 是否受 M0 影响没有单独判。
- `check-sanitizers` 与 `check-all` 分工：前者单独跑（586/586），后者不包含 sanitizer；
  两者均在归档树上跑。
- `check-all` 的 gate 11 红灯是 F1；gate 1–10 在该归档上通过。工作树 `check-docs` 绿
  只说明未跟踪文件在场，不能作为提交证据。
- 本复核未修改 `docs/design/phase85.md`、源码、测试或版本；只提交本文件与
  [DOC-81](../../issues/docs/doc-81-phase85-clean-archive-dead-link.md)、
  [DOC-82](../../issues/docs/doc-82-phase85-e85-2-gate.md)、
  [SH-107](../../issues/selfhost/sh107-m0-commit-not-buildable.md)。
