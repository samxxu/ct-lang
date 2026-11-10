# Phase 28 · 泛型 × Trait（Trait 约束的泛型函数 + 静态派发）

> 中文。
>
> **状态：规划中**（2026-11-10 立项评估完成，未开工）。本轮只产本文件并登记
> roadmap/README 索引；不改编译器、不改 golden、不 bump、不 push、不打 tag。
> **主题来源**：用户 2026-11-10「完善泛型，主要目标是让泛型能支持 Trait」；[phase26.md:39-51](phase26.md#L39-L51)
> 把「泛型 trait / `impl` 方法 / 类型参数约束」一并列为非目标，本相收回其中**约束与派发**两项。
> 关联：[phase26.md](phase26.md)（泛型函数）、[phase25.md](phase25.md)（静态映射与闭包实参）、
> [phase21.md](phase21.md)（非逃逸闭包）、[phase27.md](phase27.md)（`foreach`，已完成）、
> [language-spec.md](../language-spec.md)、[AGENTS.md](../../AGENTS.md)。

---

## 0. 结论先行

| 问题 | 结论 |
| --- | --- |
| 现状到「泛型能用 trait」差多少 | 差**四段连续改动**（约束语法 → 绑定元数据 → 模板体内方法解析 → 实例满足性检查与派发），**不差类型表示**；代码量估算 200–350 行，与 Phase 25/26 同量级 |
| 推荐路线 | **窄版（路线 A）：trait 约束的泛型函数，静态派发，单类型参数、单约束、显式实例化** |
| 为什么不直接做参数化 trait | 参数化 trait（`trait Seq<T>` / `impl Seq<int> for S`）要改已发布产物命名与 vptr 字段、要一套可注入的类型身份与 mangling、要重扫 32 处 `find_trait` 与 66 处 `*_vptr/_vtable` 引用；估算 800–1300 行，且其真正价值依赖泛型 struct（再 +1200–2000 行），单相收不了口 |
| 与 Phase 27 的关系 | **无代码依赖**。`foreach` 当前只吃一维数组（D27-4 已裁决容器协议本相不做）；本相不定义容器协议，也不改 Phase 27 的文件 |
| 本相不碰什么 | 类型表示（`MAX_TEXT 160` / `type_key` 有损归一）、既有产物命名（`<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>`）、`.h` 只放类型、L0/L1/L2、跨单元实例导出规则 |

---

## 1. 立项

### 1.1 编号与边界

| 项 | 值 |
| --- | --- |
| Phase | 28 |
| 目标版本 | `v0.27.0`（Phase 27 在 `v0.26.4` 内收口、未 bump，`v0.27.0` 仍未被占用；收口是否 bump 需用户确认；规划期不计版本，版本仍为 `v0.26.4`） |
| 改动边界 | 仅 `selfhost/ct-ast/**` + `test/**` + `examples/**` + `docs/**`；L0/L1/L2 只允许收口时改 `CTC_VERSION` |
| 判据冻结 | E28-1…E28-8 与 L28-1…L28-7 在首个实现提交前冻结；此后只向判据靠拢 |

### 1.2 一句话目标

让泛型函数能**要求类型实参实现某个 trait，并在模板体内直接调用该 trait 的方法**：
`T max2<T: Ord>(T a, T b)` 以 `max2<Point>(p, q)` 实例化时，`a.cmp(&b)` 在编译期落成
`Point_Ord_vtable.cmp(&a, &b)` 一类的裸 C 调用，不装箱、不引入运行时类型信息、不改结构体布局。

### 1.3 范围

**做什么**

| # | 内容 |
| --- | --- |
| S1 | 约束语法：`T name<T: Trait>(...)`；单类型参数 + 单约束；显式实例化口径不变 |
| S2 | 约束校验（声明期）：约束必须是**真实 trait**（非 `.m.ct` 静态 trait、非内建 `Drop`/`Handback`）；多约束 `T: A + B` 明确拒绝 |
| S3 | 模板体内派发：接收者为类型参数 `T`（值 `x.m(...)` 或指针 `p->m(...)`）时，按约束 trait 的方法签名解析、检查 arity 与实参，记为「约束调用」节点 |
| S4 | 实例化满足性检查：`max2<Point>` 要求 `Point` 的 `use` 链含 `Ord`（或存在 `impl Ord for Point`）；缺失、类型实参非 struct、`void` 等各给专属诊断 |
| S5 | 落码：约束调用发射为**经 vtable 对象的方法槽调用**（`Point_Ord_vtable.cmp(&a, …)`），同单元与跨单元一条路径；不访问 `__ord_vptr`，不改结构体布局 |
| S6 | 正例/负例夹具与 `check-ast.sh` 断言（含红证：基线 `v0.26.4` 上同一夹具必须失败） |
| S7 | 文档：语言规范一节、教程一段、样例 `examples/21_generic_bound/`；roadmap/README 索引已随本文件登记（2026-11-10） |

**不做什么（与「做什么」同样具体）**

| 不做 | 一句话理由 |
| --- | --- |
| 参数化 trait 声明（`trait Seq<T>`）、带类型实参的 `impl Trait<X> for S` | 要改已发布产物命名与 vptr 字段，见 §4.2；本相只做「用 trait」不做「给 trait 加参数」 |
| 泛型 struct / union / enum（`Box<T>`） | 布局单态化是另一个量级（Phase 26 D26-2 维持） |
| 多类型参数、类型推导、默认类型参数 | 沿用 D26-2/D26-3；推导需要双向类型检查 |
| 多约束（`T: A + B`）、约束继承（`trait Ord: Eq`） | 组合爆炸与解析歧义；先让单约束端到端可证 |
| `Self` 类型 / trait 方法签名里出现类型参数 | vtable 类型在 trait 维度共享，`Self` 会迫使 vtable 按 (trait, struct) 分裂，等同参数化 trait |
| 把 `T` 装箱进接口（`Trait i = x;`）、`T` 作接口字段/数组元素 | 装箱要 vptr 初始化与布局约定；本相只做静态派发 |
| 约束的运行时派发（按实际类型选 vtable） | 本相所有 vtable 选择在编译期由类型实参确定 |
| 泛型函数 `pub` / 跨单元导出实例 | 沿用 L26-2；实例只落在模板定义单元 |
| 递归泛型调用 / 泛型体内再调泛型 | 沿用 L26-5 |
| 约束方法返回 `T` 或接收 `T` | trait 声明早于 struct，签名里无法出现 `T`；要突破必须参数化 trait，见 §4.4 |
| 改 `type_key`、`MAX_TEXT`、实例去重键 | 本相不需要新的类型身份；改动会波及静态映射宿主匹配（Phase 25 回归面） |

### 1.4 交付物清单（每项一个路径）

| # | 路径 | 作用 |
| --- | --- | --- |
| D1 | `docs/design/phase28.md` | 本文件 |
| D2 | `selfhost/ct-ast/frontend/sym/Symbols.h.ct` | `Fn.bound`（约束 trait 名 + 行号）；约束查询辅助 |
| D3 | `selfhost/ct-ast/frontend/parse/Parser.h.ct` | `<T: Trait>` 解析、单约束/合法性校验、模板标记 |
| D4 | `selfhost/ct-ast/frontend/parse/Expr.h.ct` | 模板体内 `T` 接收者方法解析（新 `aux` 分支）、arity/实参检查、L28 诊断 |
| D5 | `selfhost/ct-ast/backend/emit/Emitter.h.ct` | 实例化满足性检查、约束调用落码（vtable 槽调用）、跨单元可见性诊断 |
| D6 | `test/ast/136_generic_bound/` | 正例：`struct Point` 实现 `Ord`，两个实例（不同 struct），值接收者 |
| D7 | `test/ast/137_generic_bound_ptr/` | 正例：指针接收者 `p->m()`、`arr[i].m()`、默认方法（trait 默认体） |
| D8 | `test/modules/p28_bound_cross_unit/` | 正例：`pub trait` + `pub struct`，impl 在依赖单元、模板与实例在消费单元 |
| D9 | `test/ast/errors/generic_bound_*.ct`（7 条） | 负例：未知约束、多约束、静态 trait 约束、内建 trait 约束、非 struct 实参、缺 impl、方法不在约束内 |
| D10 | `selfhost/check-ast.sh` | Phase 28 门禁块：红证、正例运行输出、生成 C 断言、七条负例文案与位置 |
| D11 | `examples/21_generic_bound/` | 样例：约束泛型 + trait 方法 + `char *`/struct 两实例；`expected.out` 由编译器产物生成后人工核对 |
| D12 | `docs/language-spec.md` / `docs/tutorial.md` / `AGENTS.md` / `docs/roadmap.md` / `docs/README.md` | 规范 §4.50、教程 §10.7、当前阶段；roadmap 与 design 索引已登记（2026-11-10），规范/教程/AGENTS 正文在实现切片写 |

> **门禁现状（实测）**：索引登记后 `python3 test/docs/check-docs.py` 转绿（`OK (917 relative links
> in 176 files, v0.26.4, 11 hard gates, 12 phase status)`，`design window: ok (12/12)`）；
> 中文行与英文行都含状态符号 `⬜` 并链接 `design/phase28.md`，与 `STATUS_MAP["规划中"]` 一致。

> **归档触发（本轮不做，只记条件）**：`design window` 已满（12/12，`phase17.md`–`phase28.md`
> 正好 12 份）。`check-docs` 的规则是 `floor = 最新编号 - 12 + 1`（[check-docs.py:264-296](../../test/docs/check-docs.py#L264-L296)），
> 所以窗口在**临界**：Phase 28 开工后一旦出现第 13 份编号阶段文档（Phase 29 立项卡），
> `phase17.md` 立即越窗，必须先把最早阶段文档 `git mv docs/design/phase17.md docs/history/design/`
> 并同步 `docs/README.md` 索引，否则文档门禁转红。本相不做归档。

### 1.5 退出判据草案（冻结于首个实现提交前）

| # | 判据 | 命令 / 锚点 |
| --- | --- | --- |
| E28-1 | 正例 136/137 构建、运行、输出逐字节匹配；136 的生成 C 含 `Point_Ord_vtable` 与 `__ct1`/`__ct2`，不含 `__ord_vptr` | `bash selfhost/check-ast.sh` 的 Phase 28 块：`cmp -s` + `grep -c` |
| E28-2 | 跨单元正例（D8）在 `build` 模式下链接通过并运行正确；依赖单元的 `.h` 只新增既有 `extern struct <Trait>_vtbl`，不新增函数原型 | `ct-ast build ...` + 运行比对 + `.h` 断言 |
| E28-3 | 七条负例各自只产生一条 L28 错误，文案与 `file:line:col` 精确匹配；**基线 v0.26.4 对同一夹具给出不同结果**（红证非空转） | `check-ast.sh` 的 `"fixture\|line:col\|message"` 表 + §3.1 基线记录 |
| E28-4 | 生成物无残留类型参数 `T`（复用 `tparam_residue()`），约束调用不发射 `T`、不发射 `__<trait>_vptr` | 既有扫描 + `! grep -E '__[a-z]+_vptr'` 作用于实例体 |
| E28-5 | 非泛型 golden 逐字节不变；`check-ast` 既有断言零回归 | `check-goldens.sh` / `check-ast.sh` 汇总 `0 failed` |
| E28-6 | 11 道硬门禁全绿，`check-warnings` 零新增告警 | `bash selfhost/check-all.sh` 末行 |
| E28-7 | `ct check` 与 `ct build` 对七条负例同文案（解析期诊断共用） | `ct check test/ast/errors/generic_bound_*.ct` |
| E28-8 | 文档门禁绿；样例 21 已经 `examples/README.md` 登记并进 `test/run.sh` 端到端 | `python3 test/docs/check-docs.py` + `./test/run.sh` |

> 版本判据（五处 `CTC_VERSION` + 全量 golden 重生）在收口切片单独执行；规划期不预支。

### 1.6 依赖

| 依赖 | 说明 |
| --- | --- |
| Phase 26 泛型函数 | 模板声明/实例表/发射期替换上下文是唯一插入点；本相复用 `GenericInst`、`gtparam/gtarg/gtname` |
| trait / impl / vtable（Phase 0–11） | 约束满足性看 `StructDef.use`；派发复用 vtable 符号与 `extern` 导出规则 |
| Phase 25 静态映射 | 无依赖；模板体内未解析方法当前落入 `aux==6` 的静态映射兜底，本相必须**先于**该兜底判定约束调用 |
| Phase 27 `foreach` | **无代码依赖**；只在文档/索引次序上让路（§8） |
| `MAX_GENERIC_INSTS` / `MAX_FUNCS` / `MAX_NODES` | 不新增表；约束调用只增加节点字段，不增节点种类 |

### 1.7 已知风险（每条带触发信号）

| # | 风险 | 触发信号 | 缓解 |
| --- | --- | --- | --- |
| R1 | 约束调用在解析期取证，实例化后接收者类型变了，签名检查用错类型 | 实例方法实参误报/漏报，或 `max2<Point>` 通过而 `max2<Other>` 也通过 | 约束方法签名在 trait 上是具体类型，与 `T` 无关；检查只用约束签名，实参按 `T` 位置放行 |
| R2 | 约束调用与静态映射兜底（`aux==6`）抢同一个调用点 | `receiver T` 的方法调用报 `a map call has fewer arguments…` | 在 `expr_type == T` 且模板有约束时先走约束分支，`aux==6` 只在无约束时可达 |
| R3 | vtable 符号在实例函数之后才定义，或跨单元未导出 | `cc` 报未声明标识符/未定义引用 | 统一经 `emit_vtable_fwd` 已发射的前置声明；跨单元要求 `vtable_exported()` 为真，否则编译期 L28-8 |
| R4 | 实例化时 `StructDef.use` 不含约束 trait，但同单元有 `impl`（缺 `use`） | 误报「未实现」 | 满足性判定取 `use` 链 ∪ 本程序内 `N_IMPL`（与 `impl_exists_anywhere` 同口径），两者任一成立即通过 |
| R5 | 类型实参写法 `Point` / `struct Point` 产生两份实例 | 生成物出现两份语义相同的 `__ctN` | 沿用 D26-5 的「按拼写去重」；文档写明这是既有口径，不引入归一化 |
| R6 | 约束方法名与结构体自有同名字段/函数指针字段冲突 | 误判为字段调用 | 约束分支只在 `T` 接收者上生效，具体 struct 的字段调用路径不变 |
| R7 | `tparam` 名字与约束 trait 方法参数名同名 | 替换/检查误伤 | 约束调用不做类型替换；检查按 `MethodSig` 逐参比对 |
| R8 | 约束 trait 有默认体 | 派发调到不存在的 `S_T_m` | 默认体已由 `emit_default_method` 落成 `S_T_m`，vtable 槽已填；断言覆盖 D7 |

---

## 2. 语义

### 2.1 语法

```c
trait Ord {
    int cmp(void *other);      /* trait 声明早于 struct，参数只能写具体类型 */
}

struct Point { int x; } use Ord;

impl Ord for Point {
    int cmp(void *other) {
        struct Point *o = (struct Point *)other;
        return self->x - o->x;
    }
}

/* 泛型函数：单类型参数 + 单约束 */
T max2<T: Ord>(T a, T b)
{
    if (a.cmp(&b) > 0) return a;
    return b;
}

Point m = max2<Point>(p, q);
```

- 约束写在类型参数之后、`>` 之前，复用 C 风格 `<...>`；不新增关键字。
- 方法调用形态只增加两种接收者：`x.m(...)`（`x: T`，发射时取 `&x`）与 `p->m(...)`（`p: T *`，发射时用 `p`）。
- 其它 `T` 的用法完全沿用 Phase 26：类型位替换、值位置硬错（SH-64）、数组维度硬错（SH-66）。

### 2.2 声明期校验（L28-1…L28-4）

| 码 | 触发 | 文案（草案，实现前冻结） |
| --- | --- | --- |
| L28-1 | 约束名不是已知 trait | `unknown trait '<name>' in a generic bound` |
| L28-2 | 多约束 `T: A + B` | `only one trait bound is supported` |
| L28-3 | 约束是 `.m.ct` 静态 trait / `Drop` / `Handback` | `trait '<name>' cannot bound a type parameter` |
| L28-4 | 约束后缺函数体、`pub` 泛型等既有规则 | 沿用 L26-2 等既有文案 |

### 2.3 实例化与落码

对 `max2<Point>`：

1. **满足性**：`Point` 必须是 struct，且 `StructDef.use` 含 `Ord` 或程序中存在 `impl Ord for Point`；
   否则 L28-5 / L28-6。
2. **实例**：沿用 `generic_instance()` 的 `<name>__ctN` 命名与「按拼写去重」，不新增产物命名。
3. **派发**：模板体内 `a.cmp(&b)` 的节点（新 `aux` 分支）发射为
   `Point_Ord_vtable.cmp(&a, &b)`；指针接收者发射为 `Point_Ord_vtable.cmp(p, &b)`。
   - 不读 `__ord_vptr`，因此不要求结构体已初始化 vptr，也不改结构体布局；
   - 同单元时 vtable 是 `static`，跨单元时是 `extern`（既有 `vtable_exported` 规则），一条路径覆盖两种情形；
   - 接收者必须是可寻址的变量/元素/成员链（与既有方法调用同一条限制），否则沿用
     `method receiver must be a variable, an element, a call or a field chain`。
4. **跨单元退化**：若约束满足但 `vtable_exported()` 为假（trait 或 struct 非 `pub`），
   发出 L28-8 `trait '<Trait>' is not exported for '<S>'; instantiate in the implementation unit`。

### 2.4 实例化期诊断（L28-5…L28-8）

| 码 | 触发 | 文案（草案） |
| --- | --- | --- |
| L28-5 | 类型实参不是 struct（`int`、`void`、接口类型等） | `type argument '<type>' cannot satisfy trait '<Trait>' (not a struct)` |
| L28-6 | struct 未实现约束 trait | `type argument '<S>' does not implement trait '<Trait>'` |
| L28-7 | 约束 trait 无该方法 / 实参个数或类型不符 | `trait '<Trait>' has no method '<m>'`；arity 与实参沿用既有 warning 口径（§2.3 的检查） |
| L28-8 | 跨单元 vtable 不可见 | 见 §2.3 第 4 条 |

诊断统一走 `ct_sem_error(line, col, msg, path)` 与既有 `fail` 通道；`ct check` 与编译路径同文案（E28-7）。

### 2.5 与 Phase 26 规则的关系

| 规则 | 本相 |
| --- | --- |
| 单类型参数 / 显式实例化 / 非 `pub` | 不变 |
| 发射期替换上下文（不写 AST） | 不变；约束调用不参与类型替换 |
| `T` 作值、数组维度、`_Generic`、裸模板名 | 沿用 SH-64 / SH-66 / D26-14 的硬错 |
| 递归/嵌套泛型调用 | 沿用 L26-5 |

---

## 3. 差距评估（现状 → 可用）

### 3.1 现状红证（`v0.26.4` 实测，2026-11-10）

用本仓自举链构建的编译器（`ct-ast v0.26.4`）跑两个探针（放在 `/tmp/p28probe`，不进仓）：

| 探针 | 期望能力 | 实测 |
| --- | --- | --- |
| `bound_syntax.ct`，第 18 行 `T max2<T: Ord>(T a, T b)` | 解析约束 | `bound_syntax.ct:18:9: error: expected '>' after the type parameter`，退出 1 |
| `unbounded.ct`，第 19 行 `a.cmp(&b)`（`a: T`，无约束语法） | 泛型体内派发 | `unbounded.ct:19:1: error: no method 'cmp' for type 'T'`，退出 1 |

两条都是**响亮的失败**（不是静默坏产物），说明缺口在「能力未实现」，不在「已实现但错误」；
因此本相的红证可以直接用这两条现状文案作对照。

代码锚点（为什么现在必然失败）：

| 环节 | 现状 | 锚点 |
| --- | --- | --- |
| 类型参数解析 | 只吃 `T`，遇 `:` 即要求 `>` | [Parser.h.ct:1002-1022](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1002-L1022) |
| `Fn` 元数据 | 只有 `ntparams/tparam/body`，无约束字段 | [Symbols.h.ct:91-99](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L91-L99) |
| 方法解析 | 按接收者**静态类型拼写**查 `StructDef.use`；`T` 查不到 → 落 `aux==6` 静态映射兜底 | [Expr.h.ct:2415-2520](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2415-L2520)、[Symbols.h.ct:729-767](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L729-L767) |
| 方法落码 | 只认已解析 trait（`__<trait>_vptr->m`）、接口（`.vt->m`）与静态映射三种 | [Emitter.h.ct:3336-3356](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3336-L3356) |
| 约束满足性 | `impl`/`use` 是解析期符号，发射期只扫 `N_IMPL` 做 vtable 去重 | [Emitter.h.ct:247-258](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L247-L258)、[Symbols.h.ct:212-216](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L212-L216) |

### 3.2 分层依赖链

量级为**估算**，校准见 §3.3；「新增」指 ct-ast 源码行数（不含夹具与文档）。

| 层 | 需要什么 | 现状 / 数据表示 | 新增或重构 | 估算 |
| --- | --- | --- | --- | --- |
| L0 语法 | `T: Trait` 约束子句 | `parse_func` 的 `tparam` 读取 | Parser：约束名解析、单约束与合法性校验 | 30–60 |
| L1 绑定元数据 | 模板行的约束 trait 名与位置 | `Fn` 16 个字段，无约束位 | `Fn.bound[160]` + 行号；实例复制时清空 | 10–20 |
| L2 模板体内解析 | `T` 接收者 → 约束 trait 的方法 | 方法解析按类型拼写；`T` 落入静态映射兜底 | Expr：`aux==7` 分支、签名查找、arity/实参检查 | 60–120 |
| L3 实例化检查 | 类型实参是否实现约束 | `StructDef.use[64]`、共享 arena 的 `N_IMPL` | Emitter/Symbols：满足性判定 + L28-5/6 | 40–80 |
| L4 派发落码 | `S_T_vtable.m(&recv, …)` | vtable 已发射、已前向声明、可 `extern` | Emitter：约束分支 + 接收者取址 | 30–60 |
| L5 跨单元格式 | `.h` 中的 `extern struct T_vtbl S_T_vtable;` | 既有 `emit_link_externs` / `vtable_exported` | **零新增格式**；补不可用诊断 | 0–15 |
| L6 诊断 | L28-1…L28-8 | `fail` / `ct_sem_error` | 8 条文案与位置 | 20–40 |
| **合计（路线 A）** |  |  |  | **190–395 行** |
| G 门禁/夹具 | 正例 3 + 负例 7 + 断言 | `check-ast.sh` Phase 26 块模板 | 夹具与断言 | 150–250 行 |

### 3.3 估算校准（实测 diff，非估算）

| 相 | ct-ast 插入/删除 | 说明 |
| --- | --- | --- |
| Phase 25（闭包进静态映射） | +304 / −44，3 文件 | 本相与之同量级：改解析 + 落码，复用既有 ABI |
| Phase 26（泛型函数） | +303 / −7，6 文件 | 本相不需要新表、不需要新的发射上下文，故略小于它 |
| Phase 24（数组 range 初值） | +776，11 文件 | 涉及多单元布局，不具可比性 |
| Phase 21（闭包） | +2185，14 文件 | 语言级新 ABI，量级上限参照 |

结论：路线 A 的 190–395 行落在 Phase 25/26 之间，属于**单相可收口**范围；主要不确定性在 L2
（方法解析要插进已很拥挤的 `aux` 分流）与 L4（接收者取址的表达式限制）。

### 3.4 结构性前置：哪些东西本相**不需要**动

| 前置 | 路线 A | 路线 B |
| --- | --- | --- |
| 类型表示（字符串、`MAX_TEXT 160`、`type_key` 有损归一） | **不动**：约束只比较 trait 名与 struct 名，实例名仍是 `__ctN` | 必须新增**可注入**的类型身份（`type_key` 明确有损：`const char *` 与 `char *` 归一，不能作 mangling 键） |
| 产物命名 | **不动**：`<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>` 原样 | vtable/vptr 必须按 (trait, 类型实参) 分裂，现有命名装不下；需改已发布约定 |
| `.h` 格式 | **不动**：只复用既有 `extern ... vtable` | 需要携带参数化 trait 的 vtable 类型与每参数 vptr 字段，头文件结构变化 |
| 实例去重键 | 沿用 `(模板, 类型拼写)`；`Point` 与 `struct Point` 会各生成一份（文档写明） | 需要规范化键，否则同一实参多种拼写产生重复 vtable |
| 跨单元 | 复用 `vtable_exported` 规则 | 需定义参数化 vtable 的导出与命名 |

---

## 4. 两条路线

### 4.1 路线 A（窄版）：trait 约束的泛型函数

**能力边界**

- 能给类型参数加**一个** trait 约束，并在模板体内调用该 trait 的方法（值/指针接收者）。
- 实例化在编译期确定；派发是「经 vtable 对象的方法槽」的间接调用，无装箱、无 vptr 读取。
- 不能：参数化 trait、泛型 struct、trait 方法签名出现 `T`/`Self`、多约束、`T` 装箱。

**实现代价**：190–395 行 ct-ast + 150–250 行门禁；不改命名、不改 `.h`、不改类型表示、不改 L0/L1/L2。

**对 ABI / 产物的影响**：零新增符号类别；生成的实例仍是 `static <ret> <name>__ctN(...)`；
新增的只是实例体里对既有 vtable 符号的引用。

**会在哪些真实场景撞墙**

| 场景 | 撞墙原因 | 现状替代 |
| --- | --- | --- |
| `max2(a, b)` 里希望 `cmp(T, T)` 签名 | trait 声明早于 struct，签名不能出现 `T` | 约束方法写 `cmp(void *)`，impl 内转型（样例 21 就是这样） |
| 通用容器 `Vec<T>` 的 `push(T)` | 需要泛型 struct + 参数化 trait | 不做；挂到后续阶段（触发信号见 §9） |
| `T: Ord + Show` | 本相单约束 | 拆成两个泛型函数，或等触发信号 |
| 希望在泛型体里把 `T` 装箱成接口 | 装箱需要 vptr 与布局 | 用具体类型写非泛型封装，或等参数化 trait |
| `HashMap<K, V>` | 多类型参数 + 泛型 struct | 不做 |

### 4.2 路线 B（完整版）：参数化 trait（+ 泛型 impl）

**能力边界**

- `trait Seq<T> { T get(int i); }`、`impl Seq<int> for IntBox`、`impl Seq<char *> for StrBox`；
  trait 方法签名可含类型参数；同一 struct 可对同一 trait 的多个实参分别实现。
- 若要「一个实现服务所有 T」，还需要泛型 struct（`Box<T>`），本路线估算只含前者。

**实现代价（估算）**

| 层 | 内容 | 估算 |
| --- | --- | --- |
| B1 | trait 身份从 `name` 扩为 `(name, args[])`；32 处 `find_trait` 调用点逐个决定是否需要实参 | 200–350 |
| B2 | vtable/vptr 按 (trait, 实参) 分裂；66 处 `*_vptr`/`*_vtable` 引用与 `.h` 导出规则 | 250–450 |
| B3 | 类型身份与稳定 mangling（不能用有损 `type_key`；`MAX_TEXT 160` 不够嵌套） | 150–300 |
| B4 | 参数化 `impl` 的 satisfy/dispatch 与诊断 | 150–250 |
| **合计（不含泛型 struct）** |  | **750–1350 行** |
| B5 | 泛型 struct 布局单态化（若包含） | +1200–2000 |

**对 ABI / 产物命名的影响**

- 已发布命名 `<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>`、`<Struct>_<Trait>_<vtable>`
  装不下「同一 trait 多实参」：要么加类型实参序号后缀（`__seq_1_vptr`、`S_Seq__ct1_vtable`），
  要么按实参全名 mangling。两条都要改**已发布产物命名**，并重新生成全部带 vtable 的 golden。
- 结构体布局变化（每个 (trait, 实参) 一个 vptr 字段），`.h` 结构与 `sizeof` 全部受影响。
- 这是本路线最大的隐性成本：不是代码行数，而是**对外约定变更**（项目记忆：非用户要求不得改命名）。

**会在哪些真实场景撞墙**

| 场景 | 撞墙原因 |
| --- | --- |
| 无泛型 struct 时的 `Seq<T>` | 只能对具体 struct × 具体实参逐对实现，写不出 `Vec<T>`，收益有限 |
| 嵌套实参 `Seq<Seq<int>>` | 字符串类型表示 + `MAX_TEXT 160` 上限；需要 B3 的完整方案 |
| 已有 `use Trait`（无实参）代码 | 需同时保留无参形态，trait 名空间与类型名表（`type_kind==3`）冲突面扩大 |
| 跨单元导出 | 头文件要携带参数化 vtable 类型，破坏「`.h` 只放类型」的既有简化 |

### 4.3 判据对照与推荐

| 判据 | 路线 A | 路线 B |
| --- | --- | --- |
| C1 兑现「泛型能用 trait」（编译期可证） | ✅ 约束调用 + 实例化检查 | ✅ 更强 |
| C2 不改已发布产物命名 / vptr 布局 | ✅ 零变化 | ❌ 必须改 |
| C3 不触碰类型表示（字符串 / `MAX_TEXT` / 有损 `type_key`） | ✅ 不需要 | ❌ 必须新增类型身份层 |
| C4 单相内可用证据门禁收口（红证可写） | ✅ 红证已实测（§3.1） | ❌ 无泛型 struct 时收益不足，含 struct 则单相收不了 |
| C5 跨单元可用 | ✅ 复用 vtable 导出规则 | ⚠️ 需新增导出格式 |
| C6 真实场景收益 | 中：算法/比较/序列化等「一个实现服务多类型」 | 高但延迟兑现：依赖泛型 struct |
| C7 回归风险面 | 小：只新增分支，非泛型路径不变 | 大：32+66 个耦合点与全部 vtable golden |

**推荐：路线 A**。理由全部是可核对的判据：C2/C3/C4 任一为否则无法在本仓现有约束（冻结命名、
`.h` 只放类型、单相收口、证据门禁）下交付；路线 B 的唯一优势 C1/C6 要等泛型 struct 才有实际收益，
属于「先付 ABI 变更、后拿收益」。

路线 B 的启动触发信号（写死在 §9，不写「待定」）：

1. 出现至少两个真实消费者要求「同一 struct 对同一 trait 的多个类型实参分别实现」，且无法用
   两个具体 trait 名绕过；
2. 或 `foreach` 容器协议（D27-4 遗留）被重新冻结，且其消费者要求 `Seq<T>` 形态；
3. 或用户明确要求改 ABI 命名以支持参数化 trait。

### 4.4 为什么「trait 方法收 `T`」不在窄版里

trait 声明先于 struct，方法签名只能写具体类型；`Self` 若进签名，`struct <Trait>_vtbl` 这一
**trait 维度共享**的 vtable 类型就无法同时容纳 `S1`/`S2` 两种签名，只能按 (trait, struct) 分裂
——那已经是路线 B 的命名与布局变更。因此窄版把该诉求转化为文档规则（用 `void *` + impl 内转型），
并在样例 21 演示，避免「写不出想要的签名」被误解为缺陷。

---

## 5. 切片

| 切片 | 内容 | 主要文件 | 完成信号 |
| --- | --- | --- | --- |
| 28.1 | 约束语法与元数据：`<T: Trait>`、`Fn.bound`、L28-1/2/3 | `Parser.h.ct`、`Symbols.h.ct` | 模板可解析；多约束/静态 trait/内建 trait 负例红 |
| 28.2 | 模板体内解析：`T` 接收者、约束方法查找、arity/实参检查 | `Expr.h.ct` | `a.cmp(&b)` 生成约束调用节点；无约束时仍报 `no method 'cmp' for type 'T'` |
| 28.3 | 实例化与落码：满足性检查、vtable 槽调用、跨单元诊断 | `Expr.h.ct`、`Emitter.h.ct` | `max2<Point>` 生成 `Point_Ord_vtable.cmp(&a, &b)`；缺 impl 报 L28-6 |
| 28.4 | 夹具与门禁：正例 136/137、跨单元模块、负例 7 条、红证 | `test/ast/**`、`test/modules/**`、`check-ast.sh` | `check-ast` 全绿且基线红证成立 |
| 28.5 | 样例：`examples/21_generic_bound/` | `examples/**` | `expected.out` 由产物生成并人工核对 |
| 28.6 | 文档与收口：spec §4.50、tutorial §10.7、AGENTS；roadmap/README 索引已登记 | `docs/**`、`AGENTS.md` | 文档门禁绿 |
| 28.7 | 版本收口（可选、单列）：五处 `CTC_VERSION` + 全量 golden | 五处版本文件、`test/**` | 11 道硬门禁绿 |

> 28.1–28.3 合并为一个功能提交（中间态不可运行）；28.4/28.5 可分开；28.6/28.7 各一项。

---

## 6. 决策表（D28-nn）

| 编号 | 决策 | 理由 | 生效条件 / 范围 |
| --- | --- | --- | --- |
| D28-1 | 语法 `T name<T: Trait>(...)`，单类型参数 + 单约束 | 复用 Phase 26 的 `<...>`，不新增关键字；单约束先让端到端可证 | 本相全部泛型函数 |
| D28-2 | 约束必须是真实 trait：`.m.ct` 静态 trait、`Drop`、`Handback` 一律拒绝 | 前两者没有 vtable/方法体，后者无 vtable；放行会发射不可解析的符号 | L28-3 |
| D28-3 | 派发统一「经 vtable 对象的方法槽」调用，不读 `__<trait>_vptr` | 一条路径同时覆盖同单元（static）与跨单元（extern），不要求值已初始化 vptr，也不改布局 | 约束调用落码 |
| D28-4 | 满足性判定取 `StructDef.use` ∪ 程序内对应 `N_IMPL` | 两种采纳写法都存在（`use` 与仅 `impl` 的历史夹具），只看其一都会误报 | 实例化检查 |
| D28-5 | 约束方法签名不得出现 `T`/`Self`；需要时用 `void *` + impl 内转型 | `Self` 会迫使 vtable 类型按 struct 分裂，等同参数化 trait（§4.4） | 本相；文档写明 |
| D28-6 | 参数化 trait、泛型 struct、多约束、`T` 装箱不做 | 见 §4.2/§4.3 判据；任一先做都要求 ABI 或类型表示变更 | 本相；触发信号见 §9 |
| D28-7 | 不引入新的类型身份：实例去重仍按 `(模板, 类型拼写)` | `type_key` 有损，不能作 mangling 键；本相没有命名需求 | 本相 |
| D28-8 | 跨单元要求 `vtable_exported()` 为真，否则编译期 L28-8 | 不把「未定义引用」留给链接器；不新增 `.h` 内容 | 跨单元实例 |
| D28-9 | L0/L1/L2 只允许收口时改 `CTC_VERSION` | 冻结层规则；新能力只落 ct-ast | 发布切片 |
| D28-10 | 不在本相定义容器协议，不改 Phase 27 文件 | `foreach` 已收口（Phase 27，`v0.26.4` 内、未 bump）；D27-4 已裁决协议本相不做 | 文档与索引 |
| D28-11 | 新增夹具编号 136+，样例 21 | Phase 27 已占用夹具 132–135 与样例 20，本相从 136 / 21 起，避免编号冲突 | 夹具/样例 |

---

## 7. battle 记录

### B28-1 · 约束解析位置：解析期绑定 vs 发射期推断

| 席 | 主张 |
| --- | --- |
| 主张 | **解析期按约束解析方法**（`aux==7`），把 trait 名与方法签名固定进节点 |
| 反对 | 发射期按 `gtarg` 反查 struct 的 `use`，再推断方法 |
| 证据 | E1：发射期反查需要把每个方法调用的接收者表达式类型重新推导一遍，而局部变量在发射期已出作用域（[Expr.h.ct:2421-2424](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2421-L2424) 的注释即此约束）；E2：解析期已有 `MethodSig` 与 `method_trait`，arity/实参检查也只在此处有一份实现；E3：若发射期推断，`tparam_residue` 与 `ct check` 的文案将分叉，违反 E28-7；E4：解析期方案新增面仅一个 `aux` 分支与一次签名查找。 |
| 裁判 | **upheld（解析期）**。生效范围：所有带约束的模板体；若出现「同一调用点在不同实例下解析到不同 trait」，退回并重开（单约束下不可能）。 |

### B28-2 · 派发形态：vtable 槽 / 直呼 static 方法 / 装箱

| 席 | 主张 |
| --- | --- |
| 主张 | **vtable 槽调用** `S_T_vtable.m(&x, …)` |
| 反对 | 同单元直呼 `S_T_m(&x, …)`（更短、可内联），跨单元再退化 |
| 证据 | E1：impl 方法一律 `static`（[Emitter.h.ct:1754-1762](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1754-L1762)），跨单元不可见；若做「同单元直呼 + 跨单元 vtable」就有两条路径与两套测试；E2：vtable 已有前向声明（[Emitter.h.ct:1497-1531](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1497-L1531)），且实例函数在其后发射；E3：装箱需要构造 `Trait_iface` 并保证 vptr 已初始化，额外引入布局要求。 |
| 裁判 | **upheld（vtable 槽）**。代价是一次间接调用，换来单一落码路径与零布局要求；若后续有性能判据（内联收益可测），再开 battle 增加同单元直呼快路径。 |

---

## 8. 与 Phase 27（`foreach`）的关系

| 项 | 结论 |
| --- | --- |
| 代码依赖 | **无**。Phase 27 改 `Stmt.h.ct` / `Emitter` 的发码段与 `Var.dims`；本相改 `Parser` 的类型参数、`Expr` 的方法解析与 `Emitter` 的调用落码段 |
| 合并次序 | **Phase 27 先收口**（已完成，`main` = `bcd95c9`），本相基于其收口提交开工 |
| 容器协议（D27-4 遗留） | 本相**不解冻**。`foreach` 当前只吃一维数组；即使有了约束泛型，`foreach` 也不是泛型语句，无法按容器类型实例化。协议留给「有真实容器实现」的阶段 |
| `item` 与 trait 值 | Phase 27 的 L27-4 明确拒绝接口值（避免拷贝 vptr）；本相不产生接口值，规则不受影响 |
| 命名 | `foreach`（语句）与库层 `each`（trait 方法 / 泛型自由函数）分工不变；本相不新增同名语法 |
| 索引登记 | `examples/README.md` 与 `docs/README.md` 的 design 索引、`docs/roadmap.md` 的 Phase 28 行：roadmap/README 已随本文件一次性登记（2026-11-10）；`examples/README.md` 待样例 21 落地时登记（D28-10） |
| Phase 27 收口后仍待定的设计 | ①容器协议形状；②`foreach` 是否接受 `item` 为 struct 值（当前是值拷贝）；③若未来引入泛型 struct，`foreach` 对含 vptr 字段的结构体的拷贝/迭代规则。本相不冻结其中任何一项 |

---

## 9. 开放项与触发信号（不写成「待用户决定」）

| # | 开放项 | 当前处置 | 触发信号 / 重新评估条件 |
| --- | --- | --- | --- |
| O1 | 多约束 `T: A + B` | 本相拒绝（L28-2） | 出现至少两个真实算法需要「同一 T 同时满足两个 trait」，且拆函数会重复实现体 |
| O2 | `Self` 类型 / trait 方法签名含 `T` | 本相拒绝（D28-5） | 同上；且需先把 vtable 类型按 (trait, struct) 分裂，即启动路线 B |
| O3 | 参数化 trait / 泛型 impl | 本相不做（D28-6） | §4.3 的三条触发信号 |
| O4 | 泛型 struct `Box<T>` | 本相不做 | 路线 B 落地后，或 ct-pkg 侧出现真实容器需求 |
| O5 | 约束调用的直接调用优化 | 不做（B28-2） | 有可测的内联收益，且跨单元路径已有同等测试覆盖 |
| O6 | 同一 trait 的跨单元满足性在 `.h.ct` 边界上的可见性 | 依赖共享的 `Symbols`/`Arena`（构建期全程序解析）；28.3 用跨单元正例固定 | 若未来改为逐单元独立进程编译，需把采纳信息写进 `.h` |
| O7 | `Point` 与 `struct Point` 产生两份实例 | 沿用 D26-5 的拼写去重，文档写明 | 若同一程序两种写法都用且 golden 体积成为问题，再考虑归一化（会波及 Phase 25 宿主匹配） |

---

## 10. 本轮不做（自查）

- 未修改任何编译器源码、测试、golden、版本串；未改 `docs/design/phase27.md`；未 bump、未 push、未打 tag。
- 本轮新增本文件，并只按约定在 `docs/roadmap.md`（中英各一行）与 `docs/README.md`（中英各一行）
  登记索引。§3.1 的探针放在 `/tmp/p28probe`，构建产物放在 `/tmp/p28build`，均不入仓。
- `python3 test/docs/check-docs.py` 已转绿：`check-docs: OK (917 relative links in 176 files,
  v0.26.4, 11 hard gates, 12 phase status)`，`design window: ok (12/12)`。
