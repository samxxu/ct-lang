# 全局变量 mangling 与限定引用

> 中文 · [English](#english)
>
> **状态：已获用户批准（2026-10-22），本文件是该批次的实现依据。**
> 锚点：commit `c554d10`（v0.12.0，2026-10-22）。
> 前置：Batch 2（[batch2-cross-unit-oo.md](batch2-cross-unit-oo.md)）已落地，`pub` 全局与跨单元
> vtable 可用；本批次只补 Batch 2 / 2b.3 留下的那处偏差。

## 中文

### 1. 问题

Batch 2 的 2b.3 规定 `map trait T for instance A::B::h` 的 C 名是 `A_B_h`，但实现时全局变量
**不做 mangling**，限定写法只被"接受并取最后一段"。后果有两层：

- 两个命名空间不能各有一个同名全局：`a::h` 与 `b::h` 都会发射 `int h;`，链接期重复符号；
- `map` 派生的 vtable / 包装函数名（`<inst>_<Trait>_vtable`）因此也不含命名空间，同名实例会撞名。

### 2. 规则

1. **命名空间内的全局变量按命名空间 mangling**：`namespace A::B; int h;` 发射 `A_B_h`。
   规则与类型名、`pub` 函数一致（前缀用 `_` 连接，末尾带 `_`）。
2. **`extern` 豁免**：`extern int lib_flag;` 声明的符号属于 C 库，保留原名，命名空间记为空。
3. **限定引用**：表达式里的 `a::h` 解析到该命名空间的导出全局；只有一个候选时裸名照常可用。
   两个被导入的命名空间导出同名全局时，裸名报
   `variable 'h' is exported by more than one namespace; use a qualified name`。
4. **`map` 跟随实例的 C 名**：vtable 名为 `<实例 C 名>_<Trait>_vtable`，包装函数为
   `<实例 C 名>_<Trait>_<方法>`；包装函数体里引用的全局按 C 名重写（`.` / `->` 后的成员名、
   字面量不参与）。

### 3. 实现要点

- `Var` 增加 `cname` / `ns` / `is_global` / `imported` / `ambiguous`：`name` 仍是源码名，
  `cname` 是发射用的 C 名，`ns` 是下划线形式的声明命名空间。
- 导入单元在加载时把依赖单元的 `pub` 全局按同样的 mangling 规则登记；两处同名且 C 名不同即标歧义。
- 表达式节点把全局的 C 名放在 `N_VAR.text3`，发射器优先用它；文件作用域声明由
  `emit_global_decl` 统一拼 `<prefix><name>`（`extern` 不拼）。
- 单元记录新增 `nsprefix`（mangled 形式），`write_unit_c` / `write_unit_header` 写单元前设置发射器
  的 `gprefix`；compile 模式取 `sym->ns`。

### 4. 非目标

- 不做命名空间限定的**类型**名（仍用 `import a::b::T as T;`）。
- 不改变 `static` 全局的链接属性（它们仍单元私有）；他们同样按命名空间 mangling，保持规则单一。
- 不引入新的容量上限；`Var` 体积增大，但符号表是静态存储，`MAX_VARS` 不变。

### 5. 验收

| 项 | 验收 |
| --- | --- |
| mangling | `test/modules/ns_globals`：`a.h` 含 `extern int a_h;`、`a.c` 含 `int a_h = 1;`，两个命名空间的 `h` 互不干扰，运行输出正确 |
| 限定引用 | 同上，消费单元用 `a::h` / `b::h` 读写 |
| 歧义 | `test/modules/ambig_global` 必须非零退出，诊断含 `exported by more than one namespace` |
| map | `test/modules/map_ns` 的 vtable 名为 `hal_uart1_hal_Writer_vtable`，包装函数体引用 `hal_uart1` |
| 回归 | `bash selfhost/check-all.sh` 九关全绿、零 `FAIL`；`git status` 不出现 `test/cases/**`、`examples/**` 的 `.expected.*` 变化 |

---

## English

**Status: approved by the user (2026-10-22); this file is the implementation baseline.**
Anchor: `c554d10` (v0.12.0, 2026-10-22). Prerequisite: Batch 2 has landed.

### 1. Problem

2b.3 asked for the C name `A_B_h` for `map trait T for instance A::B::h`, but the implementation did not
mangle globals at all: the qualified spelling was accepted and reduced to its last segment. Two things
follow: two namespaces cannot each declare `h` (both emit `int h;`, a duplicate symbol), and the map's
derived names (`<inst>_<Trait>_vtable`, wrappers) carry no namespace, so same-named instances collide.

### 2. Rules

1. A global inside a namespace is **mangled** by that namespace: `namespace A::B; int h;` emits `A_B_h`,
   the same prefix rule types and `pub` functions follow.
2. **`extern` is exempt**: `extern int lib_flag;` names a symbol the C library owns, so it keeps its own
   spelling and an empty namespace.
3. **Qualified references**: `a::h` in an expression resolves to that namespace's exported global; a bare
   name still works while only one candidate exists. Two imported namespaces exporting one name make the
   bare reference an error that asks for the qualified form.
4. **`map` follows the instance's C name**: the vtable is `<inst-cname>_<Trait>_vtable` and a wrapper is
   `<inst-cname>_<Trait>_<method>`; globals named in a wrapper body are rewritten to their C spelling,
   skipping member names after `.` / `->` and literals.

### 3. Implementation notes

`Var` gains `cname` / `ns` / `is_global` / `imported` / `ambiguous` (source name, emitted spelling,
underscore-form namespace, provenance). An importing unit registers its dependencies' `pub` globals under
the same mangling; two imports with different C names mark the name ambiguous. `N_VAR.text3` carries the
C spelling for the emitter, `emit_global_decl` composes `<prefix><name>` for file-scope declarations, and
each `Unit` records its mangled `nsprefix`, which the build writers hand to the emitter.

### 4. Non-goals

Qualified **type** names, a change to the linkage of `static` globals, and any new capacity limit.

### 5. Acceptance

`test/modules/ns_globals` (mangled exports, qualified reads and writes, correct output),
`test/modules/ambig_global` (non-zero exit with the ambiguity diagnostic), `test/modules/map_ns`
(`hal_uart1_hal_Writer_vtable` plus `hal_uart1` in the wrapper body), and nine hard gates green with no
change under `test/cases/**` or `examples/**`.
