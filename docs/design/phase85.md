# Phase 85 — v1-pre 准备：inventory / spike / M0 粗切 / A 机制

> **状态：完成**（2026-11-21 收口；`v0.85.0`；S85a–S85d 交付；E85-2 **有条件通过（D-018）**；REV 打回 F1–F4 修复见 §7.7）。
> **签收：EDITOR 2026-11-21**（主编统一签收；卡作者 REQ）。
> **施工闸门**：PH-84 已收口（含 S84e 文档一致性，`10c23c77`），闸门已过。
> **前置**：PH-84（ADT/match + 文档一致性）；[D-017](../decisions/D-017.md)、D1–D9。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase85.md`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-85（legacy 文件 `phase85.md`） |
| 目标 | 为重写建立度量、粗切边界与检查机制：inventory、单切片 spike、M0 粗切、A 机制接线 |
| 范围 | 子系统/函数集 inventory、spike 报告、M0 5–6 单元粗切、集合基线、状态清单、A `off/warn/error` |
| 非目标 | 完整重写（PH-86–88）；M1 精细切分（v1.1）；新语言特性；行为/发射格式变更 |
| 交付物 | inventory/spike 报告、M0 粗切提交、集合基线 + 旧→新映射、状态清单、A 机制 |
| 任务清单 | §2（S85a–S85d） |
| 退出判据 | E85-1…E85-8（§3） |
| version-minor | 85（PH-85，`d=0`） |
| 已知风险 | R85-1…R85-5（§4） |

## 1 需求与边界

### 1.1 判据两级制（D-017 A1）

- **测试语料**的发射产物逐字节不变；
- **编译器自身实现**的发射 C 允许差异；验收 = 自举不动点 + ASan + 行为测试；
- 两层禁止混用。

### 1.2 inventory（S85a）

- 按子系统列出函数集合、职责、文件级状态（`g_sb`/`g_slice_used`/`g_emit` 等）、
  import 图与环清单；
- 标出 R 切片将合并的 helper（`?`/errdefer/match 折叠），避免 M0 搬错对象。

### 1.3 spike（S85b）

- 选一个子系统（建议词法器或发射器）做完整等价重写；
- 产出：行数/编译耗时前后、测试语料逐字节一致的原始输出、sharp edge 清单；
- **spike 通过才排 PH-86–88**；不通过则退化为“按 inventory 逐项替换”，不承诺整体重写。

### 1.4 M0 粗切（S85c，D-017 C3）

- 按子系统粗切 **5–6 个单元**，零精细分类；
- 纯搬移：函数体哈希集合不变 + 机械行白名单（import/include/声明重排）；
- 允许 `static→pub` 的接口变化，但不得改行为；
- 单元名 `<Subsystem><Role>.h.ct`（PascalCase、全局唯一）；
- 期望文件集合基线 + 旧→新映射；同一 commit 更新；
- M 不新增 import 环；现状环破环单独成案；
- **单写者**：同一时刻只有一个会话持有搬移分支；合入窗口要求 `check-all` 全绿。

### 1.5 A 机制（S85d，D2 = B+）

- 把 B 的 checker 接进 build 路径，提供 `off / warn / error` 级别；
- 默认 `off`；本卡不改默认值；
- 机制在重写前就位，便于 42.8k 行新代码 dogfood。

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S85a inventory | 子系统/函数集/状态/import 环清单 | `p85_inventory`（文档 + 抽查） | M |
| S85b spike | 单切片等价重写与度量 | `p85_spike` | M |
| S85c M0 粗切 | 5–6 单元纯搬移 + 集合基线/映射 | `p85_m0` | M |
| S85d A 机制 | checker 进 build，`off/warn/error` | `p85_a_wire` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S85a 可为 `no-test:`，由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E85-1 | inventory 覆盖全部子系统；函数集/状态/import 环清单可复核 |
| E85-2 | spike 报告含行数、编译耗时、测试语料逐字节一致原始输出、sharp edge 清单；门通过 |
| E85-3 | M0 为纯搬移（函数体哈希不变 + 机械行白名单）；不新增 import 环 |
| E85-4 | 期望集合基线 + 旧→新映射入库；集合比对在自举段可跑 |
| E85-5 | A 机制可用（`off/warn/error`），默认 `off`，行为零变化 |
| E85-6 | 测试语料发射逐字节不变；编译器自身发射差异按两级制处理 |
| E85-7 | 既有测试/示例全绿；`check-all` 与 ASan 通过；无新增警告 |
| E85-8 | 文档/证据入库；单卡回滚不影响 `enum`/`switch`/C enum 旧代码 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R85-1 | spike 不通过 | 退化为逐项替换；不进入整体重写 |
| R85-2 | 文件级状态搬迁破坏“纯搬移” | 先交状态清单与归属规则；允许接口变化、不允许行为变化 |
| R85-3 | 命名/产物集合变化影响下游 | 集合基线 + 映射；产物名检查进卡 |
| R85-4 | M0 与并行会话冲突 | 单写者分支；其他会话绕开；合入窗口全绿 |
| R85-5 | 范围蔓延到精细切分/重写 | 非目标写死；M1 留 v1.1 |

回滚：单卡回滚；M0 回退到原文件边界；A 机制默认 `off`，可单独撤。

## 5 决策记录（本卡内，`D85-*`）

| ID | 内容 |
| --- | --- |
| D85-1 | M0 只搬“不依赖宿主类型、也不被宿主类型签名约束”的自由函数；方法搬移必然让宿主与新单元互相 import（成环），归 PH-86–88 的切片 |
| D85-2 | 新增单元的命名/形状照 `Sh.h.ct` 先例：无状态 marker 类型 + `pub` 自由函数 + 同命名空间；宿主单向 import 新单元 |
| D85-3 | A 机制用 `ct build --check-level=off|warn|error`（默认 `off`）；`ct check --types` 不变；`error` 在写产物前失败 |
| D85-4 | 语料 sha256 清单把生成物 banner 的版本 token 归一化：本卡有意 bump 版本，banner 以下的字节才是“发射不变”的判据 |
| D85-5 | spike 只证结构等价；整子系统“新语法等价重写”记为**不通过（未覆盖）**，按 R85-1 退化（见 §8） |

## 7 收口对照表（2026-11-21，v0.85.0）

### 7.1 任务逐项

| 任务 | 交付 | 验收命令 | 原始输出 | effort |
| --- | --- | --- | --- | --- |
| S85a inventory | `tools/p85_inventory.py` + [p85_inventory.md](p85_inventory.md) + 探针 | `bash test/ast/p85_inventory.sh` | `p85inventory: 9 passed, 0 failed` | M |
| S85b spike | [p85_spike.md](p85_spike.md) + 证据 + patch + 探针 | `bash test/ast/p85_spike.sh <ct-ast>` | `p85spike: 14 passed, 0 failed` | M |
| S85c M0 粗切 | 6 个新单元 + [p85_m0.md](p85_m0.md) + 基线/映射 + 探针 | `bash test/ast/p85_m0.sh <ct-ast>` | `p85m0: 4 passed, 0 failed` | M |
| S85d A 机制 | `--check-level` + Diag `type_fail` + 探针 | `bash test/ast/p85_a_wire.sh <ct-ast>` | `p85a: 9 passed, 0 failed` | S |

`no-test:` 例外：无。S85a 的验收是“文档 + 抽查”，探针已把抽查机械化（不再是纯文档任务）；
四个任务都先有 `test(<scope>): p85<X> 红` 提交（§7.2），随后实现转绿。

### 7.2 红证（T-7；baseline `10c23c77`，实现前；归档重建）

```console
$ git archive 10c23c77 | tar -x -C /tmp/p85red && sh .temp/build-ct-ast.sh . /tmp/p85red/.temp/b
built /tmp/p85red/.temp/b/ct-ast
$ cd /tmp/p85red && bash test/ast/p85_inventory.sh .temp/b/ct-ast
p85inventory: 0 passed, 9 failed                     exit=1
$ bash test/ast/p85_spike.sh .temp/b/ct-ast
p85spike: 1 passed, 13 failed                        exit=1
$ bash test/ast/p85_m0.sh .temp/b/ct-ast
p85m0: 1 passed, 3 failed                            exit=1
$ bash test/ast/p85_a_wire.sh .temp/b/ct-ast
p85a: 3 passed, 6 failed                             exit=1
```

红的原因逐条：inventory 的文档/函数集合尚不存在；spike 的 report/patch/证据尚不存在；
M0 的映射与新单元尚不存在；A 的 `--check-level` 在 baseline 上是 unknown option。

注（提交拓扑）：四项红证都在 PH-85 基线 `10c23c77` 上复跑（`git merge-base --is-ancestor
10c23c77 HEAD` 为真）。首个 `test(...) 红` 提交的直接父提交是 `32e3e482`（同期另一席位的
battle 文档提交，路径只在 `battle/`，不含编译器改动），因此“实现前”的判据仍由 `10c23c77`
承载——本卡没有用实现后的工作树复跑红证。

### 7.3 退出判据（E85-1…8）

| ID | 断言 | 证据 | 结论 |
| --- | --- | --- | --- |
| E85-1 | inventory 覆盖全部子系统；函数集/状态/import 环清单可复核 | `p85_inventory`：27 单元逐行比对、17 个单例状态、138 边、0 环 | ✅ |
| E85-2 | spike 含行数/耗时/逐字节/ sharp edge；门结论明确 | [p85_spike.md](p85_spike.md)：391→425 行、`next` 309→39、构建 1053→994 ms、66 文件逐字节、10 条 sharp edge；**整子系统新语法重写门不通过**，按 R85-1 移交 PH-86 per-function（§8） | **有条件通过（D-018）**：spike 已执行 + 度量/逐字节/sharp edge + 明确门结论；不把“门不通过”记成“通过” |
| E85-3 | M0 纯搬移（body-hash + 机械行白名单）；不新增 import 环 | `p85_m0`：827 个基线 body 全在；6 单元只含自由函数、不 import 宿主；0→0 环 | ✅ |
| E85-4 | 期望集合基线 + 旧→新映射入库；集合比对在自举段可跑 | `p85_m0_baseline.json`（20 产物）+ `p85_m0_mapping.tsv`（6 行）+ `p85_m0` 产物比对 26 | ✅ |
| E85-5 | A 机制 `off/warn/error` 可用，默认 `off`，行为零变化 | `p85_a_wire` 9/9；default ≡ off（产物逐字节 diff 空）；`error` 无产物、退出非 0 | ✅ |
| E85-6 | 测试语料发射逐字节不变；编译器自身差异按两级制 | `p85_m0`/`p85_spike` 的 66 文件清单一致（banner token 归一化）；自举不动点 `diff -r` 空 | ✅ |
| E85-7 | 既有测试/示例全绿；`check-all` 与 ASan 通过；无新增警告 | 见 §7.4（**干净归档** `git archive HEAD` 重跑；F1 已修） | ✅ |
| E85-8 | 文档/证据入库；单卡回滚不影响 `enum`/`switch`/C enum 旧代码 | 卡 §7/§8 + 3 份 design 文档 + 探针；**实跑回滚**（先 revert S85d 再 M0）见 §7.5，`enum`/`switch` 样例输出一致 | ✅ |

### 7.4 总门禁（收口实跑）

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)                       rc=0
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)                rc=0
$ git archive b2a85409 | tar -x -C /tmp/ph85final2   # 干净归档（F1 的判据树）
$ cd /tmp/ph85final2 && TMPDIR=$PWD/tmp bash selfhost/check-all.sh
...
VERDICT
check-all: OK (11 hard gates green)                              rc=0
```

逐门：

| 门 | 结果 |
| --- | --- |
| 1 `test/run.sh` | L0 八层全绿（ASan/UBSan 层含在 `test/run.sh`；另跑 `check-sanitizers.sh`，见下） |
| 2 `check-goldens.sh` | `L1 golden coverage: 25 pass, 0 new, 0 pending, 0 regression`；`L1': 25 passed`；`L2: 25 passed`；`OK` |
| 3 `check-archive.sh` | `single-unit 3 / diagnostics 10 / multi-unit 4 / designed 47 pass, 0 regression`；`OK` |
| 4 `check-m2a.sh` | `L1 vs L2 on the split tree: 2 unit(s) identical, 0 differing` |
| 5 `ct-tour.sh` | 9 步全 ok（含 `ct-ast` 以 `ct` 身份运行） |
| 6 编辑器语法 | `ok`（167 断言） |
| 7 包管理 | `test/pkg/run.sh` 全绿 |
| 8 `check-ast.sh` | `summary: 1561 passed, 0 failed, 5 skipped`（含 `p85/inventory`、`p85/spike`、`p85/m0`、`p85/a-wire` 四行 ok；归档里多出 1 个 skip 是 `p83/dist`——`dist/` 不入库，本地无产物时按设计 skip） |
| 9 `check-warnings.sh` | `check-warnings: 500 ok, 0 failed` |
| 10 `check-semantics.sh` | `check-semantics: OK (23 assertions)` |
| 11 `check-docs.py` | `check-docs: OK (2328 relative links in 379 files, v0.85.0, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 11 signoff(s))`（**干净归档** `git archive b2a85409`；F1 后归档与工作树只差另一席位的未跟踪 guide） |

补充：

- **ASan/UBSan**：`bash selfhost/check-sanitizers.sh` → `check-sanitizers: OK (586 checks, no sanitizer report)`，`rc=0`（见 §7.4.1）。
- **dist 产物**：`ZIG=.temp/ph83/zig/zig bash selfhost/make-dist.sh`
  → `sha256: 6a1acf74…; smoke: ct v0.85.0`（Linux x64 static musl，QEMU 实跑 `ct -v`）。
  重建时发现并修复一处 M0 的跨 host 声明遗漏：`ct_norm_path` 依赖的
  `extern char *realpath(...)` 原在 `Module.h.ct`，随函数搬进 `ModuleBoundary.h.ct`；
  macOS 的 libc 头默认暴露它、musl `-std=c99` 不暴露，故只有 Linux 交叉构建会红。
  该声明行已补进新单元（机械行白名单内，函数体未变）。

#### 7.4.1 ASan/UBSan 原始输出

```console
$ bash selfhost/check-sanitizers.sh
== build the bootstrap chain and the AST compiler (sanitized) ==
...
  ok    vararg_fnptr_void
  ok    variadic_impl
  ok    variadic_no_named

check-sanitizers: OK (586 checks, no sanitizer report)          rc=0
```

另：`p80_retain` 的 ASan/UBSan 轨迹在 check-ast 内为 `ok`（E85-7 的“既有测试/示例全绿”）。

### 7.5 回滚（演练，逆序实跑）

演练在临时 worktree 上做（`git worktree add --detach`），从 HEAD 先 revert S85d、再 revert
M0，然后构建并跑 `enum`/`switch` 样例。逆序是必须的：S85d 的实现调用 M0 搬出的函数，先
ret 掉 M0 会让 S85d 的调用悬空。

```console
$ git worktree add --detach /tmp/p85roll HEAD
$ cd /tmp/p85roll && git revert --no-edit 602d3a25      # S85d（A 机制）
[detached HEAD 1f71c4e7] Revert "feat(ct-ast): p85_a_wire（S85d，B 检查器接进 build，off/warn/error）"
 8 files changed, 6 insertions(+), 118 deletions(-)
$ git revert --no-edit 33f06d17                          # S85c（M0 粗切）
CONFLICT (modify/delete): docs/design/p85_m0.md deleted in parent of 33f06d17
  and modified in HEAD.
# 唯一冲突：M0 之后补写的 F2 说明在同一文件里。按“文档随单元一起删”解：
$ git rm docs/design/p85_m0.md && git revert --continue
[detached HEAD c74c4570] Revert "feat(ct-ast): p85_m0（S85c，6 单元纯搬移）"
 delete mode 100644 selfhost/ct-ast/backend/emit/EmitterText.h.ct
 ...（其余 5 个新单元 + 映射表 + design 文档删除）
$ cp .temp/build-ct-ast.sh . && sh build-ct-ast.sh . .temp/b   # 全链
built .temp/b/ct-ast                                     rc=0（-Wall -Wextra -std=c99 零警告）
$ for fx in 28_switch 30_enum 271_qualified_enum; do
>   ./.temp/b/ct-ast test/ast/$fx/prog.ct -o /tmp/$fx.c && cc -std=c99 /tmp/$fx.c -o /tmp/$fx.bin \
>     && /tmp/$fx.bin | diff -q test/ast/$fx/prog.expected.out -; done
28_switch: output matches expected
30_enum: output matches expected
271_qualified_enum: output matches expected
$ # 语料回归：test/cases 25/25（compile-only 计入），0 失败
```

逐项：

- **S85a**：删 `tools/p85_inventory.py` / `docs/design/p85_inventory.md` / 探针即可；
  无源码影响（只与文档/工具相关）。
- **S85b**：spike 不在主线（patch 只在 `test/probes/`），不应用即回滚；66 语料清单不变。
- **S85c**：revert M0 → 6 个新单元删除、宿主恢复原函数与 `import`、产物集合回到 20；
  `enum`/`switch`/C enum 旧代码的发射路径未被 M0 触及，样例输出逐字节一致（上）。
- **S85d**：revert A → `--check-level` 消失、Diag 回到无 `types_level`；默认 `off` 的构建
  路径本来就不经过新代码，回滚不影响任何既有产物（上：全链构建 + 样例通过）。
- 逆序回滚的依赖：S85d 的 `Module.build_main`/`Expr` 内核调用 M0 搬出的
  `SymbolsTypeText`/`ModuleBoundary` 函数，故必须先 ret S85d；顺序写进本卡，避免“单卡
  回滚”被误解为任意顺序。
- 源码零冲突；唯一的 modify/delete 冲突在 `docs/design/p85_m0.md`（F2 的说明在 M0 之后
  补写），按“文档随单元一起删”解决即 rc=0。回滚后 `p85_m0` 探针会红、`p85_m0_mapping.tsv`
  被删——这是预期的“M0 任务自身消失”，其余任务（inventory/spike/A）的源码不受影响。

### 7.6 流程说明

- 单会话 + 单写者：M0 在一条工作分支内一次搬完；合入窗口要求 `check-all` 全绿（§7.4）。
- 红证按 T-7 在实现前用基线归档复跑；VERIFY 签字为角色席位（单会话偏离，见 AGENTS 0.3）。

## 8 未覆盖 / 简化（诚实登记）

| # | 项 | 现状 | 去向 |
| --- | --- | --- | --- |
| 1 | spike 的“整子系统新语法等价重写” | **未覆盖**：只重写了结构（方法拆分），没有迁移 `Str` token 视图、没有 `?`/`errdefer`（词法器无错误通道/无资源）；按 R85-1 记为**门不通过**，E85-2 按 [D-018](../decisions/D-018.md) 记**有条件通过** | PH-86 按 per-function 拆（punct → number → quoted/pp_line → Str 视图），每段独立红绿；不承诺整体重写 |
| 2 | M0 只搬“不依赖宿主类型”的自由函数 | 方法、带 `struct X *` 参数的函数、`size_t` 参数的 SHA 组都留在宿主（`p85_m0.md` §2 表）；80 个单元级函数只搬了 63 个 | PH-86–88 的切片逐项处理；`Sha256` 组可单列一个小任务 |
| 3 | A 机制只接 B 的 `--types` 判定 | `--semantics`（CFG/own）不在本卡；`warn` 的发现走 stderr 文本，不进 `--diagnostics=json` | v1.1 S2（A 默认强制）时扩展 JSON 与语义层 |
| 4 | A 的默认强制 | 本卡只交付机制，默认 `off`（卡 §1.5） | v1.1 S2；v1.0 只要求 FP=0 证据 |
| 5 | 导入图仍偏重 | parse 7 单元互依；M0 只保证“不新增环” | 破环单独成案（D-017 A4） |
| 6 | 单元数上限/4K 阈值 | 卡 §1.4 允许“不设上限、阈值仅告警”；最大单元 `Emitter` 8876 行、`Expr` 8750 行 | M1（v1.1 S1）再校准 |
| 7 | `p85_spike` 无法在 check-ast 内重建 spike | 归档 patch + 证据；探针只校验 patch 可应用、证据自洽、当前语料一致 | 不需要：spike 是实验，产物是报告 |

### 7.7 REV 打回修复（2026-11-21，verdict `5c2acb26`）

REV 判不通过，四条阻断/判据项 F1–F4；本地未推历史按 T-4 重写（`git rebase -i`），
**版本仍 `0.85.0`**（未发布；不是 fix，不占 PATCH）。

#### F1 干净归档 dead link（DOC-81）

`docs/README.md` 曾链到未入库的 `guide-for-c-programmers.md`（另一席位的未跟踪文档）。
修法：从 `docs/README.md` 移除该行（不动对方的未跟踪文件），并把该链接的“入口”留给
对方文档入库时再加。修后：

```console
$ R=$(mktemp -d /tmp/ph85docs.XXXXXX); git archive HEAD | tar -x -C "$R"
$ (cd "$R" && python3 test/docs/check-docs.py); echo rc=$?
check-docs: OK (2328 relative links in 379 files, v0.85.0, 11 hard gates,
             12 phase status, 5 适用版本 header(s), 2 superseded link(s),
             11 signoff(s))
design window: ok (12/12)
rc=0
```

（工作树与归档的差异只剩对方的未跟踪 guide；归档是判据，工作树删除该行后不再依赖它。）

#### F2 M0 提交独立可构建（SH-107）

`e88561af`（旧）缺 3 条调用方 import，`Driver`/`Parser`/`TypeCheck` 调用的搬移函数
没有原型。重写历史把三条 import 移进 M0 提交，并顺带把 `ct_norm_path` 的
`extern char *realpath(...)` 声明也放进 M0（随函数走，Linux musl 交叉构建才暴露）：

```console
$ git archive 104dfc54 | tar -x -C /tmp/p85f2 && cd /tmp/p85f2
$ cp .temp/build-ct-ast.sh . && sh build-ct-ast.sh . .temp/b
built .temp/b/ct-ast                                 rc=0（全链，零警告）
$ ./.temp/b/ct-ast -v
ct-ast v0.84.1                                       # 该提交未到收口，版本仍是旧值
$ CT_C_BOUNDARY=allow ./.temp/b/ct-ast test/cases/01_trait_basic.ct -o /tmp/m0x.c \
>   && cc /tmp/m0x.c -o /tmp/m0x && /tmp/m0x
Hello, I'm Tom, age 36
Hello Jerry, I'm Tom
```

HEAD 上 `p85_m0` 仍绿（见 §7.4 的 check-ast）。`p85_m0_s85d_edits.tsv` 是 S85d 的夹具，
在 M0 提交处尚不存在，因此 M0 提交的验收是“**可独立构建 + 行为不变**”；探针的全套
断言在 HEAD 上跑。

#### F2 残留（二次打回，SH-107 续）

第一次修 F2 时，M0 提交仍带 8 行 S85d 代码——`Module.h.ct` 的 `--check-level`
help 文本（1 行）与 `nsem` 提前退出守卫（7 行），来自“按最终工作树暂存整个文件”。
后果：M0 提交的 `p85_m0` 因允许清单缺失/为空而红，`ct build --help` 列出未实现的
选项。修法（REV 指定的最小修）：重写未推历史，把这 8 行移回 S85d 实现提交
`602d3a25`，M0 提交 `33f06d17` 只保留 import/realpath 机械行；M0 测试提交
`bfad7c37` 的 `p85_m0_s85d_edits.tsv` 置为空文件（0 条 S85d 改动），S85d 测试提交
再写入 11 条。

```console
$ git archive 33f06d17 | tar -x -C /tmp/p85m0v && cd /tmp/p85m0v
$ cp .temp/build-ct-ast.sh . && sh build-ct-ast.sh . .temp/b
built .temp/b/ct-ast                                   rc=0（全链，零警告）
$ ./.temp/b/ct-ast -v
ct-ast v0.84.1
$ ./.temp/b/ct-ast build --help | grep -c check-level
0                                                       # 不再列出未实现的选项
$ python3 tools/p85_inventory.py m0
p85_m0: body hashes preserved (827 bodies, 838 functions, 6 moved units,
        0 declared S85d edits), 26 products, 0 cycles
$ bash test/ast/p85_m0.sh ./.temp/b/ct-ast
p85m0: 4 passed, 0 failed
```

HEAD 上仍是 `827 bodies, 842 functions, 11 declared S85d edits`（4 个 S85d 新函数 +
11 条 allowlist），`p85_m0` 4/4。

#### F3 E85-2 口径（DOC-82）

新增 [D-018](../decisions/D-018.md)（REVIEW 签收、EDITOR 批准；T-8 要求 decision 由非作者签收）：E85-2 = spike 已执行 + 度量 +
逐字节 + sharp edge + **明确门结论**；整子系统新语法重写按 R85-1 移交 PH-86 的
per-function 切片。卡 §3（E85-2 行）、§8、`AGENTS.md`、`docs/history/phase-log.md`、
`docs/roadmap.md`、`docs/session-map.md` 六处统一为“**E85-2 有条件通过（D-018）**”，
不再有“E85-1…8 全部无条件通过”。

#### F4 回滚（E85-8）

见 §7.5：逆序 revert S85d → M0，临时 worktree 构建 rc=0，`enum`/`switch`/限定枚举
三个样例输出与 `prog.expected.out` 一致，`test/cases` 25/25。
HEAD 提交链（重写后）：

```console
$ git log --oneline 10c23c77..HEAD
5865d6e2 docs(ph85): F2 残留修复后的数字与证据（M0 838/827/0）
a5a1c762 review: PH-85 复核（v0.85.0，打回 F2 残留）   # REV 第二次打回
4d1ada1c docs(ph85): 回滚演练按最终 HEAD 复核（源码零冲突，文档随单元删）
41221fea docs(ph85): 记录干净归档 11/11 与 ASan 586（REV 打回后复跑）
6395cc2f fix(ph85): REV 打回 F1–F4（D-018、干净归档、M0 可独立构建、回滚演练）
6997a841 review: PH-85 复核（v0.85.0，打回）      # REV 第一次打回（原 5c2acb26）
8e81762d docs(pkg): ct-pkg index 消费侧…           # 另一席位
59b8b164 chore(ph85): v0.85.0 收口（S85a–S85d，E85-1…8）
602d3a25 feat(ct-ast): p85_a_wire（S85d）
c34cdf93 test(ct-ast): p85_a_wire 红
33f06d17 feat(ct-ast): p85_m0（S85c，6 单元纯搬移）   # F2：3 imports + realpath；0 行 S85d
bfad7c37 test(ct-ast): p85_m0 红                        # 空允许清单
d9dcc0b8 feat(ct-ast): p85_spike（S85b）
4345d08c test(ct-ast): p85_spike 红
b6dacb3c feat(ct-ast): p85_inventory（S85a）
89766116 test(ct-ast): p85_inventory 红
32e3e482 battle(ct-guide-1): ……                    # 另一席位
```

（上面的 sha 是重写后的本地历史；未 push、未 tag。第二次打回只改了 M0/S85d 两个
提交及其下游 sha，`6395cc2f` 之后为证据补写，HEAD 以 `git log -1` 为准。）
