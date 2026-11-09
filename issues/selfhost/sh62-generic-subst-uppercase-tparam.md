# SH-62 · 泛型单态化的 `(T)` / `sizeof(T)` / `_Alignof(T)` / `offsetof(T, …)` 不成立；`sizeof(T)` 静默产出非法 C

| 模块 | selfhost |
| --- | --- |
| 严重度 | **P1（High）** |
| 锚点 | `v0.26.0` / `ac1c7cd`（HEAD = `main`） |
| 文件 | [Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1684-L1694)、[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2082-L2083)、[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2095)、[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2109-L2110)、[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2767)、[Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2995-L3037) |
| 状态 | **fixed**（2026-11-09，`87b03ec` + `4995dff`，`v0.26.1`；`verified` 待评审回写） |

## 现象

`docs/design/phase26.md` §2.3（L151–158）与 §2.4（L169）把 `N_CAST` / `N_SIZEOF` / `N_OFFSETOF`
列为“替换点”，`docs/language-spec.md` §4.48（中 L1905–1906、英 L4166–4168）明确承诺：

> 实例体内的返回类型、形参、局部声明、`(T)` 转型、`sizeof(T)` / `_Alignof(T)`、`offsetof(T, …)` 都按实例的具体类型写出。

实测只有“返回类型 / 形参 / 局部声明”三处成立，其余三处不成立：

| 写法 | 期望 | 实测 |
| --- | --- | --- |
| `sizeof(T)` | 发射 `sizeof(int)` | `ct compile` **退出 0**，生成 C 里残留 `sizeof(T)`，`cc` 报 `‘T’ undeclared` |
| `(T)x` | 发射 `(int)(x)` | 解析期报 `error: unexpected token`，退出 1 |
| `_Alignof(T)` | 发射 `_Alignof(int)` | 解析期报 `error: _Alignof needs a type in parentheses`，退出 1 |
| `offsetof(T, y)` | 发射 `offsetof(struct Point, y)` | 解析期报 `error: offsetof needs a struct type`，退出 1 |

`sizeof(T)` 这一条最严重：编译器**静默成功**并写出明知编译不过的 C，违反
[AGENTS.md](../../AGENTS.md#L120-L121)“不允许生成明知编译不过的 C 代码”的硬约束。

## 证据（可复现）

把下面内容存为 `/tmp/p26-sizeof.ct`（其余探针同理替换函数体）：

```c
#include <stdio.h>

int widthOf<T>(T x)
{
    (void)x;
    return sizeof(T);
}

int main(void)
{
    printf("%d\n", widthOf<int>(0));
    return 0;
}
```

```console
$ ct compile /tmp/p26-sizeof.ct -o /tmp/p26-sizeof.c ; echo "ct=$?"
ct=0
$ grep -n 'sizeof' /tmp/p26-sizeof.c
12:    return sizeof(T);
$ cc -std=c99 /tmp/p26-sizeof.c -o /tmp/p26-sizeof ; echo "cc=$?"
/tmp/p26-sizeof.c:12:19: error: ‘T’ undeclared (first use in this function)
cc=1
```

`(T)` 转型：

```console
$ ct compile /tmp/p26-cast.ct -o /tmp/p26-cast.c ; echo "ct=$?"
/tmp/p26-cast.ct:5:15: error: unexpected token
ct=1
```

`offsetof`：`ct compile` → `/tmp/p26-offsetof.ct:8:29: error: offsetof needs a struct type`，退出 1。

## 根因

`next_is_type_name()` 的兜底分支把“全大写标识符”当成宏常量、拒绝识别为类型
（[Expr.h.ct:1684-1694](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1684-L1694)）：

```c
caps = (self->lex->toktext[0] != 0);
for (i = 0; self->lex->toktext[i]; i++) { ... 仅 A-Z 0-9 _ ... }
if (!caps && self->sym->find_var(...) < 0 && self->sym->find_func(...) < 0) { ... }
```

类型参数名 `T` 恰好是全大写，于是 `sizeof(T)` 走“操作数”分支、`(T)` 不被当作转型，
`Emitter.h.ct:3016/2995` 处为 `T` 准备的替换点永远拿不到 `text == "T"` 的类型节点（死代码）。
`offsetof(T, …)` 是另一条路径：[Expr.h.ct:2767](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2767)
用 `find_struct(targ)` 直接解析字段，模板参数在实例化前无法解析。

**反证**：把类型参数改成小写 `t`，同一实现立刻正确：

```console
$ ct compile /tmp/p26-lower.ct -o /tmp/p26-lower.c ; echo "ct=$?"
ct=0
$ grep -n 'sizeof\|return (int)' /tmp/p26-lower.c
13:    return sizeof(int);
16:    return (int)(x);
$ /tmp/p26-lower
4 9
```

即缺陷不在发射器，而在解析阶段把 `T` 排除在“类型名”之外。

## 影响

- 立项 S4 只完成 3/6；`docs/language-spec.md` §4.48（中英）与教程之外的规格文本是**假承诺**。
- 用户按规格书写 `sizeof(T)` 会拿到退出码 0 的坏产物，错误延迟到 `cc` 或链接阶段才暴露。
- E1/E2 之所以全绿，是因为两个正例夹具的函数体只有 `return x;`，不含任何类型位置（见 TEST-17）。

## 修复建议

1. 解析泛型模板体期间，把当前类型参数登记为“类型名”（或让 `next_is_type_name()` 先于
   ALL_CAPS 启发式识别 `in_generic` 的 `tparam`），使 `sizeof(T)` / `(T)` 走类型分支；
   `offsetof(T, …)` 需要在模板体内允许 tparam，或直接给出明确“本相不支持”的诊断。
2. 若决定不实现，必须删除 §4.48 与 phase26 §2.3/§2.4 的承诺，并在 `docs/design/phase26.md` §6.2 登记偏差。
3. 无论选哪条，都要补上“局部声明 / `(T)` / `sizeof(T)` / `offsetof`”四类夹具（TEST-17）。

## 修复（`v0.26.1`，`87b03ec` + `4995dff`）

按 [phase26.md §5 B26-2](../../docs/design/phase26.md) 的 battle 判决采用**方案 A：真实现替换**（两方案成本差 < 2×，判据见该节 E1–E5 与 §8）。

- `next_is_type_name()`：`in_generic && toktext == in_generic_tparam` 时先于 ALL_CAPS 启发式返回 1，`sizeof(T)` / `(T)` 走类型分支。
- `parse_type()`：同一条件把裸 `T` 当类型参数收下（局部声明、形参、返回类型）；`offsetof(T, …)` 在模板体内允许 tparam 并保留 `T` 待发射期替换。
- 发射器的 `N_SIZEOF` / `_Alignof` / `N_OFFSETOF` / `N_CAST` 替换点因此首次真正命中；另外补了同根因的 `va_arg(ap, T)`（`N_VAARG`），避免留下第五条静默通道——范围扩展理由见 phase26 §6.2 第 8 条。`_Generic(...)` 的选择体原样透传、无法安全替换，模板体内出现类型参数改为解析期硬错 `type parameter cannot be used inside _Generic`（夹具 `test/ast/errors/generic_generic_selector.ct`），同样不再产生退出 0 的坏产物。

证据：

```console
$ bash selfhost/check-ast.sh
== summary: 812 passed, 0 failed ==
# 红证（v0.26.0 基线编出的 ct-ast）= 退出 0 且生成物残留 sizeof(T)，cc 报 'T' undeclared
# 绿证（v0.26.1）：生成 sizeof(int)，运行输出 4；125 夹具输出 4 4 4 4 5
```
