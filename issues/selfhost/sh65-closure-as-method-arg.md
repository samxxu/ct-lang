# SH-65 trait / impl 方法收不了闭包实参

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`Expr` 的常规方法调用路径 / `Emitter` 的 `N_MCALL` / `l0`） |
| 严重度 | **Medium**（不误编译；但让 OO 化的回调接口写不出来，且 `ct compile` 落到内部诊断） |
| 锚点 | commit `e99a5fd`（2026-11-10，`v0.26.4`） |
| 文件 | [Expr.h.ct:2587-2607](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2587-L2607)（常规 `.method(...)` 的 19.1/19.2，未计闭包）；[Expr.h.ct:3235-3249](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3235-L3249)（自由调用的同一对钩子）；[Emitter.h.ct:3365](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3365)（自由调用的闭包打包）与 [:3378](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3378)（`unknown expression node` 兜底）；[l0/ctc.c:561](../../selfhost/l0/ctc.c#L561)（L0 声明解析尾巴） |
| 状态 | **open**（本仓语言侧未改；09/10/12 的 OO 化因此搁置） |

## 现象

`trait` / `impl` 方法声明函数指针参数时，`ct-ast` 能解析、也能用**显式** `(fn, env)` 两个实参调用；
但把不逃逸闭包 `=>` 放在实参位置，三种入口给出三种结论：

| 形态 | `ct check` | `ct compile` |
| --- | --- | --- |
| pair 形（`int (*f)(void *env, int x), void *env`）+ `b.each(x => …)` | `error: arity mismatch: 'each' takes 2 argument(s), 1 given` | `error: unknown expression node` |
| 单函数指针形（`int (*f)(int x)`）+ `b.each(x => …)` | 退出 `0`（静默） | `error: unknown expression node` |
| 显式两参（`b.each(fn, env)`） | 退出 `0` | 退出 `0` |

同样的 pair 形闭包传给**自由函数**是正常的（`examples/09_callback/callback_tier2.ct`：`ring_each(&r, (int x) => x + base)`，`compile` / `check` 都退出 `0`），说明缺口只在 `.method(...)` 路径。

另外，L0 引导编译器（`selfhost/l0/ctc.c`）解析不了带函数指针参数的 trait 方法声明，所以这类样例目前也进不了 L0 golden 链（`test/cases/**`）。

## 复现

```c
/* pair-form.ct：trait 方法按「函数指针 + env」的 ABI 声明 */
trait Each {
    int each(int (*f)(void *env, int x), void *env);
}

struct Box {
    int total;
} use Each;

impl Each for Box {
    int each(int (*f)(void *env, int x), void *env) {
        self.total = f(env, 3);
        return self.total;
    }
}

int main(void) {
    Box b;
    int base;
    b.total = 0;
    base = 10;
    return b.each((int x) => x + base);   /* ← 闭包作方法实参 */
}
```

```console
$ ct-ast check pair-form.ct
pair-form.ct:21:14: error: arity mismatch: 'each' takes 2 argument(s), 1 given
rc=1
$ ct-ast compile pair-form.ct -o pair-form.c
pair-form.ct:21:1: error: unknown expression node
rc=1
```

```c
/* single-form.ct：只有函数指针参数，闭包按「单槽」类比 */
trait Each {
    int each(int (*f)(int x));
}
```

```console
$ ct-ast check single-form.ct
rc=0
$ ct-ast compile single-form.ct -o single-form.c
single-form.ct:20:1: error: unknown expression node
rc=1
```

```console
$ ctc-l0 pair-form.ct > pair-form.c
pair-form.ct:3:1: error: unexpected '(void *env, int x), void *env)' after declaration of 'each'
rc=1
```

对照组（显式两参 / 自由函数闭包）均 `rc=0`：

```c
return b.each(add_one, &base);        /* 显式 fn/env：compile rc=0 */
return ring_each(&r, (int x) => x + base);  /* 自由函数闭包：compile rc=0 */
```

## 影响

- **examples 的 OO 化被挡住**：把 ring 的遍历 / 映射做成 `trait` 方法时，`each` / `map` 收不了闭包，
  只能退回「传结构体 + 自由函数 + 判 tag」，也就是 09、10、12 三个样例保持函数式写法的直接原因。
- **两个入口结论分叉**：`ct check` 报 arity、`ct compile` 报内部兜底；单函数指针形更糟——`check` 静默通过，
  `compile` 才炸。`check` 是 build 的超集这条直觉被打破。
- **诊断质量**：`unknown expression node` 是内部兜底（`Emitter.h.ct:3378`），出现在用户源码上是
  fail-loud 但指错了地方。

## 根因

- 常规方法调用在 [Expr.h.ct:2587-2607](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2587-L2607)
  只用 `arg_count` 调 `map_arity`，没有像自由调用那样先走
  `closure_arg_count` / `closure_arg_check`（[3235-3249](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3235-L3249)）。
  四个静态映射形态已在 Phase 25.1 补上（[3139](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3139)、
  [3164](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3164)），只有 `.method(...)` 漏了。
- Emitter 的 `N_MCALL` 实参逐个 `expr()`，闭包节点落到兜底；自由调用在
  [3365](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3365) 有专门的 `(fn, env)` 打包。
- L0 的声明解析（[ctc.c:561](../../selfhost/l0/ctc.c#L561)）把函数指针参数的剩余 token 当成非法尾巴。

## 建议方向

1. **方法调用复刻自由调用的两个钩子**：arity 侧 `+ closure_arg_count(args)`；检查侧先
   `closure_arg_check` 再判 19.2。pair 形应把闭包展开成 `(fn, env)` 两个实参；单函数指针形应报
   已有的 `a closure cannot be used where a plain function pointer is expected`，而不是内部错误。
2. **Emitter 的 `N_MCALL` 参数打包补 `N_CLOSURE`**，与自由调用同规，消掉 `unknown expression node`。
3. **L0 排在后面**：等「变参 / 函数指针参数的 trait 方法」在引导链可解析后再进 `test/cases`；
   在此之前这类用例只挂在 ct-ast 链（`test/ast` / `test/modules`）。
4. **验收**：`test/ast` 增正例（pair 形闭包作 impl 方法实参，生成 `(fn, env)`）与负例（单函数指针形，
   报上面那句）；`ct check` 与 `ct compile` 结论一致；`bash selfhost/check-all.sh` 全绿。
