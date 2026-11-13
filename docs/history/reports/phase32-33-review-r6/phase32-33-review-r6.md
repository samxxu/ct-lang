# Phase 32 / 33 立项卡第六轮独立评审

- 对象：`docs/design/phase32-draft.md`、`docs/design/phase33-draft.md`（提交 `9450a57`，只含两张卡）
- 范围：只评审这两张卡；Phase 31 与 34–36 不在范围（仅在核对编号占用时读取目录声明）
- 方式：只读 + 单条 `ct-ast` / `cc` 探针，产物在 `/tmp/r6/**`；未跑 `check-all.sh`；未改卡片、未 commit
- 探针二进制：`/tmp/ct-ast`（v0.26.4）

## 0 上轮 High 闭合情况

| 轮次 | 编号 | 内容 | 本轮判定 | 证据 |
| --- | --- | --- | --- | --- |
| R5 | P32-H1 | L32 负例放 `errors/` 被编译期负向扫描判红 | **闭合** | 已迁 `check_errors/`；`check-ast.sh:3022` 只 glob `test/ast/errors/*.ct`，不递归（见 §1 入口表） |
| R5 | P32-H2 | 11 条 skip 放 `211/prog.ct` 被行为循环 `cc` | **闭合** | 已移 `211/check_only/`；行为循环只取顶层 `$d/prog.ct`（`check-ast.sh:502/506/507`） |
| R5 | P32-H3 | fnptr actual 被当作可编译形态 | **闭合** | `:307` 已改为"闭包/fnptr/void actual 一律进 `check_only/`" |
| R5 | P32-H4 | L32-7 的 CLI 夹具跑在冻结 L2 上 | **闭合（留 Medium）** | `:279`/`:305` 已改挂 S8 的 `check-ast.sh` 主线 `ct-ast`；但未给具体调用行 → M2 |
| R5 | P32-H5 | 209 正例过不了 `check-warnings` | **闭合** | `:306` 已把 `1.5` 与指针互转移入 `check_only/`，`prog.ct` 只剩零告警形态；四类形态实测零告警（见 §3 E1） |
| R5 | P32-H6 | 211 与 Phase 34 撞号 | **闭合** | Phase 34 已改为 215–218/228；P32 保留 209–211，不再相交 |
| R5 | P33-H1 | 209 与 Phase 32 撞号 | **闭合** | 已改 `207_depth4_boundary`；全卡 `209` 零命中，显式 207 三处 + 范围 `200–208` 两处 |

七条 High 全部闭合。**但本轮在 Phase 33 的改号动作里发现 1 条新 High**（§4 H1：207 的 pattern 示例既不平衡又是 4 层，不是 5 层）。

## 1 `check-ast.sh` 全部 `test/ast` 入口（逐条抄匹配式）

| # | 位置 | 实际匹配表达式 | 作用 | 是否命中 `check_errors/` | 是否命中 `211/check_only/` |
| --- | --- | --- | --- | --- | --- |
| 1 | `check-ast.sh:502` | `for d in test/ast/*/; do` | 顶层目录枚举 | 命中目录，但 `:506 src="$d/prog.ct"`、`:507 [ -f "$src" ] \|\| continue` → **直接跳过** | 不命中（`*` 不跨 `/`） |
| 2 | `check-ast.sh:515` | `find "$d" \( -name '*.m.ct' -o -name '*.h.ct' \)` | 判断是否多单元 | 无可执行（已在 #1 跳过） | 只匹配 `.m.ct`/`.h.ct`，`check_only/*.ct` 不在内 |
| 3 | `check-ast.sh:520` | `find "$d" -name '*.shim.h'` | 收集 include 根 | 同上 | 不匹配 `.ct` |
| 4 | `check-ast.sh:428`（`fixture_sources`） | `find "$1" -name '*.ct' -type f \| sort` | 给 `tparam_residue` 当**文本**输入 | 不被调用（#1 已跳过） | **会递归读到**，但只喂 `sed -n 's/^...<\(T\)>...(/'` 抽泛型函数声明；`void z;`/`int y=f();` 不匹配该式，无影响 |
| 5 | `check-ast.sh:570` | `tparam_residue "$out" $(fixture_sources "$d")` | 产物残留模板名扫描 | 不执行 | 执行，但 `check_only/` 里没有 `<T>(` 形态声明 |
| 6 | `check-ast.sh:3022` | `for f in test/ast/errors/*.ct; do` | 编译模式负向扫描 | **不命中**（不同目录，非递归） | 不命中 |
| 7 | `check-warnings.sh:107/111` | `for d in test/ast/*/` + `[ -f "$d/prog.ct" ] \|\| continue` | 生成 C 零告警 | **跳过** | 不命中（嵌套） |
| 8 | `test/fuzz/run.sh:114` | `for src in $(find test/ast -name '*.ct' \| sort); do` | nightly fuzz 种子 | **命中** | **命中** |

**裁定（battle）**：硬门禁侧（`check-ast.sh`、`check-warnings.sh`、`check-archive.sh`、`test/run.sh`）**没有任何递归编译入口**，两套目录约定成立。唯一递归入口是 `test/fuzz/run.sh:114`，但该脚本：
- 明确"不属 `selfhost/check-all.sh`"（文件头 D17-6），只在 `.github/workflows/nightly.yml:33` 夜间跑；
- 只把种子**变异后**编译（截断/删行/换 token），"拒绝是预期结果"，**从不把种子原样当正例编译**。

所以它不会把 `check_errors/` 判红，但卡片 `:196` 的绝对措辞"`check_errors/` 两者都不进，只由 `p32_*` bespoke 断言块读"**不准确**：nightly fuzz 会递归收作种子。这不是 High（拆分目的仍是"避开会把它们误判为正例的门禁"），但必须改措辞或加排除（M5）。

## 2 逐项回答

| 用户问题 | 结论 |
| --- | --- |
| 1. `check_errors/*.ct` 会不会被抓 | 硬门禁不会（#1/#6/#7）；nightly fuzz 会（#8），仅作变异种子，不判红 |
| 2. `211/check_only/` 会不会被抓 | 硬门禁不会（嵌套目录不在 `test/ast/*/`）；fuzz 会收作种子。`prog.ct` 已只剩 6 条 ok；四类可测形态实测零告警（E1），两条 `Vec` 行依赖 Phase 31 且构造形态未钉死（M4） |
| 3. `p32_coverage` 接线位置 | **未写明**。卡片 `:198`/`:218` 只说"硬编码在 `check-ast.sh` 的 `p32_coverage`"，没有段锚点、没有命令、没有期望 stderr 的落点 → M1 |
| 4. E32-11 的二进制与调用行 | 二进制已写明"主线 `ct-ast`"（`:279`/`:305`），但**没有具体调用行**，也没写 `x.ct` 的放置目录与 `-o` 处理；`ct build --types x.ct` 的报错先后（缺 `-o` 先报还是 `--types` 先报）未钉 → M2 |
| 5. 12 个夹具的 rc 由谁保证 | E32-1–E32-9 + E32-17 覆盖全部 12 个文件，逐条"恰一条 L32-n"；但 §3.6 `:218` 只给 7 行矩阵，另外 5 个文件（`assign_ptr`/`return_missing`/`container_set`/`container_put`/`generic_arg`）没有逐文件的 expected 子串与 `line:col`，块结构也未规定"12 条独立断言" → M3 |
| 6. 矩阵 24 行可核对性 | 7+6+11+0=24 ✓；期望元组确实要求硬编码在 `check-ast.sh` 或独立 `check_coverage.expected.tsv`（`:198`/`:259`），不是读实现方 TSV ✓。但 6 条 ok 共用 1 个退出码、11 条 skip 共用 4 个文件，17 行不可单独观测 → L1 |
| 7. Phase 33 编号与判定 | `207` 三处显式 + 两处 `200–208` 范围，`209` 零命中 ✓；P33 `200–208`、P32 `209–211`、P34 `215–218`/`228`、P35 `219–224`、P36 `225–227`/`229–232` 互不相交 ✓。但 `:119` 的"`Drop`/`Handback` 不是可声明的 trait"**事实错误**（M6）；E33-11 的 207 示例**拼写不平衡且层数错**（H1） |
| 8. 估算 | P32 945–1,560 ✓、P33 840–1,570 ✓，均等于逐片求和；P32 最大片 S10=150、P33 最大片 S8/S9=150，均 ≤150 ✓ |

## 3 实测证据

### E1 211 的 6 条 ok 中 4 条可测形态零告警

用全局 `Circle`（避免返回栈上接口的悬挂）构造：
```
ct rc=0
cc rc=0
warn bytes: 0
c=1
c=2
x=1 y=3
run rc=0
```
另：`Vec<int> v; v.push(1); v.len();` 用 v0.26.4 + `lib/std` 编译通过但**运行 rc=139（段错误）**——T31-4 明确 `Vec<T> v;` 不做零初始化。故 211 的两条 `container` 行必须用 Phase 31 的 `Vec<int> v = {1};` / `Vec<Show> v = {circle};`，卡片未写（M4）。

### E2 `trait Drop` / `trait Handback` 都可声明

```
trait Drop { void x(); }
struct A { int v; } use Drop;
impl Drop for A { void x() { } }
→ rc=0
产物：struct Drop_vtbl { ... }; struct Drop_iface { ... }; static void A_Drop_drop(void *self); static void A_Drop_x(void *self)
trait Handback → rc=0
```
`:119` 的"两者不是可声明的 trait"不成立（M6）。

### E3 `207` 示例按卡片字面拼写无法解析

卡片 `:186`：`impl<T> Box<Box<Box<Box<T>>>>>`（5 层，depth=4）
- 计数：`impl<T>` 1 个 `<`，4 个 `Box<` → 共 5 个 `<`；结尾 `>>>>>` + `impl<T>` 的 `>` → 共 6 个 `>`。**括号不平衡**。
- 实测：
```
bad.ct:5:29: error: expected '>' after the type arguments
```
- 正确的 5 层写法 `impl<T> Box<Box<Box<Box<Box<T>>>>>`（5 个 Box，6 个 `<`/6 个 `>`）实测 `rc=0`。
- 按 `:167` 基准（`Box<T>`=0、n 层=n-1），4 个 Box = depth 3，不是 depth 4。

→ H1。

## 4 Phase 33

### High

#### H1 `ast/207_depth4_boundary` 的 pattern 示例层数错且括号不平衡

- 位置：`phase33-draft.md:186`（§3.2.2 夹具表），被 `:283`（E33-11）、`:295` 引用
- 问题：示例 `impl<T> Box<Box<Box<Box<T>>>>>` 只有 **4 个 `Box`**（depth=3），且比配平多一个 `>`；按字面建夹具会得到 `error: expected '>' after the type arguments`，`rc≠0`，E33-11 的"depth=4 不报"直接失败。负向侧若照同一偏一层的写法写"6 层"，实际只有 5 层（depth=4），同样不会触发 L33-4。
- 修法：把 `:186` 的示例改为 `impl<T> Box<Box<Box<Box<Box<T>>>>>`（5 个 `Box`、6 个 `<`、6 个 `>`），并在 `:283` 写明"6 层 = `Box<Box<Box<Box<Box<Box<T>>>>>>`（6 个 `Box`，depth=5）"。改完后 E3 的 `good.ct` 即为可用的正例骨架。
- 验证：`/tmp/ct-ast` 对 5 个 Box 的 pattern `rc=0`；对 6 个 Box 的 pattern 报 `generic type arguments nest deeper than 4`（旧文案），实现后应改为 L33-4。

### Medium

| ID | 位置 | 问题 | 可验证修法 |
| --- | --- | --- | --- |
| M6 | `:119` | "`Drop`/`Handback` 按名字无条件拒绝（两者不是可声明的 trait）"——后半句错误，实测两者都可 `trait` 声明并生成 `*_vtbl`/`*_impl`（E2）。按名拒绝本身与函数路径 `Parser.h.ct:1141` 一致，规则可保留，但理由要改，否则会误导实现者以为 `find_trait` 必有特殊返回值 | 改为"`Drop`/`Handback` 是内建语义占用的名字（`*_vtbl` 生成路径按名特判），不参与用户 bound；因此按名无条件拒绝，与 `find_trait` 无关"；并补一句"用户声明同名 trait 不在支持范围" |
| M7 | `:186`、`:283` | 207 只写"pattern-only、不得实例化具体 5/6 层类型"是对的，但没有写"pattern 递归不得转调 `parse_type`"；`parse_type` 的 `type_depth>4`（`Expr.h.ct:1737-1746`）会在 6 层时先报旧文案，抢在 L33-4 之前 | 在 §3.2.1/E33-11 加一句"pattern 深度计数独立于 `type_depth`，递归分支不得调用 `parse_type` 解析嵌套模板名" |

### Low

| ID | 位置 | 问题 | 修法 |
| --- | --- | --- | --- |
| L2 | `:183-184` | `_ptr`/`_fnptr` 行写"替换既有解析错"，但没给替换前的原文；红证只有"当前 rc≠0"，无法证明替换的是哪条 | 在 §7.1 或台账里补"替换前文案"两行 |
| L3 | `:285` | 208 被挂在 S11（O3）而它是 O1 声明期夹具，仅靠 E33-15 的跨阶段块成立 | 在 S11 行注明"208 由 E33-15 的第二个 `ct build` 驱动，不单独行为循环" |

## 5 Phase 32

### High

无。六条 R5 High 均已闭合。

### Medium

| ID | 位置 | 问题 | 可验证修法 |
| --- | --- | --- | --- |
| M1 | `:198`、`:218`、`:282` | `p32_coverage` 只说"硬编码在 `check-ast.sh` 的 `p32_coverage` 中"，没有段锚点、没有逐条命令、没有期望 stderr；实现者无法判断它插在行为循环前还是后、读不读 `prog.expected.out` | 在 §3.6 尾补一段伪代码/命令清单：`p32_coverage` 放在 `check-ast.sh` 第 8 段（行为循环之后、汇总之前），逐条 `"$work/ct-ast" check --types <fixture>`，断言 `rc`、`grep -c`、`stderr` 为空，并打印 `coverage: 24 rows, ...` |
| M2 | `:279`、`:305` | E32-11 只写"主线 `ct-ast` 跑临时 `x.ct`"，没有具体调用行、`x.ct` 目录、`-o` 处理；`ct build --types x.ct` 若先校验 `-o` 会先报别的错，"恰一条 L32-7"不成立 | 写死 `"$work/ct-ast" build --types "$work/p32_cli_x.ct"`（无 `-o`），并规定驱动必须先校验 `--types` 再校验输出目录；断言 `rc!=0`、`grep -c 'ctc: --types is only valid' == 1` |
| M3 | `:218`、`:299-303`、`:311` | 12 个夹具里只有 7 个进矩阵；`check_assign_ptr`、`check_return_missing`、`check_container_set`、`check_container_put`、`check_generic_arg` 只有 E 行的"恰一条 L32-n"，没有逐文件 expected 子串/位置；`:218` 也只说"7 条逐行" | 在 §3.6 补一张 12 行表（fixture / L 码 / 完整 expected 子串 / rc / line:col），并要求 `p32_errors` 逐文件 12 条独立 `if`，禁止一条 `for` 循环只看退出码 |
| M4 | `:211`、`:306` | 6 条 ok 的构造形态未钉死：`return/interface←struct` 用局部 `Circle` 实测输出为栈垃圾（不确定）；`Vec<int> v; v.push(1);` 实测运行段错误（T31-4 不做零初始化）。`prog.expected.out` 无法确定 | 写明 211 必须用全局/静态元素（`Circle gc;`）与 Phase 31 的 `Vec<int> v = {1};` / `Vec<Show> vv = {circle};`；`prog.expected.out` 固定 |
| M5 | `:196` | "`check_errors/` 两者都不进，只由 `p32_*` bespoke 断言块读"不准确：`test/fuzz/run.sh:114` 递归 `find test/ast -name '*.ct'`，会把 `check_errors/**` 与 `check_only/**` 收作 nightly fuzz 种子（不按原样编译、不判红） | 二选一：(a) 改措辞为"不进任何编译/负向硬门禁；nightly fuzz 会收作变异种子"；(b) 把 `test/fuzz/run.sh` 的 find 加 `-maxdepth 2` 或 `-path '*/check_errors/*' -prune`，并把该文件列入 S10 文件清单 |
| M6 | `:121`、`:125`、`:161`、`:165` | 字面量 0 的放行写在 `chk_assignable(formal, actual, diag)` 内部，但该签名只有三个字符串参数，拿不到 `is_zero`；§3.4 的调用点虽然从 `chk_type` 取了 `&is_zero`，却没有传给 `chk_assignable`。按卡片写法 `int *p = 0;` 会被 `r==1` 误报 | 给 `chk_assignable` 增加第 4 参 `is_zero`（并更新 §3.2/§3.3/§3.4/初值四处调用），或在四个调用点前置"`expr` 是 `N_NUM` 且值为 0 且 formal 含 `*` → 跳过"，同时删掉 §3.2 第 125 行的内部规则 |

### Low

| ID | 位置 | 问题 | 修法 |
| --- | --- | --- | --- |
| L1 | `:211`、`:218` | 6 条 ok 共用 1 个 `prog.ct` 与 1 个退出码，24 行中的 6 行无法单独观测；错一行只能知道"文件失败" | 在 `p32_coverage` 里额外打印每行 `ok` 的形态名并要求与 6 条硬编码名逐条相等（仍是静态集合，但至少能定位） |
| L2 | `:165` | "`chk_type` 是三参数状态返回 + 可选 `is_zero` 出参"与 `:161` 的 4 实参调用字面矛盾 | 改成"三必选参数 + 1 个可选出参（共 4 个位置参数）" |

## 6 是否需要收缩能力（用户额外授权）

**不需要。** 逐条核对验证位置：

| 主张 | 可信验证位置 | 结论 |
| --- | --- | --- |
| 6 个源码 L 码（12 夹具） | `check-ast.sh` 第 8 道硬门禁的 `p32_errors`（跑 `ct check --types`） | 可测 |
| 7 行矩阵 + 6 ok + 11 skip | 同一脚本的 `p32_coverage` + `check-warnings.sh` + 行为循环 | 可测 |
| L32-7（CLI） | 同一脚本的 `p32_cli` | 可测 |
| S13 合法语料零新增 | 同一脚本的 `p32_legal_manifest` | 可测 |
| 样例 35 | `test/run.sh` | 可测 |

没有任何一条必须新建门禁脚本或改动 11 道硬门禁的语义。唯一"测不到"的是 nightly fuzz 的种子集合，但 fuzz 本就不属于本相断言语义，不构成收缩理由。

## 7 结论

| 卡片 | 结论 | High | Medium | Low |
| --- | --- | --- | --- | --- |
| Phase 32 | **GO（附 6 条 Medium 修法）** | 0 | 6 | 2 |
| Phase 33 | **NO-GO** | 1 | 2 | 2 |

- Phase 32：上轮 6 条 High 全部真闭合；两套目录约定在硬门禁侧成立；24 行矩阵与 945–1,560 均自洽。剩余问题都是"夹具怎么建、命令写在哪"的精度问题，可在实现前一次性补完，不构成阻断。
- Phase 33：只差一处——`207` 的 pattern 示例层数错且括号不平衡（H1）。把 `:186` 改成 5 个 `Box`、`:283` 补 6 层的完整拼写，并把 M6（`Drop`/`Handback` 理由）与 M7（不得转调 `parse_type`）补上，即可转 GO。

## 8 纪律声明

- 未修改两张卡、`docs/roadmap.md`、任何 golden/版本号；未 `git add`/`commit`。
- 未跑 `bash selfhost/check-all.sh`；只跑单条 `/tmp/ct-ast`、`cc`，产物在 `/tmp/r6/**`。
- `2026-11-11/` 评审目录未触碰、未提交。
