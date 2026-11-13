# Phase 32 / 33 立项卡第五轮独立评审

- 评审对象：`docs/design/phase32-draft.md`、`docs/design/phase33-draft.md`，以及 `docs/roadmap.md` 第 47/48 行（英文表第 1025/1026 行）
- 基线：`b9cfe2e`（工作区干净，评审期间未改任何文件、未 `git add`/`commit`）
- 评审方式：只读核对 + 单条 `ct-ast` / `cc` 探针（产物全部写 `/tmp/r5/**`）；按指令**未跑** `bash selfhost/check-all.sh`
- 探针二进制：`/tmp/ct-ast`（v0.26.4），仅用于确认方向；判据红证仍须 S0 在 Phase 31 收口提交上重跑

## 0 结论

| 卡片 | 结论 | High | Medium | Low |
| --- | --- | --- | --- | --- |
| Phase 32 | **NO-GO** | 6 | 5 | 2 |
| Phase 33 | **NO-GO** | 1 | 6 | 2 |

Phase 32 的阻断点不是措辞：四条独立实测表明，按卡片当前写法的夹具**跑不过它们自己指定的门禁**（`check-ast.sh` 的 `test/ast/errors/*.ct` 编译负向扫描、行为循环的 `cc`、`check-warnings.sh`、`check-archive.sh` 的 L2 驱动）。Phase 33 的 High 只有一条，是本轮（`b9cfe2e`）新引入的编号硬冲突；其余条件项基本已落地。

---

## 1 Phase 32 核查

### 1.1 逐项核对结果（用户指定 6 项）

| # | 核查项 | 结论 | 依据 |
| --- | --- | --- | --- |
| 1 | 209/210 拆分是否真成立 | **成立** | `check-ast.sh:502` 的 glob 是 `test/ast/*/`，`check-ast.sh:506` 只取 `$d/prog.ct`；`check-warnings.sh:107-111` 同样只取顶层目录的 `prog.ct`。嵌套 `check_only/` 不会被行为循环或告警门禁编译。`fixture_sources()`（`check-ast.sh:427-429`）会递归收 `*.ct`，但只喂 `tparam_residue` 文本扫描，不参与编译。实测 209 的八行内容可 `ct-ast` → `cc` → 运行通过（见 §3 证据 E1） |
| 1b | bespoke 断言块在 S10 文件清单 | **在**（`phase32-draft.md:278` 列了 `selfhost/check-ast.sh`） | 但调用行、期望 rc、期望 stderr 未逐条写明 → M1 |
| 2 | `chk_assignable` / `chk_type` 签名一致性 | **一致** | 全文只有 3 处 `chk_assignable(`（:121 / :151 / :161）与 2 处 `chk_type(`（:97 / :160），均为三参数；无单参数返回字符串写法 |
| 3 | CLI 夹具与既有 `cli_*` 格式、`check-archive.sh` | **不成立** | 格式（`compile.args` + `expected.err`）逐字一致，但 `check-archive.sh` 用**冻结 L2** 驱动 `test/modules/*/{compile,build}.args`（:274 `l2="$work/ctc-l2"`，:492-529 调 `$l2`），L2 无 `check` 子命令 → E32-11 永远测不到 L32-7（H4） |
| 4 | 切片归属与估算 | **同步** | 209/210 归 S10（:278/:304/:378 三处一致）、211 归 S12（:280/:377）、S0 只留探针（:61/:268）。逐片求和 510–830 + 325–530 + 80–140 + 30–60 = **945–1,560**，与 `roadmap.md:47` / `:1025` 一致；每片 ≤150。S11 无独立成片必要 → M4 |
| 5 | 指针口径三处统一 | **统一** | `phase32-draft.md:29`（非目标）、`:226`（D32-6）、`:247`（B32-4）均为"基类型与层数均不校验"；`:128` 行为仍只是"两侧都是指针且 `r != 0` 跳过"，未加层数比较 |
| 6 | 编号冲突 | **冲突** | 209 与 Phase 33 撞（见 Phase 33 H1）；211 与 Phase 34 撞（H6）。实测 `test/ast/` 当前最高为 `164`，208–211 目录均不存在 |

### 1.2 High

#### H1 `test/ast/errors/*.ct` 放 L32 专属负例，会被编译期负向扫描判红

- 位置：`phase32-draft.md:198-206`（矩阵夹具列）、`:293-301`（E32-1–E32-9）、`:321-326`（L32 台账）、`:334`、`:375`、`:278`（S10 文件清单）
- 事实：`check-ast.sh:3022-3033` 对 `test/ast/errors/*.ct` **逐个用编译模式**跑 `ct-ast`，要求非零退出并带 `file:line:col: error:`。而本相 12 个 L32 夹具在编译模式全部 `rc=0`（实测见证据 E2）。D32-1 又禁止在 `ct build`/`compile` 新增诊断，所以它们**不可能**在编译模式变红。
- 后果：落地后 `check-ast.sh` 至少新增 11 条 `expected a non-zero exit` 失败，phase 32 无法收口。
- 可验证修法：把 `check_init_ptr.ct`、`check_assign_ptr.ct`、`check_struct_assign.ct`、`check_return_ptr.ct`、`check_return_struct.ct`、`check_return_missing.ct`、`check_return_in_void.ct`、`check_container_push.ct`、`check_container_struct.ct`、`check_container_set.ct`、`check_container_put.ct`、`check_generic_arg.ct` 移出 `test/ast/errors/`，改放顶层目录 `test/ast/check_errors/`（无 `prog.ct`，行为循环 `check-ast.sh:507` 直接 `continue`，负向扫描也不会命中），由 `p32_*` bespoke 块用 `ct check --types` 断言；同步改 E32-1–E32-9/17、§8 台账、§12 交付物。
- 验证方式：修完后 `bash selfhost/check-ast.sh` 中不得出现 `check_* "expected a non-zero exit"`。

#### H2 §3.6 的 11 条 `skip` 放在被编译的 `211_coverage_aux/prog.ct` 里，`cc` 必挂

- 位置：`phase32-draft.md:208-213`（"固定 11 条 skip（共用 `ast/211_coverage_aux/prog.ct`，退出 0）"）、`:280`（S12）、`:377`
- 事实：`ast/` 夹具要过行为循环（`check-ast.sh:583-594`：`cc -Wall -Wextra` 必须成功 → 运行 → 比对输出）。而 `skip:void actual` 的两行生成非法 C：
  - `int y = f();`（`void f()`）→ `error: initializing 'int' with an expression of incompatible type 'void'`
  - `vv.push(f())` → `error: passing 'void' to parameter of incompatible type 'int'`
  - 证据 E3。
- 后果：`211_coverage_aux` 自身 `bad`，且与 E32-13"actual void 进 `check_only/`"的写法**自相矛盾**（§3.6 又把它放回 `prog.ct`）。
- 可验证修法：§3.6 的 skip 行拆两处——可编译的（array actual）留在 `211_coverage_aux/prog.ct`；`void actual` 与 fnptr actual 放 `test/ast/211_coverage_aux/check_only/`，由 `p32_coverage` 直接跑 `ct check --types` 断言 rc=0 与 expected `-`；行数与 24 行集合不变。

#### H3 E32-13 把"函数指针实际值"当可编译形态，实测不可编译

- 位置：`phase32-draft.md:305`（"可编译形态进 `prog.ct`，`void actual` 进 `check_only/`"）、`:211`（`skip:fnptr actual`）
- 事实：`int x = f;`（`int f(void)`）编译模式 `rc=0`，但生成的 C 过不了 `cc`：`error: incompatible pointer to integer conversion initializing 'int' with an expression of type 'int (void)'`（证据 E4）。闭包实际值同样不是合法 C/CT 初始化形态。
- 后果：`210_valid_skip_forms/prog.ct` 只要含 fnptr/closure actual 就挂行为循环。
- 可验证修法：E32-13 明确 `fnptr actual`、`closure actual`、`void actual` 三类**都进 `check_only/`**，`prog.ct` 只保留 array actual 与 struct 指针互转（后者需消除告警，见 H5）。

#### H4 E32-11 的 CLI 夹具跑在冻结 L2 上，测不到 L32-7

- 位置：`phase32-draft.md:279`（S11）、`:303`（E32-11）、`:170`（`--types` 只与 `check` 组合）、`:376`
- 事实：`test/modules/*/compile.args` 的唯一执行者是 `check-archive.sh` 第 7 组，而它调用 `$l2`（`:274` 构建、`:524` `( cd "$stage" && "$l2" $args )`），注释 `:128` 明说"cli_* 钉的是 L2 驱动"。`selfhost/l2/*.ct` 中不存在 `"check"` 子命令，L2 对 `--types` 只会报自己的未知选项。
- 后果：E32-11 要么永远红，要么被写成断言 L2 文案（等于没测 L32-7）。
- 可验证修法：删除 `test/modules/cli_types_wrong_subcommand/`，改为 `check-ast.sh` 内的 bespoke CLI 块（与既有 `--bogus` 块 `check-ast.sh:4064-4070` 同形）：`"$work/ct-ast" build --types x.ct` → rc≠0 且 `grep -Fq "--types is only valid with 'ct check'"`。S11 相应改为"check-ast.sh CLI 断言"，不碰 `check-archive.sh`。

#### H5 E32-12 的 209 正例内容过不了 `check-warnings.sh`

- 位置：`phase32-draft.md:304`（`char *s="hi"; char *p=0; int x=1.5; long n=1; void *v=s; Show sh=circle; struct A *pa; char *pc=pa;`）、`:226`（D32-6 说明该形态有意跳过）
- 事实：门禁 9（`check-warnings.sh:82-95`）对每个 `test/ast/*/prog.ct` 的生成 C 用 `-Wall -Wextra -std=c99 -c`，**stderr 非空即失败**。按这八行生成的 C 实测有 6 条告警（证据 E1）：`-Wliteral-conversion`（`int x = 1.5`）、`-Wincompatible-pointer-types`（`char *pc = pa`）、3×`-Wunused-variable`、`-Wuninitialized`。
- 后果：209 正例自己把门禁 9 打红；这不是"能不能编译"，而是"生成 C 必须零告警"的硬约束。
- 可验证修法：`prog.ct` 只留零告警形态——`int x = 1; long n = 1; void *v = p;` 并用 `printf` 消费所有变量；`int x = 1.5`、`struct A *pa; char *pc = pa;` 移入 `check_only/`（`ct check --types` 专属，不生成 C）。E32-12 与 §12 同步，并补一句"`prog.ct` 必须过 `check-warnings.sh` 零告警"。

#### H6 `211_coverage_aux` 与 Phase 34 的 `211_option_basic` 撞号

- 位置：`phase32-draft.md:280`、`:377`；对照 `docs/design/phase34-draft.md:205`、`:269`
- 事实：Phase 34 的 `ast/211_option_basic` 早在 `3a81e68` 就存在；`211_coverage_aux` 是本卡在 `38e5e56` 才引入（`git log -S` 可复现）。
- 后果：两个阶段会在 `test/ast/` 下产生同号目录，样例/夹具台账无法唯一索引。
- 可验证修法：按"新卡改号"原则，Phase 32 的 `211_coverage_aux` → `229_coverage_aux`（229 当前空闲；228 属 P34，221–227 属 P36，215–220 属 P35）。同步 `:208-213`、`:280`、`:377` 三处。**不要**动 Phase 34。

### 1.3 Medium

| ID | 位置 | 问题 | 可验证修法 |
| --- | --- | --- | --- |
| M1 | `:278`、`:304-305` | check_only 专属形态只写了"由 bespoke 断言块直接跑 `ct check --types` rc=0"，没有逐条给出**调用行、期望 rc、期望 stderr**；E32-12/13 只锁 rc=0 | 在 S10 写死三条命令（例如 `"$work/ct-ast" check --types "$d/check_only/void_var.ct"`），并断言 `rc=0` 且 `[ ! -s stderr ]` |
| M2 | `:307`（E32-15） | 合法语料改用"显式清单、禁止 glob"后，清单没有任何**收录规则**，S13 可以只挑能过的文件，从而自证"新增诊断=0" | 把清单定义为规则+排除：`test/ast/*/prog.ct`、`test/cases/*.ct`、`examples/*/*.ct` 全体，减去显式列出的 `errors/**`、`modules/**`、`probes/fixtures/**` 与**逐条给理由**的例外表；清单由脚本生成后冻结 |
| M3 | `:97`、`:101` | `chk_type` 是 `(expr, out, cap)` 状态返回，表里却写 `N_NUM → int（保留 num 值）`；签名没有回传数值的通道，空指针 0 判定实际只能由调用点再看 AST | 改为"`N_NUM` 判为 `int`；是否字面量 0 由调用点检查 `N_NUM` 且 `toknum==0`"，或给 `chk_type` 增加可选 `is_zero` 出参并在 §3.2/§3.3/§3.4 统一 |
| M4 | `:279` | S11 只有 5–10 行且门禁本身就错（H4）；H4 修完后它只是 `check-ast.sh` 里一个 if 块，独立成片没有意义 | 并入 S8（`--types` 解析）或 S10；若坚持独立，S 表与 §10/roadmap 必须同步（当前 945–1,560 的算术是正确的，只在合并时才会变） |
| M5 | `:181` | 文案表写 `--types is only valid with 'ct check'`，缺 `ctc:` 前缀；既有 CLI 诊断（`cli_cannot_open` 等）全部是 `ctc: ...` | 文案改为 `ctc: --types is only valid with 'ct check'`，并在 E32-11 写全行 |

### 1.4 Low

| ID | 位置 | 问题 | 修法 |
| --- | --- | --- | --- |
| L1 | `:304` | "`prog.ct` 只含 <八行>"按字面无法编译：缺 `trait Show` / `struct Circle` / `struct A` / `main` / `prog.expected.out` | 改为"核心载荷是这八行；外加最小声明与 `main`，并提交空的 `prog.expected.out`" |
| L2 | `:78`、`:181`、`:183` | L32-7 先被"删除"又被复用为 CLI 诊断，同一编号两段历史易误读 | 建议 CLI 诊断改用 L32-8，或把 :78/:183 的"原 L32-7"改称"旧接口初值诊断（原编号已回收）" |

---

## 2 Phase 33 核查

### 2.1 逐项核对结果（用户指定 7–12）

| # | 核查项 | 结论 | 依据 |
| --- | --- | --- | --- |
| 7 | L33-6 的"复用/不复用"表述 | **基本落地，有一处不自洽** | `phase33-draft.md:116-119` 明确"复用 `:` 后 token 读取与 `A + B` 拒绝形状、不复用 `resolve_type`/`find_trait` 即时校验"，且"仅在 `find_trait` 命中时拒绝 static/Drop/Handback"。但函数路径（`Parser.h.ct:1131-1148`）对 `Drop`/`Handback` 是**按名字无条件拒绝**，不依赖 `find_trait`；见 M2 |
| 8 | `ast/208_bound_decl_only` 能否构造 | **能** | `struct Box<T> { T value; }` 无实例化：`ct-ast` rc=0、`cc` rc=0、运行 rc=0、产物无 `struct Box_T`（证据 E5）。带 `T: Nope` 后声明期仍应 rc=0（本相行为），由 L33-6 推迟到跨单元实例化 |
| 9 | E33-11 的层数与计数基准 | **计数自洽，但与 `type_depth` 冲突** | `:167` 的基准 `Box<T>`=0、n 层=n-1：5 层=depth 4、6 层=depth 5，与 `:186`、`:283` 一致。但今天 `parse_type` 的 `type_depth > 4`（`Expr.h.ct:1737-1746`）会先拒绝**具体 5 层类型**（证据 E6：`error: generic type arguments nest deeper than 4`）；5 层 **impl pattern** 反而今天就能过（E7）。卡片没写 209 必须是 pattern-only、不得实例化具体 5 层类型 → M1 |
| 10 | L33-5 是否收窄、S6 是否收窄 | **收窄成立，但夹具无归属** | `:168` 把 L33-5 限定在 `parse_generic_impl` 的 pattern 分支，并明确泛型函数实参路径与 `phase26.md`/`language-spec.md` 文案不变；已核对 `phase26.md:194`、`language-spec.md:1903`、`:4336` 均为 `expected '>' after the generic type argument`（单数），与被替换的 pattern 文案 `expected '>' after the type arguments` 不同，不会互相污染；`test/` 中确实没有该 pattern 文案的既有负例。S6 文件清单（`:255`）已收窄为 `Symbols.h.ct`/`Parser.h.ct`，未含 `Expr.h.ct`。但 4 个 L33-5 夹具不在任何片的文件清单里 → M4 |
| 11 | D33-12 与 B35-7 是否冲突 | **不冲突** | D33-12（`:219`）说的是 `StructImpl.pat[]` 的**pattern 串**长度，`ct_inst_encode` 的 `_h%08x` 哈希管的是实例类型名；B35-7（`phase35-draft.md:177`）删除的是"实例名超长"错误。两者对象不同 |
| 12 | S4a/S4b 与 O1 求和、E33-15 写法 | **成立** | S4a 60–100、S4b 20–40，均 ≤150；O1 = 60+50+50+60+20=240 ~ 110+90+90+100+40=430，与 `:331` 一致；E33-15（`:287`）已写"同一 `p33_cross_unit` 块内的第二个 `ct build`、独立临时目录、不复用 E33-13 正向产物" |

### 2.2 High

#### H1 `ast/209_depth4_boundary` 与本轮之前的 Phase 32 `ast/209_valid_assignments` 撞号

- 位置：`phase33-draft.md:186`、`:256`（S7）、`:283`（E33-11）、`:295`、`:370`；对照 `phase32-draft.md:278`、`:304`、`:378`
- 事实：`git log -S '209_valid_assignments' -- docs/design/phase32-draft.md` 显示该编号自 `2d9d2f7` 起存在；`209_depth4_boundary` 由 `b9cfe2e` 首次引入。Phase 33 是本轮才占用 209 的一方。
- 后果：同一 `test/ast/209_*` 目录前缀被两张卡同时申请，夹具台账与样例编号无法唯一；按"新卡改号"的既定规则属硬冲突。
- 可验证修法：Phase 33 的 `209_depth4_boundary` → `207_depth4_boundary`（207 空闲，且与 200–206 连续），同步改 `:186`、`:256`、`:283`、`:295`、`:370` 五处。**不要**动 Phase 32 的 209（它是先占方），也**不要**动 208（无冲突）。
- 备注：Phase 32 的 `211_coverage_aux` 与 Phase 34 撞号（Phase 32 H6），两处必须分别修，不能靠一次重排同时解决。

### 2.3 Medium

| ID | 位置 | 问题 | 可验证修法 |
| --- | --- | --- | --- |
| M1 | `:167`、`:186`、`:283` | 边界夹具只写"5 层 `Box<...>` rc=0"，未写"仅 pattern、不得出现具体 5 层类型"。实测 `Box<Box<Box<Box<Box<int>>>>>` 今天被 `type_depth > 4` 拒绝（E6），而 5 层 `impl<T> Box<...>` 今天 rc=0（E7）。若实现者把 209 写成具体类型实例化，E33-11 永远失败 | 在 §3.2.2 与 E33-11 写明：209 只含 `impl<T> Box<Box<Box<Box<T>>>> { … }`，**不实例化**具体 5 层类型；并写明 pattern 递归不得转调 `parse_type`（否则 `type_depth` 会抢在 L33-4 前报"nest deeper than 4"） |
| M2 | `:116-119` | "仅在 `find_trait` 命中时拒绝 static/Drop/Handback"与"与函数 bound 同一份拒绝表"冲突：`Drop`/`Handback` 从未注册为 trait，`find_trait` 恒为 -1，按此写法声明期永不拒绝；函数路径则是按名字无条件拒绝（`Parser.h.ct:1132-1148`） | 改为两段：static trait 仅在 `find_trait` 命中时拒绝；`Drop`/`Handback` 按名字无条件拒绝，与函数路径一致；或明确写"struct 声明期不查 `Drop`/`Handback`，推迟到实例化"并补一条 L/E 覆盖 |
| M3 | `:303-308`、`:292`（E33-20） | L33-1/2/3/6 没有冻结文案，而 E33-2/5/6/15 要求"恰一条 L33-n"、E33-20 要求 `ct check` 与编译"同文案同位置"；没有文案就无法把断言写死 | 在 §8 台账前补一张与 Phase 32 §3.5 同形的文案表，逐条给出完整一行（含 `file:line:col` 与 `error:` 之后正文） |
| M4 | `:168`、`:255`、`:284`、`:307` | L33-5 的 4 个夹具（`nested_pattern_{wild,arr,ptr,fnptr}.ct`）以及 `errors/bound_unsatisfied.ct`、`impl_bound_dup.ct`、`multi_bound.ct`、`nested_pattern_depth.ct`、`nested_pattern_mismatch.ct`、`nested_pattern_repeat_mismatch.ct` 没有出现在任何片的"主要文件"列；`:295` 只说"S4/S7/S10/S11 建"，但 S4a 只列 200–202、S7 只列 203–206+209+样例 37 | 在 S4a/S6/S7 的文件列里按切片逐条点名这些 `errors/*.ct`，并据此复核 O1/O2 估算是否仍 ≥ 实际夹具量 |
| M5 | `:209`（D33-2） | D33-2 写"复用 `check_generic_bounds`"，但该函数只遍历 `sym->ginsts`（泛型**函数**实例行，`Parser.h.ct:948`），无法校验 `StructInst`；§3.1.3（`:125`）的"相同的满足性判定"才是可实现口径 | D33-2 改成"复用 `impl_declares` + struct `use` 列表判定（与 `check_generic_bounds` 同一谓词），新增 StructInst 扫描" |
| M6 | `:283` | E33-11 的位置只写"pattern 内层"，不是可断言的 `line:col`；同相其它 L 判据都要求位置固定 | 给出确定位置（例如最深一层 `<` 的 token 列），并在夹具首行标注期望 `file:line:col` |

### 2.4 Low

| ID | 位置 | 问题 | 修法 |
| --- | --- | --- | --- |
| L1 | `:168` | 只说"泛型函数实参路径与 `phase26.md` / `language-spec.md` 的相关文案不变"，未点到具体锚点（`Expr.h.ct:1605/1781`、`phase26.md:194`、`language-spec.md:1903/4336`）；本轮已实测这些锚点内容确实不同、不会被误改 | 直接引用这 5 个锚点，减少下一轮复查成本 |
| L2 | `:260`（S11） | 208 是 O1 的声明期夹具，却挂在 O3 的 S11；靠 E33-15 的跨单元负向块才成立 | 在 S11 说明"208 由 E33-15 的 `p33_cross_unit` 负向子断言驱动，不单独行为循环"，避免被误读为 O1 夹具漏建 |

---

## 3 实测证据（原始输出摘录）

探针目录 `/tmp/r5/**`，二进制 `/tmp/ct-ast`（v0.26.4）。

### E1 209 八行正例（`ct-ast` → `cc -Wall -Wextra -std=c99` → 运行）

```
ct-ast rc=0
cc rc=0
prog.c:37:13: warning: implicit conversion from 'double' to 'int' changes value from 1.5 to 1 [-Wliteral-conversion]
prog.c:44:12: warning: incompatible pointer types initializing 'char *' with an expression of type 'struct A *' [-Wincompatible-pointer-types]
prog.c:36:12: warning: unused variable 'p' [-Wunused-variable]
prog.c:39:12: warning: unused variable 'v' [-Wunused-variable]
prog.c:44:12: warning: unused variable 'pc' [-Wunused-variable]
prog.c:44:17: warning: variable 'pa' is uninitialized when used here [-Wuninitialized]
6 warnings generated.
circle
1 1 hi
run rc=0
```

→ 行为循环能过（`cc` 无 `-Werror`），但 `check-warnings.sh:90-93` 的"stderr 非空即失败"会红（H5）。

### E2 `test/ast/errors/*.ct` 的三个代表夹具在编译模式下全部 rc=0

```
init_ptr compile rc=0
struct_assign compile rc=0
return_in_void compile rc=0
```

对应 `check-ast.sh:3022-3033` 的 `expected a non-zero exit` → H1。

### E3 `skip:void actual` 的生成 C 过不了 `cc`

```
cc(int y=f()) rc=1
prog.c:8:9: error: initializing 'int' with an expression of incompatible type 'void'
cc(v.push(f())) rc=1
v.c:156:23: error: passing 'void' to parameter of incompatible type 'int'
```

### E4 `skip:fnptr actual` 的生成 C 过不了 `cc`

```
fnptr-as-int ct rc=0
cc rc=1
p.c:9:9: error: incompatible pointer to integer conversion initializing 'int' with an expression of type 'int (void)' [-Wint-conversion]
```

### E5 208 声明期夹具可行

```
decl-only generic struct rc=0
cc rc=0
run rc=0
struct Box_T count = 0
```

### E6 具体 5 层类型被既有 `type_depth` 拒绝

```
5-layer type rc=1
prog.ct:7:25: error: generic type arguments nest deeper than 4
```

### E7 5 层 impl pattern 今天就能过；6 层报旧文案

```
5-layer impl rc=0
6-layer impl rc=1
deep6.ct:5:33: error: generic type arguments nest deeper than 4
```

→ 6 层的红证成立（文案不同），但若新 pattern 递归仍转调 `parse_type`，L33-4 会被这条旧文案抢先（M1）。

### E8 伪实例与匹配器基线

```
impl<T> Box<Box<T>> + Box<Box<int>>.depth()
rc=1
prog.ct:16:1: error: no method 'depth' for type 'struct Box_Box_lint_r'
```

→ 与 `phase33-draft.md:81` 的基线一致。

---

## 4 编号占用矩阵（`test/ast/` 实列 + 各卡声明）

当前目录最高 `164`；165–198 由 Phase 31；208–211 目录均不存在。

| 号 | Phase 31 | Phase 32 | Phase 33 | Phase 34 | Phase 35 | Phase 36 | 结论 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 199 | – | – | – | – | – | – | 空闲 |
| 200–206 | – | – | 33 占 | – | – | – | 无冲突 |
| 207 | – | – | **建议改到这里** | – | – | – | 空闲 |
| 208 | – | – | 33 占 | – | – | – | 无冲突 |
| 209 | – | **32 占（先）** | **33 占（本轮新）** | – | – | – | **冲突**（33 让号） |
| 210 | – | 32 占 | – | – | – | – | 无冲突 |
| 211 | – | **32 占（新）** | – | **34 占（先）** | – | – | **冲突**（32 让号） |
| 212–214 | – | – | – | 34 占 | – | – | 无冲突 |
| 215–220 | – | – | – | – | 35 占 | – | 无冲突 |
| 221–227 | – | – | – | – | – | 36 占 | 无冲突 |
| 228 | – | – | – | 34 占 | – | – | 无冲突 |
| 229+ | – | **建议 211→229** | – | – | – | – | 空闲 |

**裁定（battle）**：编号归属按"先占用者保留、后引入者改号"，以 `git log -S` 的引入提交为准，而不是按卡片的阶段序号。因此 Phase 33 的 209 必须改（本轮引入），Phase 32 的 211 必须改（相对 Phase 34 是后引入且 34 不在本次可改范围）。两者分开修，互不替代。

---

## 5 估算与 roadmap 复核

| 项 | 卡片 | 逐片求和 | roadmap | 结论 |
| --- | --- | --- | --- | --- |
| P32 编译器 | 510–830 | 90+40+40+50+60+70+70+50+40=510；130+80+70+80+100+110+110+80+70=830 | `:47` / `:1025` | ✅ |
| P32 合计 | 945–1,560 | 510+325+80+30=945；830+530+140+60=1,560 | `:47` / `:1025` | ✅ |
| P33 O1 | 240–430 | 60+50+50+60+20=240；110+90+90+100+40=430 | `:48` / `:1026` | ✅ |
| P33 合计 | 840–1,570 | 670+80+70+20=840；1,250+140+140+40=1,570 | `:48` / `:1026` | ✅ |
| 单片 ≤150 | 全部 | 最大 S8/S9=150（P33）、S10=150（P32） | — | ✅ |

→ 算术与 roadmap 同步均无问题；H4/H6 的修法若改变切片（S11 合并、211 改名），§10 与 roadmap 两行需再核一次。

---

## 6 转 GO 的最小条件

**Phase 32**
1. H1：L32 负例移出 `test/ast/errors/`（建议 `test/ast/check_errors/`），`p32_*` 用 `ct check --types` 断言。
2. H2/H3：`void actual`、`fnptr actual`、`closure actual` 一律进 `check_only/`；§3.6 的 211 行拆"可编译 prog.ct"与"check_only"两段。
3. H5：209 `prog.ct` 改为零告警形态，`int x = 1.5` 与 `char *pc = pa` 进 `check_only/`。
4. H4：L32-7 改由 `check-ast.sh` bespoke CLI 块断言，删除 `test/modules/cli_types_wrong_subcommand` 计划。
5. H6：`211_coverage_aux` → `229_coverage_aux`。
6. M1–M5 顺次补齐（调用行/期望 stderr、manifest 收录规则、`chk_type` 零值通道、S11 去留、`ctc:` 前缀）。

**Phase 33**
1. H1：`209_depth4_boundary` → `207_depth4_boundary`（5 处）。
2. M1：写明 209 是 pattern-only、不实例化具体 5 层类型，且 pattern 递归不转调 `parse_type`。
3. M2：拆开 static trait（依赖 `find_trait`）与 `Drop`/`Handback`（按名无条件拒绝）。
4. M3–M6：补 L33-1/2/3/6 文案表、夹具归片、D33-2 口径、E33-11 精确位置。

修完 H1 与 M1–M2 后，Phase 33 可立即转 GO；其余 Medium 不构成阻断但应同批改完，避免第六轮再来一次。

---

## 7 评审纪律声明

- 本次只读：未修改 `docs/design/phase32-draft.md`、`phase33-draft.md`、`docs/roadmap.md` 任何字节，未 `git add`/`commit`。
- 未运行 `bash selfhost/check-all.sh`；仅运行单条 `/tmp/ct-ast` 与 `cc`，产物全部落 `/tmp/r5/**`。
- 未改判据、未改 golden、未动版本号；所有"冲突"裁定均给出可复现的 `git log -S` 或实测命令。
- 评审期间另有会话并发修改 `docs/design/phase34-draft.md`、`phase35-draft.md`、`phase36-draft.md` 与 `docs/roadmap.md`（`git status` 可见）。这些改动不在本次范围，评审未触碰；`roadmap.md` 第 47/48 行与英文表第 1025/1026 行在复核时仍是 `945–1,560` / `840–1,570`，上述引用有效。
