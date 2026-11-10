# SH-66 · 泛型仍有两条退出 0 的静默坏产物：类型参数用于数组维度、模板名作值

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`Expr` 的类型实参/值位置解析、`Emitter` 的单态化替换） |
| 严重度 | **High**（编译器退出 0 并写出 `cc` 必拒的 C，与已修的 SH-62 / SH-64 同类） |
| 锚点 | `v0.26.4`（HEAD `48d793f`，2026-11-10 只读审计） |
| 文件 | [language-spec.md:1907-1925](../../docs/language-spec.md#L1907-L1925)（§4.48 的替换点与「这些都在源码处硬报错」）；[phase26.md:149-165](../../docs/design/phase26.md#L149-L165)（D26-6 只列 7 个类型位）；[phase26.md:50](../../docs/design/phase26.md#L50)（非目标：类型参数用于数组维度） |
| 状态 | **已修**（2026-11-10，`v0.26.4` + 本补丁，随 `fix(selfhost)` 提交落地；红/绿对照与门禁见文末「修复」；`verified` 留给独立评审） |

## 现象

规范承诺「类型参数只出现在类型操作数 / 标签上，其余位置硬报错，不静默降级」，且把
「类型参数用于数组维度」列为**明确不支持**。实测有两条路径既没有替换、也没有诊断，
编译器退出 0 并原样发射 `T`：

| 形态 | `ct` | `cc -std=c99 -Wall -Wextra -Werror` |
| --- | --- | --- |
| 数组维度里的 `sizeof(T)`：`T a[sizeof(T)]` | 退出 **0**，发射 `int a[sizeof(T)];` | 退出 1：`use of undeclared identifier 'T'` |
| 模板名作值：`int (*p)(int) = id;` | 退出 **0**，发射 `int (*p)(int) = id;`（模板不落 C 符号） | 退出 1：`use of undeclared identifier 'id'` |

第一条违反 §4.48 的「不静默降级」；第二条违反「模板本身不生成任何 C 符号」的配套要求——
既然不发射模板，就应在源码处拒绝裸模板名，而不是留给 `cc`。

## 复现

```c
/* dim.ct */
T first<T>(T x) {
    T a[sizeof(T)];      /* ← 维度不在 D26-6 的替换点里 */
    a[0] = x;
    return a[0];
}
int main(void) { return (int)first<int>(4); }
```

```console
$ ct dim.ct -o dim.c
rc=0
$ grep 'a\[' dim.c
    int a[sizeof(T)];
$ cc -std=c99 -Wall -Wextra -Werror dim.c -o dim
dim.c:10:18: error: use of undeclared identifier 'T'
```

```c
/* value.ct */
T id<T>(T x) { return x; }
int main(void) { int (*p)(int) = id; return p(1); }
```

```console
$ ct value.ct -o value.c
rc=0
$ grep '= id' value.c
    int (*p)(int) = id;
$ cc -std=c99 -Wall -Wextra -Werror value.c -o value
value.c:6:21: error: use of undeclared identifier 'id'
```

## 影响

- 与 SH-62 / SH-64 同一失败模式：用户拿到退出码 0，错误延迟到 `cc` 或链接阶段，
  且诊断指向生成物而非源码。
- 数组维度是容器/缓冲区泛型最自然的写法之一（`T buf[sizeof(T)]`、`T tmp[N]`），
  用户会先撞到这条静默通道。
- 模板名作值会让「把泛型函数当回调传」看起来可用，实际产物里没有符号；
  这会诱导写出只在 `cc` 阶段失败的代码。

## 根因方向

- 数组维度：`ct_generic_subst` 的替换点只覆盖 `N_FUNC` / `N_PARAM` / `N_DECL` /
  `N_CAST` / `N_SIZEOF` / `N_OFFSETOF` / `N_VAARG`（phase26 §2.3）；数组维度既不在替换点，
  也没有「此处不允许类型参数」的解析期守卫。
- 模板名作值：`parse_primary` 的 `T_ID` 分支只拦「当前标识符等于模板类型参数」，
  不拦「当前标识符是已登记的泛型模板名且未带 `<type>`」。

## 建议方向（二选一，均需先补负例再修）

1. **按规范硬错（推荐）**：数组维度出现类型参数 → 解析期报 `a type parameter cannot be used in an array dimension`；
   裸模板名作值 → 报 `generic function '<name>' needs a type argument` 的同一文案（复用 L26-1）。
2. **真实现替换**：把数组维度纳入替换点，`T a[sizeof(T)]` 实例化为 `int a[sizeof(int)]`；
   模板名作值仍需硬错（没有实例就无法取地址）。

无论选哪条，都应在 `test/ast/errors/` 增两条负例，并把它们纳入 `tparam_residue()` 的
`build` / `.h` 覆盖口径（TEST-18 已扩到这两个位置）。

## 与既有条目的关系

- 不与 SH-62 / SH-63 / SH-64 重复：那三条已修并 `verified`，本条目是**未被这些修复覆盖**的两条路径。
- 不涉及 Phase 26 的显式非目标（泛型 struct/union/trait、约束、推导、多参数、`pub`、递归）——
  那些都有 L26 诊断或专门的解析错误，不属于静默坏产物。

## 修复（2026-11-10，`v0.26.4` + 本补丁）

**处置选择**：按「建议方向 1（按规范硬错）」。§4.48 已把「类型参数用于数组维度」列为明确不支持，
D26-6 的替换点只有 7 个类型位；要把数组维度纳入替换，必须同时改 D26-6 与 phase26 §1.3 的非目标，
那是另一个量级的语言变更，不属于本补丁。裸模板名作值没有 `<type>` 就没有实例、没有符号，
只能硬错。

**根因 1（数组维度）**：`parse_array_dims` 把括号内的文本逐字抄进 `text3`（`[sizeof(T)]`），
它既不在 `ct_generic_subst` 的七个替换点里，也没有「此处不允许类型参数」的守卫，
于是实例体内原样留下 `sizeof(T)`。

**根因 2（裸模板名）**：`parse_primary` 的 `T_ID` 出口只在后跟 `(` 时查模板（L26-1）；
值位置经 `find_var` 失败后落到「ALL_CAPS 宏 → 裸函数名 → `fnval_ok`」三条兜底。
`id` 既不是变量也不是宏，而函数指针初始化让 `fnval_ok` 为真，于是整名原样发射成 `N_RAW`。

**改动**

| 文件 | 改动 |
| --- | --- |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct`（`parse_array_dims`） | 读到 `[` 时按标识符边界扫描该维度的源文本（块注释先跳过，注释里的 `T` 不算）；当前模板的类型参数出现在维度里即 `fail("type parameter 'T' cannot be used in an array dimension")`，位置钉在 `[` |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct`（`parse_primary` 的「未声明名字」分支） | 在 ALL_CAPS 兜底之前查 `find_func(nm)`：命中 `ntparams == 1` 即复用 L26-1 文案 `generic function '<name>' needs a type argument`（大小写模板名都走这条，不会从宏兜底漏出去） |
| `test/ast/errors/generic_tparam_array_dim.ct` | 新负例：`T a[sizeof(T)]` |
| `test/ast/errors/generic_template_value.ct` | 新负例：`int (*p)(int) = id;` |
| `selfhost/check-ast.sh` | 两条 `p26_diag`（退出码 + 位置 + 文案）与两条 `p26_chk`（`ct check` 同文案） |
| `docs/language-spec.md` §4.48（中英） | 写明这两条诊断与位置口径 |
| `docs/design/phase26.md` §2.3 | 记录数组维度不是替换点、裸模板名按 L26-1 拒绝 |

**红证（变异前，`fa480e8` 构建的 `v0.26.4`）**

```console
$ ct test/ast/errors/generic_tparam_array_dim.ct -o /tmp/sh66-red/generic_tparam_array_dim.c
rc=0
$ grep -n 'a\[' /tmp/sh66-red/generic_tparam_array_dim.c
9:    int a[sizeof(T)];
$ cc -std=c99 -Wall -Wextra -Werror /tmp/sh66-red/generic_tparam_array_dim.c
...:9:18: error: use of undeclared identifier 'T'
cc rc=1
$ ct check test/ast/errors/generic_tparam_array_dim.ct
check rc=0
```

```console
$ ct test/ast/errors/generic_template_value.ct -o /tmp/sh66-red/generic_template_value.c
rc=0
$ grep -n '= id;' /tmp/sh66-red/generic_template_value.c
5:    int (*p)(int) = id;
$ cc -std=c99 -Wall -Wextra -Werror /tmp/sh66-red/generic_template_value.c
...:5:21: error: use of undeclared identifier 'id'
cc rc=1
$ ct check test/ast/errors/generic_template_value.ct
check rc=0
```

两条都是「`ct` 与 `ct check` 都退出 0，`cc` 才失败」，与 SH-62 / SH-64 的失败模式一致。

**绿证（本补丁）**

```console
$ ct test/ast/errors/generic_tparam_array_dim.ct -o out.c
test/ast/errors/generic_tparam_array_dim.ct:6:8: error: type parameter 'T' cannot be used in an array dimension
rc=1
$ ct check test/ast/errors/generic_tparam_array_dim.ct
test/ast/errors/generic_tparam_array_dim.ct:6:8: error: type parameter 'T' cannot be used in an array dimension
check rc=1
$ ct test/ast/errors/generic_template_value.ct -o out.c
test/ast/errors/generic_template_value.ct:10:23: error: generic function 'id' needs a type argument
rc=1
$ ct check test/ast/errors/generic_template_value.ct
test/ast/errors/generic_template_value.ct:10:23: error: generic function 'id' needs a type argument
check rc=1
```

两次失败都不写产物文件；`ct build` 同口径（`check-ast.sh` 的负例总扫要求每条
`test/ast/errors/*.ct` 都带 `file:line:col: error:` 且非零退出）。

**验证命令与门禁**（本补丁的最终工作树）

```console
$ bash selfhost/check-all.sh
...
=============================================================
check-all: OK (11 hard gates green)
```

| 门禁 | 结果 |
| --- | --- |
| `test/run.sh`（L0） | `unit: 112 checks, 0 failed` |
| `check-goldens` | `131 passed, 0 failed` |
| `check-archive` | `108 checks, 0 failed`；multi-unit `82 passed, 0 failed` |
| `check-ast`（含 `p26_diag_*` / `p26_check_*`） | `844 passed, 0 failed` |
| `check-warnings` | `258 ok, 0 failed` |
| docs 门禁 | ok |

- 两条新负例在 gate 8 里分别由 `p26_diag_generic_tparam_array_dim`、
  `p26_diag_generic_template_value`、`p26_check_generic_tparam_array_dim`、
  `p26_check_generic_template_value` 钉住，并被 `test/ast/errors/*.ct` 总扫的
  `rejected with a positioned diagnostic` 复述一遍。
- 正例 `123`–`131`、语料与示例零回归。
- `tparam_residue()` 口径未变：两条新负例在解析期退出，不产生可扫描的产物。

`verified` 留给独立评审。

