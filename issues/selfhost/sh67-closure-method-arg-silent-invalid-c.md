# SH-67 · 闭包先绑变量再传 trait 方法：退出 0 并发射未声明的函数指针

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`Expr` 的方法调用实参 / `Emitter` 的 `N_MCALL` 与 `emit_closure_decl`） |
| 严重度 | **High**（`ct` 退出 0 并写出 `cc` 必拒的 C，违反「生成物必须可编译」的产物契约） |
| 锚点 | `v0.30.0`（HEAD `bd91bfe`，2026-11-11；`ct-ast` 由 HEAD 重建，只读复现） |
| 文件 | [Expr.h.ct:3745-3764](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3745-L3764)（方法调用的 arity / 实参类型后处理，未计闭包）；[Emitter.h.ct:3372-3378](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3372-L3378)（闭包绑定故意不声明 C 变量）；[Emitter.h.ct:3997-4002](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3997-L4002)（`N_MCALL` 实参逐个 `emit_expr`）；[Emitter.h.ct:4008-4023](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4008-L4023)（只有自由调用 `N_CALL` 才展开 trampoline）；[language-spec.md:2016](../../docs/language-spec.md#L2016)（§4.49「绝不发射坏 C」）；[AGENTS.md:59](../../AGENTS.md#L59)（生成的 `.c` 必须自包含、可单独编译） |
| 状态 | **open**（本轮只登记；未改代码、未修发射） |

## 现象

同一个闭包，传进 trait / impl 方法实参时有两种入口，结论不同：

| 形态 | `ct-ast check` | `ct-ast compile` | `cc` |
| --- | --- | --- | --- |
| 字面量直接传：`r.run((int x) => x + 1);` | 退出 **0** | 退出 **1**，`error: unknown expression node` | 未到 |
| 先绑变量再传：`int (*f)(int) = (int x) => x + 1; r.run(f);` | 退出 **0** | 退出 **0**，写出 `.c` | 退出 **1**：`use of undeclared identifier 'f'` |

第二行是本次登记的核心：**编译器退出 0，但生成的 C 不可编译**。字面量那行虽然 fail loud，但落的是内部兜底文案，也不是可读诊断。

## 复现

```c
/* literal.ct：闭包字面量作方法实参 */
#include <stdio.h>

trait Runner { int run(int (*f)(int)); }

struct R { int z; } use Runner;

impl Runner for R {
    int run(int (*f)(int)) { return f(self->z); }
}

int main(void)
{
    struct R r;

    r.z = 1;
    printf("%d\n", r.run((int x) => x + 1));
    return 0;
}
```

```console
$ ct-ast check literal.ct
check rc=0
$ ct-ast literal.ct -o literal.c
literal.ct:16:1: error: unknown expression node
compile rc=1
```

```c
/* two_step.ct：先把闭包绑到函数指针变量，再传进方法 */
#include <stdio.h>

trait Runner { int run(int (*f)(int)); }

struct R { int z; } use Runner;

impl Runner for R {
    int run(int (*f)(int)) { return f(self->z); }
}

int main(void)
{
    struct R r;
    int (*f)(int) = (int x) => x + 1;

    r.z = 1;
    printf("%d\n", r.run(f));
    return 0;
}
```

```console
$ ct-ast check two_step.ct
check rc=0
$ ct-ast two_step.ct -o two_step.c
compile rc=0
$ grep -n 'tramp\|cl_env\|__runner_vptr->run\|int main' two_step.c
40:struct __ct_cl_env_0 {
43:static int __attribute__((unused)) __ct_cl_tramp_0(void *self, int x);
44:static int __attribute__((unused)) __ct_cl_tramp_0(void *self, int x)
49:int main(void) {
51:    struct __ct_cl_env_0 __attribute__((unused)) __ct_cl_env_v_0 = { 0 };
53:    printf("%d\n", r.__runner_vptr->run(&r, f));
$ cc -std=c99 -Wall -Wextra -Werror two_step.c -o two_step
two_step.c:53:45: error: use of undeclared identifier 'f'
   53 |     printf("%d\n", r.__runner_vptr->run(&r, f));
      |                                             ^
cc rc=1
```

生成的 C 里有 trampoline（`__ct_cl_tramp_0`）和栈上 env（`__ct_cl_env_v_0`），但**没有 `f` 的声明**；第 53 行直接引用了这个名字。

## 违反的红线

- [AGENTS.md:59](../../AGENTS.md#L59)：生成的 `.c` 必须自包含，保证生成物可单独编译。本条产物连 `cc` 都过不了，直接违反。
- [language-spec.md:2016](../../docs/language-spec.md#L2016)（§4.49）：不可迭代形态一律硬错，**绝不发射坏 C**；同节 [2093](../../docs/language-spec.md#L2093) 把同一原则表述为「不会把非法 C 交给 `cc`」。
- AGENTS 的产物门禁要求生成物 `-Wall -Wextra` 零告警；本条在 `-Werror` 下直接失败。

按契约，正确处置只有两种：在解析/检查期硬错并给出可读诊断，或正确发射闭包绑定。当前两者都不是。

## 影响

- **退出码 0 是成功信号**：只检查编译器退出码的脚本、CI 或 `ct build` 调用方会放过这条源码，错误要到 `cc`（甚至链接）才暴露。
- **它正是 SH-65 的「退一步」写法**：用户在字面量失败后，很自然会改成「先绑变量再传」，结果从「响亮失败」变成「静默坏产物」。
- **诊断位置失真**：单文件模式没有 `#line`，`cc` 报的是 `two_step.c:53`，不是 `.ct` 行号（与 B1 同类）。
- **闭包与 OO 回调接口无法组合**：集合的 `each` / `map` 一旦做成 trait 方法，就收不了闭包；这不是「写法啰嗦」，是产物错误。

## 根因

- `emit_closure_decl` 的注释写明：闭包绑定**不声明 C 变量**，只写 env 的栈实例，并把名字登记到 `closure_var_lookup`，供后续调用展开（Emitter 3372-3378）。
- 自由调用 `N_CALL` 有专门的展开：`f(a)` → `__ct_cl_tramp_<ci>(&__ct_cl_env_v_<ci>, a)`（Emitter 4008-4023）。
- 方法调用 `N_MCALL` 的实参循环只逐个 `emit_expr`（Emitter 3997-4002），没有 `closure_var_lookup` 分支；于是 `f` 作为普通标识符原样落到生成的 C。
- 解析侧方法调用的 arity 用 `arg_count(args)`，没有加 `closure_arg_count`，也未走 `closure_arg_check`（Expr 3745-3764）；因此 `check` 对两种形态都退出 0。

## 与 SH-65 的关系

- **同一入口族**：都是 trait / impl 方法实参位置没有处理闭包。SH-65 记录的是**字面量直接传**：`compile` 退出 1（`unknown expression node`），`check` 与 `compile` 结论分叉；本条记录的是**先绑变量再传**：两个入口都过，发射非法 C。严重度从 SH-65 的 Medium 升为 **High**。
- **不是重复**：SH-65 的建议方向 2（`N_MCALL` 打包 `N_CLOSURE`）只覆盖字面量；本条还要求方法实参位的闭包变量也走 `closure_var_lookup`，或者直接硬错。两条的验收夹具不同。
- **修复可以同批，但门槛不同**：SH-65 可以按「pair 形展开、单函数指针形报错」慢慢做；本条必须先把「退出 0 发射坏 C」堵住。

## 建议处置（硬错优先）

1. **先硬错（推荐，小补丁）**：在方法调用实参解析处（Expr 3745 附近）识别两种形态——`N_CLOSURE` 字面量、以及绑定到闭包的变量名——报已有文案 `a closure cannot be used where a plain function pointer is expected`，位置钉在实参，且不写产物。这样立刻满足红线，不依赖 codegen 改造。
2. **后续（并入 SH-65 / F3）**：pair 形方法参数（`int (*f)(void *env, int), void *env`）按 `(fn, env)` 展开，`N_MCALL` 复用 `N_CALL` 的 trampoline 逻辑；单函数指针形保持硬错。
3. **验收**：`test/ast/errors/` 增两条负例——`closure_method_arg_literal.ct` 与 `closure_method_arg_var.ct`；`check-ast.sh` 断言 `compile` 与 `check` 都退出 1、文案与 `文件:行:列` 一致、且失败时不写 `.c`。正例（pair 形展开）留给 F3。
