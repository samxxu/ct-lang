# Phase 29 · 泛型 struct + 内置 `Vec` / `Map`（含 `foreach` 容器协议）

> 中文。
>
> **状态：实施中**（2026-11-11 独立收口评审结论 **NO-GO**：上一版「E29-1…13、P29-1…5 全满足、
> Phase 29 完成」的声明不成立。评审列出的 5 项 High、6 项 Medium、2 项 Low 已逐条修复，修复块记在
> §11.2 的 V29-1…V29-5 与 §3.1 的基线红证；当前状态等复评裁决，不再自称完成）。
> 已修复的关键项：`Map<long,V>` 的 `strcmp` 误判与键白名单（V29-1）、`retain` 后二次 `release`
> 的 UAF（V29-2）、经典 `impl` 里的 `static`（V29-3）、容器下标（含 `(*p)` / 成员 / 调用基座）与花括号初值的非法 C（V29-4）、
> 容器元素为接口/带 vptr struct（V29-5）；E29-10 的 `ct build` 过期说法、E29-7 的基线红证、
> P29-4 的证据行、`std::vec::Vec` 别名、`import std::vec` 升级说明、`Vec<Vec<int>>` 的 S2/B7 描述、
> L29-5/6/13/14 的状态词、roadmap/§10.3.5 的计数、§2.3 的实现偏差均已按事实更正。
> 另：`selfhost/l2/core.ct` 的 `MAX_CALLS 512→1024` 在 `AGENTS.md` 第 93 行有例外记录，故不回退，
> §1.1 的冻结层条款已同步。
> **主题来源**：用户 2026-11-10「`Vec` 和 `Map` 应该作为内置的数据结构，从 ct-pkg 的 `std` 移到
> 内置类型」「`foreach_statement.ct` 没有把 map 纳入进来」；同日的取舍「`Callable` 内建先不做」。
> 关联：[phase28.md](phase28.md)（约束泛型函数）、[phase26.md](phase26.md)（泛型函数）、
> [phase27.md](phase27.md)（`foreach` 语句形态与 D27-4）、[phase21.md](phase21.md)（闭包与
> `Callable` 延后记录）、[map-options.md](map-options.md)（既有容器选型）、
> [language-spec.md](../language-spec.md)、[AGENTS.md](../../AGENTS.md)。

---

## 0. 结论先行

| 问题 | 结论 |
| --- | --- |
| 泛型 struct 的最小可用形态 | **显式实例化 + 布局单态化**：`struct Name<T, U>`（最多 2 个类型参数），`Name<int>` / `Map<char *, int>` 在编译期各生成一份 C 结构体；不做推导、不做运行时泛型 |
| 泛型 struct 对用户开放吗 | **开放，不是编译器特例**：用户可写 `struct Stack<T> { T items[8]; }` 并显式实例化 `Stack<int>`；内置 `Vec`/`Map` 与用户泛型 struct 共用同一张 `StructInst` 表、同一编码器、同一布局发射与 `.h` 导出路径（E29-12）。`Vec`/`Map` 只是**随编译器发行**的 `lib/std/*.ct`，不享受私有语法分支 |
| `Vec` / `Map` 放哪 | **本仓内置层** `lib/std/`，随编译器发行、无需 `ct get`；`Vec` / `Map` 是全局保留名，`std::vec::Vec` / `std::map::Map` 是同一类型的显式路径 |
| 实例命名 | **按规范化类型拼写编码**：`Vec_int`、`Map_char_p_int`；这是对 D26-5「类型拼写不进 C 标识符」的**用户授权例外**（见 §4.1、D29-6） |
| `foreach` 容器协议 | **解冻 D27-4**：`Vec` 用 `len()` + `get(int)`，`Map` 用 `len()` + `entry(int)`；只对内置 `Vec`/`Map` 生效，用户自定义可迭代类型本相不做 |
| `foreach` 的绑定 | 统一 `item` = **当前元素**；数组/`Vec` **必须同时**提供 `item`（元素）与 `i`（下标），两者都是规定绑定；`Map` 用 `item.key`/`item.value`，体内出现 `i` 为硬错（L29-18）；`items[i]` 不是规定语法（用户 2026-11-10 已裁定） |
| `Map` 的键值绑定 | `item.key` / `item.value`；`item` 是值拷贝，块内改写不回写容器（与 Phase 27 数组一致） |
| `Map` 的遍历顺序 | **插入序**：紧凑 entries + 删除左移；扩容/重哈希不改顺序，golden 稳定 |
| `Map` 的键类型 | 白名单 `int` / `long` / `char *`；不做 `Hash` / `Eq` 约束（Phase 28 的约束方法签名装不下 `T`） |
| 容器拷贝 | **移动语义 + 显式 `retain()`**：变量间直接拷贝硬错；从函数调用初始化/赋值视为移交；`release()` 递减引用计数 |
| 自动析构 | 本相**不做**：容器不自动 `release`，`own` / `borrow` 值不得存入容器；自动析构留给后续阶段（触发信号见 §9） |
| `std` 迁移 | `Vec` / `Map` 从 `ct-pkg/std` **迁入** `lib/std/`（搬迁，不计净增）；`str` / `io` / `math` 等其余模块**留在 `ct-pkg/std` 不动**；ct-pkg 侧同版本删除 `Vec` / `Map`，避免两份实现并存（§2.7） |
| 闭包与 `Callable` | **本相零依赖**：D21-5（非逃逸、栈上环境）与 D21-13（闭包是绑定）原样有效；`Callable` 内建**延后**，不在本相也不在下一相 |
| 量级（估算） | 编译器**新增 900–1550 行**；`Vec`/`Map` **迁入 400–700 行（搬迁，净增 0）**；夹具/门禁 **400–700 行**；文档 **250–450 行**。校准见 §3.3–3.4 |

---

## 1. 立项

### 1.1 编号与边界

| 项 | 值 |
| --- | --- |
| Phase | 29 |
| 目标版本 | `v0.29.0`（Phase 28 收口 `v0.28.0` 后；本相不在 `v0.26.x` / `v0.28.x` 内夹带） |
| 改动边界 | `selfhost/ct-ast/**`、新增 `lib/std/**`（迁入 `Vec`/`Map`）、`test/**`、`examples/**`、`docs/**`、`AGENTS.md`；L0/L1/L2 只允许收口时改 `CTC_VERSION`，外加 AGENTS 已登记的 L2 `MAX_CALLS 512→1024` 例外（不改变任何产物） |
| 冻结层 | `selfhost/l0/ctc.c`、`selfhost/l1/**`、`selfhost/l2/**` 只读（版本串与 AGENTS「例外（Phase 29 自举容量）」登记的 `MAX_CALLS` 除外，见 `AGENTS.md` 第 93 行）；新能力只落 `selfhost/ct-ast/**` 与 `lib/std/**` |
| 判据冻结 | E29-1…E29-13 与 L29-1…L29-18 在首个实现提交前冻结；此后只向判据靠拢 |

### 1.2 一句话目标

让 CT 能写 `struct Pair<T, U>` / `struct Stack<T>` 这样的**用户自定义**泛型结构体，并随编译器内置
`Vec<T>` / `Map<K, V>`；内置容器与用户泛型 struct 走**同一条**单态化路径，不是编译器特例。
`foreach` 能直接遍历这些容器（`Map` 通过 `item.key` / `item.value` 取键值），
所有实例在编译期单态化，产物是普通 C 结构体与普通 C 循环，不引入运行时类型信息。

### 1.3 范围

**做什么**

| # | 内容 |
| --- | --- |
| S1 | 泛型 struct 声明（**对用户开放**）：`struct Name<T>` / `struct Name<T, U>`，最多 2 个类型参数；字段类型可引用类型参数；用户自定义与内置容器无语法差异 |
| S2 | 显式实例化：`Name<int>`、`Map<char *, int>`、`Box<Box<int> >`（嵌套）；**容器不能作容器元素**（L29-11，`Vec<Vec<int>>` 是负例）；嵌套类型实参深度 ≤ 4 |
| S3 | 布局单态化：每个 `(模板, 实参拼写)` 生成一份独立 C 结构体，字段按替换后的类型发射；不写 AST、不改类型表示 |
| S4 | 实例命名：`<Template>_<encoded-args>`，编码规则、溢出摘要与碰撞检查见 §2.2 与 D29-6 |
| S5 | 泛型 impl：`impl<T> Pair<T, int> { … }` 形态的方法按实例化落成 `<MonoStruct>_<Trait>_<method>`；既有 vtable 命名族只做**组合扩展**，不改既有规则 |
| S6 | 内置层：新增 `lib/std/`，`Vec<T>` / `Map<K, V>` 为内置泛型 struct；`Vec` / `Map` / `MapEntry` 为保留名 |
| S7 | 容器 API：`Vec` 的 `len/get/set/push/pop/clear/retain/release`；`Map` 的 `len/put/get/remove/clear/entry/retain/release`；缓冲头引用计数见 §2.4 |
| S8 | `foreach` 容器协议：`Vec` → `len()` + `get(int)`；`Map` → `len()` + `entry(int)`；`item` 为元素/条目值拷贝 |
| S9 | `foreach` 绑定：统一 `item`（元素值 / `MapEntry`）；数组与 `Vec` **同时规定** `item` 与只读 `i`；`Map` 用 `item.key` / `item.value`，体内使用 `i` 硬错（L29-18）；`Map` 按插入序遍历 |
| S10 | `Vec` / `Map` 迁入：从 `ct-pkg/std` 搬入 `lib/std/`，原处同版本删除；`str` / `io` / `math` 等其余模块**不动**；内置路径优先于 `vendor/` |
| S11 | 诊断 L29-1…L29-18（见 §2.6），编译路径与 `ct check` 共用 |
| S12 | 正例/负例夹具、`check-ast.sh` 断言、样例 `examples/22_foreach_map/` 与 `examples/23_generic_stack/`，以及 spec / tutorial / AGENTS 更新 |
| S13 | **无特例保证**：内置 `Vec`/`Map` 与用户自定义泛型 struct 走同一 `StructInst` 表、同一编码器、同一布局发射与 `.h` 导出；错误检查（参数个数、保留名、深度、命名碰撞）对两者是同一段代码（E29-12） |

**不做什么（与「做什么」同样具体）**

| 不做 | 一句话理由 |
| --- | --- |
| 泛型 union / enum | 布局与判别位单态化是另一套规则；本相只做 struct |
| 类型推导、默认类型参数、变参泛型 | 沿用 D26-2 / D26-3；推导需要双向类型检查 |
| 泛型函数的多类型参数 | Phase 28 仍是单参数；只有 struct 放宽到 2 个（`Map` 需要） |
| 泛型 trait、参数化 trait（`trait Seq<T>`） | 要改已发布 vtable 命名与 vptr 布局，Phase 28 §4.2 已论证单相收不了 |
| 泛型体内的泛型调用（函数调函数） | 沿用 D26-9；本相只允许**类型实参**嵌套，不允许实例化递归 |
| 用户自定义可迭代类型 | `foreach` 协议只认内置 `Vec` / `Map`；结构性协议会误伤同名 `len/get`，放行需另立判据 |
| 闭包逃逸、堆闭包、内置 `Callable` | `Callable` 已按用户 2026-11-10 取舍延后（见 [phase21.md](phase21.md#callable-内建的延后记录2026-11-10)）；本相不推翻 D21-5 / D21-13 |
| 容器自动析构（`Drop` 级联释放元素） | 需要泛型 `Drop` 合成与元素级 drop 钩子；先用手动 `release()` 把语义钉住 |
| 容器持有 `own` / `borrow` 值 | 所有权移交与容器共享冲突；本相硬错，等自动析构落地再放开 |
| 容器元素为接口值 / 含 vptr 的 struct | 值拷贝会丢 vptr 或制造悬垂，沿用 Phase 27 L27-4 的同类判断 |
| `Vec<Vec<T>>` 这类**内置容器作元素** | 元素拷贝需要按类型生成 retain/drop 助手；本相先拒绝，登记触发信号 |
| 修改 `MAX_TEXT` / 引入 `type_key` 之外的类型身份 | `MAX_TEXT 160` 先按名长预算约束（L29-6）；扩容是独立迁移 |
| 改 `ct-pkg` 仓库 | 本仓只记录边界与对齐方案；跨仓动作需单独授权（§2.7） |

> **范围量级（估算，非实测）**：Phase 28 + Phase 29 **新增**约 **2,030–3,600 行**
> （编译器 + 夹具 + 文档，**不含迁入代码**）；其中 ct-ast 编译器代码 **1,100–1,920 行**。
> `Vec` / `Map` 从 `ct-pkg/std` **迁入 400–700 行**，属**搬迁、不计入净增**；原处同版本删除，
> 避免两份实现并存。泛型累计（Phase 26 的 +303 + 28 + 29）为 **1,403–2,223 行**，
> 占 ct-ast 现有 22,798 行的 **6.2%–9.8%**（分母不变）。
> 逐单元区间、`MAX_*` / `MAX_TEXT` 影响与校准误差见 **§3.4**。

### 1.4 交付物清单（每项一个路径）

| # | 路径 | 作用 |
| --- | --- | --- |
| D1 | `docs/design/phase29.md` | 本文件 |
| D2 | `selfhost/ct-ast/frontend/parse/Parser.h.ct` | `struct Name<T, U>` 解析、类型实参解析（含 `>>` 拆分）、保留名与深度检查 |
| D3 | `selfhost/ct-ast/frontend/sym/Symbols.h.ct` | `StructDef` 的模板标记与类型参数；`StructInst` 表；编码/去重 |
| D4 | `selfhost/ct-ast/frontend/type/TypeCheck.h.ct` | 实例化后的字段类型替换与 `sizeof` / 字段访问检查 |
| D5 | `selfhost/ct-ast/backend/emit/Emitter.h.ct` | 实例结构体发射、impl 方法发射、`.h` 导出、命名预算诊断 |
| D6 | `selfhost/ct-ast/frontend/parse/Stmt.h.ct` | `foreach` 接受内置容器、`Map` 的 `item.key`/`item.value` |
| D7 | `lib/std/vec.ct` | 内置 `Vec<T>` 与实现 |
| D8 | `lib/std/map.ct` | 内置 `Map<K, V>`、`MapEntry<K, V>` 与实现 |
| D9 | `lib/std/mem.ct` | `Vec` / `Map` 直接依赖的 malloc / realloc / free `.m.ct` 映射；**不搬** `ct-pkg/std` 的公开 `mem` 模块 |
| D10 | `ct-pkg/std` 删除 `Vec` / `Map`（**跨仓，需授权**） | 原处同版本移除，避免两份实现并存；`str` / `io` / `math` 等**不动** |
| D11 | `lib/std/README.md` | 内置层边界、与 `ct-pkg/std` 的版本对齐、保留名清单 |
| D12 | `test/ast/138_generic_struct/`、`139_generic_struct_two/`、`144_generic_struct_user/` | 正例：单/双类型参数、struct 实参、嵌套实参；**144 是用户自定义 `Stack<T>` / `Box<T>`**，与内置容器走同一路径（E29-12） |
| D13 | `test/ast/140_foreach_vec/`、`141_foreach_map/` | 正例：`foreach` 遍历 `Vec` 与 `Map`（`item.key`/`item.value`） |
| D14 | `test/ast/errors/generic_struct_*.ct`（10 条） | 负例：参数过多、禁用实参、深度超限、命名碰撞、保留名、键类型不支持、容器拷贝、`own`/`borrow` 入容器、**内置与用户泛型 struct 的参数个数检查走同一路径（2 条）** |
| D15 | `test/ast/errors/foreach_container_*.ct`（5 条） | 负例：非容器、缺 `get`/`entry`、接口元素、嵌套容器元素、`Map` 体内用 `i` |
| D16 | `test/modules/p29_builtin_std/` | 正例：不 `ct get` 即用 `Vec`/`Map`；`vendor/std` 遮蔽告警；`import std::str` 仍需 `ct get`（负例） |
| D17 | `selfhost/check-ast.sh` | Phase 29 门禁块：红证、正例运行、生成 C 断言、负例文案 |
| D18 | `examples/22_foreach_map/` | 样例：`Vec<int>`、`Vec<Point>`、`Map<char *, int>` 各遍历一遍；`Map` 打印 `item.key=item.value`，输出是插入序；`Vec` 同时演示只读 `i` |
| D19 | `examples/23_generic_stack/` | 样例：**用户自定义** `struct Stack<T> { T items[8]; }` 与 `struct Pair<T, U>`，显式实例化 `Stack<int>` / `Stack<char *>`，证明泛型 struct 不是只对 `Vec`/`Map` 生效（E29-12） |
| D20 | `docs/language-spec.md`、`docs/tutorial.md`、`AGENTS.md` | 规范 §4.51、教程 §10.8、当前阶段与内置层边界 |
| D21 | `docs/roadmap.md`、`docs/README.md`、`examples/README.md` | 索引与状态（本文件登记时同步；样例 22–25 落地时登记） |
| D22 | `examples/24_vec_ops/` | 覆盖矩阵 B2：`Vec` 增删查改 + `retain`/`release` + `foreach`（`item` 与只读 `i`） |
| D23 | `examples/25_wordcount/` | 覆盖矩阵 B4：`Map<char *, int>` 词频统计 + 排序输出的近真实程序 |
| D24 | `test/ast/147_generic_impl/` | 覆盖矩阵 B5：`impl<T> …` 按实例落码、跨实例命名 |
| D25 | `test/modules/p29_generic_struct/`、`test/modules/errors/generic_struct_pub_fn.ct` | 覆盖矩阵 B6：`pub` 泛型 struct 跨单元共享布局；泛型函数 `pub` 负例（L26-2） |

### 1.5 退出判据草案（冻结于首个实现提交前）

> **`Map` 遍历是硬判据**：E29-3 不通过即视为本相未收口，不得以「设计已覆盖」替代真实样例。

| # | 判据 | 命令 / 锚点 |
| --- | --- | --- |
| E29-1 | 泛型 struct 正例 138/139/144 构建、运行、输出逐字节匹配；生成 C 中两个实例是**不同的结构体标签**，字段类型已替换，整份产物无残留类型参数；**144 用用户自定义 `Stack<T>` 走完全相同的发射路径** | `bash selfhost/check-ast.sh` 的 Phase 29 块：`cmp -s` + `grep -c 'struct Pair_int'` + `tparam_residue()` |
| E29-2 | 跨单元：`.h` 携带单态化结构体定义；两个单元各自用 `Pair<int>` 时布局逐字段一致；不出现同名不同布局 | `test/modules/p29_generic_struct/` 构建 + 生成 `.h` 断言 + 布局比对脚本 |
| E29-3 | **`foreach` 能遍历内置 `Map`**：夹具 141 与样例 22 编译、运行、输出逐字节匹配；`item.key` / `item.value` 各自取到正确类型；`Vec` 的 `item` 遍历同时覆盖；**`Map` 输出顺序为插入序**，重复运行与两次编译产物一致 | `bash selfhost/check-ast.sh` 的 Phase 29 块 + `./test/run.sh` 跑 `examples/22_foreach_map` + 两次构建 `cmp` |
| E29-4 | `foreach` 容器语义：`item` 是值拷贝（块内改写不回写，与 Phase 27 数组一致）；数组 / `Vec` **同时**有 `item` 与只读 `i`，`i` 不可重声明（L29-16/17）；`Map` 体内使用 `i` 报 L29-18；长度在循环前快照一次（沿用 D27-7）；`break` / `continue` / `return` 与数组形态一致；非容器与缺方法的负例各只报一条 L29 | 夹具 140/141 + `foreach_container_*` 负例表 |
| E29-5 | 内置层只覆盖容器：不执行 `ct get std` 时 `Vec` / `Map` 可直接使用（无需 import）；**`std::str` / `std::io` / `std::math` 仍需 `ct get std`**（本相不迁）；`vendor/std` 存在时给一条遮蔽告警且仍用内置 `Vec`/`Map` | `test/modules/p29_builtin_std/` + 告警文案断言；另断言 `import std::str;` 在无 vendor 时仍失败 |
| E29-6 | 容器 API 正例：`push` / `get` / `set` / `pop` / `clear` / `retain` / `release` 与 `put` / `get` / `remove` / `entry` 的返回值和边界行为符合 §2.4；`retain` 后两个句柄都能读，`release` 到 0 后不重复释放 | `test/ast/142_vec_api/`、`143_map_api/` 运行输出 + ASAN 门禁 |
| E29-7 | 十条泛型 struct 负例（含 2 条「内置 / 用户泛型 struct 无特例」）与五条 `foreach` 负例各自只产生一条 L29 错误，文案与 `file:line:col` 精确匹配（`p29_neg` 校验文案 + 位置 + 单条）；基线 `1c87fab` 对同一夹具给出不同结果（红证非空转，§3.1） | `check-ast.sh` 的 `p29_neg` 表 + §3.1 基线原始输出与 SHA |
| E29-8 | 非泛型 golden 逐字节不变；既有 `check-ast` 断言零回归；`check-warnings` 零新增告警 | `check-goldens.sh` / `check-ast.sh` 汇总 `0 failed` |
| E29-9 | 11 道硬门禁全绿；`ct check` 与 `ct build` 对负例同文案 | `bash selfhost/check-all.sh` 末行 |
| E29-10 | 文档：spec / tutorial / AGENTS 已更新；样例 22–25 已进 `examples/README.md` 与 `test/run.sh`；文档门禁绿 | `python3 test/docs/check-docs.py` + `./test/run.sh` |
| E29-11 | 跨仓边界：本仓不修改 `ct-pkg`；`lib/std/README.md` 写明**只迁 `Vec`/`Map`、其余模块不动**、旧包同版本删除、版本对齐规则 | 文件存在 + 文案断言（不联网） |
| E29-12 | **无特例**：内置 `Vec`/`Map` 与用户自定义泛型 struct 共用同一 `StructInst` 表、同一编码器与同一 `.h` 导出；负例 `generic_builtin_arity.ct`（`Vec<int, int>`）与 `generic_struct_user_arity.ct`（`Stack<int, int, int>`）命中**同一** L29-2 文案与同一诊断函数；`Stack<int>` 的实例名遵循同一编码规则（`Stack_int`），`.h` 携带同一形态的单态化定义 | `check-ast.sh` 的 E29-12 块：两条负例文案逐字相同 + `grep` 生成名 + `.h` 定义比对 |
| E29-13 | **样例覆盖矩阵每行都有可运行样例**：B1–B9 逐行有 `expected.out`、`//@ct-requires: ct-ast`，进 `test/run.sh` 或 `check-ast.sh` 语料；每行有对应负例或产物断言；B9 的「本相不做」必须写明理由，不能留空；不允许用 `/tmp` 探针替代 | §1.5.1 矩阵逐行核对 + `test/run.sh` / `check-ast.sh` 汇总 |

> 版本判据（五处 `CTC_VERSION` + 全量 golden 重生）在收口切片单独执行；规划期不预支。

### 1.5.1 样例覆盖矩阵（**硬性退出判据**，不是建议）

> 用户 2026-11-10 明确要求：泛型复杂，样例必须多角度覆盖，不能只给一两个。
> 每行都要有**可运行样例**（`expected.out` + `//@ct-requires: ct-ast`，进 `test/run.sh` 或
> `check-ast.sh` 语料），并且有对应的**负例或产物断言**证明行为正确；`/tmp` 探针不算覆盖。
> 空角度也必须写明「27 已覆盖」或「本相不做，理由 X」，不许留空。

| 角度 | 样例 | 演示点 | 门禁归属 | 反向证明（负例 / 断言） |
| --- | --- | --- | --- | --- |
| B1 **用户自定义泛型 struct**（容器） | `examples/23_generic_stack/` + `test/ast/144_generic_struct_user/` | `struct Stack<T> { T items[8]; T *slot; T *heap; }`，三种字段形态 `T` / `T*` / `T[]` 都出现；实例化 `Stack<int>` 与 `Stack<char *>` | `test/run.sh` + `check-ast.sh` | 负例 `generic_struct_user_arity.ct`：3 个参数报 L29-2，与 `Vec<int, int>` 的文案逐字相同（E29-12） |
| B2 **内置 `Vec`：增删查改 + `foreach`** | `examples/24_vec_ops/` + `test/ast/142_vec_api/`、`140_foreach_vec/` | `push/get/set/pop/clear/retain/release` 全走一遍；`foreach (v)` 同时用 `item` 与只读 `i` | `test/run.sh` + `check-ast.sh` + ASAN | 负例：写 `i`（L29-16）、重声明 `item`/`i`（L29-17）；越界 `get` 返回零值断言 |
| B3 **内置 `Map`：`foreach` 键值 + 顺序** | `examples/22_foreach_map/` + `test/ast/141_foreach_map/` | `item.key` / `item.value`；插入序输出；`remove` 后左移补位顺序不变；`put` 已有键原位改值 | `test/run.sh` + 两次构建 `cmp` | 负例 `foreach_container_map_i.ct`：`Map` 体内用 `i` 报 L29-18；重复运行与两次编译产物逐字节一致 |
| B4 **接近真实程序**：`Map` 词频统计 | `examples/25_wordcount/`（新） | 读固定词表 → `Map<char *, int>` 计数 → `foreach` 输出 → 按计数排序后输出；`char *` 键 + 整数值的真实组合 | `test/run.sh` + ASAN | `expected.out` 逐字节比对；同一输入两次运行一致；无泄漏 |
| B5 **泛型 impl** | `test/ast/147_generic_impl/`（新） | `impl<T> Pair<T, int> { … }`、`impl<T> Stack<T> use Show`；方法按实例落成 `<MonoStruct>_<Trait>_<method>` | `check-ast.sh` | `grep` 两份实例方法名；负例 `test/ast/errors/generic_impl_missing_method.ct`：方法名不匹配报既有硬错 `no method 'nope' for type 'struct Pair_int_int'`；arity 不匹配沿用既有**警告**（`arity mismatch: 'second' takes 1 argument(s), 0 given`），不是硬错 |
| B6 **泛型 + 模块边界** | `test/modules/p29_generic_struct/` + `test/modules/errors/generic_struct_pub_fn.ct`（新） | `pub` 泛型 struct 跨单元共享布局；泛型**函数** `pub` 仍被拒（L26-2） | `check-ast.sh` 的跨单元块 | `.h` 携带单态化定义断言；L26-2 文案逐字匹配；两单元布局逐字段比对 |
| B7 **双参数 / 嵌套实参** | `test/ast/138_generic_struct/`、`139_generic_struct_two/` | `Pair<int, char *>`；`Box<Box<int> >`（`>>` 拆分，非容器）；深度 4 上限；**`Vec<Vec<int> >` 不在此列**，它是 L29-11 的负例（`container_element.ct`） | `check-ast.sh` | 负例：深度 5 报 L29-4；3 参数报 L29-2；禁用实参报 L29-3；容器作元素报 L29-11 |
| B8 **所有权 / 容器语义负例** | `test/ast/errors/container_own.ct`、`container_copy.ct` | `own` / `borrow` 值入容器（L29-10）；容器按值拷贝（L29-9）；容器元素为容器（L29-11） | `check-ast.sh` + `142/143` 的 ASAN | 三类负例各自只报一条 L29；`retain` / `release` 到 0 不重复释放（ASAN） |
| B9 泛型 + 闭包回调 / 泛型体内实例化容器 | 本相**不做** | 闭包非逃逸且容器不可持有闭包；泛型函数体内实例化 `Vec<T>` 属 D26-9 禁止的「泛型体内泛型调用/实例化」 | — | 闭包角度由 [phase28.md](phase28.md) §1.5.1 的 A3 覆盖；泛型体内实例化登记为 §8 O9 的触发信号 |

### 1.6 依赖

| 依赖 | 说明 |
| --- | --- |
| Phase 28 约束泛型 | 复用 `<T: Trait>` 的解析、模板体方法解析与实例满足性检查；29 把同一套「模板 + 实参」机制从函数扩到类型 |
| Phase 26 泛型函数 | 复用 `GenericInst` 的「按拼写去重」与发射期类型替换上下文（D26-7）；29 新增 struct 实例表，不复制函数实例逻辑 |
| Phase 27 `foreach` | 复用语句展开、`item` 绑定、长度快照与 L27 诊断；29 只加「集合是内置容器」分支 |
| trait / impl / vtable | 泛型 impl 的方法落码复用既有命名族；vtable 只在实例需要时发射 |
| `map` / `.m.ct` | `lib/std/mem.ct` 用既有映射机制调用 libc；不新增映射语法 |
| 容量 | 新增 `StructInst` 表建议 `MAX_STRUCT_INSTS 128`；`MAX_STRUCTS 128` 不动（实例是否占用 struct 表见 D29-4） |

### 1.7 已知风险（每条带触发信号）

| # | 风险 | 触发信号 | 缓解 |
| --- | --- | --- | --- |
| R1 | 实例名编码碰撞：`char *` 与 `char*`、`struct P` 与 `P` 归一后同名 | 编译期编码表报告「同一编码对应两个规范拼写」 | 规范拼写由 `parse_type` 产出；编码表做双向校验，冲突即 L29-5，不静默合并 |
| R2 | `MAX_TEXT 160` 装不下「模板名 + 实参 + trait + 方法」 | 组合名长度 ≥ 160 | 实例名编码上限 64，超出截断 + 8 位摘要；组合名在发射前预检，超限 L29-6 |
| R3 | 跨单元布局漂移（同一实例在两个单元字段不同） | `.h` 两份定义的字段序列不一致 | 由同一模板 + 同一实参在同一 `Symbols`/`Arena` 上生成；E29-2 做逐字段比对 |
| R4 | `>>` 词法把嵌套实参的收尾吞成右移 | `Box<Box<int>>` 解析失败 | 类型实参上下文允许拆 `>>`；词法器不改，解析器在类型位分流（D29-2） |
| R5 | 泛型 impl 方法名与结构体自有字段/方法重名 | 方法解析选错 | 实例方法按「结构体自有 > trait 方法」既有优先级；新增夹具覆盖 |
| R6 | 容器在 `foreach` 中被修改导致越界 | 循环体 `push` / `remove` 后读到零值 | 长度快照 + `get` / `entry` 边界返回零值，不越界；文档写明「迭代中修改不扩展循环」 |
| R7 | 引用计数漏释放 | ASAN 报 leak 或释放后使用 | `retain`/`release` 逐次断言；`own` 值禁止入容器；样例在 ASAN 门禁下运行 |
| R8 | `vendor/std` 与内置层同名模块产生重复定义 | 链接期重复符号 | 内置优先 + 遮蔽告警 L29-W1；不把两者同时编入 |
| R9 | `Map` 键为 `char *` 时悬垂键 | 键指向的字符串先释放 | 文档写明键不拷贝、生命周期由调用方保证；与 `std::map` 既有口径一致 |
| R10 | 哈希质量导致 `Map` 退化 | 大量键冲突时查找变慢 | 白名单键用固定哈希（int/long 混合、`char *` FNV-1a）；本相不做 DoS 防护，文档标注 |

### 1.8 design window 与归档（本轮必须执行）

`check-docs.py` 的规则是 `floor = 最新编号 - 12 + 1`（[check-docs.py:264-296](../../test/docs/check-docs.py#L264-L296)）。
本轮只新增**一份**编号文档 `phase29.md`：

- `max = 29`，`floor = 29 - 12 + 1 = 18`；
- `phase17.md` 低于 floor，**必须** `git mv docs/design/phase17.md docs/history/design/`；
- `phase18.md` 不低于 floor，**保留在 `docs/design/`**；
- 同步更新 roadmap 的 Phase 17 行链接、`docs/README.md` 的索引说明、`docs/history/README.md`
  的中英表，以及仓库内指向 `design/phase17.md` 的相对链接。

> 判定以实际运行 `python3 test/docs/check-docs.py` 为准；若脚本口径变化，以脚本输出为准并在此记录。

---

## 2. 语义

### 2.1 语法

```c
/* 声明：最多两个类型参数 */
struct Pair<T, U> {
    T first;
    U second;
}

struct Vec<T> {
    struct __ct_buf *h;   /* 内置头：refs / len / cap，见 §2.4 */
    T *data;
}

/* 实例化：类型实参写在类型位置 */
struct Pair<int, char *> p;
Vec<int> nums;
Map<char *, int> ages;

/* 泛型 impl：方法体按实例单态化 */
impl<T> Pair<T, int> {
    int secondIs(int v) { return self->second == v; }
}
```

- 类型参数只允许出现在**类型位置**：字段类型、指针基类型、`sizeof` / `_Alignof` / cast 的类型操作数；
  出现在值位置一律硬错（沿用 Phase 26 的 `tparam` 值位置守卫，D26-15）。
- 类型实参的合法形态：内置标量、`struct` / `union` / `enum` 类型、指针、其他泛型 struct 实例。
  **禁止**：`void`、数组类型、函数指针类型、带 `const` / `volatile` 限定的类型（L29-3）。
- 嵌套实参深度 ≤ 4（`Box<Box<Box<Box<int> > > >` 是上限；容器不能作容器元素，见 L29-11）；`>>` 在类型实参上下文由解析器拆分。
- `Vec` / `Map` / `MapEntry` 是保留名；用户声明同名类型即 L29-7。内置层没有 `std::vec::Vec` 这类
  模块路径别名：它是预解析的一个单元，不在 `std` 包里（V29 评审后修正）。

### 2.2 实例化、布局与命名

**实例身份**：`(模板名, 类型实参的规范拼写列表)`。规范拼写由 `parse_type` 产出（类型别名先展开），
只做三件事：去首尾空白、折叠连续空白、把 `*` 贴到前一个 token。`Pair<int, char *>` 与
`Pair<int,char*>` 因此是同一实例；`struct P` 与 `P`（别名展开后同为 `struct P`）也是同一实例。

**布局单态化**：每个实例在发射期用 D26-7 的「类型替换上下文」生成一份 C 结构体，
字段类型按实参替换；**不复制 AST**。实例表 `StructInst { template, nargs, args[2][160], cname[160] }`
占用独立容量（`MAX_STRUCT_INSTS 128`），不挤占 `MAX_STRUCTS 128`。
模板本身不落 C 符号；只有被使用的实例才发射。

**实例名编码**（D29-6，用户授权例外）：

| 步骤 | 规则 | 例 |
| --- | --- | --- |
| 1 | 取规范拼写 | `char *` / `struct Point` / `Vec<int>` |
| 2 | 去掉 `struct ` 前缀；`union` → `u_`、`enum` → `e_` 前缀 | `Point` / `u_U` / `e_E` |
| 3 | `*` → `_p`，空格 → `_`，`_` → `__`，`<` → `_l`，`>` → `_r`，`,` → `_c` | `char_p` / `Vec_l_int_r` |
| 4 | 组合：`<Template>_<arg1>[_<arg2>]` | `Vec_int`、`Map_char_p_int`、`Pair_int_char_p` |
| 5 | 编码超过 64 字符：保留前 40 + `_h` + FNV-1a 32 位 8 位十六进制 | `Map_..._h9f3a2b1c` |
| 6 | 发射前做双向校验：编码 → 规范拼写必须一对一 | 冲突 → L29-5 |

**对已发布命名族的改动面**：

- 既有四条规则 `<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>`、
  `<Struct>_<Trait>_<vtable>` **文本不变**；改变的是 `<Struct>` 槽现在可以是单态化名
  （`Pair_int_char_p_Show_show`、`Pair_int_char_p_Show_vtable`）。
- 既有 golden **零变化**：今天的程序没有泛型 struct 实例，不会生成新名字；新名字只出现在新夹具。
- 用户可见诊断永远显示 `Pair<int, char *>`，不显示 `Pair_int_char_p`；编码只进 C 标识符。
- 组合名超过 159 字符时 L29-6，提示缩短模板名或实参类型；本相不扩 `MAX_TEXT`。

### 2.3 内置层与 `Vec` / `Map` 的形态

**内置层**：`lib/std/` 是本仓的新顶层目录，但**只放**内置 `Vec` / `Map`（含 `MapEntry`）及其直接依赖（`mem.ct`）；`std` 的其余模块不在本仓。加载顺序固定为
**内置层 → 用户 import → `vendor/`**；内置层里的 `Vec` / `Map` / `MapEntry` 无需 import 即可见。
`lib/std/` 内的模块仍是普通 CT 源码，遵循 `.h.ct` 只放类型、`.m.ct` 只放映射的既有规则。

| 类型 | 布局（实现现状） | 说明 |
| --- | --- | --- |
| `Vec<T>` | `{ struct ct_buf *h; T *data; }`，`ct_buf = { int refs; int len; int cap; }` | 动态数组；容量 2 倍增长；`data` 由 libc `malloc` / `realloc` 直接管理 |
| `Map<K, V>` | `{ struct ct_buf *h; struct MapEntry<K, V> *entries; }` | 紧凑 entries，**线性扫描**；`len` 是 entries 的有效条数 |
| `MapEntry<K, V>` | `{ K key; V value; }` | `foreach` 的 `item` 类型；也是 `entry(int)` 的返回类型 |

> **实现偏差（V29-1 后按事实记录）**：本节初稿写的是 `__ct_buf`、`Map` 带 `int *index` 的开放寻址
> 索引、白名单键用内置哈希（整数混合 / FNV-1a）。落地的是 `ct_buf`（无下划线前缀）、**无索引**的
> 线性扫描、以及按类型分的两个 `impl` 块：`int` / `long` 比字节，`char *` 比 `strcmp`。没有哈希，
> 因为没有 `Hash` / `Eq` 约束可用（D29-9 的原始理由）；`get` / `put` / `remove` 是 O(n)，`len` 仍是
> O(1)。§10.2 只保留与实现相关的剩余偏差，本节不再重复承诺未落地的形态。

**`Map` 的键白名单**（D29-9，已由 L29-8 强制）：`int`、`long`、`char *`。理由：Phase 28 的约束方法
签名不允许出现类型参数，写不出 `trait Hash { int hash(K); }`；为 `Map` 单独引入参数化 trait 会把
Phase 29 拖进 Phase 28 §4.2 的 750–1350 行路线。白名单在 `parse_inst_type` 里对 `Map` 的第一个类型
实参检查，白名单外的键给出 `Map does not support key type '<type>' (use int, long or char *)`，
**不发射任何 C**。键的比较按类型分派：`int` / `long` 用 `memcmp` 比字节，`char *` 用 `strcmp`。

**容器语义**（D29-10）：

- 容器是**移动语义**的：`Vec<int> b = a;`、`b = a;`、把 `a` 作为实参或返回另一个容器，全部 L29-9。
- 允许的两类「移交」：从函数调用初始化/赋值（`Vec<int> v = vec_new<int>();`）、以及显式
  `a.retain()` 得到共享句柄。`release()` 递减 `refs`，到 0 释放 `data` 与 `h`；**无论是否归零，
  该句柄都被清空**，所以同一句柄第二次 `release` 是 `abort`（V29-2），不会把兄弟句柄还持有的缓冲
  再减一次。
- 容器不自动 `release`；`own` / `borrow` 值不得 `push` / `put`（L29-10），避免所有权与引用计数冲突。
- `get` / `entry` 越界返回零值（元素/条目清零），不越界访问；迭代中修改不会扩展循环（长度快照）。

### 2.4 容器 API（本相冻结的签名）

| 类型 | 方法 | 语义 |
| --- | --- | --- |
| `Vec<T>` | `int len()` | 当前元素数 |
| | `T get(int i)` | 越界返回零值；返回**值拷贝** |
| | `void set(int i, T v)` | 越界 no-op；`v` 不能是容器或 `own` |
| | `int push(T v)` | 成功 1、失败 0（分配失败）；不能是容器或 `own` |
| | `T pop()` | 空返回零值 |
| | `void clear()` | `len = 0`，不释放缓冲 |
| | `Vec<T> retain()` | `refs++`，返回同一缓冲的新句柄 |
| | `int release()` | `refs--`；到 0 释放；返回剩余 `refs` |
| `Map<K, V>` | `int len()` | 有效条目数 |
| | `int put(K k, V v)` | 覆盖或插入；`char *` 键不得为 NULL；满且无法扩容返回 0 |
| | `V *get(K k)` | 未命中返回 NULL；命中返回内部指针（生命周期到下一次修改） |
| | `int remove(K k)` | 命中删除并返回 1；删除后**左移补位**，保持插入序 |
| | `void clear()` | 清空索引与条目，不释放缓冲 |
| | `MapEntry<K, V> entry(int i)` | `0 <= i < len()` 返回第 `i` 个条目（插入序）的值拷贝；越界返回零值 |
| | `Map<K, V> retain()` / `int release()` | 同 `Vec` |

### 2.5 `foreach` 容器协议（D27-4 解冻）

**协议**：`Vec` 用 `len()` + `get(int)`；`Map` 用 `len()` + `entry(int)`。
`foreach` 只对**内置 `Vec` / `Map` 的实例**启用该分支；其他类型仍走 Phase 27 的数组检查与 L27 诊断。

**绑定判据（用户 2026-11-10 已裁定）**：统一 `item` = 当前元素；数组 / `Vec` 的 `item` 是元素值，
`Map` 的 `item` 是 `MapEntry<K, V>`（键值用 `item.key` / `item.value`）。
数组 / `Vec` **必须同时提供** `item` 与只读 `i`，两者都是规定绑定，不是可选糖；
`Map` 没有自然下标，循环体内出现 `i` 是**硬错**（L29-18），不提供隐含序号。
`items[i]` 不是规定语法，保留裸 `for` 作为需要下标写回的逃生门。

`Vec` 的展开：

```c
{
    Vec_int *__ct_foreach_c_0 = &v;
    int __ct_foreach_n_0 = (*__ct_foreach_c_0).len();
    for (int __ct_foreach_i_0 = 0; __ct_foreach_i_0 < __ct_foreach_n_0; __ct_foreach_i_0++) {
        int i = __ct_foreach_i_0;            /* 规定绑定：只读下标 */
        int item = (*__ct_foreach_c_0).get(__ct_foreach_i_0);
        /* body */
    }
}
```

`Map` 的展开（无 `i`；体内引用 `i` 在解析期报 L29-18）：

```c
{
    Map_char_p_int *__ct_foreach_c_0 = &m;
    int __ct_foreach_n_0 = (*__ct_foreach_c_0).len();
    for (int __ct_foreach_i_0 = 0; __ct_foreach_i_0 < __ct_foreach_n_0; __ct_foreach_i_0++) {
        MapEntry_char_p_int item = (*__ct_foreach_c_0).entry(__ct_foreach_i_0);
        /* item.key / item.value */
    }
}
```

- **`item` 是值拷贝**：块内 `item = …` / `item.field = …` 只改副本，不回写容器——与 Phase 27 数组
  的 `item` 行为一致。需要写回时：数组用 `arr[i] = …`，`Vec` 用 `v.set(i, …)`，`Map` 用 `m.put(…)`。
- **数组 / `Vec` 的 `i` 是规定绑定且只读**：`i = …` / `i++` / 取地址一律硬错（L29-16）；作用域只在
  循环体；循环体再声明同名 `i` 或 `item` 硬错（L29-17）。
- **`Map` 的 `i` 是硬错**：即使外层有同名变量，`foreach (m)` 体内写 `i` 也报 L29-18，
  避免把「条目序号」误读成顺序保证；需要位置时用 `item.key` 或自行计数。
- 集合表达式仍必须是**普通变量**（D27-3 / L27-4 的既有约束），这样取地址与长度快照都成立。
- `K` / `V` 不能是接口值、含 vptr 的 struct、内置容器（L29-15）；这些值在 `foreach` 的 `item` 值拷贝里
  会丢 vptr 或制造二次所有权。V29-5 之后这三类在**容器声明点**就由 L29-13 / L29-11 硬错，
  `foreach` 侧只保留对内置 `MapEntry` 元素的兜底（夹具 `foreach_container_element.ct`）。
- **`Map` 遍历顺序钉死为插入序**：`put` 新键追加到 entries 末尾；`put` 已有键原位改值；
  `remove` 左移补位保持相对顺序；扩容/重哈希只动索引，不动 entries。因此样例输出与 golden 稳定。
- 长度快照沿用 D27-7：循环体内 `push` / `put` 不扩展本轮；`remove` 造成的缩短由 `get` / `entry`
  的越界零值兜底，不越界访问。

### 2.5.1 为什么 `items[i]` 不作为规定语法

用户的原始设想是「`Vec` 内置 `i`，用 `items[i]` 访问值」。它的问题不是可读性，而是三条硬约束：

1. **依赖调用点的标识符拼写**：`foreach (v)` 里没有 `items`；`foreach (t.names)` 里连一个简单名字
   都没有。要让它成立，编译器必须假设集合变量恰好叫 `items`，或把集合表达式重复求值。
2. **`Vec` 没有 `[]`**：CT 的索引只对数组/指针成立。要支持 `v[i]` 就得给容器加运算符重载，
   这是比 `foreach` 大得多的语言改动，且会隐藏一次方法调用，违背「零隐藏调用」的落码口径。
3. **同一元素两条读法**：`item` 与 `v[i]` 并存会让诊断、优化与「块内修改是否写回」的规则分叉。

保留用户设想的**可用部分**：数组 / `Vec` 的只读隐式 `i` 解决「需要下标」的场景，`item` 仍是唯一元素读法。
如果用户想要的就是裸循环，直接写 `for` 即可；`foreach` 的职责是绑定元素，不是替代 `for`。

### 2.6 诊断（草案，实现前冻结）

| 码 | 触发 | 文案（草案） |
| --- | --- | --- |
| L29-1 | 类型实参语法错误 / 未知类型 | `unknown type argument '<text>'` |
| L29-2 | 类型参数超过 2 个 | `a generic struct takes at most 2 type parameters` |
| L29-3 | 禁用实参（`void` / 数组 / 函数指针 / 限定类型） | `type argument '<type>' cannot instantiate a generic struct` |
| L29-4 | 嵌套深度 > 4 | `generic type arguments nest deeper than 4` |
| L29-5 | 实例名编码碰撞 | `two type arguments encode to the same C name '<name>'` |
| L29-6 | 组合名超过 `MAX_TEXT - 1` | `the instantiated name exceeds 159 characters; shorten the template or its arguments` |
| L29-7 | 用户重定义保留名 | `'<name>' is a built-in type and cannot be redeclared` |
| L29-8 | `Map` 键不在白名单 | `Map does not support key type '<type>' (use int, long or char *)` |
| L29-9 | 容器按值拷贝 | `a container is moved, not copied; use retain() or a function result` |
| L29-10 | 向容器存入 `own` / `borrow` 值 | `a container cannot hold an 'own' or 'borrow' value` |
| L29-11 | 内置容器作元素 / 条目 | `a built-in container cannot be an element of another container` |
| L29-12 | `foreach` 的集合不是数组也不是内置容器 | 沿用 L27-4，文案追加 「or a Vec/Map」 |
| L29-13 | 容器元素是接口值 / 含 vptr 的 struct | `interface and vptr-bearing values cannot be stored in a container` |
| L29-14 | `.h` 中实例定义缺失或布局不一致 | `the monomorphised '<name>' has no consistent definition across units` |
| L29-15 | `foreach` 元素/条目类型不可值拷贝 | `foreach cannot iterate a container of '<type>' (interface, vptr-bearing or container element)` |
| L29-16 | 写只读索引 `i` | `the foreach index 'i' is read-only` |
| L29-17 | 循环体重声明 `item` / `i` | `cannot redeclare the foreach binding '<name>'` |
| L29-18 | `Map` 的 `foreach` 体内使用 `i` | `'i' has no meaning in a Map foreach; use item.key / item.value` |
| L29-W1 | `vendor/std` 遮蔽内置模块 | `the built-in std shadows 'vendor/std'; remove the package`（warning，不占错误名额） |

### 2.7 `std` 迁移与跨仓边界

| 项 | 结论 |
| --- | --- |
| 本仓角色 | `lib/std/` **只承载内置 `Vec` / `Map`（含 `MapEntry`）及其直接依赖**，不是整个 `std` 的新家；`Vec` / `Map` 随编译器 `v0.29.0` 发行、无需 import |
| `ct-pkg/std` 角色 | **只移除 `Vec` / `Map` 两个模块**；`str` / `io` / `math` 等其余模块原样保留、继续维护。移除后发一个包版本（major/minor 待跨仓授权） |
| 索引 | `ct-pkg/index` 的 `std` 条目**保留为在用**，只更新到「已移除 `Vec`/`Map`」的版本；**不标 superseded**（std 其余模块仍由它供） |
| 版本对齐 | 内置 `Vec` / `Map` 的 API 版本 = 编译器版本（`v0.29.0`）；`ct-pkg/std` 其余模块继续走自己的包版本。`lib/std/README.md` 记录「编译器版本 → 内置容器 API」 |
| 重复导入 | 内置层优先；`vendor/std` 存在时 L29-W1 告警并忽略其同名模块；不把两者同时编入 |
| 跨仓动作 | **本轮不做**。需要 ct-pkg 仓授权后才能删除 `Vec`/`Map` 并发布新版本；本仓只记录对齐方案与验收口径，待删清单写在 [lib/std/README.md](../../lib/std/README.md) |
| 迁入原则 | **只搬 `Vec` / `Map`（最小直接依赖随迁），不搬 `str` / `io` / `math`**；原处删除与版本发布在同一跨仓动作里完成，禁止两份实现并存 |

### 2.8 与闭包 / `Callable` 的边界

- 本相不引入逃逸闭包，也不引入内置 `Callable`；D21-5（非逃逸、栈上环境）与 D21-13（闭包是绑定）
  **原样有效**，不产生取代记录。
- `Vec<Callable<...>>` 这类形态在本相**无法表达**（`Callable` 不存在）；容器元素也禁止内置容器，
  所以不会出现「容器持有闭包环境」的悬垂面。
- 若未来重启 `Callable` 内建，前置条件是先接受逃逸/堆闭包；届时再评估容器元素与自动析构的联动，
  见 [phase21.md 的延后记录](phase21.md#callable-内建的延后记录2026-11-10)。

### 2.9 Phase 29 收口后的能力边界（写死，不留「待定」）

**能写**

| # | 能力 | 形态 | 依据 |
| --- | --- | --- | --- |
| C1 | **用户自定义泛型 struct** | `struct Stack<T> { T items[8]; }`、`struct Pair<T, U> { … }`；显式实例化 `Stack<int>`、`Pair<int, char *>` | S1 / D29-1；正例 144、样例 23 |
| C2 | 内置 `Vec<T>` / `Map<K, V>` | 随编译器发行，无需 `ct get`；与 C1 同路径 | S6 / D29-8；E29-5、E29-12 |
| C3 | 泛型 impl（非参数化 trait） | `impl<T> Pair<T, int> { … }`，方法按实例落成 `<MonoStruct>_<Trait>_<method>` | S5 / D29-6 |
| C4 | `pub` 泛型 struct / 跨单元实例共享 | `.h` 携带单态化结构体定义，消费单元可直接声明变量 | D29-5；E29-2 |
| C5 | 类型实参嵌套 | `Box<Box<int> >`，深度 ≤ 4；`>>` 由解析器拆分；容器作元素是 L29-11 的负例（`Vec<Vec<int> >`） | S2 / D29-2、D29-7 |
| C6 | 约束泛型函数（**Phase 28 已交付**） | `T max2<T: Ord>(T a, T b)`；单类型参数、单约束、显式实例化、静态派发 | [phase28.md](phase28.md) §1.3；本相不扩展约束语法 |
| C7 | `foreach` 遍历数组 / `Vec` / `Map` | 统一 `item`；数组与 `Vec` 另有只读 `i`；`Map` 用 `item.key` / `item.value` | S8/S9 / D29-13、D29-14；E29-3、E29-4 |

> **C6 的边界要说清**：`<T: Trait>` 只对**函数**成立。Phase 29 **不**允许 `struct Stack<T: Ord>`，也
> **不**允许 `impl<T: Ord> …`；泛型 impl 的方法解析可以复用 Phase 28 的「模板体 + 约束调用」代码，
> 但语法上没有新增 struct/impl 约束位。这条是刻意的：给 struct 加约束需要先决定「约束在实例化点
> 还是声明点检查」，与布局单态化耦合，单相不做。

**仍不能写**

| # | 不能写 | 原因 / 去向 |
| --- | --- | --- |
| N1 | 泛型 union / enum | 布局与判别位单态化是另一套规则；本相只做 struct |
| N2 | 泛型 trait / 参数化 trait（`trait Seq<T>`） | 要改已发布 vtable 命名与 vptr 布局；见 phase28 §4.2，单相收不了 |
| N3 | 带类型实参的 `impl Trait<X> for S` | 同 N2；泛型 impl 指「impl 里出现类型参数」，不是「trait 带实参」 |
| N4 | 多约束 `T: A + B`、约束继承、`Self`、trait 方法签名含 `T` | 沿用 phase28 §1.3 的拒绝口径 |
| N5 | 类型推导、默认类型参数、变参泛型 | 沿用 D26-2 / D26-3 |
| N6 | 泛型函数的多类型参数 | Phase 28 仍单参数；只有 struct 放宽到 2 个 |
| N7 | 泛型函数 `pub` / 跨单元导出实例 | 沿用 L26-2；函数实例只落模板定义单元（与 C4 的 struct 规则不同） |
| N8 | 递归 / 互相递归的泛型实例化 | 类型实参可嵌套（C5），但泛型体内不得调用泛型函数；无实例化环 |
| N9 | 用户自定义可迭代类型进 `foreach` | 只认内置 `Vec`/`Map`；开放需另立判据（O1） |
| N10 | 容器自动析构、容器持有 `own`/`borrow`、容器元素为容器 | 本相用移动语义 + 显式 `retain()`/`release()`；见 D29-10、D29-11、L29-10、L29-11 |
| N11 | 闭包逃逸 / 堆闭包 / 内置 `Callable` | 用户 2026-11-10 取舍**延后**；D21-5 / D21-7 / D21-13 原样有效 |

**一句话回答「29 之后 struct 能不能进泛型」**：能，而且是**普通用户可写**的泛型 struct，不是只给
`Vec`/`Map` 开的内部通道；但泛型 **trait**、泛型 **union/enum**、struct 上的**约束位**仍不在。

---

## 3. 差距评估与估算校准

### 3.1 现状红证（基线 = 提交 `1c87fab`，Phase 29 之前）

**基线口径（按事实）**：仓库没有 `v0.28.0` tag（`git tag` 最新为 `v0.27.0`）。本文件的基线是
Phase 28 收口提交 `1c87fab733e0a02955bfcdeff668d10aec2017f3`。复现方式：`git archive 1c87fab`
解到 `/tmp` 副本，用该树自己的 `l0 → l1 → l2 → ct-ast` 链重建编译器，再把下表夹具原样拷进去跑。

| 探针（当前夹具） | 期望能力 | 基线 `1c87fab` 原始输出 | 退出码 |
| --- | --- | --- | --- |
| `struct Box<T> { T v; }` | 解析泛型 struct | `fx/probe_generic_struct.ct:1:11: error: expected a name` | 1 |
| `Box<int> b;` | 实例化 | `fx/probe_generic_inst.ct:3:8: error: use of an undeclared variable` | 1 |
| `foreach (m)`（`m` 是容器） | 容器遍历 | `fx/probe_foreach.ct:3:15: error: use of an undeclared variable` | 1 |
| `Vec<int>` / `Map<…>` 夹具（`container_*`、`foreach_container_*`、`generic_builtin_arity`） | 内置层 | 一律 `…:3:8: error: use of an undeclared variable`（基线没有 `lib/std`，`Vec`/`Map` 尚未内置） | 1 |
| `generic_struct_arity` / `_depth` / `_user_arity` | L29-2 / L29-4 诊断 | `…:3:11–13: error: expected a name`（解析在 `struct X<T` 处就停，走不到判据） | 1 |
| `impl Calc for Num { static int base() }` | V29-3 硬错 | `fx/impl_static_trait.ct:13: warning: signature mismatch: 'base' in impl of 'Calc' for 'Num': return type 'static int' does not match the trait's 'int'` | **0** |
| `foreach_empty` | L27-4 文案 | `fx/e/foreach_empty.ct:3:14: error: foreach needs a collection expression` | 1 |

结论：这批夹具在基线上要么走不到判据、要么只告警退出 0，红证非空转。

**记录位置（按事实更正）**：上述红证是收口后补做的一次性采集，**没有**写进 `check-ast.sh`——门禁只跑
当前编译器，跑不了 `1c87fab` 的产物。`check-ast.sh` 里只有各夹具的「文案 + `line:col` + 单条」预期
表（`p29_neg`）。红证原文与 SHA 以本节为准。

### 3.2 分层估算（**估算**，非实测）

| 层 | 内容 | 估算（行） |
| --- | --- | --- |
| L0 | 泛型 struct 声明解析、2 参数、`>>` 拆分、保留名与深度检查 | 120–200 |
| L1 | `StructInst` 表、规范拼写、编码器、碰撞校验 | 100–180 |
| L2 | 布局单态化、字段替换、`sizeof` / 字段访问、`.h` 导出 | 200–350 |
| L3 | 泛型 impl 方法与实例落码、方法解析 | 150–300 |
| L4 | 内置层加载、加载顺序、遮蔽告警 | 80–150 |
| L5 | `foreach` 容器分支与 `Map` 的 `item.key` / `item.value` | 120–220 |
| L6 | 容器移动语义检查（L29-9/10/11） | 80–150 |
| L7 | 诊断 L29-1…L29-14 | 50–100 |
| **编译器小计** |  | **900–1550** |
| L8 | `lib/std/vec.ct` / `map.ct`（**从 `ct-pkg/std` 迁入，非新增**） | 400–700（搬迁） |
| L9 | `ct-pkg/std` 侧删除 `Vec` / `Map` | 跨仓动作，本仓不计 |
| **内置库小计（净增）** |  | **0**（搬迁 400–700，不计入新增） |
| G | 正例 6 + 跨单元 1 + 负例 11 + 门禁断言 | 400–700 |
| D | spec / tutorial / AGENTS / `lib/std/README.md` | 250–450 |

### 3.3 估算校准（实测 diff）

| 相 | `selfhost/ct-ast` 插入/删除 | 夹具 / 样例 | 说明 |
| --- | --- | --- | --- |
| Phase 21（闭包，新 ABI） | +1245 / −12 | +3077 / −71 | 语言级新子系统，量级上限参照 |
| Phase 25（闭包进静态映射） | +304 / −44 | +431 / −74 | 改解析 + 落码，复用既有 ABI |
| Phase 26（泛型函数） | +303 / −7 | +187 / −83 | 单类型参数 + 单态化，与本相 L0–L3 同源 |
| Phase 27（`foreach`） | +391 / −36 | +238 / 0 | 语句展开 + 诊断，与本相 L5 同源 |
| **Phase 29（本相）** | **900–1550（估算）** | **400–700（估算）** | 约为 Phase 26 的 3–5 倍：多了布局、命名、容器迁入、`foreach` 协议、跨单元 `.h` |

结论：本相**不是单切片能收口**的相，必须按 §5 的 29.1–29.7 分片，每片独立可验证；
编译器部分与容器迁入部分可以在同一相内并行，但门禁必须分块（泛型 struct / 内置层 / `foreach Map`）。

### 3.4 按单元拆分的总量估算（Phase 28 + Phase 29，相对 `v0.26.4`）

> 口径：`v0.26.4` 时 `selfhost/ct-ast/**` 共 **22,798 行**（用户口径约 22.4k，差异来自
> `MapBuild.h.ct` 等附属单元；占比按 22,798 计算）。下表是**新增行数（added LOC）**，不是净变更；
> 历史各相的删除量都很小（−7 ~ −44），不影响量级。区间来自 §3.3 的实测校准，单元级误差约 ±25%，
> 合计误差约 ±20%；标「低置信」的格子是改动点尚未落到具体函数，只有间接证据。

| 单元（`selfhost/ct-ast/**`） | 文件状态（现有行数） | Phase 28 | Phase 29 | 合计 | 主要改动点 |
| --- | --- | --- | --- | --- | --- |
| `frontend/parse/Parser.h.ct` | 改既有（2,539） | +45~85 | +120~200 | +165~285 | `<T: Trait>` 参数表；`struct Name<T,U>` 模板头；2 参数上限、`>>` 拆分、保留名、深度 |
| `frontend/parse/Expr.h.ct` | 改既有（3,782） | +75~150 | +80~140 | +155~290 | `parse_type`（:1278）接受 `Name<...>`；泛型 `impl` 头；类型实参解析 |
| `frontend/parse/Stmt.h.ct` | 改既有（2,536） | 0 | +100~180 | +100~180 | `foreach` 容器分支；`item`/`i` 绑定；`Map` 的 `item.key`/`item.value`；`i` 硬错 |
| `frontend/parse/ParseSupport.h.ct` | 改既有（633） | +0~10 | +0~20 | +0~30 | 共享 token / 类型名辅助（**低置信**） |
| `frontend/sym/Symbols.h.ct` | 改既有（1,314） | +20~40 | +150~250 | +170~290 | `Fn.bound`；`StructDef.tparams`；`StructInst` 表（新增）；编码器；碰撞检查 |
| `frontend/type/TypeCheck.h.ct` | 改既有（913） | +10~25 | +180~290 | +190~315 | 约束满足检查复用；布局替换、`sizeof` / 字段访问、移动语义（**29 的高置信大头**） |
| `frontend/module/Module.h.ct` | 改既有（1,728） | 0 | +60~100 | +60~100 | 内置层加载顺序（内置 → 用户 import → `vendor/`）；遮蔽告警 |
| `backend/emit/Emitter.h.ct` | 改既有（3,896） | +40~95 | +200~320 | +240~415 | 实例结构体发射、impl 方法落码、`.h` 导出、命名预算（收口 `MAX_TEXT` 边界） |
| `tool/diag/Diag.h.ct` | 改既有（511） | +0~10 | +20~35 | +20~45 | 新增 L28 / L29 文案表 |
| `tool/pkg/Pkg.h.ct` | 改既有（2,021） | 0 | +0~20 | +0~20 | 仅路径与遮蔽检测（**低置信**；本仓不改 `ct-pkg`） |
| `runtime/arena/Arena.h.ct` | 改既有（154） | 0 | +0~15 | +0~15 | 临时拼写缓冲（**低置信**） |
| `main.ct` | 改既有（119） | 0 | +0~10 | +0~10 | 内置层根路径注入 |
| `lib/std/**`（`vec.ct` / `map.ct`，**从 `ct-pkg/std` 迁入**） | **搬迁（非新增）** | 0 | 0（搬迁 400~700） | 0 | `Vec`/`Map`/`MapEntry`；原处同版本删除，禁止两份实现并存 |
| **编译器小计（ct-ast 内）** |  | **190~395** | **910~1525** | **1,100~1,920** | 与 §3.2 的 900–1550 同量级 |
| `test/ast/**`、`test/ast/errors/**`、`test/modules/**`、`check-ast.sh` 断言 | 改 / 新增 | +200~350 | +400~700 | +600~1,050 | 正例、负例、覆盖矩阵、跨单元、红证 |
| `docs/**`、`AGENTS.md` | 改既有 | +80~180 | +250~450 | +330~630 | spec / tutorial / 本卡 / 索引 |
| **总计（编译器 + 夹具 + 文档；不含迁入代码）** |  | **470~925** | **1,560~2,675** | **2,030~3,600** | 不含版本收口的 golden 重生；`lib/std` 的 400~700 是搬迁，不计入 |

> **口径说明（2026-11-10 更正）**：早先的「内置库 +600~1,000」把 `str`/`io`/`math` 的
> 200~300 行也算进了迁移；用户裁定 **std 其余模块一律不动**，只剥离 `Vec`/`Map`，因此迁入量收敛为
> **400~700 行**，且属**搬迁、不计净增**。`+600~1,000` 不是新写的编译器代码，不并入编译器增量；
> 编译器侧只增加「内置层加载」（已计入 `Module.h.ct` 的 +60~100）。

**累计泛型相关行数（相对 `v0.26.4`）**

| 项 | 行数 | 占 `selfhost/ct-ast` 22,798 行 |
| --- | --- | --- |
| Phase 26 已落地（泛型函数，实测 +303） | 303 | 1.3% |
| Phase 28（本表，估算） | 190~395 | 0.8%~1.7% |
| Phase 29 编译器部分（本表，估算） | 910~1,525 | 4.0%~6.7% |
| **泛型累计（编译器新增代码）** | **1,403~2,223** | **6.2%~9.8%** |
| `Vec`/`Map` 迁入（来自 `ct-pkg/std`） | 搬迁 400~700（**净增 0**） | —（不计入占比） |
| 夹具 / 门禁（不计入 ct-ast 占比） | 600~1,050 | — |
| 文档（不计入 ct-ast 占比） | 330~630 | — |

> 分母固定为 `selfhost/ct-ast` 的 **22,798 行**，不因迁入而改变；迁入代码在 ct-pkg 侧已有，
> 不计入本仓净增，也不进分子。若未来把 `lib/std/` 计入编译器体量，需另立口径并重算。

**`MAX_*` / `MAX_TEXT` 影响**

| 项 | 结论 |
| --- | --- |
| 既有 `MAX_*` | Phase 28 / 29 **都不改**既有上限（`MAX_STRUCTS`、`MAX_FUNCS`、`MAX_VARS` 等保持原值） |
| 新增常量 | Phase 29 新增 `MAX_STRUCT_INSTS 128`、`MAX_STRUCT_TPARAMS 2`、`MAX_TYPE_DEPTH 4`；Phase 28 不新增 |
| `MAX_TEXT 160` | **不扩**。实例名按 159 字符预算，超限走 L29-6 硬错；夹具不触碰 `MAX_TEXT` |
| 夹具 / 断言 | `check-ast.sh` 新增 Phase 28 / 29 块；`test/ast/**` 与 `test/ast/errors/**` 只加文件与断言，不改上限 |

**校准依据与误差**

| 参照 | 实测 | 用途 |
| --- | --- | --- |
| Phase 21（闭包，新 ABI） | +1,245 / −12 | Phase 29 的 910–1,525 上限参照：同为语言级新子系统，但 29 复用 Phase 26 的实例化骨架 |
| Phase 25（闭包进静态映射） | +304 / −44 | `Parser` / `Expr` / `Emitter` 三单元的「改既有」量级参照 |
| Phase 26（泛型函数） | +303 / −7 | Phase 28 的 190–395 直接同源（多出约束检查与 vtable 槽） |
| Phase 27（`foreach`） | +391 / −36 | Phase 29 的 `Stmt.h.ct` +100~180 是它的容器扩展，不是重写 |
| 估算误差 | 单元 ±25%，合计 ±20% | 低置信格子：`ParseSupport`、`tool/pkg`、`runtime/arena`、`main.ct` |

---

## 4. battle 记录与决策

### 4.1 B29-1 · 实例命名：计数器 / 拼写编码 / 哈希 / 双轨

| 候选 | 方案 | 判据 |
| --- | --- | --- |
| A | 复用泛型函数的 `__ctN` 计数器：`Vec__ct1` | 单元内确定，但**跨单元不稳定**：A 单元的 `Vec__ct1` 与 B 单元的 `Vec__ct1` 可能指不同类型；`.h` 里无法自解释 |
| B | 规范化拼写编码：`Vec_int`、`Map_char_p_int` | 跨单元稳定、可读、与既有 `<Struct>_<Trait>_<method>` 组合自然；代价是类型拼写进入 C 标识符（与 D26-5 相反） |
| C | 纯哈希：`Vec_7f3a2b1c` | 稳定但不可读，调试与 grep 成本高；`type_key` 有损，不能直接作哈希键 |
| D | 内置容器专用规则 + 用户泛型 struct 用计数器 | 两套规则、同一单元可能出现两个名字指同一类型；拒绝 |

**判决：选 B。** 关键判据是 `.h` 必须携带实例定义，而 `.h` 的消费单元无法知道定义单元分配过哪些
计数器；只有拼写编码能自解释。可读性是次要收益。风险用三条工程手段兜住：

1. 规范拼写由 `parse_type` 统一产出，避免 `char *` / `char*` 分叉；
2. 编码表双向校验，冲突即 L29-5；
3. 长度上限 64 + 摘要后缀，组合名超限 L29-6。

**授权记录**：用户 2026-11-10 明确要求 `Vec` / `Map` 内建并迁入内置层，该改动必然触碰已发布命名族；
按**用户已授权**记录，但改动面仍在 §2.2 与本节逐条列出，供审计。

### 4.2 B29-2 · `Map` 的键值绑定：字段 vs 双隐式绑定

| 候选 | 方案 | 判据 |
| --- | --- | --- |
| A | `item.key` / `item.value`，`item: MapEntry<K, V>` | 复用既有「隐式 `item`」规则；`item` 是真实类型，可传参、可取地址、可参与类型检查；`MapEntry` 本身也是普通泛型 struct，可单测 |
| B | 双隐式绑定：`foreach (m) { key, value }` | 要新增绑定语法、遮蔽规则与诊断；与数组/`Vec` 的单 `item` 形态不一致；无既有先例 |
| C | `item` 是 `V`，键另给 `item.key` | 让 `item` 有两种含义（值 vs 条目），类型不稳定；拒绝 |

**判决：选 A。** `item` 始终是「集合元素」这一条规则不变：数组是元素类型，`Vec` 是 `T`，
`Map` 是 `MapEntry<K, V>`。这也让 `foreach` 的展开模板只需换元素类型，不新增语法分支。

### 4.3 B29-3 · 内置容器的实现位置：编译器内建 vs 仓内 CT 库

| 候选 | 方案 | 判据 |
| --- | --- | --- |
| A | 发射器硬编码 `Vec` / `Map` 布局与方法 | 编译器能保证布局与性能；但把容器语义写进 C 生成器，后续改 API 要改编译器，违背「`.h.ct` 只放类型、库逻辑用 CT 写」的既有分层 |
| B | `lib/std/` 用普通 CT 泛型 struct + 泛型 impl 实现，随编译器加载 | 复用本相的泛型 struct / impl 机制；容器逻辑可读、可测、随编译器发行；迁入后 ct-pkg 侧删除，避免双份 |
| C | 独立 `ct-pkg` 包，仅把默认路径内置 | 仍是跨仓依赖；用户明确要求迁入本仓，且 `ct get` 不应是使用 `Vec` 的前置 |

**判决：选 B。** 编译器只负责：解析/单态化/加载内置层/保留名/`foreach` 识别；
`Vec` / `Map` 的字段、增长策略、哈希与比较全部在 `lib/std/*.ct` 里。这样 29.1（泛型 struct）
与 29.2（容器库）可以分开验证：前者用用户自写的 `Pair<T, U>`，后者才引入 `Vec` / `Map`。

### 4.4 B29-4 · `Map` 的键：泛型 `Hash` 约束 vs 白名单

| 候选 | 方案 | 判据 |
| --- | --- | --- |
| A | `Map<K: Hash, V>`，`trait Hash { int hash(); }` | 需要 trait 方法在 `Self` 上工作；Phase 28 的约束方法签名不允许 `T` / `Self`，要扩就是参数化 trait（750–1350 行），单相收不了 |
| B | 白名单 `int` / `long` / `char *`，内置哈希 | 覆盖真实场景的绝大多数；不引入新 trait 体系；哈希/比较实现可单测；不支持的键给出明确 L29-8 |
| C | 只支持 `int` 键 | `char *` 是最常见的字符串键，砍掉会让 `Map` 失去一半用途 |

**判决：选 B。** 白名单是**能力边界**而不是永久结论；重启条件见 §9（出现真实的自定义键类型，
且至少两个包需要）。

### 4.5 B29-5 · 容器拷贝：禁止 / 引用计数 / 深拷贝

| 候选 | 方案 | 判据 |
| --- | --- | --- |
| A | 直接禁止容器出现在初始化式/赋值/实参/返回 | 规则最简单，但 `Vec<int> v = vec_new<int>();` 这类「从调用初始化」也被误伤 |
| B | 移动语义 + 显式 `retain()`；调用结果视为移交 | 覆盖真实写法；共享语义明确；引用计数可测；不引入隐式深拷贝 |
| C | 每次拷贝都深拷贝 | 需要元素级拷贝函数与 `Drop`，正是本相不做的那一块；且性能不可预测 |
| D | 引用计数 + 编译器自动插入 retain | 用户最省心，但要在声明/赋值/实参/返回/字段/元素六处插桩，回归面大；先收窄到显式 `retain()` |

**判决：选 B。** 显式 `retain()` 让共享点可 grep；自动插入留到有真实痛点时再评估（§9）。

### 4.6 B29-6 · 泛型 impl 的落码：实例方法 vs vtable

| 候选 | 方案 | 判据 |
| --- | --- | --- |
| A | 实例方法直接发射为 `<MonoStruct>_<Trait>_<method>`，调用点静态解析 | 泛型 struct 的接收者类型在编译期完全已知；不需要 vtable；与 Phase 28 的约束调用（vtable 槽）分工清晰 |
| B | 每个实例生成 vtable，调用走 `__<trait>_vptr` | 需要实例 vptr 字段与初始化，布局与拷贝都变复杂；本相没有运行时多态需求 |

**判决：选 A。** `foreach` 的 `len/get/entry` 也走 A：编译器知道接收者是 `Vec<T>` / `Map<K,V>` 实例，
直接落成静态方法调用，不引入 vtable。

### 4.7 B29-7 · `foreach` 绑定：`items[i]` vs 统一 `item` + 只读 `i`

> **用户 2026-11-10 已裁定**：统一 `item`；数组 / `Vec` **同时规定** `item` 与 `i`；`Map` 体内
> 使用 `i` 硬错。本节保留判据记录，不再重新论证。

| 判据 | A：用户早期设想（Vec 用 `i` + `items[i]`；Map 用 `item`） | B：统一 `item` + 数组/Vec 的只读 `i` | C：只有 `item`，无 `i` | D：Map 双隐式绑定（`key, value`） |
| --- | --- | --- | --- | --- |
| 与 Phase 27 一致 | ❌ 数组的 `item` 是元素，Vec 却要改成 `i` + 容器下标，同一关键字两种语义 | ✅ `item` 在所有集合形态里都是「当前元素」 | ✅ 同 B | ⚠️ `item` 规则不变，但新增一套绑定语法 |
| 集合是字段 / 表达式 | ❌ `foreach (t.names)` 里没有 `items` 这个名字；要成立只能假设变量名恰好是 `items` | ✅ 绑定与集合表达式无关 | ✅ 同 B | ✅ 同 B |
| 零运行时 | ✅ 下标是普通数组访问 | ✅ 索引是普通 `int`，无隐藏调用 | ✅ 同 B | ✅ 同 B |
| 诊断可读性 | ❌ 两套「元素怎么读」的规则，`item` 在不同容器上含义分裂 | ✅ 一条规则：`item` 是元素；`i` 只是位置 | ✅ 同 B | ⚠️ 新增 `key`/`value` 不能重名的诊断 |
| 实现代价 | ❌ 要给 `Vec` 加 `[]`（运算符重载）或把 `items` 特判成集合变量的别名 | ✅ 展开模板多一行 `int i = …` | ✅ 最低 | ⚠️ 新绑定语法 + 遮蔽规则 |
| golden 稳定性 | ⚠️ Map 顺序未钉死时不确定 | ✅ Map 顺序钉死为插入序 | ✅ 同 B | ✅ 同 B |
| 写回语义 | ❌ `items[i] = …` 会变成「通过别名写容器」，与 Phase 27 的 `item` 值拷贝分叉 | ✅ `item` 值拷贝；写回用 `arr[i]` / `v.set(i, …)` / `m.put(…)` | ✅ 同 B | ✅ `item` 仍是值拷贝 |

**判定：选 B（已由用户裁定）。** `items[i]` 不作为规定语法，原因保留在 §2.5.1 供审计：
它依赖调用点标识符、`Vec` 没有 `[]`、且会给同一元素制造两条读法。`i` 在数组 / `Vec` 上出现；
`Map` 体内出现 `i` 直接报 L29-18，避免「条目位置」被误读成顺序保证。

### 4.8 决策表（D29-nn）

| # | 决策 | 依据 | 影响 |
| --- | --- | --- | --- |
| D29-1 | 泛型 struct 最多 **2 个**类型参数；泛型函数仍 1 个 | `Map<K, V>` 的最小需求；函数侧不扩，避免与 Phase 28 的 L28 诊断冲突 | 解析器、`StructDef` |
| D29-2 | 显式实例化；`>>` 在类型实参上下文拆分；嵌套深度 ≤ 4 | 用户写法 `Vec<Vec<int>>`；深度上限保护 `MAX_TEXT` 与递归 | 解析器、诊断 L29-4 |
| D29-3 | 发射期类型替换、不复制 AST | 沿用 D26-7；布局与函数实例共用一套替换上下文 | `Emitter` / `TypeCheck` |
| D29-4 | 实例占独立 `StructInst` 表，不挤占 `MAX_STRUCTS` | 模板与实例是两类对象；容量可独立调 | `Symbols` |
| D29-5 | 泛型 struct 可 `pub`，`.h` 携带单态化定义；泛型函数仍 `static` | 消费单元必须能声明变量；函数实例仍只在定义单元 | `Emitter`、跨单元 |
| D29-6 | 实例名 = `<Template>_<encoded-args>`；溢出截断 + FNV-1a 后缀；碰撞硬错 | 跨单元稳定、可读、与既有命名族组合；**用户授权例外** | `Symbols`、`Emitter` |
| D29-7 | 类型实参可嵌套；泛型函数体仍不得调用泛型函数 | 区分类型嵌套与调用递归 | 解析器、`GenericInst` |
| D29-8 | `Vec` / `Map` / `MapEntry` 为内置保留名，随 `lib/std/` 加载 | 用户要求内建并迁入本仓；保留名避免双定义 | `Parser`、加载器 |
| D29-9 | `Map` 键白名单 `int` / `long` / `char *`，内置哈希 | 约束系统装不下 `Hash<K>`；白名单覆盖主场景 | `lib/std/map.ct`、L29-8 |
| D29-10 | 容器移动语义 + 显式 `retain()`；调用结果视为移交 | 避免隐式深拷贝与六处插桩；共享点可 grep | 检查器、L29-9 |
| D29-11 | 容器不自动析构；`own` / `borrow` 不得入容器 | 自动析构需要泛型 `Drop` 级联；本相先钉语义 | 检查器、L29-10 |
| D29-12 | 容器 API 按 §2.4 冻结 | 正向夹具需要确定的边界行为 | `lib/std/vec.ct` / `map.ct` |
| D29-13 | `foreach` 只认内置 `Vec` / `Map`，不开放给用户类型 | 结构性协议会误伤同名 `len/get`；开放需另立判据 | `Stmt` / `Emitter` |
| D29-14 | `foreach` 统一 `item`；数组/`Vec` **同时规定** `item` 与只读 `i`；`Map` 体内用 `i` 硬错；`items[i]` 非规定语法；`item` 值拷贝 | 用户 2026-11-10 裁定 + §4.7 判据 | `Stmt` / `Emitter`、L29-16/17/18 |
| D29-15 | `Map` 遍历顺序 = 插入序；删除左移补位 | golden 与样例必须确定；哈希序会漂移 | `lib/std/map.ct`、E29-3 |
| D29-16 | 本相不引入 `Callable`、不改闭包语义 | 用户 2026-11-10 取舍；D21-5/D21-13 原样有效 | 文档边界 |

---

## 5. 取代台账（可审计，不静默改写）

> 本相只取代「泛型 struct / 泛型 impl 非目标」这一族，以及 D27-4 的容器协议冻结。
> **不取代** D21-5 / D21-7 / D21-13：闭包仍是非逃逸、栈上环境、绑定语义；`Callable` 内建延后。

| 旧决策 | 旧结论 | 旧理由 | 旧理由是否仍成立 | 被谁取代 / 现状 | 影响面 |
| --- | --- | --- | --- | --- | --- |
| D26-2（`function-only` 部分） | 泛型只做函数，单类型参数 | 「多参数会引入 `>>` 词法与组合实例化；结构体/联合需要布局单态化」 | 「另一量级」**仍成立**；本相就是专门付这个量级的阶段。被取代的是「非目标」这一永久措辞，不是成本判断 | D29-1 / D29-2：struct 最多 2 参数；函数仍单参数 | 新增 `StructInst`、布局发射；函数实例路径不变 |
| D26-4 | 泛型必须 `static`，拒绝 `pub` | 「跨单元需要头文件导出实例；本相不做半成品」 | 对**函数**仍成立；对**struct** 不成立——`.h` 必须携带实例定义，否则消费单元无法声明变量 | D29-5：泛型 struct 可 `pub`；泛型函数仍 `static` | `.h` 新增单态化结构体定义；函数导出规则不变 |
| D26-5 | 实例名 `<name>__ctN`，类型拼写不进 C 标识符 | 「确定性、可 grep、避免类型拼写进入 C 标识符」 | 对**函数**仍成立（实例是单元内 `static`）；对**跨单元 struct** 不成立——计数器无法自解释 | D29-6：struct 用拼写编码；函数保留 `__ctN` | 已发布命名族组合扩展；既有 golden 零变化；新夹具使用新名 |
| D26-9（范围收窄） | 泛型体内禁止递归/嵌套泛型调用 | 「避免实例化循环与缓存键递归」 | 对**函数调用**仍成立；对**类型实参**不成立——`Vec<Vec<int> >` 是有限的类型嵌套，不是调用递归 | D29-7：类型实参可嵌套，深度 ≤ 4；泛型函数体仍不得调用泛型函数 | 新增深度检查与 `>>` 拆分 |
| D27-1 / D27-2（部分） | 数组 `foreach` 只绑定 `item` | 「单个隐式绑定足够；索引可自行计数」 | **不再成立**：用户 2026-11-10 要求数组 / `Vec` 同时提供 `i` 与 `item` | D29-14：数组与 `Vec` 都绑定 `item` + 只读 `i` | 数组 `foreach` 体里原先声明局部 `i` 的写法现在命中 L29-17；需在 spec/教程写迁移说明，既有夹具若声明 `i` 要改名 |
| D27-4 | 容器协议 `len()+get(int)` / `len()+entry(int)` **本相不做** | 「本仓无 std 容器；无夹具即无红证；容器元素落码无既有夹具」 | **不再成立**：本相把 `Vec`/`Map` 变为内置并有真实样例，红证可写 | D29-8 / §2.5：协议解冻，只对内置 `Vec`/`Map` 生效 | `foreach` 解析/落码新增分支；Phase 27 的数组路径不变 |
| D17-7 / [map-options.md](map-options.md) §2 | `std::map` 是有界、不可增长的唯一推荐容器，位于 ct-pkg | 「单态类型为主、有界开放寻址、不用 `delete`」 | 对**旧编译器**仍成立；`ct-pkg/std` 只移除 `Vec`/`Map`，其余模块不动。对新编译器，内置 `Map` 提供增长与遍历，`std::map` 不再是唯一选择 | D29-9 / D29-10：内置 `Map<K,V>`；旧 `std::map` 随 `ct-pkg/std` 的其余模块保留 | 文档口径变更；不得声称旧决策「错误」 |

**明确不取代**：

- D21-5（E1–E7 逃逸硬错、E8 文档级）：本相没有逃逸闭包，原样有效。
- D21-7（`Callable` 按签名一族、不内建）：本相不做 `Callable`；延后记录见 phase21 §4.12，不是取代。
- D21-13（闭包是绑定不是值）：本相不做可存储闭包，原样有效。
- D21-12（Phase 21 不引入泛型）：已被 Phase 26 事实上取代；本表补记，不静默。

---

## 6. 切片

| 切片 | 内容 | 主要文件 | 完成信号 |
| --- | --- | --- | --- |
| 29.1 | 泛型 struct 语法、参数、深度、`>>` 拆分、保留名（**用户可写**） | `Parser.h.ct`、`Symbols.h.ct` | `struct Pair<T, U>` / `struct Stack<T>` 可解析；L29-1/2/3/4 负例红 |
| 29.2 | 实例表、规范拼写、编码器、碰撞检查、布局发射；**内置与用户泛型 struct 共用同一路径** | `Symbols.h.ct`、`Emitter.h.ct`、`TypeCheck.h.ct` | `Pair<int, char *>` / `Stack<int>` 生成独立 C 结构体；夹具 138/139/144、样例 23 绿；E29-1/E29-12 绿 |
| 29.3 | 泛型 impl 与实例方法落码 | `Expr.h.ct`、`Emitter.h.ct` | 夹具 147 的实例方法可调用；命名组合正确 |
| 29.4 | 内置层加载、`Vec`/`Map` **迁入**、`mem.ct` 直接依赖、保留名与遮蔽 | `lib/std/**`、`Parser.h.ct` | `Vec`/`Map` 不 `ct get` 可用；夹具 142/143、样例 24/25 绿；E29-5/6 绿 |
| 29.5 | 容器移动语义与诊断 L29-9/10/11/13 | `Expr.h.ct`、`TypeCheck.h.ct` | 拷贝/own/嵌套容器负例红（B8） |
| 29.6 | `foreach` 容器协议与 `Map` 绑定 | `Stmt.h.ct`、`Emitter.h.ct` | 夹具 140/141 与样例 22 绿（**E29-3 硬判据**）；样例 25 的 `Map` 遍历绿 |
| 29.7 | `Vec`/`Map` 迁入收口、跨单元 `.h`、模块边界、文档与收口 | `lib/std/**`、`test/modules/**`、`docs/**` | 夹具 B6 跨单元绿；E29-2/5/8/9/10/11/13 绿 |

> 29.1–29.3 合并为一个功能提交（中间态不可运行）；29.4 可独立；29.5/29.6 各自独立；
> 29.7 拆成「迁入」「文档」「版本收口」三个提交。每个提交都必须 `check-docs` 绿。

---

## 7. 与 Phase 28 的边界

| 项 | Phase 28 | Phase 29 |
| --- | --- | --- |
| 泛型载体 | 函数 | struct（+ 泛型 impl）；**对用户开放**，`struct Stack<T>` 可写 |
| 类型参数个数 | 1 | 2（`Map` 需要） |
| 约束 | `T: Trait`，单约束 | 不新增约束语法（`struct Stack<T: Ord>` 拒绝）；泛型 impl 可复用 Phase 28 的约束检查 |
| 派发 | 经 vtable 方法槽 | 静态方法调用（接收者类型编译期已知） |
| 实例命名 | `<name>__ctN` | `<Template>_<encoded-args>` |
| `pub` / 跨单元 | 泛型函数拒绝 `pub` | 泛型 struct 允许 `pub`，`.h` 携带实例定义 |
| `foreach` | 不涉及 | 解冻容器协议，`Map` 为硬判据 |
| 闭包 | 不涉及 | 不涉及（D21-5/D21-13 原样） |
| `Callable` | 不涉及 | 不涉及（延后） |

**合并次序**：Phase 28 先收口（`v0.28.0`），Phase 29 基于其收口提交开工。两相共用
`Parser.h.ct` / `Expr.h.ct` / `Emitter.h.ct`，但改动段落不同；若并行开发，先在 28 冻结
`aux` 约束分支的编号，29 不复用同一编号。

---

## 8. 开放项与触发信号（不写成「待用户决定」）

| # | 开放项 | 当前处置 | 触发信号 / 重新评估条件 |
| --- | --- | --- | --- |
| O1 | 用户自定义可迭代类型 | 本相只认内置 `Vec`/`Map` | 至少两个真实包需要 `foreach` 自己的容器，且它们的 `len/get` 签名稳定 |
| O2 | `Map` 的自定义键类型 | 白名单 `int`/`long`/`char *` | 至少两个包需要自定义键，且参数化 trait 已立项 |
| O3 | 容器自动析构 / `Drop` 级联 | 手动 `release()` | 出现「忘记 release」的真实泄漏，或 `Callable` 内建重启并统一生命周期 |
| O4 | 容器元素为内置容器（`Vec<Vec<T>>`） | 硬错（L29-11） | 需要按类型生成 retain/drop 助手，且自动析构已落地 |
| O5 | 编译器自动插入 `retain` | 不做，显式 `retain()` | 显式 `retain()` 在真实代码中成为主要噪声，且有可测的漏释放统计 |
| O6 | `MAX_TEXT` 扩容 | 先按 159 字符预算 | 组合名超限在真实程序中反复出现，且缩短命名不可行 |
| O7 | 内置层与 `ct-pkg/std` 的双向迁移工具 | 只做一次性搬运 | 旧包仍有独立 bug 修复需求，或需要回滚到旧编译器 |
| O8 | `foreach` 迭代中修改容器 | 长度快照 + 越界零值 | 出现真实的数据竞争/漏遍历报告，且可定义稳定语义 |
| O9 | 泛型函数体内实例化泛型容器（如 `Vec<T>`） | 本相不做，沿用 D26-9 的「泛型体内禁止泛型调用/实例化」 | 用户明确要求「泛型函数返回 `Vec<T>`」；重启前需先解决实例化键的递归替换与去重（`Vec<T>` → `Vec_int`） |
| O10 | `Vec` 的 range 初值 / 下标 / 字面量语法糖（`Vec<int> v = 4..8 { $ * $ }`、`v[i]`、`Map<char *, int> m = { "k": 1 }`、`m["k"]`） | 第 1 条由 P29-1 补成合法语法（range 初值 + `Vec<T>::from` 入口，见 §11）。第 2–4 条**仍不支持**：`v[i]` / `m["k"]` 指向的是 C 结构体，`{ "k": 1 }` 的 `:` 不在 C 聚合初值语法里。它们不再是「静默放行、把非法 C 交给 cc」：V29-4 在编译期给出位置化诊断（`a Vec is not subscriptable…` / `a Map is not subscriptable…` / `a Map cannot be initialized from a brace list…`），因此没有新增语法，但守住了「绝不发射非法 C」 | 出现第二个真实项目要求 `v[i]` / `m[k]`，且能接受「构造入口 + 纯降级」的语义；否则保持显式 `Vec_int_get` / `Map_*_get` |

---

## 9. 本轮不做（自查）

- 未创建 `phase30.md`；`Callable` 内建按用户 2026-11-10 取舍**延后**，记录在
  [phase21.md §4.12](phase21.md#callable-内建的延后记录2026-11-10)，不保留空壳立项卡。
- 未修改任何编译器源码、`lib/**`、测试、golden、版本串；未改 `docs/design/phase27.md` 的已收口内容。
- 未 bump、未打 tag、未修改 `ct-pkg`。
- 归档按实际 `check-docs.py` 规则执行：只 `git mv` `phase17.md`（`floor = 18`），`phase18.md` 保留。
- 门禁输出以实际运行 `python3 test/docs/check-docs.py` 为准，贴在提交说明与 §10。

---

## 10. 门禁记录（本轮，实测）

实现与文档各自成提交；未 bump、未打 tag。收口时 `check-all.sh` **11 道硬门禁全绿**。

```text
$ python3 test/docs/check-docs.py
spec pin: ok (1.0.0, 93a8e968)
check-docs: OK (967 relative links in 178 files, v0.26.4, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
```

- **design window**：`max = 29`、`floor = 29 − 12 + 1 = 18`；只有 `phase17.md` 越窗，
  已 `git mv` 到 `docs/history/design/phase17.md`；`docs/design/` 现存 `phase18.md`–`phase29.md`
  共 12 份。
- 归档同时更新了 `docs/roadmap.md`、`docs/README.md`、`docs/history/README.md`、`docs/glossary.md`、
  `docs/tutorial.md`、`issues/README.md`、`issues/selfhost/sh43-build-no-cc.md`、`AGENTS.md`
  中指向 `design/phase17.md` 的链接。
- 后续实现相的每一切片都必须重跑此门禁并保持 `OK`；实现期的 `check-ast.sh` / `check-all.sh`
  原始输出贴在各切片的提交说明里。

### 10.1 实现期实测（2026-11-11）

三个切片各自提交、各自重跑门禁：

| 切片 | 提交内容 | 门禁 |
| --- | --- | --- |
| 29.1–29.2 | 符号层、`parse_type` 实例分支、`impl<T>` 解析与静态派发 | `check-ast.sh` 903 passed / 0 failed |
| 29.3–29.4 | `lib/std/Vec.h.ct` 内置层与自动加载 | `check-ast.sh` 903 passed / 0 failed |
| 29.6 | `foreach` 容器协议、样例 22–25、夹具 138–142/144/147、负例、跨单元夹具 | `check-ast.sh` **936 passed / 0 failed** |
| 收口（首轮） | 文档同步、`lib/std/README.md`、未使用变量清理 | `check-all.sh` **11 hard gates green**（`check-ast.sh` 936 passed / 0 failed、`check-warnings.sh` 282 ok、`check-docs` 967 links）。复核发现 E29-5 / E29-6 / E29-13 未满足，状态回退为「实施中」，见 §10.3.1 |
| 判据补口 | L29-9/10/11 三条硬错、L29-W1 遮蔽告警、`container_*` 负例 4 条、`143_map_api`、`p29_builtin_std`（含 `needs_std.ct`）、`generic_struct_pub_fn.ct` | `check-ast.sh` **948 passed / 0 failed**；`check-docs` **OK**（967 links、12 phase status）；`check-sanitizers.sh` 中 `143_map_api` **ok**（该脚本另有 10 项既有失败：8 个带 `import` 的夹具在 compile 模式被调用、`range_init_overflow` 崩溃，均与 Phase 29 无关） |
| 最终收口（首轮） | 状态改回「完成」、§10.3 写关闭证据、roadmap / AGENTS 同步 | `check-all.sh` **OK（11 hard gates green）**：`check-ast.sh` 948 passed / 0 failed、`check-warnings.sh` 283 ok、`check-docs` OK、`test/run.sh` 137 passed、`check-goldens` 82 passed、acceptance 20 pass / 0 regression。**随后复核发现 E29-5 的 `ct build` 路径未接入内置层，状态回退「实施中」**（§10.3.4） |
| 复核补口（build 路径） | `Module.h.ct` 在 `ct build` 中加载 `lib/std/Vec.h.ct`（独立单元，不是 import 边），emitter 显式 `#include` 其头文件并每轮重发；`check-warnings.sh` 撤回 `p29_builtin_std` 的跳过；`check-ast.sh` 增加 build 路径断言 | `check-ast.sh` **949 passed / 0 failed**（含 D41 key 字节比对与热缓存）、`check-warnings.sh` **321 ok**（含 `p29_builtin_std`）、`check-all.sh` **OK（11 hard gates green）** |
| 最终验收（E29-1…E29-13 逐条） | 本轮把判据原文的缺口补进真门禁：`p29_diag` 钉住 `file:line:col` 且断言恰一条错误；新增 `generic_builtin_arity.ct` / `generic_struct_user_arity.ct` 并断言两者 arity 文案逐字相同；6 条负例的 `ct check` / `ct build` 首条错误逐字比对；138 的两个实例标签；141 两次编译与两次运行一致 | `check-all.sh` **OK（11 hard gates green）**；`check-ast.sh` **962 passed / 0 failed**、`check-warnings.sh` **321 ok / 0 failed**、`check-docs` **OK（978 links / 179 files）**、`test/run.sh` 137 passed、`check-goldens` 82 passed、acceptance 20 pass / 0 regression。逐条证据见 §10.3.5；sanitizer 的既有 10 项失败见同节末段 |

### 10.2 实现偏差与未落地项（如实记账）

| 项 | 实际口径 | 原因 / 后续 |
| --- | --- | --- |
| `Map` 索引 | 线性扫描 `entries[]`，无开放寻址 / 哈希索引 | 没有参数化 trait，无法对 `K` 做类型分派；`len` 仍 O(1)（`ct_buf` 计数），`get` / `put` / `remove` O(n) |
| `mem.ct` | 未单独建；`Vec.h.ct` 直接调 libc `malloc` / `free` / `realloc` | 内置层只有四个类型，单独建单元反而要跨单元共享 `ct_buf` |
| `MAX_CALLS` | `selfhost/l2/core.ct` 512 → **1024** | L2 是冻结 oracle，只放大接受能力以容纳变大的 ct-ast 源；行为不变，记为容量例外 |
| `frontend/module/Map.h.ct` | 改名 `MapTable.h.ct`，类型 `Map` → `MapTable` | L29-7 把 `Map` 列为保留名；编译器自己的模块表不能占这个拼写 |
| `i` 的绑定范围 | 数组与 `Vec` 都绑定只读 `i`（D29-14）；`Map` 也绑定但任何使用都是 L29-18 | 数组原先只绑 `item`，本相统一；既有夹具中在 `foreach` 体内声明 `int i` 的写法现在命中 L29-17 |
| L29-17 的范围 | 只覆盖循环体内的显式声明（`N_DECL`） | 嵌套 `foreach` 重绑 `item` 仍是 D27-10 的警告（`ct check` 下为错误），不叠加第二个诊断 |
| L29-5 | **已实现** | `ct_inst_add` 在编码已存在但规范拼写不同时返回 -2，`inst_make` 报 `two type arguments encode to the same C name '<name>'`（`Expr.h.ct`，§2.2 第 6 步）。夹具无法在不扩编码表的前提下构造碰撞，故只留代码路径与逐字文案 |
| L29-6 | **已实现** | `ct_inst_encode` 超长失败 / `ct_inst_add` 返回负值时，`inst_make` 报 `the instantiated name exceeds 159 characters; shorten the template or its arguments`（`Expr.h.ct`），不截断、不静默压缩 |
| L29-13 | **已实现（V29-5）** | `inst_make` 对 `Vec` / `Map` 的每个类型实参跑 `container_vptr_type`：接口值（`struct X_iface`）或带 vptr 的 struct（自身 `use`，或值字段递归）一律硬错 `interface and vptr-bearing values cannot be stored in a container`；`use Drop` / `use Handback` 无 vptr，不误伤。夹具 `container_iface.ct` / `container_vptr_struct.ct` |
| L29-14 | **结构上不可达（不是未实现）** | 实例布局来自模板行，而一个 build 的所有单元共享同一个 `Symbols`：模板同名即重复定义错误，不存在「两份模板」可产生两份布局；实例的定义也只由模板所在单元发布一次（`test/modules/p29_generic_struct`）。要「比对两份定义」需要一个能产生它们的编译路径，本编译器没有这条路径，故该诊断没有可达输入 |
| `ct build` 的内置层 | **已接入**（2026-11-11 二次复核后补）：`Module.h.ct` 在加载输入前解析 `lib/std/Vec.h.ct`，作为独立单元参与发射；它**不是**任何单元的 import 边（避免破坏 D41 的 cache key 拼写与热缓存），由 emitter 在消费者的 `.c` / `.h` 里显式 `#include`，层单元每轮强制重发（实例集合进不了它的 cache key）。`check-warnings.sh` 已撤回对 `p29_builtin_std` 的跳过 | 首轮曾以「未接入」记账并跳过门禁，属于判据缺口；现由 `check-ast.sh` 的 build 路径断言与 `check-warnings.sh` 的模块扫描双重覆盖（§10.3.4） |
| 固有方法实参检查 | 只检查元数，不检查实参类型 | 实例方法的形参在模板里是符号类型，`parse_type` 的实参检查需要实例上下文；已列为已知限制 |

### 10.3 退出判据复核与关闭证据（2026-11-11）

#### 10.3.1 第一次复核（状态回退的依据，保留）

复核方法：逐条在 E29-1…E29-13 的**原文**里检索 `L29-9` / `L29-10` / `L29-11` / `L29-13` / `L29-W1`。
结论是其中三条**落在退出判据内**（经 B8 → E29-13），加上 E29-5 的遮蔽告警与两条判据自带的夹具
缺失，本相当时不能标记完成；§10.2 的偏差表不能替代判据。当时回退为「实施中」。

| 偏差项 | 是否出现在 E 判据原文 | 判据原文（摘录） | 当时的结论 |
| --- | --- | --- | --- |
| L29-9 / L29-10 / L29-11 | **是**（经 B8 → E29-13） | B8：「`own` / `borrow` 值入容器（L29-10）；容器按值拷贝（L29-9）；容器元素为容器（L29-11）」；E29-13：「**样例覆盖矩阵每行都有可运行样例**…每行有对应负例或产物断言」 | 未满足 |
| L29-W1 | **是**（E29-5 正文） | E29-5：「`vendor/std` 存在时给一条遮蔽告警且仍用内置 `Vec`/`Map`」 | 未满足 |
| L29-13 | **否**：E29-1…E29-13 原文无此编号；B8 的反向证明只点名 L29-9/10/11 | B8 原文未列 L29-13；它与参数化 trait / 装箱布局耦合 | 不在判据文本内，延后不改结论 |

#### 10.3.2 补口实现（本轮，逐条对应判据）

| 判据 | 补口内容 | 实现位置 | 夹具 / 断言 |
| --- | --- | --- | --- |
| E29-13（B8）L29-9 容器按值拷贝 | 变量初始化器与赋值右侧若为**同名容器类型**的裸标识符，报硬错 | `frontend/sym/Symbols.h.ct` 的 `ct_is_container_type`；`frontend/parse/Stmt.h.ct`（声明初始化器）、`frontend/parse/Expr.h.ct`（赋值） | `test/ast/errors/container_copy.ct`；`p29_diag` 断言文案「a container is moved, not copied; use retain() or a function result」 |
| E29-13（B8）L29-10 `own` / `borrow` 入容器 | 容器 `push` / `set` / `put` 的实参若是 `own` 或 `borrow` 绑定，报硬错 | `frontend/parse/Expr.h.ct` 的固有方法调用分支（`inst_inherent_method`） | `test/ast/errors/container_own.ct`；断言「a container cannot hold an 'own' or 'borrow' value」 |
| E29-13（B8）L29-11 容器元素为容器 | 类型实参中出现按值容器（`Vec<…>` / `Map<…>`，指针不算）报硬错；容器 `push` / `set` / `put` 收到按值容器实参同样报错 | `frontend/parse/Expr.h.ct` 的 `inst_make` 与固有方法调用分支 | `test/ast/errors/container_element.ct`、`container_element_map.ct`；断言「a built-in container cannot be an element of another container」 |
| E29-5 / L29-W1 `vendor/std` 遮蔽告警 | 内置层加载成功且 cwd 存在 `vendor/std` 时记一条 `std_shadow` 告警，仍用内置 `Vec`/`Map`；**compile 与 `ct build` 两条路径都触发** | `tool/driver/Driver.h.ct` 的 `load_builtin` 调用点；`frontend/module/Module.h.ct` 的 `build_main`；`tool/diag/Diag.h.ct` 的 `record_std_shadow`（JSON `"std_shadow"` / 文本 `warning`） | `test/modules/p29_builtin_std/`（含不可编译的 `vendor/std/vec.ct` 作诱饵）；断言告警文案「the built-in Vec/Map supersede a project-local 'vendor/std' (ignored)」+ `struct Vec_int` + 输出 `7 1`，compile 与 build 各一条 |
| E29-5 内置层只覆盖容器 | 负例证明 `std::str` 仍需 `ct get std` | 模块解析既有行为（`Module.h.ct` 的 `resolve_import`） | `test/modules/p29_builtin_std/needs_std.ct`；断言「cannot resolve import 'std/str'」 |
| E29-6 容器 API | 补 `test/ast/143_map_api/`：`put` 重复键原位改值、`len`、`get` 命中/未命中、`entry` 与越界、`remove` 左移、`retain` 共享、`release` 到 0 | `lib/std/Vec.h.ct`（既有实现，未改） | `test/ast/143_map_api/prog.ct` + `prog.expected.out`；`check-ast.sh` 逐字节 `cmp`、`check-sanitizers.sh` 自动遍历 `test/ast/*/prog.ct` 做 ASAN 门禁（实测 `143_map_api` ok；该脚本的其余既有失败见 §10.1） |
| E29-13（B6）泛型函数 `pub` 负例 | 无代码改动（L26-2 既有诊断） | 既有 `pub` 检查 | `test/modules/errors/generic_struct_pub_fn.ct`；断言「generic functions cannot be pub」逐字匹配 |

补口后判据状态：

| 判据 | 状态 | 证据 |
| --- | --- | --- |
| E29-5 | **满足（两条路径）** | 遮蔽告警 + `builtin_std` 夹具 + `needs_std.ct` 负例；compile 模式与 `ct build` 各有一条运行断言（§10.3.4） |
| E29-6 | **满足** | `142_vec_api` 与 `143_map_api` 均在 `check-ast.sh` 与 `check-sanitizers.sh` 的遍历范围内 |
| E29-13 | **满足** | B1–B9 每行有夹具与断言；B6 的 `generic_struct_pub_fn.ct` 补齐；B8 的 L29-9/10/11 三条均已实现并进硬门禁 |

计数与门禁原始输出见 §10.1 的「判据补口」与「最终收口」两行。

#### 10.3.3 仍延后的项与重启信号

`L29-13`（容器元素是接口值 / 含 vptr 的 struct）在 V29-5 后**已实现**并进真门禁；`L29-14`（跨单元
布局比对）不是延后而是**结构上不可达**（理由见 §10.2 该行）：布局只有一个来源，没有第二份定义可比。
两者都不再以「未实现」记账。

#### 10.3.4 二次复核：`ct build` 路径（2026-11-11）

上一轮把 `p29_builtin_std` 从 `check-warnings.sh` 的模块段跳过，理由是「内置层未接入 `ct build`」。
按判据原文复核，这不是可以延后的偏差：E29-5 写的是「不执行 `ct get std` 时 `Vec` / `Map` 可直接使用
（无需 import）」，没有限定 compile 模式。实跑核对：

- **修复前**：`ct build src/main.ct -o out` 对只写 `Vec<int>` 的 `src/main.ct` 报
  `src/main.ct:5:8: error: use of an undeclared variable 'Vec'`，退出码 1。→ 真缺口。
- **修复**：`Module.h.ct` 在加载输入前，用与 compile 模式相同的三处探测（`CT_STD_DIR`、cwd 的
  `lib/std`、输入目录的兄弟 `lib/std`）找到 `Vec.h.ct` 并 `load_unit`；它作为独立单元参与发射，
  **不加入任何单元的 import 边**（加了会改变 cache key 的拼写、并让层单元的每轮重发污染全部下游，
  `check-ast.sh` 的 D41 字节比对与热缓存断言会红）。消费者 `.c` / `.h` 由 emitter 显式
  `#include "Vec.h"`（`ct_emit_set_builtin` 传索引），层单元每轮强制重发：它的 `.h` 携带整个 build 的
  实例定义，实例集合不进它的 cache key。审计发现不加这一条时，先 build `Vec<int>` 再改用
  `Vec<char *>` 会命中旧 `Vec.h` 而缺实例。

实跑证据（无 `CT_STD_DIR`，项目根放 `lib/std`，源码在 `src/`；`main.ct` 只有 `#include <stdio.h>` 与
`Vec<int>` / `Map<char *, int>`，没有任何 import）：

```text
$ /tmp/p29/ct-ast build src/main.ct -o out --outdir cbuild
'cc' -std=c99 -I 'cbuild' 'cbuild/Vec.c' 'cbuild/main.c' '-o' 'out'
build_exit=0
$ ./out
7 1 2
run_exit=0
```

- **遮蔽告警**：同一个 `p29_builtin_std` 夹具走 `ct build` 也输出
  `vendor/std:1: warning: the built-in Vec/Map supersede a project-local 'vendor/std' (ignored)`，
  且 `--outdir` 下的 `Vec.h` 含 `struct Vec_int`，运行输出 `7 1`。
- **门禁处理**：撤回 `check-warnings.sh` 的跳过（不是改名豁免），并新增 `check-ast.sh` 的 build 路径断言
  `p29 (builtin_std in ct build)`（编译、链接、运行、告警、实例五件事一起断言）。
- **增量缓存**：先 build `Vec<int>`，再把同一文件改成 `Vec<char *>` 重建，第二次会重发
  `Vec.c` / `Vec.h` 并正确运行（退出码 1 = `s.len()`）。

结论：E29-5 的 compile 与 `ct build` 两条路径都已满足。本轮最终验收通过（§10.3.5），
状态改回「完成」。

#### 10.3.5 最终验收：E29-1…E29-13 逐条（2026-11-11）

主卡验收先于 P29 补丁（§11）；本节只覆盖 §1 冻结的 E29 判据原文。

| 判据 | 状态 | 证据（夹具 / 断言） | 实跑 |
| --- | --- | --- | --- |
| E29-1 | 满足 | `test/ast/138_generic_struct`、`139_generic_struct_two`、`144_generic_struct_user` 走 `check-ast.sh` 的 corpus 段（编译 → `cc -Wall -Wextra` → 运行 → `cmp` `prog.expected.out`）；新增 `p29 (two instances, two distinct tags)` 断言 138 产物同时含 `struct Pair_int_char_p {` 与 `struct Pair_int_int {`；`tparam_residue()` 扫描每份产物的 `<T>` 残留；`p29 (generic struct instances and inherent method names)` 断言 144 的 `struct Stack_int` / `struct Stack_char_p` / `Stack_int_top(` | `check-ast.sh` 962 / 0；138 输出 `distinct: 1` 等全部命中 |
| E29-2 | 满足 | `test/modules/p29_generic_struct`：`main.ct` 与 `two.h.ct` 各自用 `Pair<int, int>`，`shapes.h.ct` 发布模板；断言 `shapes.h` 中 `struct Pair_int_int {` 恰一次、`two.h` 不再定义；`twice()` 跨单元按 `p.first()` / `p.b` 读同一布局 | `p29 (the template's unit publishes the instance; a second unit reuses it)`；运行输出 `7 k 9 5` |
| E29-3 | 满足 | `test/ast/141_foreach_map`、`examples/22_foreach_map` 走 corpus；`p29 (foreach Map walks entry without an index)` 断言 `Map_char_p_int_entry` 且无 `i`；新增 `p29 (Map: two builds and two runs agree)` 对 141 连续两次编译 `cmp` 产物、两次运行 `cmp` 输出 | `141/prog.expected.out` 是插入序 `b=20 / a=1 / c=3`；两次构建与两次运行一致 |
| E29-4 | 满足 | `140_foreach_vec`：断言 `Vec_int_get`、`int i = __ct_foreach_i_`、`(void)i;`，并新增 `__ct_foreach_n_`（长度循环前快照）；`141` 断言 Map 体内无 `i`；`140/prog.expected.out` 的 `seen = 4, len = 5` 证明循环中 `push` 不改本轮长度；负例见 `foreach_container_index_write` / `foreach_container_redeclare` / `foreach_container_map_i` 与 Phase 27 的 `foreach_struct`（非容器） | `check-ast.sh` 962 / 0；`item` 发射为值局部量（`int item = Vec_int_get(...)`），块内改写不回写 |
| E29-5 | 满足 | compile：`p29 (builtin_std shadow warning)` + `p29 (builtin_std is containers only)` + `needs_std.ct`；`ct build`：`p29 (builtin_std in ct build)`（编译、链接、运行、`vendor/std` 告警、`Vec.h` 含 `struct Vec_int` 五件事一起断言）。`lib/std/README.md` 明确两条路径都免 `ct get` / 免 import | §10.3.4 的原始 `cc` 行、`7 1 2`、`run_exit=0`；本轮 `check-warnings.sh` 321 / 0 |
| E29-6 | 满足 | `142_vec_api`（push/len/get/set/pop/clear/retain/release）与新增 `143_map_api`（put/len/get/entry/remove/retain/release）走 corpus，`prog.expected.out` 分别为 `142 OK` 系列与 `143 OK`；`check-sanitizers.sh` 逐一遍历 `test/ast/*/prog.ct`，`142` / `143` 均 `ok` | `check-sanitizers.sh` 中 `142` / `143` 无 ASAN/UBSAN 报告（该脚本另有 10 项既有失败，见下） |
| E29-7 | 满足 | `p29_diag` 现在同时断言 `test/ast/errors/<f>.ct:<line>:<col>: error: <冻结文案>` 与**恰一条** `error: `；覆盖 4 条 generic-struct、2 条 arity（E29-12）、4 条 foreach、4 条 container 共 14 条；Phase 26/27 的 generic-function 与 foreach 负例由各自的钉住块覆盖（合计 ≥10 + 5）；基线红证记录在 §3.1（基线 `1c87fab` 对 `Box<int>` 报 `3:8: use of an undeclared variable`，本仓库没有 v0.28.0 tag，Phase 28 也在 v0.26.4 内收口） | 14 条 `ok p29 (<fixture>)`，位置精确到 `line:col` |
| E29-8 | 满足 | `check-goldens` 82 / 0；`check-ast` 962 / 0（较 949 只多本轮新增断言，无回归）；`check-warnings` 321 / 0 | 见下「门禁」 |
| E29-9 | 满足 | `check-all.sh` 11 道硬门禁全绿；新增 6 条 `p29 (check/build agree on <fixture>)`：同一负例的 compile、`ct check`、`ct build` 首条 `error: ` 逐字相同 | 6 条 `ok`；`check-all: OK (11 hard gates green)` |
| E29-10 | 满足 | `docs/language-spec.md` §4.51、`docs/tutorial.md` §10.8、`AGENTS.md` 中英文、`examples/README.md` 22–25、`test/run.sh` 的 examples 扫描路径；`check-docs` 通过 | `check-docs: OK (978 relative links in 179 files, ...)` |
| E29-11 | 满足 | `lib/std/README.md`（两条路径自动预解析、免 `ct get`、`Vec` 源码引用）；未改 `ct-pkg`、未改 `.trae/mcp.json`；四种语法糖的实测结论见 §8 O10 | 见 O10 的原始命令与退出码 |
| E29-12 | 满足 | 新增 `test/ast/errors/generic_builtin_arity.ct`（`Vec<int, int>`）与 `generic_struct_user_arity.ct`（`Stack<int, int, int>`）；`p29 (E29-12 same arity text)` 断言两者 `error: ` 后的文案逐字相同且等于 `a generic struct takes at most 2 type parameters`；`144` 断言 `Stack<int>` → `Stack_int`；`p29_generic_struct` 的 `.h` 断言同一形态 | `Expr.h.ct` 的实例实参检查把 over-arity 统一到冻结的 L29-2 文案（无内置特判）；两条负例均 exit 1 |
| E29-13 | 满足 | B1–B9 的样品/产物断言：`examples/23` + `144`（B1）、`examples/24` + `142` + `140`（B2）、`examples/22` + `141`（B3）、`examples/25`（B4）、`147`（B5）、`p29_generic_struct` + `generic_struct_pub_fn.ct`（B6）、`138/139` + 负例（B7）、`container_own/copy` + `142/143`（B8）、B9 明确不做并给出原因；每行有负例或产物断言，未用 `/tmp` 探针替代 | `test/run.sh` 137 / 0；`check-ast.sh` 962 / 0 |

本轮新增门禁断言（`949 + 13 = 962`）：`p29_diag` 钉住位置 + 单错（14 条，替代原先仅 grep 文案）、
`p29 (E29-12 same arity text)`、6 条 `check/build agree`、`p29 (two instances, two distinct tags)`、
`p29 (Map: two builds and two runs agree)`；另加 2 条负例进入 corpus 的通用负例扫描。

```text
$ bash selfhost/check-all.sh
== summary: 137 passed, 0 failed ==      (test/run.sh)
== summary: 82 passed, 0 failed ==       (goldens)
== summary: 962 passed, 0 failed ==      (check-ast)
check-warnings: 321 ok, 0 failed
check-docs: OK (978 relative links in 179 files, v0.26.4, 11 hard gates, 12 phase status, 3 适用版本 header(s))
acceptance: 20 pass, 0 new, 0 pending, 0 regression
check-all: OK (11 hard gates green)
```

> 上表是 Phase 29 收口轮的数字。NO-GO 修复块（V29-1…V29-5、`p29_neg` 的四重断言、`142` 的
> 句柄语义调整）落地后再跑一轮，实测为 `check-ast.sh` **992 passed / 0 failed**；
> V29-4b（下标基座按表达式类型判定，新增 4 条夹具）后再跑一轮为 **1000 passed / 0 failed**，
> `check-warnings.sh` **323 ok**、`check-docs` **OK（984 links / 179 files）**、
> `test/run.sh` **139 passed / 0 failed**、goldens 82、acceptance 20/0，完整转录见 §11.3。

`sanitizer` 单独跑，失败 10 项、通过 319 项；10 项全部为既有问题，与 Phase 29 无关：

| 失败项 | 原因 | 与 29 的关系 |
| --- | --- | --- |
| `66_type_host_literals` / `67_type_alias` / `81_closure_no_typehost` / `120_map_each_closure` / `121_map_each_closure_var` / `122_map_each_tier1` / `130_generic_build_mode` / `131_generic_cross_unit`（8 项） | 夹具含 `import`，sanitizer 脚本用单文件 compile 模式调用，报 `'import' requires multi-file mode: use 'ct build'` | 脚本调用方式问题；这 8 个在 `check-ast.sh` 的 build 段全部通过 |
| `examples/json/json.ct` | ASAN/UBSAN 下 end-to-end 第 2 阶段失败（示例本身，无 `Vec`/`Map`） | 与 29 无关；示例不含本相语法 |
| `range_init_overflow` | ct-ast 崩溃（exit 134），Phase 24 的既有夹具 | 与 29 无关；`138`–`147` 的 range/容器夹具均通过 |

```text
$ bash selfhost/check-sanitizers.sh
check-sanitizers: FAIL (10 failed, 319 passed)
```

---

## 11. 补丁判据 P29（用户授权，2026-11-11）

### 11.1 授权、范围与冻结关系

用户 2026-11-11 裁定：`Vec<int> v = 4..8 { $ * $ }` 方向**不立 Phase 30，放进 Phase 29 作为补丁**，
并按「§1 冻结的 E29 判据原文不动、仿 phase26 §9 追加补丁判据」的口径执行。

- **为什么不是改写判据**：§1.1 的判据冻结约束的是「E29-1…E29-13 与 L29-1…L29-18 在首个实现提交前
  冻结，此后只向判据靠拢」。本节**没有修改、放宽或重排任何一条已冻结判据的文本**，也没有新增 L29；
  它是同一相内追加的一段判据（P29-x），与 [phase26.md §9](phase26.md) 的补丁做法一致。因此本相的
  验收状态 = 「E29-1…E29-13 全满足（§10.3.5）」∧「P29-1…P29-5 全满足（§11.2）」。
- **补丁范围**：`selfhost/ct-ast/frontend/parse/Stmt.h.ct`（`range_vec_target` / `parse_range_init`）、
  `frontend/parse/Expr.h.ct`（`inst_static_method` / `static_call_ahead` / `parse_primary`）、
  `frontend/parse/Parser.h.ct`（`impl` 体的 `static` 标记）、`backend/emit/Emitter.h.ct`
  （`emit_range_init` 的构造形态、静态方法发射、`N_MCALL aux 11`）、`lib/std/Vec.h.ct`
  （`static Vec<T> from`）、`examples/26_range_vec/`、`test/ast/errors/range_vec_*.ct`（4 条）、
  `selfhost/check-ast.sh`（P29 块）、`examples/README.md`、本文件。L0/L1/L2 未动。
- **收口评审后的补丁块（V29-1 / V29-2）**：`lib/std/Vec.h.ct`（字符串键 impl 块、`release` 清空
  句柄）、`backend/emit/Emitter.h.ct`（`impl_method_shadowed`）、`frontend/parse/Expr.h.ct`
  （L29-8 白名单检查）、`examples/27_map_keys/`、`test/ast/errors/map_key_bad.ct`、`selfhost/check-ast.sh`
  （`p29 V29-1` / `p29 V29-2` 块）。
- **B29-3 仍然有效**：编译器只读实例行里的 `tmpl` / `nargs` / `ctype[0]` / `name`，即
  「这是不是 `Vec`、元素 C 类型是什么、入口叫什么」；`Vec` 的字段、引用计数与分配策略只在
  `lib/std/Vec.h.ct` 的 `from` 里。语法糖产出的 C 里没有任何由编译器生成的 `->h` / `->data`。

### 11.2 判据与逐条证据

| # | 判据 | 证据锚点 | 实跑 |
| --- | --- | --- | --- |
| P29-1 | **range 初值可以构造 `Vec<T>`**：`Vec<int> v = 4..8 { $ * $ };` 编译、运行、输出逐字节匹配；产物是「复合字面量 + 构造入口」，即 `Vec_int_from((int[4]){ … }, 4)`；同时 `$` 仍只属于元素表达式 | `examples/26_range_vec/range_vec.ct` + `range_vec.expected.out`；`check-ast.sh` 的 `p29 P29-1` 断言（生成 C 含 `Vec_int_from((int[4]){ `、`cc -Wall -Wextra` 零告警、`diff` 期望输出）；`test/run.sh` 的 examples 扫描把该目录纳入真门禁 | `ok p29 P29-1`；`test/run.sh` 138 / 0；生成行见 §11.3 |
| P29-2 | **内置 `Vec` 有「从数组构造」的入口，且可从源码调用**：`impl<T> Vec<T>` 内的 `static Vec<T> from(T *items, int n)` 落成 `Vec_<enc>_from`（无 `self` 参数）；调用面 `Vec<int>::from(arr, n)` 可用；`static` 方法不参与实例方法解析，实例方法也不被 `::` 解析；`static` 出现在 `use Trait` 块内硬错（vtable 槽位需要接收者） | `lib/std/Vec.h.ct` 的 `from`；`Parser.h.ct` 的 `static` 分支与 `a static method cannot implement a trait`；`Expr.h.ct` 的 `inst_static_method`（只认 `c == 1`）；`Emitter.h.ct` 的 `N_MCALL aux 11` | 样例第 3 段直接调用 `Vec<char *>::from(names, 3)`，输出 `a b c`；生成 `Vec_char_p_from(names, 3)` |
| P29-3 | **编译器不认识 `Vec` 的布局**：`range_vec_target` 只看实例行的类型实参与名字；`from` 的实现全在 `lib/std/Vec.h.ct`；把 `Vec` 的字段改掉不需要改编译器 | `Stmt.h.ct` 的 `range_vec_target`（`strpbrk(base, " *[(")` 排除指针/数组，`tmpl == "Vec"`、`nargs == 1`）；`Vec.h.ct` 的 `from` 内部 `malloc` / `memcpy` / `refs/len/cap` 赋值 | 生成 C 的构造点只有 `Vec_int_from((int[4]){ … }, 4)`，语法糖不展开任何字段 |
| P29-4 | **边界与作用域各一条负例**，均位置化、单条、无 `undeclared` 回落：`$` 只能在元素表达式内；空 range 硬错；超过 1024 个元素硬错；`Map` 目标保持 Phase 24 文案 | `test/ast/errors/range_vec_index_scope.ct` / `range_vec_empty.ct` / `range_vec_too_many.ct` / `range_vec_map_target.ct`；`check-ast.sh` 的 `p29_neg` 四条断言（逐字文案 + `line:col` + 只允许一条 `error:` + 不出现 `undeclared`） | 4 条 `ok`：`unexpected token`、`an empty range has no elements`、`too many range elements (limit 1024)`、`a range initializer declares an array` |
| V29-1 | **`Map` 的键按类型分派，白名单外的键硬错**：`int` / `long` 比字节、`char *` 比 `strcmp`，不以 `sizeof` 判断键类别；`Map` 的第一个类型实参不在白名单时报 L29-8，位置化且不落任何 C；两个匹配同一实例的固有 impl 不重复发射同名方法 | `lib/std/Vec.h.ct` 的 `impl<V> Map<char *, V>`（声明在泛型块之前）与纯 `memcmp` 的 `impl<K, V> Map<K, V>`；`Emitter.h.ct` 的 `impl_method_shadowed`；`Expr.h.ct` 的 L29-8 检查 | `test/ast/errors/map_key_bad.ct`（`6:20` + 逐字文案）；`examples/27_map_keys/` 三种键端到端；`check-ast.sh` 的 `p29 V29-1` 断言（`Map<long,int>` 产物无 `strcmp`；`Map_char_p_int_put/get` 各一份定义） |
| V29-2 | **释放后的句柄不能二次 `release`**：`release()` 无论计数是否归零都清空该句柄；`retain` 出的兄弟句柄仍可读，对同一句柄二次 `release` 是 `abort`，不会把兄弟句柄的缓冲再减一次 | `lib/std/Vec.h.ct` 的 `Vec::release` / `Map::release`；`examples/24_vec_ops` 的共享句柄段 | `check-ast.sh` 的 `p29 V29-2` 断言（程序非零退出、`Vec: release on a released handle`、释放后 `sibling 1` 仍可读） |
| V29-3 | **经典 `impl Trait for Struct` 里的 `static` 是硬错**：vtable 槽位没有接收者，`static` 不能被当成返回类型限定符后只告警、仍装进 vtable | `Parser.h.ct` 的经典 impl 方法循环（在 `parse_type` 之前拦 `static`） | `test/ast/errors/impl_static_trait.ct`（`13:5` + 逐字文案）；`check-ast.sh` 的 `p29_neg` 断言（文案 + 位置 + 单条） |
| V29-4 | **容器下标与花括号初值给出可读诊断**：`v[i]`、`m[k]`、`Map<...> x = {…}` 一律编译期报错并指出位置，不再把 `subscripted value is not an array` / `expected expression` 甩给 `cc`；**下标基座按表达式类型判定**，不是只认裸变量 | `Expr.h.ct` 的 `container_base_type`（解析 `N_VAR` / `N_DEREF` / `N_MEMBER` / `N_ARROW` / `N_CALL` 的 C 类型）→ `container_index_check` / `container_init_check`（`parse_postfix` 的 `[`、局部/全局声明初值、复合字面量三处调用） | `test/ast/errors/vec_subscript.ct`（`9:13`）、`map_subscript.ct`（`8:13`）、`map_brace_init.ct`（`5:26`），以及 `vec_subscript_deref.ct`（`(*pv)[0]`，`7:17`）、`vec_subscript_member.ct`（`h.v[0]`，`9:15`）、`vec_subscript_call.ct`（`mk().v[0]`，`14:18`）、`map_subscript_deref.ct`（`(*pm)["k"]`，`7:17`）；`check-ast.sh` 的 `p29_neg` 断言 |
| V29-5 | **L29-13 的容器元素检查落地**：接口值与带 vptr 的 struct（含值字段递归）不能进 `Vec` / `Map`；`use Drop` / `use Handback` 不误伤 | `Expr.h.ct` 的 `container_vptr_type` + `inst_make` | `test/ast/errors/container_iface.ct`（`19:15`）、`container_vptr_struct.ct`（`13:14`）；`check-ast.sh` 的 `p29_neg` 断言 |
| P29-5 | **既有行为不回归**：Phase 24 的 `0..3($)` 数组形态、`check-goldens`、`check-warnings`、`check-docs` 与 E29 的 13 条证据全部维持 | `test/ast/errors/range_init_*` 与 `test/ast/1xx` 的 range 夹具照旧；`range_init_overflow` 仍报 `a range bound is out of range`（本轮手动复核） | `check-goldens: OK`、`check-warnings: 323 ok`、`check-docs: OK (984 links / 179 files)`、`check-ast: 1000 / 0` |

### 11.3 补丁后的产物与门禁

`examples/26_range_vec/range_vec.ct` 的两行生成 C（单文件模式，`Vec.h` 内联）：

```c
static __attribute__((unused)) struct Vec_int Vec_int_from(int * items, int n) { … }
    struct Vec_int sq = Vec_int_from((int[4]){ (((int)4) * ((int)4)), (((int)5) * ((int)5)), (((int)6) * ((int)6)), (((int)7) * ((int)7)) }, 4);
    words = Vec_char_p_from(names, 3);
```

```text
$ bash selfhost/check-all.sh
== summary: 139 passed, 0 failed ==      (test/run.sh, 补丁前 137)
== summary: 82 passed, 0 failed ==       (goldens)
== summary: 1000 passed, 0 failed ==     (check-ast, 补丁前 962；V29-4b 前 992)
check-warnings: 323 ok, 0 failed         (补丁前 321)
check-docs: OK (984 relative links in 179 files, v0.26.4, 11 hard gates, 12 phase status, 3 适用版本 header(s))
acceptance: 20 pass, 0 new, 0 pending, 0 regression
check-all: OK (11 hard gates green)
```

上面是 2026-11-11 修复块的最终实跑（与 §10.3.5 末尾的说明一致）；链接数随之从补丁前的 978
升到 **984**，`check-docs` 仍为 OK。

`sanitizer` 单跑仍是同样的 10 项既有失败，`passed` 从 319 升到 323（新增 4 条负例全部 `ok`）：

```text
$ bash selfhost/check-sanitizers.sh
check-sanitizers: FAIL (10 failed, 323 passed)
```

| 失败项 | 与 P29 的关系 |
| --- | --- |
| `66` / `67` / `81` / `120` / `121` / `122` / `130` / `131`（8 项） | 脚本用单文件模式调用含 `import` 的夹具，报 `'import' requires multi-file mode`；与补丁无关 |
| `examples/json/json.ct` | ASAN/UBSAN 下示例端到端第 2 阶段失败；示例不含 range / `Vec` 构造 |
| `range_init_overflow` | Phase 24 既有夹具，sanitizer 下 exit 134；非 sanitizer 构建仍正确报 `a range bound is out of range`（本轮已复核） |

### 11.4 仍未支持（与 §8 O10 对齐）

`v[3]`、`m["key"]` 与 `Map<char *, int> m = { "key": 32, "key2": 869 };` **仍不支持**：两条下标形态
指向的 `struct Vec_int` / `struct Map_char_p_int` 不能下标，字面量形态的 `:` 不在 C 聚合初值语法里。
V29-4 之后它们不再静默通过：三条都在编译期给出位置化诊断（见 §11.2 V29-4），不放行、不发射 C；
下标基座按表达式类型判定，`(*pv)[0]`、`h.v[0]`、`mk().v[0]`、`(*pm)["k"]` 与裸变量同一处文案。
新增语法不在本补丁范围内。
