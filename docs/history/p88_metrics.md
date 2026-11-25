# v0-PH-88 S88c 度量与 sharp edge：发射器按 kind 切片（v0.88.0）

> **S88c 交付物**。切片：`backend/emit/Emitter.h.ct` 的五个 kind 判别函数
> （`emit_node` / `emit_expr` / `emit_type_decl` / `emit_inline` / `emit_field`）。
> 控制组 = 基线 `47a8f786`（v0.87.0）；实验组 = 基线 + S88a 切片 + S88b fixpoint 参数化。
> 探针：`p88_emit`（切片清单 + 变异自测 + 66 语料逐字节）、`p88_fixpoint`（2/3 轮）、
> `p88_metrics`（本文数字复算）。原始输出见 [test/probes/p88_evidence.txt](../../test/probes/p88_evidence.txt)。

<!-- p88-metrics: emitter_before=8876 emitter_after=10965 total_slices=76 expr_slices=34
     node_slices=26 decl_slices=6 inline_slices=8 field_slices=2
     emitted_before=48223 emitted_after=61409 io_cap=1024
     (SH-117 后复测：out/ref owning 赋值点补 release 旧值（sb_assign）并把 ref/out
      形参登记进类型表（sb_push_params），Emitter.h.ct 9814 -> 9830；P-3.5 的
      `String`/`Str` → `char *` 检查与 `ref` 显式 release 硬错在 Expr.h.ct，
      发射 C 52218 -> 52282)
     (SH-118 后复测：`chk_brace_init` 跳过 `{ 0 }` 聚合零填充与 String/Str 字段的
      字符串字面量，发射 C 52282 -> 52304)
     (v1-PH-0 S0.5 后复测：五个判别函数的 if 链改为 84 臂的穷尽 match，76 个
      `em_*` 切片各占一臂；`expr_ctype` / `maybe_box` / `chk_type` 同步改为
      NodeKind match。动作等价由 66 语料逐字节、345 诊断逐字、2 轮自举不动点复核)
     (LANG-26 后复测：`out` 写回转换与 `CT_BINDING_CONVERSION` 开关落在
      Expr.h.ct / Emitter.h.ct / Arena.h.ct；Emitter.h.ct 10343 -> 10415，
      发射 C 54413 -> 54712，切片清单不变)
     (LANG-29 S4/B5 后复测：表达式 `match` 的 statement-expression 发射与
      sb_assign 的 match 结果临时量类型回落落在 Emitter.h.ct；切片清单仍为 76，
      判别式仍各读 1 次)
     (LANG-29 S4/B4 后复测：`map binding` 的 aux 12 展开、pair 键归一与
      --emit-map 的 registry 跳过落在 Emitter.h.ct；切片清单仍为 76)
     (S1a-0 C1 后复测：map 表与 `MapBind` 参数并行表改堆块、`--emit-map` /
      `map_visible` 全表扫描改持槽位、`emit_recipe` 的 16 项暂存改按绑定分配，
      落在 Emitter.h.ct；Emitter.h.ct 10929 -> 10953，发射 C 59247 -> 59373，
      切片清单仍为 76。同批的 `MAX_PKG_DEPS` 只改 Pkg/Driver，Emitter.h.ct
      不变，发射 C 59373 -> 59667。S1a-0 C3 的 ADT 计数动态化改
      Symbols/Stmt/Parser，Emitter.h.ct 仍不变，发射 C 59667 -> 59805)
     (S1a-0 C2 后复测：raw 块收到 TEXT_LIMIT、缓存键 / 初始化文本 / pkg 锁文本
      改按需堆块，落在 Parser/Cache/Module/TypeCheck/Stmt/Pkg；Emitter.h.ct
      仍不变，发射 C 60111 -> 60462，切片清单仍为 76)
     (S1a-0 C2e 后复测：Pkg 的 17 处 MAX_PKG_CMD 命令/路径缓冲改为 owned 按需
      文本，只改 Pkg.h.ct；Emitter.h.ct 仍不变，发射 C 60462 -> 60851，切片清单
      仍为 76)
     (S1a-0 C2f/C2g 后复测：cc 命令行与 cflags/ldflags 累加器按需增长，落在
      Module/Driver/ModuleBoundary/main；Emitter.h.ct 仍不变，发射 C 60851 ->
      61005，切片清单仍为 76)
     (S1a-0 C2h 后复测：Pkg 的行读取改 `pkg_text_fgets`、index `seen` 改指针行、
      诊断消息改 `pkg_text_setf`，落在 Pkg.h.ct / main.ct；Emitter.h.ct 仍不变，
      发射 C 61005 -> 61169，切片清单仍为 76)
     (S1a-0 C2i 后复测：包目录/树扫描路径改 `pkg_pathf` 精确分配、`sha_collect` /
      `sha_sort` 改指针行、`copy_tree` / `split_spec` / `IndexRow.dir` 按需，只改
      Pkg.h.ct；Emitter.h.ct 仍不变，发射 C 61169 -> 61335，切片清单仍为 76)
     (S1a-0 C2j 后复测：manifest 的 dep 行改 `struct DepList`（每行一条精确字符串，
      递归安全），`remember_dep` 的重复行比较按 spec 全长；只改 Pkg.h.ct，
      Emitter.h.ct 仍不变，发射 C 61335 -> 61409，切片清单仍为 76)
-->

## 1 切片清单

判别式 = `self->arena->nodes[n].kind`；每个切片 = 一个 kind 的完整分支体
（含其注释），被判别函数以 `nk` 传入。切片函数是**文件级 static 函数**，不是
trait 方法：trait 方法数计入 `MAX_METHODS`（64），且 `EmitOps` 已接近该上限。

| 判别函数 | 切片前函数体 | 切片后判别体 | 切片数 | 覆盖 kind |
| --- | --- | --- | --- | --- |
| `emit_expr` | 1162 行 | 41 行 | 34 | 33（`N_BIN` 两支：comma / 其余） |
| `emit_node` | 980 行 | 40 行 | 26 | 28（`N_DECL`/`N_EXPR`/`N_BIN` 参与多支） |
| `emit_type_decl` | 199 行 | 13 行 | 6 | 5（`N_ENUM` 两支：ADT / C enum） |
| `emit_inline` | 154 行 | 15 行 | 8 | 8（`N_DECL || N_FIELD` 一支） |
| `emit_field` | 46 行 | 9 行 | 2 | 2 |
| **合计** | **2541 行** | **118 行** | **76** | — |

- **SH-120（v1-PH-1 S0）后的 live 校准**：`Emitter.h.ct` 10415 → 10446 行（+31：
  `String.h` 头名映射、八槽注释与实例胶水前的 retain/release 前置声明），发射 C
  54712 → 54792（+80：内建层拆分后的四个字符串单元、单元归属与前置声明）。上面 PH-88
  的历史数字保持不变；本文件头部的 `emitter_after` / `emitted_after` 是 p88_metrics 的
  live pin，随每次 emitter 变更同步。
- **v1-PH-1 S1（SH-94，纯搬移）后的 live 校准**：`Emitter.h.ct` 11257 → 11062 行
  （-195：`EmitterQuery` 11 个只读查询函数与 `EmitterMapText` 6 个 map recipe
  文本/可重复性函数整段搬出；函数体逐字节不变），发射 C 56610 → 57158（+548：
  新增两个单元的头/前置声明与搬移后的单元边界，行为由 70 语料逐字节与 25/25
  goldens 复核）。切片清单仍为 76，判别式仍各读 1 次。
- **v1-PH-1 S1 方法级拆分（SH-94，纯搬移）后的 live 校准**：`Emitter.h.ct`
  11062 → 10740 行（-322：`EmitterCore` 抽出 `struct Emitter` 与 `EmitOps`
  声明，`EmitterTry` 搬出 4 个 postfix `?` 方法；函数体逐字节不变），发射 C
  57158 → 57769（+611：四个 Core 与三个方法子单元的头/前置声明和单元边界；
  Expr/Stmt 的方法组同批）。切片清单仍为 76，判别式仍各读 1 次。方法与布局见
  [sh94-m1-core-layout](../design/sh94-m1-core-layout.md)。
- **LANG-29 S4/B4（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 11173 → 11257 行
  （+84：`map binding` 的 aux 12 recipe 展开、pair 键归一、候选歧义诊断与
  `--emit-map` registry 跳过），发射 C 56258 → 56610（+352：同一代码的生成物）。
  切片清单仍为 76，判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S4/B5（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 11086 → 11173 行
  （+87：表达式 `match` 的 statement-expression 发射、`emit_match_arm` 的通配位
  位测试与 `sb_assign` 的结果临时量类型回落），发射 C 55475 → 56258（+783：同一
  代码的生成物）。切片清单仍为 76，判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S3/B2（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 11003 → 11086 行
  （+83：ADT 固有 impl 的方法体发射、`match(self)` 的值解引用、方法调用与 pub
  原型的 ADT 回落），发射 C 55384 → 55475（+91：同一代码的生成物）。切片清单仍为
  76，判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S2/B3（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 10701 → 11003 行
  （+318：ADT payload 的 owning 判定、`sb` 作用域/参数/返回的通用 retain-release、
  按 variant 发射的 `T_retain`/`T_release` 与构造/绑定插入点），发射 C 55045 →
  55384（+339：同一代码的生成物，外加内建层调用点不变）。切片清单仍为 76，
  判别式仍各读 1 次；本次没有新增 kind 分支。
- **LANG-29 S1/B1（v1-PH-1 S2b）后的 live 校准**：`Emitter.h.ct` 10446 → 10701 行
  （+255：ADT payload 布局闭合校验、按拓扑序防环/深度上限的实例壳预发射，及其
  单测注释），发射 C 54792 → 55045（+253：同一代码的生成物）。切片清单仍为 76，
  判别式仍各读 1 次；本次没有新增 kind 分支。
- `Emitter.h.ct`：8876 → 10415 行（**+1539，+17.3%**）。S88c 的增量来自 76 个
  函数头/参数/`(void)` 行与切片注释；后续阶段（SH-117、SH-118、v1-PH-0 S0.5、
  LANG-26）在同一文件继续增长，分支体本身逐字搬移（见 §3 的等价证据）。
- 每个判别函数的 `nodes[n].kind` 读数从 29/34/6/13/2 次降为 **各 1 次**；
  切片体内同结点 kind 的读取改为使用传入值 `nk`（`p88_emit` 逐个核对）。

## 2 编译/运行开销

| 指标 | 控制组 | 实验组 | 变化 |
| --- | --- | --- | --- |
| `ct-ast build --emit-c` 墙钟（5 次中位，同一台机） | 0.74 s | 0.76 s | +2.7%（噪声内） |
| `cc -Wall -Wextra -std=c99` 全产物（27 个 `.c`，5 次中位） | 0.62 s | 0.62 s | 0 |
| 发射 C 总行数（本版 ct-ast 对两棵树 `--emit-c`；实验组为 v0.88.1 复测） | 48,223 | 48,870 | +647（+1.34%） |
| 编译告警（`-Wall -Wextra -std=c99`） | 0 | 0 | 0 |
| 自举不动点 | 2 轮一致 | 2/3 轮一致 | — |

测量方法：同一目录、`TMPDIR` 私有、取 5 次 wall time 的中位数；`--emit-c` 只
计编译器自身时间，不含 `cc`。发射 C 行数用**同一版 ct-ast** 分别对基线树
（`git archive 47a8f786`）与当前树发射，隔离源码差异。

## 3 等价证据（D-017 A1）

- **第 1 层（测试语料）**：66 个语料（`test/cases/*.ct` + `examples/*/*.ct`）
  banner 归一后逐字节一致（`p88_emit` 第 3 项；清单
  [test/probes/p85_corpus_sha.tsv](../../test/probes/p85_corpus_sha.tsv)）。
- **诊断**：344 条负例 `exit + stderr sha256` 与
  [p86_error_diags.tsv](../../test/probes/p86_error_diags.tsv) 逐条一致
  （`p86_errors` 23/0；S1a-0 C1 把 `generic_too_many` 从负例改为增长正例，减 1）。
- **自举不动点**：`CT_FIXPOINT_ROUNDS=2` 与 `=3` 均逐字节一致（原始输出见 §5）。
- **第 2 层（编译器自身产物）**：允许差异；以不动点 + ASan + 行为测试验收。

## 4 sharp edge

| # | 坑 | 证据/后果 | 处置 |
| --- | --- | --- | --- |
| 1 | **不同 callee 名上限 512**：`Expr` 的 `io_names[512]` 记录全程序直接调用的源名，76 个切片把 ct-ast 自己的树推过上限（`too many distinct calls`，落在 `Pkg.h.ct`） | `ct-ast` 编译自己失败，自举链断 | 容量按 v0-PH-88 提到 1024（`io_names`/`io_owner`/`io_known`/`io_line` 与检查式），**只在 ct-ast 内部**；诊断文本不变，只是触发点后移 |
| 2 | 宏不跨单元：`io_names` 的维度写进 `Expr.h`，`#define` 只进 `Expr.c` | 用 `MAX_IO_CALLS` 宏时生成 C 报 `undeclared identifier` | 维度写死字面量 1024，检查式同数；注释说明原因 |
| 3 | `MAX_FUNCS` 是整程序顶层函数预算（512）；76 个新 free function 后 425 → 501 | 再切一批（>11 个函数）会撞顶 | 实测定量；下一相先复算 501/512；已登记为遗留约束 |
| 4 | `emit_node` 的 `N_DECL` 前处理**不返回**：它处理完后落回表达式语句支（`N_DECL` 也在该支的条件里） | 直接搬成函数会把原本的 fall-through 变成"已处理"，语义改变 | 该切片用三态：返回 `2` = 继续判别，其余返回值原样透传；判别处 `if (r != 2) return r;`。这是唯一一个 fall-through 支（脚本与探针均核对） |
| 5 | 方法体里的 `self` 在发射 C 中拼作 `_self`；切片是自由函数，`self` 是普通参数 | 如果切片签名写成方法会撞 `MAX_METHODS` 且改 vtable | 自由函数 + 显式 `struct Emitter *self` 参数；ABI/命名契约不变 |
| 6 | `String` 拼接/可增长 buffer **在本切片不适用** | 发射器是流式的：`self->out` 是 `FILE *`，逐 token `fputs/fprintf`，没有"先拼整行再写"的路径；剩余固定缓冲都受 `MAX_TEXT`=160 与 `header_guard(cap)` 的契约约束 | 不改：引入 `lib/std` 的 `String` 会给引导编译器增加一次分配器依赖与第二份 String 实现，收益为零（R88-3 的"必要时局部保留 buffer"）；登记为未覆盖项，供 M1/v1.1 复核 |
| 7 | **错误路径 `?`/errdefer 不适用**：L2 引导链不下降 v0-PH-40/v0-PH-44（v0-PH-86 battle A，REVIEW 已签），写进 ct-ast 源码会被原样发射成非法 C | 本切片保留原有 `return -1`/`fail_from`；没有可挂的 `?`/errdefer | 按 v0-PH-86 口径不改；与字面 `match` 同承接到 `v1-PH-0` |
| 8 | `-Wunused-variable`：切片里为了承接原函数顶部局部量（`c`/`op`/`m`）补声明，但有的分支只在嵌套作用域声明同名变量 | 首轮出现 1 条 unused 告警 | 切片内补 `(void)name;`；最终零告警 |

## 5 原始输出

```console
$ CT_FIXPOINT_ROUNDS=2 bash selfhost/check-ast.sh --fixpoint-only .temp/ct-ast
fixpoint: 2 rounds byte-identical
$ CT_FIXPOINT_ROUNDS=3 bash selfhost/check-ast.sh --fixpoint-only .temp/ct-ast
fixpoint: 3 rounds byte-identical
$ bash test/ast/p88_emit.sh .temp/ct-ast
  p88emit: slices=76
  p88emit: missing-arm negative is red
  p88emit: 66 corpus files are byte-identical
p88emit: 3 passed, 0 failed
$ bash selfhost/check-ast.sh          # 日常 2 轮
... self-compile (fixpoint: 2 rounds byte-identical) ...
```

## 6 与 v0-PH-85 spike 对照

v0-PH-85 的单切片 spike 是词法器 `next`（391 → 425 行，+8.7%；发射 C +42 行；
`--emit-c` 1053 → 994 ms，噪声内；零告警）。v0-PH-88 是**按 kind 切片**的另一种
形状：函数数增加更多（+76），行数 +5.6%，发射 C +0.88%，时间不变，零告警。
两者的共同结论一致：**切片本身不带来可测的运行时/构建开销**；差别在判据：
spike 只切一个方法，v0-PH-88 切 5 个判别函数并新增了"漏一个 kind 就掉切片"的清单
约束（`p88_emit` 的变异自测）。

## 7 未覆盖 / 遗留

1. 字面 `match` 未写进 ct-ast：L2 引导链不实现 v0-PH-84（证据
   [battle/p88-emit-match](../../battle/p88-emit-match/verdict.md)）；承接目标为
   **v1.0 seed cutover（`v1-PH-0`）**，届时把 76 个切片机械改成「一 kind 一臂，
   共用体调同一 helper」（v0-PH-84 无 or 模式）。
2. `String`/可增长 buffer 见 §4 第 6 条：判定不适用，未改。
3. `MAX_FUNCS` 余量 11 个顶层函数（501/512）：下一批切片前必须复算，不得静默撞顶。
