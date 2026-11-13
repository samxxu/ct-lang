# 闭包与容器回调约定（Phase 21 S0）

> 中文
>
> **状态：S0 约定**（2026-11-08，Phase 21 的第一片）。本文只写约定，不改编译器；档② 闭包（`=>`）在
> S3 之后才可用，今天能照着写的是**档①**（`struct` + `trait` + 适配函数）。
> 适用版本：`ct -v`（ct-ast 主线）。
>
> 关联：[history/design/phase21.md](history/design/phase21.md)（决策 D21-1–D21-17 与切片 S0–S7）、
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
- 闭包变量是**绑定不是值**：只在声明处创建；可以调用，也可以整对填进 `(fn, env)` 参数（R03），
  但拷贝 / 重赋值 / 字段 / 元素 / 返回值都报错（D21-13 / D21-16）。
- 环境在栈上，闭包值本身不能被容器持有（见 §0 第 3 条）。
- 字面量直接作实参（`ring_each(&r, (int x) => x + 1)`）自 S5 起与宿主 `(fn, env)` 对逐参比对，
  返回类型取宿主 `fn`（D21-14）；也可以先赋给已声明的闭包变量。已声明绑定同样可以整对作实参
  （`ring_each(&r, add)`，R03）：填入它自己的 trampoline 与环境地址，参数表按宿主尾部比对，返回
  类型沿用声明、不被宿主改写。
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
t.ct:4:9: note: tier 1: trait Op { int call(int x); } ...
```

`note:` 走独立通道：不递增错误计数、不占 `MAX_ERRORS`、不进 `--diagnostics=json` 的 `warnings`，
`ct check` 的退出码与 `ctc: N error(s) generated` 的 `N` 都不变。文案清单（小写、无句号、
标识符单引号）以 [history/design/phase21.md](history/design/phase21.md) §4.6 为准。

### 6. 已知未防护面（必须如实标注）

- **E8（不检查）**：`env` 以 `void *` 交给不透明 C 函数，或交给**另一个 CT 函数**（包括 std 规划中的
  `each(v, fn, env)`）后由对方保存到全局 / 字段 / 容器，编译器**看不到**，不会报错。接收方只看到普通
  `void *` 参数。只能靠 API 约定（容器不持 `env`）与文档约束。当编译器识别不出被调方的 `(fn, env)`
  参数对时，错误之后会经 note 通道打印下面这句，明确说明剩余风险：
  `note: the compiler cannot see whether the callee keeps the environment; the environment dies with this frame`。
  已声明绑定与内联字面量同样暴露于 E8：env 仍是栈上对象，交给会保存它的接收方同样会悬空（R03 只是
  允许它整对传参，没有改变寿命）。
- **E9（不检查）**：`goto` 跨过闭包声明是静默失效，与 `own` / `borrow` 的现状相同。
- **按设计禁止**（不是漏洞）：闭包类型出现在 `.h.ct`、作返回值、作字段或数组元素、在另一单元声明闭包变量、
  作全局（含 `pub` 全局）的初始值、按值捕获数组（C 数组没有值语义，env 里的一次赋值拷不过去）。
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
