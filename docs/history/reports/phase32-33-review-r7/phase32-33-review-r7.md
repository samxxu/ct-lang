# Phase 32 / 33 立项卡第七轮窄范围复核

- 对象：`docs/design/phase32-draft.md`、`docs/design/phase33-draft.md`（提交 `aa78952`，只含两张卡）
- 范围：Phase 32 只验 R6 的 6 Medium + 2 Low 是否落地且未改坏；Phase 33 只验 R6 的 1 High + 2 Medium
- 方式：只读 + 单条 `ct-ast` / `cc` / `grep`，产物在 `/tmp/r7/**`；未跑 `check-all.sh`；未改卡片、未 commit
- 探针：`/tmp/ct-ast`（v0.26.4）

## 0 闭合情况

| 来源 | 编号 | 内容 | 判定 | 依据 |
| --- | --- | --- | --- | --- |
| R6 | P33-H1 | 207 示例层数错、括号不平衡 | **闭合** | `:188`/`:193` 5 个 `Box`=6/6、rc=0；`:194`/`:290` 6 个 `Box`=7/7、基线 `3:33`、最内层 `<` 列 32（§1） |
| R6 | P33-M6 | Drop/Handback 的理由是断言式 | **闭合** | `Parser.h.ct:2177-2197` 实证只置 flag；内建 `use Drop` 产物只有 `A_Drop_drop`，用户 `trait Drop` 才生成 `Drop_vtbl`（§1.3） |
| R6 | P33-M7 | pattern 递归不得转调 `parse_type` | **闭合** | `:156` 明确写死"整条 pattern 都不转调 `parse_type`"，与 `type_depth` 独立计数自洽 |
| R6 | P32-M1 | `p32_types` 接线位置/命令 | **闭合** | 段锚点 `:3018` 实为 `== negative cases ... ==`；`fail` 计数在 `:228`、汇总在 `:6358`、`$work/ct-ast` 在 `:409`；无 `set -e`/`trap`、无既有 `p32_*`（§2.1） |
| R6 | P32-M2 | CLI 断言无具体调用行 | **部分闭合（留 1 Medium）** | 调用行已写死；但 `build` 在 `Driver.h.ct:165` 就转 `build_main`（`Module.h.ct:1007`），S8 文件清单没列 `Module.h.ct`；且 build 的 `-o` 本身可选（§2.2） |
| R6 | P32-M3 | 12 行逐文件表 | **闭合** | `:256-269` 12 行齐全，逐文件独立 `if`；抽 6 行核算 line:col 全部吻合（§2.3）；实际 L32 输出待实现后才能对 |
| R6 | P32-M4 | 6 条 ok 的构造/P31 时序 | **闭合** | `:4`/`:5`/`:41` 明确"31 未收口本相不开工"；`:243` 写死全局元素 + 花括号初值；实测今天 `Vec<C> vv={gc}` 报 D31-5 硬错（§2.4） |
| R6 | P32-M5 | fuzz 递归入口措辞 | **闭合** | `:204` 已写明 nightly fuzz 只做变异、不按原样判红 |
| R6 | P32-M6 | `is_zero` 四参签名 | **闭合** | `:121` 签名 4 参；`:136-143` 四个调用点全部传 `is_zero`；`:173` "3 必选 + 1 可选出参" |
| R6 | P32-L1 | 6 条 ok 不可定位 | **闭合** | `:252` 打印 6 个形态名并与硬编码名逐条相等 |
| R6 | P32-L2 | "三参数"旧表述 | **闭合** | `:173` 已改为 3 必选 + 1 可选（共 4 个位置参数） |
| 新 | P32-M7 | E32-10 的"既有"夹具不存在 | **新增 Medium** | `test/ast/errors/` 共 219 个 `.ct`，无 `check_iface_use.ct`；`grep -rl "does not use this trait" test/` 为空（§2.5） |
| 新 | P33-L | 207 缺 `prog.expected.out` | **新增 Low** | `:193` 固定正文只列 `prog.ct` 四行；行为循环 `check-ast.sh:591` 强制 `cmp prog.expected.out` |

## 1 Phase 33

### 1.1 逐字符与实测

固定正文原样落盘（`/tmp/r7/p33/d4.ct`、`d5.ct`），第 3 行统计：

| 文件 | `Box` 数 | `<` | `>` | 结果 |
| --- | --- | --- | --- | --- |
| `207_depth4_boundary` | **5** | **6** | **6** | `rc=0` |
| `nested_pattern_depth` | **6** | **7** | **7** | `rc=1`；`d5.ct:3:33: error: generic type arguments nest deeper than 4` |

- 最内层 `<` 实测列号 = **32**（`rfind('<')+1`），与 E33-11 钉的 `3:32` 一致；
- 基线 `type_depth` 报 **3:33**（指向 `<` 后的 `T`），与 E33-11 的红证描述一致；
- 三个数字（5/6 个 `Box`、6/6 与 7/7、32/33）全部实测吻合，不是照抄作者说法。

### 1.2 `parse_type` 禁转调

`:155-156` 写死：任何深度的裸 `T` 标为通配，不调 `parse_type`/`ct_type_canon`/`ct_inst_add`；**整条 pattern 都不转调 `parse_type`**，嵌套模板名与实参在同一套递归 token 读取里解析。这正好避开 `Expr.h.ct` 的 `type_depth>4`，与 §3.2.1 的独立计数自洽。

### 1.3 Drop/Handback 理由

- `Parser.h.ct:2177-2187`（Drop）、`:2188-2197`（Handback）：只 `uses_drop=1` / `uses_handback=1`，注释明说"never joins the use list — only the flag matters"。
- 实测内建路径：`struct A { int v; } use Drop;` + `impl Drop for A { void drop() {} }` → `build --emit-c` `rc=0`，产物只有 `static void A_Drop_drop(void *self);` 定义，**无** `Drop_vtbl` / `A_Drop_vtable`。
- 实测用户自声明：`trait Drop { void x(); }` → `rc=0`，产物含 `struct Drop_vtbl`；但 `use Drop` 仍走内建 flag，不生成 `B_Drop_vtable`。
- 因此"按名无条件拒绝"的理由现在是可复现的事实：bound 会引到无人定义的 `_Drop_vtable`。`:90` 的表述与实测一致。

### 1.4 Phase 33 结论

**GO。** R6 的 1 High + 2 Medium 全部真闭合；仅新增 1 条 Low：`:193` 的 207 目录除 `prog.ct` 外还需空的 `prog.expected.out`，建议在固定正文后补一句"目录另含空 `prog.expected.out`"，否则行为循环 `check-ast.sh:591` 会因 `cmp` 缺文件判红。不影响开工。

## 2 Phase 32

### 2.1 M1 接线位置

| 卡片声称 | 实测 | 判定 |
| --- | --- | --- |
| 插在行为循环 `:502` 之后、`:3018` 之前 | `:3018` 确为 `echo "== negative cases (test/ast/errors/*.ct) =="` | ✓ |
| 失败计数并入 `fail` 与 `:6358` 汇总 | `fail=0` 在 `:228`，`bad()` 在 `:230` 自增，汇总在 `:6359-6361` | ✓ |
| 用 `$work/ct-ast`（`:409` 构建） | `:409-412` 构建 `$work/ct-ast` | ✓ |
| 无冲突 | 全脚本无 `set -e`、无 `trap`、无既有 `p32_*`；502–3018 之间新增函数名只有 `run_plugin`/`p26_*`/`p28_*`/`stamp`/`mapbad` | ✓ |

`:250-253` 已给出块首 echo、三个子块（`p32_errors`/`p32_coverage`/`p32_cli`）的逐条命令与期望。M1 闭合。

### 2.2 M2 CLI（本轮唯一残留 Medium）

实测与源码：

```
/tmp/ct-ast build --types x.ct        -> ctc: unknown option '--types'   rc=1
/tmp/ct-ast build x.ct                -> cc ... -o a.out                 rc=0（-o 可选）
Driver.h.ct:165   if (argv[1]=="build") return build_main(argc-1, argv+1);
Module.h.ct:1007  int build_main(...)
Module.h.ct:1168  if (argv[i][0]=='-') { unknown option }
```

- 卡片 `:359` 要求"驱动必须在 `build` 分支参数校验的最前面判 `--types`（先于缺 `-o`/输出目录校验）"。
- 事实一：`build` 的 `-o` 是**可选**（usage `[-o <exe>]`；无 `-o` 时输出 `a.out`），不存在"缺 `-o` 校验"这个分支，所以"先于缺 `-o`"是无效约束。
- 事实二：`build` 在 `Driver.h.ct:165` 就转 `build_main`，**不经过** Driver 的通用参数循环。要产出 L32-7，只能在两处之一落点：
  (a) `run()` 在 `:165` 之前预扫 `--types`（`Driver.h.ct`，已在 S8 清单）；
  (b) `build_main` 的参数循环里、`:1168` 的 unknown-option 之前（`Module.h.ct`，**不在 S8 清单**）。
- 卡片没指定 (a) 还是 (b)，S8 文件清单只列 `Driver.h.ct`/`Parser.h.ct`。若实现者按 (b) 做，会漏改 `Module.h.ct`；按 (a) 做则清单够用。
- 修法：在 `:359` 与 S8 二选一写死——推荐 (a)：`Driver.h.ct` 的 `run()` 在 `argv[1]=="build"` 分派**之前**预扫 `--types`，非 `check` 即打印 L32-7 返回 1；并把"先于缺 `-o`"删掉，改为"先于 build 分派"。

该残留不阻断 GO（断言本身会把问题立刻暴露），但必须在 S8 开工前定死落点，否则正如你所料是这轮最容易翻车的一条。

### 2.3 M3 12 行表

`:256-269` 12 行齐全：12 个夹具、L 码、出错行原文、expected 完整子串、rc=1、`line:col`；`:251` 规定逐文件独立 `if`、`grep -cF` 恰一次、无第二条 L32、首行 `"$f:<line>:<col>: error: "`；`:272` 规定新增/删除/改文案即失败。

抽 4 行按原文逐字符核算列号，全部吻合：

| 夹具 | 原文 | 表列号 | 核算 |
| --- | --- | --- | --- |
| `check_init_ptr.ct` | `    int x = "s";` | 3:13 | `"` 在 13 ✓ |
| `check_assign_ptr.ct` | `    x = "s";` | 4:9 | `"` 在 9 ✓ |
| `check_container_put.ct` | `    m.put("a", "b");` | 4:16 | 第二个 `"` 在 16 ✓ |
| `check_generic_arg.ct` | `    p.set_second(a);` | 10:18 | `a` 在 18 ✓ |

限制：L32 尚未实现，无法把表里的 expected 子串与真实 `ct check --types` 输出逐字比对；S0 红证时基线必须仍是 `rc=0`（已核对 `ct check` 对解析期诊断返回 1，见 §2.4）。M3 闭合。

### 2.4 M4 P31 时序

- 卡片 `:4`/`:5`：基线是 **Phase 31 收口提交**，S0 在该提交上重建二进制；`:41`："31 未收口时本相不开工，不得用旧容器形态替代"。
- `:243`：元素必须全局/静态，容器必须用 Phase 31 花括号初值（`Vec<int> v = {1};`、`Vec<Show> vv = {gc};`，L31-10 只允许局部）。
- 实测今天（P31 未落地）：`trait Show; struct C use Show; Vec<C> vv = {gc};` → `error: interface and vptr-bearing values cannot be stored in a container`（D31-5），确认依赖真实存在。
- 判定：时序前置已在卡片顶部与 §2.1 写死，不是"开工当天才红"；M4 闭合。

### 2.5 M5 / M6 / L1 / L2

- M5：`:204` 已准确描述 nightly fuzz（`test/fuzz/run.sh:114` 的 `find`，只变异、不按原样判红）✓。
- M6：`:121` 签名 `chk_assignable(formal, actual, is_zero, diag)`；`:136-143` 四个调用点（初值/赋值+into/return/容器实参）全部从 `chk_type(...,&is_zero)` 取值并原样传入；`:159` 容器路径同样；`:173` 明确 3 必选 + 1 可选（共 4 个位置参数）✓。
- L1：`:252` 打印 6 个 ok 形态名并与硬编码名逐条相等 ✓。
- L2：`:173` 表述已修正，与 `:97`/`:161` 的 4 实参调用一致 ✓。

### 2.6 新增 Medium（M7）：E32-10 的"既有"夹具不存在

- 位置：`:48`/`:304`（E32-10）、`:373`（台账引用）
- 事实：`test/ast/errors/` 现有 219 个 `.ct`，**没有** `check_iface_use.ct`；`grep -rln "does not use this trait" test/` 为空。卡片称其为"既有编译期负例"。
- 实测该用例本身可建：`trait Show; struct Other; Show sh = o;` → 编译 `rc=1`、`ct check` `rc=1`，均输出 `7:16: error: the struct does not use this trait`，所以放进 `errors/` 不会破坏负向扫描。
- 修法：E32-10 的夹具列改为 `errors/check_iface_use.ct`（**待建**），并在 S10 的文件清单与 `p32_*` 断言里点名；`p32_errors` 的 12 个 `check_errors` 之外，单独保留这条"既有诊断 + `--types` 不追加"的 `p32_iface` 子断言（或并入 `p32_errors` 但明确它是第 13 个、位于 `errors/`）。

### 2.7 矩阵与估算

- `24 = 7 L32-n + 6 ok + 11 skip + 0 n/a` 未变（`:243-249`、`:366`）。
- 估算 `945–1,560` 未变（`:397-401`）：510–830 + 325–530 + 80–140 + 30–60 = 945–1,560；逐片均 ≤150（S10=150）✓。
- P33 `840–1,570` 未变，逐片 S8/S9=150 ≤150 ✓。

## 3 最终结论

| 卡片 | 结论 | High | Medium | Low |
| --- | --- | --- | --- | --- |
| Phase 32 | **GO**（附 2 条开工前修正） | 0 | 1（M2 落点）+ 1（M7 夹具） | 0 |
| Phase 33 | **GO** | 0 | 0 | 1（207 需 `prog.expected.out`） |

**Phase 32 开工前必须补的两句**
1. `:359`/S8 定死 `--types` 的落点：推荐在 `Driver.h.ct` 的 `run()` 里、`argv[1]=="build"` 分派之前预扫；删掉"先于缺 `-o`"（`build` 的 `-o` 可选）。
2. E32-10 的 `errors/check_iface_use.ct` 标注为待建，并纳入 S10 文件清单与断言；不要写"既有"。

**Phase 33 开工前建议补一句**：`:193` 的 207 目录除 `prog.ct` 四行外还需空的 `prog.expected.out`。

其余 R6 项全部实测闭合，未发现改坏：编号 `209` 在 P33 仍零命中、`207` 三处一致、P32 的 24 行/945–1,560 与 P33 的 840–1,570 均未漂移。

## 4 纪律声明

- 未改两张卡、未 commit、未跑 `check-all.sh`；只跑单条 `ct-ast`/`cc`/`grep`，产物在 `/tmp/r7/**`。
- `2026-11-11/` 评审目录未触碰、未提交。
