# 受限语义检查 · 设计 spike

> 中文 · [English](#english)
> 状态：**spike 完成，结论 GO（限定范围）** · 2026-11-02
> 锚点：工作树 `v0.16.3`；行为探针用已安装的 `ct v0.16.2`
> 落点：[history/design/phase19.md](../history/design/phase19.md)

---

## 中文

### 1. 要回答的问题

「加一层轻量语义检查」是否可行？拆成三个子问题：

1. **数据够不够**：签名、参数类型、接收者类型是否已在符号表 / AST 里？
2. **现有覆盖到哪**：哪些检查其实已经做了？
3. **误报风险多大**：CT 允许 C 直通、宏、`.m.ct` recipe，检查器能否不误伤？

### 2. 方法

黑盒探针 4 例（`ct compile <file> -o <file>.c`）+ 代码核对。探针文件放在 `/tmp`，不进入仓库。

| 探针 | 输入 | 实测结果 | 含义 |
| --- | --- | --- | --- |
| 方法不存在 | `struct S s; s.missing();` | `spike-method.ct:8:1: error: no method 'missing' for type 'struct S'`，exit 1 | **已有**方法存在性检查 |
| impl 与 trait 签名不一致 | trait 声明 `f(int)`，impl 写 `f()` | `warning: signature mismatch … takes 0 parameter(s), the trait declares 1`，**exit 0** | 已有检查，但只是**警告**，不阻断 |
| 调用点少传参 | impl `f(int)`，调用 `s.f()` | exit 0，生成 `s.__t_vptr->f(&s);` | **缺口**：调用点 arity 不查 |
| 普通函数少传参 | `int add(int a,int b)`，调用 `add(1)` | exit 0 | **缺口**：函数调用 arity 不查 |

CLI 探针：`ct --help` 只有 `compile` 形态，**没有 `check` 模式**。

### 3. 已有覆盖（不需要重做）

- 方法存在性：[Emitter.h.ct:2693](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2693)（`no method '%s' for type '%s'`）。
- impl ↔ trait 签名不匹配：[Parser.h.ct:2056](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2056)，经 [Diag.h.ct:192](../../selfhost/ct-ast/tool/diag/Diag.h.ct#L192) 打印。
- 字段存在性：[Expr.h.ct:1438](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1438)。
- `impl` 完整性：[Parser.h.ct:2123](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2123)。
- map 绑定参数个数：[MapBuild.h.ct:735](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct#L735)。
- **数据已在**：`Fn.ptype[16][160]` / `nparams`（[Symbols.h.ct:40-45](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L40-L45)）、`MethodSig.ptype[16][160]` / `nparams`（[:96-98](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L96-L98)）、实参链 [Expr.h.ct:1162-1167](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1162-L1167) / [:1260-1263](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1260-L1263)。

### 4. 缺口

1. **调用点 arity**：函数与 trait 方法都未查；签名不匹配只是警告。
2. **实参类型兼容**：目前没有按 `ptype` 比对；不做推断，只做粗粒度（精确名 / 指针层级 / struct / interface）。
3. **歧义**：多 trait 同名方法静默取首个（SH-46）。
4. **跨单元签名漂移**：导入单元的导出签名是否与本地 impl 一致，未统一核对。
5. **入口与严重度**：没有 `ct check`；无法把「检查」与「产物」分离。

### 5. 风险

- **误报**：C 直通、宏调用、`.m.ct` recipe、raw 块没有 CT 类型，必须一律视为 `unknown` 并跳过，不能猜。
- **类型表示是字符串**：`expr_type` 对普通 vtable 调用返回 `-1`；19.x 只对能确定的实参做比对，其余跳过。
- **自举**：检查器只能落在 `ct-ast`，不得要求 `ct-ast` 源码使用新语法；`L2` 仍要能编译它。

### 6. 结论

**GO，但限定范围。** 不是从零加一层，而是把已有的 `Parser` / `Emitter` / `Diag` 检查补齐成「调用点 + 类型 + 歧义 + 跨单元」四块：

- 代码增量约 **+700–1,300 行（4–8%）**，4 个切片（见 [phase19.md](../history/design/phase19.md)）。
- 不做完整类型系统，不做泛型，不改变 `ct compile` / `ct build` 的产物与默认退出码。

### 7. 出口（spike 验收）

- 383 个 `.ct` 文件、9,649 行语料（`test` / `examples` / `std` / `bindings`）上**零误报**；
- 能捕获上表 4 个探针（缺少方法已捕获，其余三类在 19.1 后捕获）；
- 11 道硬门禁与 `ct compile` / `ct build` 产物不变。

---

## English

### 1. Question

Is a bounded semantic-check layer feasible? Three sub-questions: is the data present, what is already covered, and how high is the false-positive risk?

### 2. Method

Four black-box probes with `ct compile` plus a code review. Probe files live in `/tmp` and never enter the repository.

| Probe | Input | Observed | Meaning |
| --- | --- | --- | --- |
| missing method | `struct S s; s.missing();` | `no method 'missing' for type 'struct S'`, exit 1 | **already checked** |
| impl/trait signature mismatch | trait `f(int)`, impl `f()` | `warning: signature mismatch …`, **exit 0** | checked, but only a warning |
| call-site arity | impl `f(int)`, call `s.f()` | exit 0, emits `s.__t_vptr->f(&s);` | **gap** |
| function arity | `add(int,int)`, call `add(1)` | exit 0 | **gap** |

`ct --help` exposes no `check` mode.

### 3. Already covered

Method existence ([Emitter.h.ct:2693](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2693)), impl/trait signature mismatch ([Parser.h.ct:2056](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2056)), field existence ([Expr.h.ct:1438](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1438)), impl completeness ([Parser.h.ct:2123](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2123)), map-binding arity ([MapBuild.h.ct:735](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct#L735)). Parameter types and counts are already stored in `Fn` and `MethodSig`.

### 4. Gaps

Call-site arity; coarse argument-type compatibility; trait-method ambiguity (SH-46); cross-unit signature drift; a separate `ct check` entry point and severity policy.

### 5. Risks

Pass-through C, macros, `.m.ct` recipes and raw blocks must be treated as `unknown` and skipped. Types are strings today; only decidable arguments are compared. The checker must live in `ct-ast` and must not require new syntax in `ct-ast` sources.

### 6. Verdict

**GO, bounded.** Roughly **+700–1,300 lines (4–8%)** across four slices. No full type system, no generics, no change to `ct compile` / `ct build` output or default exit codes. Plan: [phase19.md](../history/design/phase19.md).

### 7. Exit

Zero false positives on the 383-file / 9,649-line corpus; the four probes are caught; the 11 hard gates and generated artifacts stay unchanged.
