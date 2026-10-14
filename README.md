# ct — C with Traits 编译器

> **v0.0.1** · 中文 · [English](#english)

**ct** 是一个 **source-to-source 编译器**：把带 trait 语法的 `.ct` 源文件，翻译成纯 C 的 `.c` 文件。
它不做类型检查、不做优化；Phase 0（用 trait 写完整 OO）已完成，当前目标是**自举**（Phase 1，用 CT 重写编译器）——已达成的能力与后续计划见 [docs/roadmap.md](docs/roadmap.md)。

命名约定：项目与语言叫 **ct**（*C with Traits*，源文件后缀 `.ct`），编译器命令叫 **`ctc`**（ct compiler，好比 `tinycc` 仓库发布的命令是 `tcc`），GitHub 仓库叫 **`ct-lang`**（`ct` 作仓库名太短、检索不到）。

```bash
gcc ctc.c -o ctc
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

```
Hello, I'm Tom, age 36
Hello Jerry, I'm Tom
```

---

## 中文

### 1. 它解决什么问题

C 没有虚函数表，想在 C 里模拟「接口 + 多态」要手写一大堆样板代码：vtable 结构体、函数指针赋值、每个方法的第一参数手工强转、构造对象时手工填充 vptr。
`ctc` 让你用接近 Rust/D 的语法写这些声明，然后由编译器把样板代码生成出来 —— 生成结果是**可读的普通 C**，不依赖任何运行时库。

### 2. 快速开始

```bash
# 1) 构建编译器
gcc ctc.c -o ctc

# 2) 编译 .ct 到 .c（同时生成同名 .h）；产物可放任意目录
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c

# 3) 用系统 C 编译器构建产物
gcc /tmp/greeter.c -o /tmp/greeter
/tmp/greeter
```

命令行接口：

| 用法 | 说明 |
| --- | --- |
| `ctc <input.ct>` | 输出到 `<input>.c`、`<input>.h`（单文件模式） |
| `ctc <input.ct> -o <output.c>` | 输出到指定路径，头文件为同目录同名的 `.h` |
| `ctc compile <input.ct>` | 同上（`compile` 是默认子命令） |
| `ctc build <a.ct> <b.ct>… -o <dir>` | **多文件模式**：每个输入生成 `<dir>/<base>.c` + `.h`；`.c` 会 `#include` 自己的 `.h`；`pub` 符号进 `.h`；最后打印建议的 `cc …` 命令（不自己调用 `cc`） |
| `--line` / `--no-line` | 强制开 / 关生成的 `#line`（多文件模式默认开、单文件模式默认关），使 C 报错行号映回 `.ct` |
| `--diagnostics=json` / `--diagnostics=text` | 警告格式：JSON（`ct compile` 走 stdout）或人可读 stderr（默认）；目前仅泄漏警告 |
| `ctc -v` / `ctc --version` | 打印版本，如 `ctc v0.0.1` |
| `ctc -h` / `ctc --help` | 打印用法 |

退出码：成功 `0`；语法错误或 I/O 错误 `1`。错误信息格式为 `文件:行:列: error: 描述`。

> 命令的最终形态是单入口 `ct`（`ctc` 保留为兼容别名），尚未落地，见 [docs/roadmap.md](docs/roadmap.md)。

### 3. 语法与展开规则

| 输入（`.ct`） | 输出（`.c`） |
| --- | --- |
| `trait Greeter { void greet(); }` | `struct Greeter_vtbl { void (*greet)(void *); };` |
| `struct Person { char *name; } use Greeter;` | `struct Person { char *name; struct Greeter_vtbl *__greeter_vptr; };` |
| `impl Greeter for Person { void greet() {…} }` | `static void Person_Greeter_greet(void *self) { struct Person *_self = (struct Person *)self; … }` + `static struct Greeter_vtbl Person_Greeter_vtable = { .greet = Person_Greeter_greet };` |
| `Person p = { .name = "Tom" };` | `struct Person p = { .name = "Tom", .__greeter_vptr = &Person_Greeter_vtable };` |
| `Person p = { "Tom", 36 };` | `struct Person p = { "Tom", 36, .__greeter_vptr = &Person_Greeter_vtable };` |
| `Person p;` | `struct Person p = { .__greeter_vptr = &Person_Greeter_vtable };` |
| `p.greet();` | `p.__greeter_vptr->greet(&p);` |
| `Person *q = &p; q->greet();` | `struct Person *q = &p; q->__greeter_vptr->greet(q);` |
| 方法体内 `self->other();` | `_self->__greeter_vptr->other(_self);`（并在方法函数前补一行 vtable 前向声明） |
| 方法体内 `self->who->greet();` | `_self->who->__greeter_vptr->greet(_self->who);`（字段链递归） |
| 方法体内参数 `o` / 局部变量 `q` 上的 `o->greet();`、`q.greet();` | `o->__greeter_vptr->greet(o);`、`q.__greeter_vptr->greet(&q);`（方法体与顶层代码走同一重写管线） |
| 函数签名 `void f(Person p)` / `Person *q` | `void f(struct Person p)` / `struct Person *q`（参数登记后，体内 `p.greet()` / `q->greet()` 照常重写） |
| `static Person mk(char *n)` | `static struct Person mk(char *n)` |
| `struct Shop { Person owner; };` | `struct Shop { struct Person owner; };` |
| `s.owner.greet();` | `s.owner.__greeter_vptr->greet(&s.owner);` |
| `Person ps[2];` | 声明 + 块内循环逐元素写 vptr，之后 `ps[0].greet()`、`ps[i].greet()` 可派发；`Person *ptrs[2]` 的元素自身是指针，用 `ptrs[i]->greet()` |
| `delete q;` | `if (q) free(q);`（现对**任意指针**成立，含 `char *`） |
| `T *p = malloc(sizeof(struct T));` | 声明后自动写 vptr（含嵌套值字段）：`p->__x_vptr = &T_X_vtable;` |
| `Greeter g = p;`（`Greeter` 是 trait） | `struct Greeter_iface g = (struct Greeter_iface){ (void *)&p, &Person_Greeter_vtable };` |
| `void announce(Greeter who)` / `announce(p)` | 形参展开为 `struct Greeter_iface`；实参按签名表自动装箱 |
| `g.greet();` | `g.vt->greet(g.self);`（运行时按装箱对象派发） |
| `namespace A::B { struct Person … }` | 其中的 struct / trait / impl 符号加前缀 `A_B_`（`struct A_B_Person`、`A_B_Person_Greeter_greet`、`A_B_Person_Greeter_vtable`），vptr 字段仍是 `__greeter_vptr` |
| `A::B::Person p;` | `struct A_B_Person p;`（限定引用 `A::B::Name` → `A_B_Name`） |
| `A::B::fn();` | `fn();`（普通函数名不修饰，只去掉路径） |
| `pub trait T {…}` / `pub struct S {…}`（多文件模式） | 定义写入 `.h`（其它符号只进 `.c`）；`pub` 被剥离，不进入生成的 C |
| `pub int f(int);`（多文件模式） | 函数原型写入 `.h` |
| `import A::B;`（多文件模式，`ct build` 的根文件） | 解析为 `<目录>/A/B.ct`（或 `A/B.h.ct`），递归编入依赖，并在各单元 `.c` 里自动 `#include` 被导入单元的 `.h` |
| 其它任意 C 代码 | 原样透传 |

命名规则：

| 产物 | 规则 | 例子（trait `Greeter`，struct `Person`，方法 `greet`） |
| --- | --- | --- |
| vtable 类型 | `<Trait>_vtbl` | `Greeter_vtbl` |
| vptr 字段 | `__<trait小写>_vptr` | `__greeter_vptr` |
| 方法实现函数 | `<Struct>_<Trait>_<method>` | `Person_Greeter_greet` |
| vtable 变量 | `<Struct>_<Trait>_vtable` | `Person_Greeter_vtable` |

细节约定：

- **`self` 是隐式参数**。方法体与顶层代码走**同一重写管线**：先登记 `self`（指向当前 struct 的指针）与方法参数，再逐行改写，最后把标识符 `self` 重命名为 `_self`。因此 `self->field` → `_self->field`、兄弟调用 `self->other()` → `_self->__<trait>_vptr->other(_self, …)`，字段链 `self->who->m()`、方法参数 `o->m()`、方法体内局部变量 `q.m()` 也都照常派发；生成的函数第一行固定插入 `struct <Struct> *_self = (struct <Struct> *)self;`。
- **调用方传值地址**。`p.greet(1)` → `p.__greeter_vptr->greet(&p, 1)`，`&p` 由编译器自动补上；指针接收者 `p->greet(1)` → `p->__greeter_vptr->greet(p, 1)`，不再补 `&`。
- **多 trait**：`use Greeter, Counter;` 合法，每个 trait 生成一个 vptr 字段；方法名冲突时按 `use` 中的书写顺序取第一个匹配。
- **初始化列表**：指定初始化、位置式初始化、空列表都会在 `}` 前追加 vptr 项；无初始化式的声明 `Person p;` 会被补成 `struct Person p = { .__<trait>_vptr = &… };`。
- **函数签名**：普通函数的返回类型与参数里的已知 struct 名会自动加 `struct `（含 `static` 前缀、多词类型、指针返回、原型）；有函数体的函数，其参数会登记进变量表，体内 `p.greet()` / `q->greet()` 照常重写。
- **块作用域**：变量与参数按花括号块作用域回滚，同名局部变量/参数在不同函数间不会串味。
- **组合 / 数组**：struct 字段若是另一 ct struct 会自动补 `struct ` 并**递归写入内层 vptr**（用声明后的赋值，不会覆盖用户自己写的初始化）；`ps[0].m()`、`ps[i].m()`、`s.owner.m()` 与指针字段链 `b.who->m()` 都会派发（下标可为任意表达式）。`delete q;` 展开为 `if (q) free(q);`。**变量下标**接收者的表达式会被求值两次，带副作用的下标（`ps[i++]`）不保证正确；**右值接收者** `f().m()`（值返回）、`mk()->m()`（指针返回，含字段跳 `f().a.b.m()`）已支持：接收者提升为临时变量 `__ct_tmp<N>` 只求值一次，且仅允许出现在**语句行首**或**赋值/声明初始化式 RHS 行首**，其它位置按 `文件:行:列: error:` 报错。
- **接口多态**：把 trait 当类型用（`Greeter g`）→ 生成胖指针 `struct <Trait>_iface { self, vt }`；`g.greet()` 运行期派发到装箱的具体实现。装箱覆盖**声明、赋值、实参、`return`**（`Greeter g = p;`、`announce(p)`、`return p;`）。
- **字符串/注释安全**：`"p.greet()"` 或 `// p.greet()` 不会被改写；`#` 开头的预处理行完全不参与改写。
- **生成物带溯源注释**：生成的 `.c` 首行与 `.h` 的版本注释形如 `Generated by ctc v0.0.1 from <输入路径>`（版本号来自 `ctc.c` 的 `CTC_VERSION`）。

完整语法定义见 [docs/language-spec.md](docs/language-spec.md)。

### 4. 示例

`examples/` 下每个例子一个目录，只放源文件 `<name>.ct` 与期望输出 `<name>.expected.out`（展开出的 `.c`/`.h` 按需生成，不入库）：

| 目录 | 展示的内容 |
| --- | --- |
| [examples/01_greeter/](examples/01_greeter/greeter.ct) | 最小用例：一个 trait、一个 struct、一次 impl、带参与不带参的方法调用 |
| [examples/02_market/](examples/02_market/market.ct) | 三个 trait / 两个 struct / 三个对象：同一 trait 在不同类型上有不同实现，对象之间传值与嵌套调用（`bob.earn(alice.spend(6))`），解析 `examples/02_market/market.ct` 得到 11 行输出 |
| [examples/03_receivers/](examples/03_receivers/receivers.ct) | 一般接收者：下标元素 `ps[i]`、指针数组元素 `slots[0]`、指针字段链 `b.who` 都能正常派发 |
| [examples/04_rvalue/](examples/04_rvalue/rvalue.ct) | 右值接收者：工厂调用返回的 struct 直接作接收者（`make_person("Ann", 30).greet()`），接收者只求值一次 |
| [examples/05_body_dispatch/](examples/05_body_dispatch/body_dispatch.ct) | 方法体内的派发：字段链递归（`self->lhs->emit()`）、参数与局部变量接收者 |
| [examples/06_iface_field/](examples/06_iface_field/iface_field.ct) | 接口值作 struct 字段：子节点是胖指针，`sum.lhs = one;` 装箱、`self->lhs.show()` 派发，递归组合成表达式树 |

一键跑通全部示例：`./test/run.sh`（examples 层会生成 → 编译 → 运行 → 与 `.expected.out` 比对）。

`examples/01_greeter/greeter.ct`：

```c
trait Greeter {
    void greet();
    void greet_name(char *name);
}

struct Person {
    char *name;
    int age;
} use Greeter;

impl Greeter for Person {
    void greet() {
        printf("Hello, I'm %s, age %d\n", self->name, self->age);
    }
    void greet_name(char *name) {
        printf("Hello %s, I'm %s\n", name, self->name);
    }
}

int main() {
    Person p = { .name = "Tom", .age = 36 };
    p.greet();
    p.greet_name("Jerry");
    return 0;
}
```

生成的核心片段：

```c
struct Greeter_vtbl {
    void (*greet)(void *);
    void (*greet_name)(void *, char *);
};

struct Person {
    char *name;
    int age;
    struct Greeter_vtbl *__greeter_vptr;
};

static void Person_Greeter_greet(void *self) {
    struct Person *_self = (struct Person *)self;
    printf("Hello, I'm %s, age %d\n", _self->name, _self->age);
}

static void Person_Greeter_greet_name(void *self, char *name) {
    struct Person *_self = (struct Person *)self;
    printf("Hello %s, I'm %s\n", name, _self->name);
}

static struct Greeter_vtbl Person_Greeter_vtable = {
    .greet = Person_Greeter_greet,
    .greet_name = Person_Greeter_greet_name
};

int main() {
    struct Person p = { .name = "Tom", .age = 36, .__greeter_vptr = &Person_Greeter_vtable };
    p.__greeter_vptr->greet(&p);
    p.__greeter_vptr->greet_name(&p, "Jerry");
    return 0;
}
```

### 5. 测试

```bash
./test/run.sh            # 全部跑一遍；退出码 0 = 通过
CC=gcc ./test/run.sh     # 指定 C 编译器（默认 cc）
```

```
test/
├── run.sh                       驱动器：构建 → 单测 → golden 快照 → 负例诊断
├── unit/test_helpers.c          白盒单测（40 项断言，直接 include ctc.c 以触达 static 函数）
├── cases/                       golden 正例：<name>.ct + <name>.expected.c / .h / .out
└── errors/                      负例：<name>.ct + <name>.expected-err
```

五层断言：

| 层 | 断言内容 |
| --- | --- |
| build | `ctc` 自身在 `-Wall -Wextra -std=c99` 下零警告 |
| unit | `trim` / `param_type_only` / `parse_params` / `split_decl` / `decl_end_is_bare` / `put_own_vptr` / `put_nested_assignments` / `last_ident` / `already_qualified` / `analyse_param` / `emit_qualified_type` / `word_at` / `match_delim` 等纯函数的 68 项断言 |
| cases | `ctc` 退出 0 → 生成物与 golden 逐字节一致（`.c` 与 `.h`）→ 生成物编译通过 → 含 `main` 的用例运行 stdout 与 golden 一致 |
| examples | `examples/**` 端到端：生成 → 用 `-Wall -Wextra` 构建 → 运行 → stdout 与 `.expected.out` 一致（不做逐字节比对，只保证示例真的能跑） |
| errors | `ctc` 必须非 0 退出，诊断必须带 `文件:行:列: error:` 前缀且包含期望文案 |

当前 28 个 golden 正例（`test/cases`）、6 个端到端示例（`examples`）与 63 个负例诊断用例（`test/errors`），另加 unit / multifile / import / `#line` / warnings / limits / cli 等分层断言。

`test/cases/*.expected.*` 是 golden 基线，**只能**用 `./ctc <case>.ct -o <case>.expected.c` 重新生成后人工核对，禁止手写；`examples/**/*.expected.out` 同理（见 [AGENTS.md](AGENTS.md) 第 6 节）。`test/cases/01_trait_basic.ct` 与 `examples/01_greeter/greeter.ct` 内容相同，但前者做生成物逐字节比对、后者做运行结果比对，两者互补。

VS Code 插件另有一份独立的语法冒烟测试，校验的是高亮规则而不是编译器，因此不进 `./test/run.sh`：

```bash
python3 editors/vscode/test/check-grammar.py   # 13 项断言；退出码 0 = 通过
```

### 6. 目录结构

```
ct/
├── ctc.c                     编译器全部实现（单文件，无第三方依赖）
├── examples/                 可运行示例，每个例子一个目录
│   ├── 01_greeter/           greeter.ct   + greeter.expected.out
│   ├── 02_market/            market.ct    + market.expected.out
│   ├── 03_receivers/         receivers.ct + receivers.expected.out
│   └── 04_rvalue/            rvalue.ct    + rvalue.expected.out
├── test/                     测试：runner、白盒单测、golden 正例与负例
├── editors/vscode/           VS Code 插件：CT 语法高亮 + 片段（纯 JSON，无构建，MIT）
├── .gitignore                忽略构建产物与 examples 下的生成物
├── LICENSE                   GPL-3.0 全文（编译器本体）
├── LICENSE.EXCEPTION         输出例外 + examples/test/editors 的 MIT
├── README.md                 本文件
├── AGENTS.md                 给 AI 编码代理的项目规约
└── docs/
    ├── vision.md             定位、设计原则与生态策略（为什么）
    ├── roadmap.md            阶段规划、已定决策与验收标准（接下来做什么）
    ├── language-spec.md      .ct 语法规范与展开规则（现状）
    ├── architecture.md       编译器内部结构与关键算法
    └── design/bootstrap.md   自举设计草案（未实现）
```

展开产物（`.c` / `.h`、可执行文件）一律不入库，写到临时目录或按需生成。

### 7. 已知限制与问题

**设计内不做（Phase 0 明确排除）**

- 可见性修饰符（`pub` / `readonly` / `setter`）
- 泛型、继承、多文件编译
- 类型检查、错误恢复（遇错即退出）
- 嵌套定义（`namespace` 已支持，是唯一可嵌套的构造）

**当前实现限制**

- 变量与参数按花括号块作用域回滚（同一作用域内同名取最先登记者）；跨行的方法调用语句、以及参数列表跨多行的函数签名不识别。
- **文件作用域的对象 / 数组**：vptr 由生成的构造器 `__ct_init`（`__attribute__((constructor))`，D5=A）在 `main` 前写入（单文件与多文件模式均生效）。
- 数组只支持 `Type name[<n>];`（无初始化式、常量下标）。
- **堆对象 vptr 自动写入**：`T *p = malloc(sizeof(struct T));`（或 `calloc`）会在声明后自动写 vptr（含嵌套值字段）；不再需要手写。`use Drop` 的类型在 `delete` 时递归释放其 Drop 值字段（见 §3 的 `Drop`）。
- **泄漏警告**：局部 ct-struct 堆对象在其作用域结束前既未 `delete`、未 `return`、也未逃逸（赋给非自身左值）时告警——保守、路径不敏感，**不影响退出码**（仍 0）；`--diagnostics=json` 输出 JSON，暂无抑制语法。
- 接口多态：接口**数组**不支持；接口**字段**不参与构造期自动装箱（类型会展开，可手动赋值）；装箱只接受变量、`&变量` 或返回同款接口的调用。
- **命名空间只修饰 struct / trait / impl 的符号与限定类型引用**；普通函数名不修饰，因此不同 namespace 下的同名普通函数会在 C 层重名冲突。
- **多文件模式**（`ctc build`）：生成的 `.c` 会 `#include` 自己的 `.h`（不再自包含）；只有 `pub` 的 trait/struct 定义与 `pub` 函数原型进 `.h`；用 `import A::B;` 可跨单元按名使用被导入单元的 `pub` 类型；默认在 `.c` 里发 `#line`（单文件模式默认关，`--line`/`--no-line` 覆盖）；但**跨单元使用带 trait 的对象**（写 vptr / 装箱）尚不可（被导入单元的 vtable 仍是 `static`）。
- 定义必须先于使用：`impl` 必须出现在调用它的函数之前，否则生成的 C 无法编译。
- **构造头部必须完整**：`trait IDENT {` / `struct IDENT {` / `impl IDENT for` 缺一不可；只写到一半
  （如 `trait T`、`struct S`、`impl`）**不报错**，该行按普通 C **原样透传**——这是为兼容把
  `trait` / `impl` 当普通标识符的合法 C（如 `impl[i] = 0;`）。
- **构造与语句写在同一行时不重写**：重写按行进行，`int main(void){ Person p = { … }; p.greet(); }`
  里的 `p.greet()` 不会被改写（拆成多行即可）。
- **容量上限一律报错、不静默截断**：标识符 ≤ 127、函数参数 ≤ 16、参数表文本 ≤ 255、函数签名表 64、
  变量 512、嵌套作用域 256、struct 字段 32、trait 16、struct 32、方法 32、嵌套深度 8、`ct build`
  输入 32 / 编译单元 64 / 每单元 import 16。

### 8. 相关文档

- [AGENTS.md](AGENTS.md) —— 改动边界、代码风格、验证流程
- [docs/glossary.md](docs/glossary.md) —— 术语表：统一项目名、语言构造与内部符号
- [docs/vision.md](docs/vision.md) —— 定位、设计原则与生态策略
- [docs/roadmap.md](docs/roadmap.md) —— 后续阶段与已定决策
- [docs/language-spec.md](docs/language-spec.md) —— 语法规范
- [docs/architecture.md](docs/architecture.md) —— 内部实现
- [docs/design/bootstrap.md](docs/design/bootstrap.md) —— 自举设计草案（未实现）

### 9. 许可

| 对象 | 许可 |
| --- | --- |
| 编译器本体（`ctc.c`、`ctc`） | **GPL-3.0-or-later**，全文见 [LICENSE](LICENSE) |
| 你的 `.ct` 源码、ctc 生成的 `.c`/`.h`、以及用它们构建的程序 | **不受 GPL 约束**，可任意许可、可闭源分发，见 [LICENSE.EXCEPTION](LICENSE.EXCEPTION) |
| `examples/`、`test/` 与 `editors/vscode/`（VS Code 插件） | **MIT**（方便直接抄进你自己的项目） |

ctc 会往产物里插入样板（vtable 结构体、`__<trait>_vptr` 字段、`_self` 强转行），而"编译器输出算不算衍生作品"本有争议，因此这里照 GNU Bison 的先例**显式声明例外**，并让它**随产物走**——每条生成的 `.c`/`.h` 都在 banner 里重复这句话。

### 10. 联系

- 作者：Sam X. Xu
- 邮箱：samxxu@gmail.com
- 问题、建议与 bug：优先开 [Issue](https://github.com/samxxu/ct-lang/issues)，这样答案能被别人搜到；不适合公开的内容再发邮件。

---

## English

**ct** is a **source-to-source compiler** that translates `.ct` files (C plus trait syntax) into
plain C. It performs no type checking and no optimisation; Phase 0 ("writing full OO with traits") is
complete and the current goal is **self-hosting** (Phase 1, rewriting the compiler in CT) — what is
done and what is planned is tracked in [docs/roadmap.md](docs/roadmap.md).

Naming: the project and language are **ct** (*C with Traits*, files end in `.ct`), the compiler
command is **`ctc`** (the ct compiler — much like the `tinycc` repository that ships a `tcc` binary)
and the GitHub repository is **`ct-lang`** (`ct` alone is too short to be findable there).

### 1. Motivation

C has no vtables. Simulating interfaces and polymorphism by hand means writing the same boilerplate
over and over: the vtable struct, the function-pointer assignments, a cast at the top of every method,
and filling in the vptr when an object is created. `ctc` lets you declare those things with near-Rust
syntax and generates the boilerplate for you. The output is **readable, ordinary C** with no runtime
library dependency.

### 2. Quick start

```bash
gcc ctc.c -o ctc
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

| Usage | Result |
| --- | --- |
| `ctc <input.ct>` | writes `<input>.c` and `<input>.h` (single-file mode) |
| `ctc <input.ct> -o <output.c>` | writes the given path plus a sibling `.h` |
| `ctc compile <input.ct>` | the same (`compile` is the default subcommand) |
| `ctc build <a.ct> <b.ct>… -o <dir>` | **multi-file mode**: each input produces `<dir>/<base>.c` + `.h`; the `.c` includes its own `.h`; `pub` symbols go into the `.h`; then the suggested `cc …` command is printed (ctc never runs `cc`) |
| `--line` / `--no-line` | force `#line` directives on / off (on by default in multi-file mode, off single-file), so C errors map back to the `.ct` |
| `--diagnostics=json` / `--diagnostics=text` | warning format: JSON (`ct compile` → stdout) or human-readable stderr (default); leak warnings only, for now |
| `ctc -v` / `ctc --version` | prints the version, e.g. `ctc v0.0.1` |
| `ctc -h` / `ctc --help` | prints usage |

Exit code `0` on success, `1` on syntax or I/O errors. Diagnostics use `file:line:col: error: message`.

### 3. Syntax and expansion rules

| Input (`.ct`) | Output (`.c`) |
| --- | --- |
| `trait Greeter { void greet(); }` | `struct Greeter_vtbl { void (*greet)(void *); };` |
| `struct Person { char *name; } use Greeter;` | `struct Person { char *name; struct Greeter_vtbl *__greeter_vptr; };` |
| `impl Greeter for Person { void greet() {…} }` | `static void Person_Greeter_greet(void *self) { struct Person *_self = (struct Person *)self; … }` + `static struct Greeter_vtbl Person_Greeter_vtable = { .greet = Person_Greeter_greet };` |
| `Person p = { .name = "Tom" };` | `struct Person p = { .name = "Tom", .__greeter_vptr = &Person_Greeter_vtable };` |
| `Person p = { "Tom", 36 };` | `struct Person p = { "Tom", 36, .__greeter_vptr = &Person_Greeter_vtable };` |
| `Person p;` | `struct Person p = { .__greeter_vptr = &Person_Greeter_vtable };` |
| `p.greet();` | `p.__greeter_vptr->greet(&p);` |
| `Person *q = &p; q->greet();` | `struct Person *q = &p; q->__greeter_vptr->greet(q);` |
| `self->other();` inside a method body | `_self->__greeter_vptr->other(_self);` (plus a vtable forward declaration before the method functions) |
| `self->who->greet();` inside a method body | `_self->who->__greeter_vptr->greet(_self->who);` (recursive field chain) |
| `o->greet();` / `q.greet();` on a method-body parameter `o` or local `q` | `o->__greeter_vptr->greet(o);` / `q.__greeter_vptr->greet(&q);` (bodies share the top-level pipeline) |
| signature `void f(Person p)` / `Person *q` | `void f(struct Person p)` / `struct Person *q` (with the parameter registered, so `p.greet()` / `q->greet()` inside the body is rewritten) |
| `static Person mk(char *n)` | `static struct Person mk(char *n)` |
| `struct Shop { Person owner; };` | `struct Shop { struct Person owner; };` |
| `s.owner.greet();` | `s.owner.__greeter_vptr->greet(&s.owner);` |
| `Person ps[2];` | the declaration plus a scoped loop writing each element's vptr, after which `ps[0].greet()` and `ps[i].greet()` dispatch; an element of `Person *ptrs[2]` is itself a pointer, so `ptrs[i]->greet()` |
| `delete q;` | `if (q) free(q);` (this now holds for **any** pointer, `char *` included) |
| `T *p = malloc(sizeof(struct T));` | the vptrs (including nested value fields) are written right after the declaration: `p->__x_vptr = &T_X_vtable;` |
| `Greeter g = p;` (`Greeter` is a trait) | `struct Greeter_iface g = (struct Greeter_iface){ (void *)&p, &Person_Greeter_vtable };` |
| `void announce(Greeter who)` / `announce(p)` | the parameter becomes `struct Greeter_iface`; the argument is boxed from the signature table |
| `g.greet();` | `g.vt->greet(g.self);` (dispatches at run time to whatever was boxed) |
| `namespace A::B { struct Person … }` | struct / trait / impl symbols get the prefix `A_B_` (`struct A_B_Person`, `A_B_Person_Greeter_greet`, `A_B_Person_Greeter_vtable`); the vptr field stays `__greeter_vptr` |
| `A::B::Person p;` | `struct A_B_Person p;` (a qualified reference `A::B::Name` → `A_B_Name`) |
| `A::B::fn();` | `fn();` (plain function names are not mangled — only the path is dropped) |
| `pub trait T {…}` / `pub struct S {…}` (multi-file mode) | the definition goes into the `.h` (everything else stays in the `.c`); the `pub` itself is stripped and never appears in the generated C |
| `pub int f(int);` (multi-file mode) | the function prototype goes into the `.h` |
| `import A::B;` (multi-file mode, in a `ct build` root) | resolved to `<dir>/A/B.ct` (or `A/B.h.ct`), dependencies compiled recursively, and each unit's `.c` automatically `#include`s the imported unit's `.h` |
| anything else | copied through verbatim |

Naming rules:

| Artifact | Rule | Example |
| --- | --- | --- |
| vtable type | `<Trait>_vtbl` | `Greeter_vtbl` |
| vptr field | `__<lowercase trait>_vptr` | `__greeter_vptr` |
| method body | `<Struct>_<Trait>_<method>` | `Person_Greeter_greet` |
| vtable variable | `<Struct>_<Trait>_vtable` | `Person_Greeter_vtable` |

Additional rules:

- **`self` is an implicit parameter.** A method body goes through the **same rewriting pipeline as
  top-level code**: `self` (a pointer to the current struct) and the method parameters are registered
  first, then every line is rewritten, and finally the identifier `self` is renamed to `_self`. Hence
  `self->field` → `_self->field`, a sibling call `self->other()` →
  `_self->__<trait>_vptr->other(_self, …)`, and a field chain `self->who->m()`, a parameter `o->m()` or
  a body-local `q.m()` all dispatch; the generated function always starts with
  `struct <Struct> *_self = (struct <Struct> *)self;`.
- **Callers pass the address.** `p.greet(1)` becomes `p.__greeter_vptr->greet(&p, 1)`; a pointer
  receiver `p->greet(1)` becomes `p->__greeter_vptr->greet(p, 1)` — no `&` is added.
- **Multiple traits** are allowed: `use Greeter, Counter;` adds one vptr field per trait. If two traits
  declare the same method name, the first one in the `use` list wins.
- **Initialiser lists** get vptr designators whether they are designated, positional or empty; a
  declaration without an initialiser, `Person p;`, becomes
  `struct Person p = { .__<trait>_vptr = &… };`.
- **Function signatures:** known struct names in a function's return type and parameters get a
  `struct ` prefix (including `static` prefixes, multi-word types, pointer returns and prototypes);
  when the function has a body its parameters are registered, so `p.greet()` / `q->greet()` inside
  the body is rewritten as usual.
- **Block scoping:** variables and parameters roll back at brace block scope, so same-named locals or
  parameters in different functions no longer bleed into each other.
- **Composition / arrays:** a struct field of another ct struct gains `struct ` and its inner vptr is
  written **recursively** (via post-declaration assignments, so user initialisers are never
  overridden); `ps[0].m()`, `ps[i].m()`, `s.owner.m()` and the pointer field chain `b.who->m()` all
  dispatch (any subscript expression is accepted). `delete q;` expands to `if (q) free(q);`. A
  **variable-subscript** receiver's expression is evaluated twice, so a subscript with a side effect
  (`ps[i++]`) is not guaranteed correct; an **rvalue receiver** `f().m()` (returned by value),
  `mk()->m()` (returned by pointer, including the field hop `f().a.b.m()`) is supported: the receiver
  is hoisted into a `__ct_tmp<N>` temporary and evaluated exactly once, and may only appear at the
  **statement head** or the **RHS of an assignment / declaration initialiser** — any other position
  reports `file:line:col: error:`.
- **Interface polymorphism:** using a trait as a type (`Greeter g`) generates the fat pointer
  `struct <Trait>_iface { self, vt }`; `g.greet()` dispatches at run time to the boxed implementation.
  Boxing covers **declarations, assignments, arguments and `return`** (`Greeter g = p;`, `announce(p)`,
  `return p;`).
- **String and comment safe:** `"p.greet()"` and `// p.greet()` are left alone, and lines starting
  with `#` are never rewritten.
- **Provenance banner:** the generated `.c` starts with, and the `.h` carries, a comment of the form
  `Generated by ctc v0.0.1 from <input path>` (the version comes from `CTC_VERSION` in `ctc.c`).

The full grammar lives in [docs/language-spec.md](docs/language-spec.md).

### 4. Examples

Each example lives in its own directory under `examples/` and holds only its source (`<name>.ct`)
plus its expected output (`<name>.expected.out`); the expanded `.c`/`.h` are generated on demand and
never committed.

| Directory | What it shows |
| --- | --- |
| [examples/01_greeter/](examples/01_greeter/greeter.ct) | The minimal case: one trait, one struct, one impl, calls with and without arguments |
| [examples/02_market/](examples/02_market/market.ct) | Three traits, two structs, three objects: the same trait implemented differently per type, values flowing between objects, and a nested call (`bob.earn(alice.spend(6))`); compiling `examples/02_market/market.ct` yields 11 lines of output |
| [examples/03_receivers/](examples/03_receivers/receivers.ct) | General receivers: a subscripted element `ps[i]`, a pointer-array element `slots[0]` and a pointer field chain `b.who` all dispatch normally |
| [examples/04_rvalue/](examples/04_rvalue/rvalue.ct) | An rvalue receiver: the struct returned by a factory call is used directly (`make_person("Ann", 30).greet()`); the receiver is evaluated exactly once |
| [examples/05_body_dispatch/](examples/05_body_dispatch/body_dispatch.ct) | Dispatch inside a method body: a recursive field chain (`self->lhs->emit()`), parameter and local-variable receivers |
| [examples/06_iface_field/](examples/06_iface_field/iface_field.ct) | An interface value as a struct field: children are fat pointers, `sum.lhs = one;` boxes and `self->lhs.show()` dispatches, composing a recursive expression tree |

`./test/run.sh` builds and runs every example and compares its output with the committed expectation.

`examples/01_greeter/greeter.ct`:

```c
trait Greeter {
    void greet();
    void greet_name(char *name);
}

struct Person {
    char *name;
    int age;
} use Greeter;

impl Greeter for Person {
    void greet() {
        printf("Hello, I'm %s, age %d\n", self->name, self->age);
    }
    void greet_name(char *name) {
        printf("Hello %s, I'm %s\n", name, self->name);
    }
}

int main() {
    Person p = { .name = "Tom", .age = 36 };
    p.greet();
    p.greet_name("Jerry");
    return 0;
}
```

The core of the generated expansion:

```c
struct Greeter_vtbl {
    void (*greet)(void *);
    void (*greet_name)(void *, char *);
};

struct Person {
    char *name;
    int age;
    struct Greeter_vtbl *__greeter_vptr;
};

static void Person_Greeter_greet(void *self) {
    struct Person *_self = (struct Person *)self;
    printf("Hello, I'm %s, age %d\n", _self->name, _self->age);
}

static void Person_Greeter_greet_name(void *self, char *name) {
    struct Person *_self = (struct Person *)self;
    printf("Hello %s, I'm %s\n", name, _self->name);
}

static struct Greeter_vtbl Person_Greeter_vtable = {
    .greet = Person_Greeter_greet,
    .greet_name = Person_Greeter_greet_name
};

int main() {
    struct Person p = { .name = "Tom", .age = 36, .__greeter_vptr = &Person_Greeter_vtable };
    p.__greeter_vptr->greet(&p);
    p.__greeter_vptr->greet_name(&p, "Jerry");
    return 0;
}
```

### 5. Tests

```bash
./test/run.sh            # run everything; exit code 0 means it passed
CC=gcc ./test/run.sh     # pick a C compiler (default: cc)
```

```
test/
├── run.sh                       driver: build → unit → golden snapshots → diagnostics
├── unit/test_helpers.c          white-box unit tests (68 assertions; includes ctc.c to reach statics)
├── cases/                       golden positives: <name>.ct + <name>.expected.c / .h / .out
└── errors/                      negatives: <name>.ct + <name>.expected-err
```

Five layers of assertions:

| Layer | What is asserted |
| --- | --- |
| build | `ctc` itself compiles warning-free under `-Wall -Wextra -std=c99` |
| unit | 68 assertions on pure helpers (`trim`, `param_type_only`, `parse_params`, `split_decl`, `decl_end_is_bare`, `put_own_vptr`, `put_nested_assignments`, `last_ident`, `already_qualified`, `analyse_param`, `emit_qualified_type`, `word_at`, `match_delim`, …) |
| cases | `ctc` exits 0 → generated `.c` and `.h` are byte-identical to the goldens → the generated C compiles → runnable cases produce the golden stdout |
| examples | `examples/**` end to end: generate → build with `-Wall -Wextra` → run → stdout matches `.expected.out` (no byte-level diff; the point is that the demos really run) |
| errors | `ctc` must exit non-zero, and the diagnostic must carry a `file:line:col: error:` prefix and contain the expected text |

Currently 28 golden positives (`test/cases`), 6 end-to-end examples (`examples`) and 63 negative
diagnostic cases (`test/errors`), plus layered assertions for unit / multifile / import / `#line` /
warnings / limits / cli.

`test/cases/*.expected.*` are golden baselines: regenerate them with
`./ctc <case>.ct -o <case>.expected.c` and review the result — never hand-write them. The same rule
applies to `examples/**/*.expected.out` (see [AGENTS.md](AGENTS.md) §6).
`test/cases/01_trait_basic.ct` and `examples/01_greeter/greeter.ct` hold the same program, but the
former asserts a byte-identical expansion while the latter asserts runtime output — they complement
each other.

The VS Code extension carries its own smoke test for the highlighting rules. It checks the extension,
not the compiler, so it is deliberately not part of `./test/run.sh`:

```bash
python3 editors/vscode/test/check-grammar.py   # 13 checks; exit code 0 means it passed
```

### 6. Directory layout

```
ct/
├── ctc.c                     the whole compiler (single file, no third-party dependencies)
├── examples/                 runnable demos, one directory per example
│   ├── 01_greeter/           greeter.ct   + greeter.expected.out
│   ├── 02_market/            market.ct    + market.expected.out
│   ├── 03_receivers/         receivers.ct + receivers.expected.out
│   └── 04_rvalue/            rvalue.ct    + rvalue.expected.out
├── test/                     tests: runner, white-box unit tests, golden positives and negatives
├── editors/vscode/           VS Code extension: CT highlighting + snippets (pure JSON, no build, MIT)
├── .gitignore                ignores build products and the files generated under examples
├── LICENSE                   GPL-3.0 full text (the compiler itself)
├── LICENSE.EXCEPTION         the output exception + MIT for examples/test/editors
├── README.md                 this file
├── AGENTS.md                 the project contract for AI coding agents
└── docs/
    ├── vision.md             positioning, design principles and ecosystem strategy (the why)
    ├── roadmap.md            phase plan, decided decisions and acceptance criteria (what is next)
    ├── language-spec.md      .ct grammar and expansion rules (current state)
    ├── architecture.md       compiler internals and key algorithms
    └── design/bootstrap.md   bootstrap design draft (not implemented)
```

Expanded artifacts (`.c` / `.h`, executables) are never committed; write them to a temporary
directory or generate them on demand.

### 7. Known limitations

Not supported by design (Phase 0): visibility modifiers, generics, inheritance, multi-file
compilation, type checking, error recovery, nested definitions (`namespace` is supported — it is the
only nestable construct).

Implementation limits:

- Variables and parameters roll back at brace block scope (within one scope a repeated name resolves
  to the earliest registration); multi-line call statements, and function signatures whose parameter
  list spans several lines, are not rewritten.
- **File-scope objects / arrays**: the vptr is written before `main` by the generated constructor
  `__ct_init` (`__attribute__((constructor))`, D5=A), in both single- and multi-file mode.
- Arrays only support `Type name[<n>];` (no initialiser, constant subscripts).
- **Heap-object vptrs are written automatically**: `T *p = malloc(sizeof(struct T));` (or `calloc`)
  writes the vptrs (including nested value fields) right after the declaration; no hand-written vptr is
  needed any more. A `use Drop` type releases its Drop value fields recursively on `delete` (see §3).
- **Leak warnings**: a local ct-struct heap object that is neither `delete`d, `return`ed, nor escaped
  (assigned to a non-self lvalue) before its scope ends is reported — conservative and
  path-insensitive, and it **never changes the exit code** (still 0); `--diagnostics=json` emits JSON,
  and there is no suppression syntax yet.
- Interface polymorphism: interface **arrays** are unsupported; interface **fields** are not boxed
  automatically at construction (the type is expanded and can be assigned by hand); boxing accepts only
  a variable, `&variable` or a call returning the same interface.
- **A namespace only mangles struct / trait / impl symbols and qualified type references**; plain
  function names are not mangled, so same-named plain functions in different namespaces collide at the
  C level.
- **Multi-file mode** (`ctc build`): the generated `.c` includes its own `.h` (no longer self-contained);
  only `pub` trait/struct definitions and `pub` function prototypes cross into the `.h`; `import A::B;`
  lets a unit use an imported unit's `pub` type names by name; `#line` is emitted in the `.c` by default
  (single-file mode is off; `--line`/`--no-line` override); but using an imported unit's
  **trait-carrying objects** (writing a vptr / boxing) is not yet possible (its vtables stay `static`).
- Definitions must precede use: an `impl` must appear before any function that calls its methods.
- **A construct header must be complete**: `trait IDENT {` / `struct IDENT {` / `impl IDENT for`. A
  half-written header (`trait T`, `struct S`, `impl`) is **not an error** — the line is **passed through
  as plain C**, so that legal C using `trait` / `impl` as ordinary identifiers (`impl[i] = 0;`) keeps
  working.
- **A construct and a statement on the same line**: rewriting is line-based, so `p.greet()` inside
  `int main(void){ Person p = { … }; p.greet(); }` is not rewritten (split it across lines).
- **Capacity limits are hard errors, never silent truncation**: identifier ≤ 127, function parameters
  ≤ 16, parameter-list text ≤ 255, signature table 64, variables 512, nested scopes 256, struct fields
  32, traits 16, structs 32, methods 32, nesting depth 8, `ct build` inputs 32 / units 64 / imports
  per unit 16.

### 8. Documentation

- [AGENTS.md](AGENTS.md) — change boundaries, code style, verification workflow
- [docs/glossary.md](docs/glossary.md) — glossary: canonical project, language and internal-symbol terms
- [docs/vision.md](docs/vision.md) — positioning, design principles, ecosystem strategy
- [docs/roadmap.md](docs/roadmap.md) — phase plan and decided design decisions
- [docs/language-spec.md](docs/language-spec.md) — language specification
- [docs/architecture.md](docs/architecture.md) — implementation internals
- [docs/design/bootstrap.md](docs/design/bootstrap.md) — bootstrap design draft (not implemented)

### 9. License

| What | License |
| --- | --- |
| The compiler itself (`ctc.c`, `ctc`) | **GPL-3.0-or-later**, full text in [LICENSE](LICENSE) |
| Your `.ct` sources, the `.c`/`.h` ctc generates from them, and the programs you build from that code | **not covered by the GPL** — license them however you like, including closed source; see [LICENSE.EXCEPTION](LICENSE.EXCEPTION) |
| Everything under `examples/`, `test/` and `editors/vscode/` (the VS Code extension) | **MIT**, so you can copy the samples straight into your own projects |

ctc inserts boilerplate of its own into the output (vtable structs, `__<trait>_vptr`
fields, the `_self` cast line), and whether compiler output counts as a derivative
work is debated. So ctc states the exception explicitly, following the GNU Bison
precedent, and makes it **travel with the output**: every generated `.c`/`.h`
repeats that sentence in its banner.

### 10. Contact

- Author: Sam X. Xu
- Email: samxxu@gmail.com
- Questions, suggestions and bugs: please open an [issue](https://github.com/samxxu/ct-lang/issues) first, so the answer stays searchable for everyone; email me directly for anything that should not be public.
