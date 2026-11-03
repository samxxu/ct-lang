# Phase 19 · 受限语义检查

> 中文 · [English](#english)
> **状态：完成**（2026-11-03，19.0–19.4 全部完成） · 版本：`v0.19.0`
> 前置：[spike-semantic-check.md](spike-semantic-check.md)（GO）；Phase 17 / 18 不阻塞本阶段

---

## 中文

### 1. 目标

在不改变「source-to-source、零运行时、零优化」定位的前提下，把 CT 声明实体的**解析与签名**检查补齐：

- 调用点参数个数（函数与 trait 方法）；
- 实参类型粗粒度兼容（精确名 / 指针层级 / struct / interface，不做推断）；
- 多 trait 同名方法的歧义（SH-46）；
- 跨单元签名漂移；
- 提供独立入口 `ct check`。

### 2. 非目标

- 不做完整类型系统、不做类型推断、不做隐式转换；
- 不做泛型（单态类型继续作为替代）；
- 不检查 C 直通、宏调用、`.m.ct` recipe、raw 块（一律 `unknown` 跳过）；
- 不改变 `ct compile` / `ct build` 的产物与默认退出码。

### 3. 现状与前置

- spike 已实测：方法存在性、impl↔trait 签名不匹配（警告）、字段、impl 完整性、map 绑定均已检查；缺口是**调用点 arity / 实参类型 / 歧义 / 跨单元**。
- 参数类型与个数已存储：`Fn.ptype` / `nparams`、`MethodSig.ptype` / `nparams`；实参链在 `N_CALL.a` / `N_MCALL.b`。
- 现有类型表示是字符串，`expr_type` 对普通 vtable 调用返回未知——因此只比较**能确定**的实参，其余跳过。

### 4. 切片

| 切片 | 内容 | 主要改动 | 出口 | 风险 |
| --- | --- | --- | --- | --- |
| **19.0** | 前置：`for` 首句 `static` 的发射改为自带块内的声明（标准 C99，不再依赖 GNU 扩展） | `backend/emit/Emitter` | `gcc -std=c99` 下 `37_empty_stmt` 通过；行为输出不变 | 作用域/缩进回归 |
| **19.1** | 调用点 arity：函数与 trait 方法；可变参、map 绑定路径不重复检查 | `Parser` / `Expr` / `TypeCheck` / `Diag` | 探针「`s.f()` 少参」「`add(1)` 少参」被捕获；383 文件零误报 | 误报；需 unknown 跳过 |
| **19.2** | 实参类型粗粒度兼容：精确名、指针层级、struct / interface；未知跳过 | `TypeCheck` / `Symbols` | 明显类型错配被捕获；无误报 | 字符串类型误判 |
| **19.3** | 歧义与跨单元：多 trait 同名方法（SH-46）报错；导入导出签名一致性 | `Symbols` / `Module` / `Parser` | SH-46 用例报错；跨单元签名负例通过 | 实例级 `map` 与静态映射的边界 |
| **19.4** | `ct check` 入口、`--diagnostics=json`、文档、门禁 | `Driver` / `Diag` / docs / `test/semantics` | CLI 可用；第 12 道门禁接入；中英文档同步 | 入口重复、退出码约定 |

### 5. 顺序与依赖

19.0 → 19.1 → 19.2 → 19.3 → 19.4。19.0 先清掉标准 C 的潜在红项（gcc 收紧时不再翻车），其余顺序不变；19.2 依赖 19.1 的调用点解析；19.3 依赖 19.1 的方法解析；19.4 最后接入门禁。每片独立可回退。

> **19.1 落地形态**：调用点 arity 在 `ct compile` / `ct build` 里以**警告**报告（`warning: arity mismatch: '<callee>' takes N argument(s), M given`），因此两处的产物与默认退出码不变；`ct check`（19.4）再把同一条记录提升为 error。只有解析到签名的被调者才比较：函数指针、未声明的 C 库名、`map` recipe、静态类型宿主一律视为未知并跳过；可变参函数只校验具名参数的下界。两个探针落点：`add(1)` 与 `s.area()`（trait 方法少参）。

> **19.2 落地形态**：实参类型按位比对在 `ct compile` / `ct build` 里以**警告**报告（`warning: type mismatch: '<callee>' argument K: expected '<formal>', got '<actual>'`），与 19.1 同一严重度策略（D19-4）。粗粒度规则：去限定词 / 去空白后精确相等即过；数值类之间（含 `enum`）总是放行；指针层级必须一致，`void *` 双向放行；struct 指针只有在双方都能在本单元符号表中解析且解析到**不同** struct 时才报；typedef、union、函数指针拼写、iface 形参（boxing 已有硬错误）、数组双方（decay）、cast 实参、无法推导的实参一律按 unknown 跳过（D19-3）。每次调用至多报第一个错配位。探针：函数 `setp(&q)` 与 trait 方法 `s.put(&q)` 的 struct 指针错配。

> **19.3 落地形态**：两条检查都以**警告**报告（D19-4），`ct compile` / `ct build` 的产物与退出码不变。**歧义（SH-46）**：裸调用解析到的 trait 之外，宿主 struct `use` 的另一个 trait 也声明同名方法时，报 `warning: ambiguous method: '<m>' declared by '<A>' and '<B>'; '<A>' is used`（`Symbols.method_trait_amb`）；消解仍按 `use` 顺序取首个——`test/cases/06_name_collision.ct` 已把该语义钉成回归，故语料断言是「恰好一条歧义警告、来自该文件」，而非零条。接口变量派发与静态类型宿主 / `map` 绑定不经过 `method_trait`，不参与判定。**跨单元签名漂移**：impl↔trait 的既有核对（返回类型、参数个数，措辞与 L2 逐字一致）之外，新增**参数类型**按位粗粒度比对，复用 19.2 的 `arg_class` 规则（`Expr.decl_type_compat`），报 `warning: signature mismatch: '<m>' in impl of '<T>' for '<S>': parameter K type '<impl>' does not match the trait's '<decl>'`；trait 在共享表中，导入单元与本单元走同一条路径，「导入导出一致性」由此统一覆盖。数组形参（decay）与不可判定拼写一律跳过（D19-3）；每个方法至多报第一个错配位。

> **19.4 落地形态**：`ct check <file>` 走 compile 的解析路径，解析成功后**直接输出诊断并返回**，不写 `.c`（即便给了 `-o`）；退出码「有任何发现为 1，干净为 0」。D19-4 的严重度在此生效：`Diag.set_strict` 让同一批记录在文本模式读 `error:`、在 JSON 对象的首字段带 `"severity":"error"`；`ct compile` / `ct build` 不设 strict，文本仍是 `warning:`、JSON 逐字节不变。`--diagnostics=json` 沿用既有开关（compile 到 stdout、build 到 stderr，check 到 stdout）。第 12 道硬门禁 [check-semantics.sh](../../selfhost/check-semantics.sh) 构建自举链后断言 8 项：干净单元 0 且无输出、四类发现（arity / 实参类型 / 歧义 / impl 参数漂移）各 exit 1 且读 `error:`、JSON 可解析且含 severity/type、同一单元走 compile 仍 exit 0 且写 C 且读 `warning:`、check 不产生 C 产物。

### 6. 版本与发布

- 阶段号 **Phase 19 ↔ `v0.19.0`**，收口时 bump；切片期间不 bump。
- 若 19.x 需要 patch，按 `v0.19.n` 递增，不改变阶段号。

### 7. 全局 DoD

- 383 个 `.ct` 文件 / 9,649 行语料**零误报**；
- 4 个探针（缺方法、impl 签名、调用点 arity、函数 arity）全部有明确诊断；
- `ct check` 退出码：有错为 1，干净为 0；`ct compile` / `ct build` 产物与默认退出码不变；
- 12 道硬门禁全绿；`check-ast` 行为等价不受影响；
- 不改 L0 / L1 / L2；文档中英双语。

### 8. 决策

| 编号 | 决策 | 取值 | 状态 |
| --- | --- | --- | --- |
| **D19-1** | 检查范围 | 只做解析与签名层，不做完整类型系统 / 推断 / 泛型 | ✅ 已确认 |
| **D19-2** | 入口形态 | `ct check` 可选；`ct compile` / `ct build` 行为不变 | ✅ 已确认 |
| **D19-3** | 未知构造 | C 直通、宏、`.m.ct` recipe、raw 一律跳过，绝不猜测 | ✅ 已确认 |
| **D19-4** | 严重度 | `ct check` 中 arity / 类型 / 歧义为 error；`ct compile` 维持现状 | ✅ 已确认 |
| **D19-5** | 泛型 | 不在 Phase 19；继续用单态具体类型 | ✅ 已确认 |

### 9. 风险

| 风险 | 影响 | 缓解 |
| --- | --- | --- |
| 误报挡住合法代码 | 高 | 未知即跳过；383 文件零误报作为硬出口 |
| 字符串类型表示 | 中 | 只比可判定项；19.2 不做推断 |
| 实例级 `map` 与静态映射 | 中 | 歧义检查区分 trait 声明与 map 绑定 |
| 自举约束 | 中 | 检查器只落 `ct-ast`；`ct-ast` 源码不用新语法 |

---

## English

### 1. Goal

Add **resolution and signature** checks for CT-declared entities without changing the source-to-source, zero-runtime, zero-optimization positioning: call-site arity for functions and trait methods; coarse argument-type compatibility (exact name / pointer depth / struct / interface, no inference); trait-method ambiguity (SH-46); cross-unit signature drift; and a separate `ct check` entry point.

### 2. Non-goals

No full type system, inference, implicit conversions, or generics; no checks over C passthrough, macros, `.m.ct` recipes or raw blocks (always `unknown`, skipped); no change to `ct compile` / `ct build` output or default exit codes.

### 3. Current state

The spike proved that method existence, impl/trait signature mismatch (warning), field existence, impl completeness and map-binding arity are already checked. The gaps are call-site arity, argument types, ambiguity and cross-unit signatures. Parameter types and counts are already stored in `Fn` and `MethodSig`; types are strings today, so only decidable arguments are compared.

### 4. Slices

| Slice | Content | Touch points | Exit | Risk |
| --- | --- | --- | --- | --- |
| **19.0** | prerequisite: emit a `for`-init `static` as a declaration inside its own block (standard C99, no GNU extension) | `backend/emit/Emitter` | `37_empty_stmt` passes under `gcc -std=c99`; program output unchanged | scope/indent regressions |
| **19.1** | call-site arity for functions and trait methods; variadics; no duplicate map-binding checks | `Parser` / `Expr` / `TypeCheck` / `Diag` | both arity probes caught; zero false positives on 383 files | false positives; need `unknown` skip |
| **19.2** | coarse argument-type compatibility | `TypeCheck` / `Symbols` | clear mismatches caught; no false positives | string-based types |
| **19.3** | ambiguity (SH-46) and cross-unit signature drift | `Symbols` / `Module` / `Parser` | SH-46 case errors; cross-unit negative case passes | instance-level `map` edges |
| **19.4** | `ct check`, `--diagnostics=json`, docs, gate | `Driver` / `Diag` / docs / `test/semantics` | CLI works; 12th gate wired; bilingual docs | entry duplication, exit codes |

### 5. Order

19.0 → 19.1 → 19.2 → 19.3 → 19.4. 19.0 first removes the standard-C hazard so a stricter gcc cannot trip it; each slice is independently revertible.

> **How 19.1 lands**: a call-site arity mismatch is reported as a **warning** (`warning: arity mismatch: '<callee>' takes N argument(s), M given`) so `ct compile` / `ct build` keep their artifacts and default exit codes; `ct check` (19.4) raises the same record to an error. Only a callee whose signature resolved is compared — function pointers, undeclared C library names, `map` recipes and static type hosts stay unknown and pass; a variadic function checks only the lower bound of its named parameters. Probes: `add(1)` and `s.area()` (a trait method with a missing argument).

> **How 19.2 lands**: an argument type is compared positionally against the resolved signature and reported as a **warning** (`warning: type mismatch: '<callee>' argument K: expected '<formal>', got '<actual>'`), same severity policy as 19.1 (D19-4). The coarse rules: qualifier- and whitespace-normalised equality passes; numerics (including `enum`) always pass; pointer depths must match, with `void *` accepted both ways; a struct pointer is reported only when both tags resolve in the unit's own table to *different* structs. Typedefs, unions, function-pointer spellings, interface formals (boxing already errors), arrays on either side (decay), cast arguments and underivable arguments stay unknown and pass (D19-3). At most the first mismatching position is reported per call. Probes: `setp(&q)` (function) and `s.put(&q)` (trait method), each handed the wrong struct pointer.

> **How 19.3 lands**: both checks report **warnings** (D19-4), so `ct compile` / `ct build` keep their artifacts and default exit codes. **Ambiguity (SH-46)**: when a trait other than the resolved one also declares the method on the receiver's struct, the bare call warns `warning: ambiguous method: '<m>' declared by '<A>' and '<B>'; '<A>' is used` (`Symbols.method_trait_amb`); resolution still takes the first match in `use` order -- `test/cases/06_name_collision.ct` pins that behaviour, so the corpus gate asserts *exactly one* ambiguity warning, from that file, rather than zero. Interface-variable dispatch and static type hosts / `map` bindings never pass through `method_trait` and stay out of the check. **Cross-unit signature drift**: the existing impl/trait comparison (return type, parameter count; wording byte-identical to L2) now also compares **parameter types** positionally, reusing 19.2's `arg_class` rules (`Expr.decl_type_compat`), and reports `warning: signature mismatch: '<m>' in impl of '<T>' for '<S>': parameter K type '<impl>' does not match the trait's '<decl>'`. The trait lives in the shared table, so an imported unit and the local unit take the same path -- which is what "import/export consistency" means here. Array parameters (decay) and undecidable spellings pass as unknown (D19-3); at most the first mismatching position is reported per method.

> **How 19.4 lands**: `ct check <file>` walks compile's parse path and **returns right after parsing**, reporting the findings and writing no `.c` (even when handed `-o`); the exit code is 1 on any finding and 0 when clean. D19-4's severity takes effect here: `Diag.set_strict` makes the same records read `error:` in text mode and carry `"severity":"error"` as each JSON object's first field, while `ct compile` / `ct build` never set strict -- their text stays `warning:` and their JSON is byte-identical. `--diagnostics=json` reuses the existing switch (compile to stdout, build to stderr, check to stdout). The 12th hard gate, [check-semantics.sh](../../selfhost/check-semantics.sh), builds the bootstrap chain and asserts 8 items: a clean unit exits 0 silently; each of the four finding classes (arity, argument type, ambiguity, impl parameter drift) exits 1 and reads `error:`; the JSON document parses and carries severity/type; the same unit through compile still exits 0, warns, and writes its C; and check produces no C artefact.

### 6. Version

Phase 19 ↔ `v0.19.0`, bumped at close; patches use `v0.19.n`.

### 7. Global DoD

zero false positives on the 383-file / 9,649-line corpus; all four probes diagnosed; `ct check` exits 1 on errors and 0 when clean; `ct compile` / `ct build` artifacts and default exit codes unchanged; 12 hard gates green; `check-ast` behavioral equivalence unaffected; no L0 / L1 / L2 changes; bilingual docs.

### 8. Decisions

D19-1 bounded resolution/signature scope only; D19-2 `ct check` optional, compile/build unchanged; D19-3 unknown constructs skipped; D19-4 errors in `ct check` only; D19-5 no generics in Phase 19. All confirmed.

### 9. Risks

False positives (mitigated by `unknown` skip and the zero-false-positive gate), string-based types (only decidable cases compared), instance-level `map` edges (ambiguity checks distinguish trait declarations from map bindings), and the self-hosting constraint (checker lives in `ct-ast`, no new syntax in its own sources).
