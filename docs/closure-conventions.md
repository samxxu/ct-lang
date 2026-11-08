# 闭包与容器回调约定（Phase 21 S0）

> 中文 · [English](#english)
>
> **状态：S0 约定**（2026-11-08，Phase 21 的第一片）。本文只写约定，不改编译器；档② 闭包（`=>`）在
> S3 之后才可用，今天能照着写的是**档①**（`struct` + `trait` + 适配函数）。
> 适用版本：`ct -v`（ct-ast 主线）。
>
> 关联：[design/phase21.md](design/phase21.md)（决策 D21-1–D21-17 与切片 S0–S7）、
> [language-spec.md](language-spec.md)、[memory-guide.md](memory-guide.md)、
> 可运行示例 [../examples/09_callback/callback.ct](../examples/09_callback/callback.ct)。

---

## 中文

### 0. 一页结论

| # | 约定 | 内容 |
| --- | --- | --- |
| 1 | 回调只有一种形态 | `(fn, env)` 两词，`env` 是回调的**第一个**参数；不打包结构体 |
| 2 | 容器不持回调 | 容器只在本调用内使用 `(fn, env)`，**不得**把两词中的任一个存起来 |
| 3 | 闭包是绑定不是值 | 闭包变量不能拷贝、重赋值、作字段 / 元素 / 返回值，也不能被容器持有 |
| 4 | 无 env 槽的 C 回调 | `qsort` 这类签名收不了档②，也收不了档①；不要拿它当收益例子 |
| 5 | 逃逸尽量在源码位置报 | 拦不住的只有「env 以 `void *` 交给别人保存」（E8），见 §6 |

### 1. 容器回调签名

容器 / 算法接受回调的函数**只允许**下面这一种形态：

```c
int ring_each(struct IntRing *r, int (*fn)(void *env, int x), void *env);
```

- `env` 永远是回调的第一个形参，`fn` 与 `env` 在参数表里**相邻**，`fn` 在前。
- `env` 由调用方提供、由调用方保证寿命；容器只把它原样传给 `fn`。
- 元素类型是具体的：没有泛型时 `VecInt` / `VecStr` 各自要一份容器函数，闭包省掉的是**调用点**的
  adapter，不是容器函数本身。
- 闭包作为实参时是**一个源级实参**，在 `(fn, env)` 参数对上展开为两个 C 实参，arity 检查按两个算。
  识别规则窄而可判：被调方参数表中存在相邻的 `ret (*P)(void *self, …)` + `void *E`，闭包实参必须
  落在这个对的起点。
- **容器不得保留 `env`**：栈上环境活不过容器；需要长期持有的回调走档①，由调用方自己管寿命。
- **没有 env 槽的 C 回调**（`qsort` 的比较函数 `int (*)(const void *, const void *)`）两档都塞不进去，
  这是签名决定的，不是闭包能力缺口。

### 2. 今天就写档①

档① 是显式的 `struct` + `trait`：对象本身就是 `env`，适配函数就是 `fn`。

```c
trait IntOp {
    int apply(int x);
}

struct Adder {
    int n;
} use IntOp;

impl IntOp for Adder {
    int apply(int x) {
        return x + self->n;
    }
}

/* 适配函数：形状与生成的 impl 包装一致，env 就是对象本身 */
static int adder_call(void *env, int x) {
    struct Adder *a;
    a = (struct Adder *)env;
    return a->apply(x);
}

struct Adder a = { .n = 10 };
ring_each(&r, adder_call, &a);
```

impl 包装函数 `<Struct>_<Trait>_<method>(void *self, …)` 本身就是现成的 `fn`，但它发射为 `static`，
**不能按名字在源码里引用**，因此跨单元或需要传地址时由作者写上面这段两行适配函数。
完整可运行示例见 [../examples/09_callback/callback.ct](../examples/09_callback/callback.ct)。

### 3. 档② 落地后的形态（S3 之后）

```c
int n = 3;
int (*add)(int x) = (int x) => x + n;   /* 左侧函数指针给出返回类型，不推断 */
ring_each(&r, add);
```

- 表面类型复用函数指针声明，不引入 `auto`，不做类型推断（D21-1）。
- 捕获**按值**、创建点求值、捕获名只读；写捕获名或取捕获名地址一律报错，写回用指针显式解引用（D21-2）。
- 闭包变量是**绑定不是值**：只在声明处可用，拷贝 / 重赋值 / 字段 / 元素 / 返回值都报错（D21-13 / D21-16）。
- 环境在栈上，闭包值本身不能被容器持有（见 §0 第 3 条）。
- 字面量直接作实参（`ring_each(&r, (int x) => x + 1)`）自 S5 起与宿主 `(fn, env)` 对逐参比对，
  返回类型取宿主 `fn`（D21-14）；也可以先赋给已声明的闭包变量。
- 块体写法 `(int x) => { … }` 与嵌套闭包自 S5 起可用；内层捕获按值从外层 env 字段拷出，不产生
  env 之间的指针链。

### 4. 生成物与命名（S3 冻结的形态）

以下形态在档② 落地（S3）时冻结：

```c
struct __ct_cl_env_1 { int n; };
static int __ct_cl_tramp_1(void *self, int x) {
    struct __ct_cl_env_1 *e = self;
    return x + e->n;
}
int apply(int base) {
    int n = 3;
    struct __ct_cl_env_1 __ct_cl_env_v_1 = { n };
    return __ct_cl_tramp_1(&__ct_cl_env_v_1, 5);
}
```

- 三个名字共用同一个 `N`：`__ct_cl_env_<N>`（结构体 tag）、`__ct_cl_tramp_<N>`（trampoline）、
  `__ct_cl_env_v_<N>`（栈上实例）。`N` 是**单元级单调计数器**，分配后不复用；不带函数名，也不带
  namespace 前缀（D21-3 / D21-8）。
- env 结构与 trampoline 一律发在**本单元 `.c` 的文件作用域**，trampoline 为 `static`，绝不进 `.h`；
  `ct build` 的两个单元各自有 `__ct_cl_tramp_1` 也合法。
- 发射时机是「按 owner 函数预扫、就地发在函数体之前」（D21-15）；**零闭包单元的生成物逐字节不变**。
- `__ct_` 是编译器保留前缀，用户声明以 `__ct_` 开头的标识符报错。
- env 结构不登记进符号表；每个闭包占 1 个源级变量 + 1 个闭包表项。

### 5. ABI 冻结与诊断

ABI 在 **S3 冻结**：`(fn, env)` 的顺序、命名规则与调用点展开规则之后不再改；冻结条款不包括
「闭包字面量直接作实参」这一形态（那在 S5，D21-14）。

诊断是**稳定英文文案**（无错误码），每条错误之后另起一条 `note:` 给出可抄的档① 写法（`note:` 通道在
S4 落地，这里先钉住契约）：

```text
t.ct:4:9: error: a closure cannot escape through 'return'
t.ct:4:9: note: use an explicit Callable struct + trait: ...
```

`note:` 走独立通道：不递增错误计数、不占 `MAX_ERRORS`、不进 `--diagnostics=json` 的 `warnings`，
`ct check` 的退出码与 `ctc: N error(s) generated` 的 `N` 都不变。文案清单（小写、无句号、
标识符单引号）以 [design/phase21.md](design/phase21.md) §4.6 为准。

### 6. 已知未防护面（必须如实标注）

- **E8（不检查）**：`env` 以 `void *` 交给不透明 C 函数，或交给**另一个 CT 函数**（包括 std 规划中的
  `each(v, fn, env)`）后由对方保存到全局 / 字段 / 容器，编译器**看不到**，不会报错。接收方只看到普通
  `void *` 参数。只能靠 API 约定（容器不持 `env`）与文档约束。当编译器识别不出被调方的 `(fn, env)`
  参数对时，错误之后会经 note 通道打印下面这句，明确说明剩余风险：
  `note: the compiler cannot see whether the callee keeps the environment; the environment dies with this frame`。
- **E9（不检查）**：`goto` 跨过闭包声明是静默失效，与 `own` / `borrow` 的现状相同。
- **按设计禁止**（不是漏洞）：闭包类型出现在 `.h.ct`、作返回值、作字段或数组元素、在另一单元声明闭包变量。
- **可以跨单元**：把 trampoline / impl 包装的**地址**当实参传给别单元的函数，由对方在运行期调用；
  `static` 只挡「按符号名引用」。

### 7. 什么时候用哪一档

| 场景 | 选择 |
| --- | --- |
| 回调只在本次调用内使用（就地循环、当场传参） | 档②（S3 之后）；今天用档① |
| 回调要被容器 / 全局 / 字段长期持有 | 档①（对象自己管寿命） |
| 需要写回捕获的变量 | 捕获指针并在闭包内显式解引用（D21-2）；或档① |
| 同一回调要跨单元按符号引用 | 档① 并自写 `pub` 包装 |
| C 回调签名没有 `void *` 槽（`qsort` 等） | 都不行；改签名或写全局状态 |

---

## English

### 0. One-page summary

| # | Convention | Rule |
| --- | --- | --- |
| 1 | One callback shape only | `(fn, env)`: `env` is the callback's **first** parameter; do not pack a struct |
| 2 | Containers never retain callbacks | Use the pair for the call only; store neither word |
| 3 | A closure is a binding, not a value | No copy, no reassignment, no field / element / return value, no container ownership |
| 4 | C callbacks without an env slot | `qsort`-style signatures take neither tier; not a closure gap |
| 5 | Escape errors stay at the source position | The only uncaught case is handing `env` out as `void *` (E8, §6) |

### 1. Container callback signature

A container or algorithm that takes a callback accepts exactly one shape:

```c
int ring_each(struct IntRing *r, int (*fn)(void *env, int x), void *env);
```

- `env` is always the callback's first parameter; `fn` and `env` are **adjacent** in the callee's parameter
  list, `fn` first.
- The caller owns `env` and guarantees its lifetime; the container only forwards it.
- Element types are concrete: without generics each element type needs its own container function.
  Closures remove the **call-site** adapter, not the container function.
- A closure argument is one source-level argument that expands to two C arguments over the `(fn, env)` pair;
  arity counts it as two. The recognition rule is narrow: an adjacent `ret (*P)(void *self, …)` + `void *E`
  pair, with the closure filling the start of that pair.
- **A container must not retain `env`**: a stack environment dies with the frame. Long-lived callbacks use
  tier 1 and manage their own lifetime.
- C callbacks with no env slot (`qsort`) accept neither tier. That is the signature talking, not a missing
  closure feature.

### 2. Tier 1 today

Tier 1 is an explicit `struct` + `trait`: the object is the `env`, an adapter function is the `fn`.
See [../examples/09_callback/callback.ct](../examples/09_callback/callback.ct) for a runnable version.

The generated impl wrapper `<Struct>_<Trait>_<method>(void *self, …)` already has the shape, but it is
emitted `static` and **cannot be named in source**; write the two-line adapter when you need its address
or a cross-unit reference.

### 3. Tier 2 once it lands (after S3)

`int (*add)(int x) = (int x) => x + n;` — the left-hand function pointer supplies the return type, with no
`auto` and no inference (D21-1). Captures are by value, evaluated at creation, read-only (D21-2); a closure
variable is a binding, not a value (D21-13 / D21-16); the environment lives on the stack and a closure value
cannot be held by a container. A literal passed directly as an argument is compared against the host
`(fn, env)` pair from S5 on, with the return type taken from the host `fn` (D21-14); block bodies and
nested literals also land in S5, and an inner capture copies a value out of the outer environment field.

### 4. Generated names (frozen at S3)

The shape below is frozen when tier 2 lands (S3):

`__ct_cl_env_<N>` (struct tag), `__ct_cl_tramp_<N>` (`static` trampoline) and `__ct_cl_env_v_<N>` (stack
instance) share one unit-level counter `N`. They live at `.c` file scope, never in `.h`; no function name
and no namespace prefix (D21-3 / D21-8). The emitter pre-scans each owner function and emits the products
right before its body (D21-15); a unit without closures keeps byte-identical output. `__ct_` stays reserved.

### 5. Frozen ABI and diagnostics

`(fn, env)` order, naming and call-site expansion are frozen at **S3**; direct literal arguments are excluded
from the freeze and land in S5 (D21-14). Diagnostics are stable English text with a separate `note:` line
carrying a copy-pasteable tier-1 recipe (the channel ships in S4; the contract is pinned here).
`note:` does not count toward `MAX_ERRORS`, does not enter
`--diagnostics=json`, and does not change `ct check`'s exit code or the `N` in `ctc: N error(s) generated`.
The full message list lives in [design/phase21.md](design/phase21.md) §4.6.

### 6. Known unprotected surfaces

- **E8 (unchecked)**: `env` handed to an opaque C function, or to **another CT function** (including a
  future std `each(v, fn, env)`), and then stored in a global / field / container. The callee sees a plain
  `void *`; there is no cross-procedure analysis. Only the API convention and documentation guard this.
- **E9 (unchecked)**: `goto` jumping over a closure declaration behaves like `own` / `borrow` today.
- **Forbidden by design** (not holes): a closure type in `.h.ct`, as a return value, as a field or array
  element, or a closure variable in another unit.
- **Allowed across units**: passing a trampoline / impl wrapper **address** to another unit's function;
  `static` only blocks reference by symbol name.

### 7. Which tier

| Situation | Choice |
| --- | --- |
| Callback used only for this call (local loop, immediate argument) | tier 2 after S3; tier 1 today |
| Callback retained by a container / global / field | tier 1, caller manages lifetime |
| Need to write back a captured variable | capture a pointer and dereference explicitly (D21-2), or use tier 1 |
| Callback referenced by symbol across units | tier 1 plus a `pub` wrapper |
| C callback with no `void *` slot (`qsort`) | neither; change the signature or use global state |
