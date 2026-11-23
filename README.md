# ct — C with Traits 编译器

> **v0.88.3** · 中文 · [English](README.en.md)

**ct** 是一个 **source-to-source 编译器**：把带 trait 语法的 `.ct` 源文件翻译成纯 C 的 `.c` 文件。
`ct compile` 不做类型检查、不做优化；`ct build` 自 SH-115 起默认以 `--check-level=warn` 跑 B 的
静态类型检查（赋值/初值/`return`/`$` 目标/调用实参；`--check-level=off` 可静默），只报
`warning:`、生成物不变；`ct check` 只做受限语义检查（调用点 arity、实参类型、trait 方法歧义、
impl 签名漂移）。需要更早发现类型问题时用 `ct check --types`（可选子集，见
[spec §4.53](docs/language-spec.md#453-可选类型检查-ct-check---typesphase-32)）。生成物是
**可读的普通 C**，vtable 与 `_self` 强转等样板代码都由编译器生成。

**兼容承诺（v1.0 起）**：Ct 不再自称 C 超集。C 的表达式、语句与类型核心仍按原语法透传，但不再
承诺 C 全集（函数式宏、strict 边界下的 `#include`、旧 L1/L2 管线语法），也不以“C 代码原样全收”
为目标。旧工程用 v0.x 编译器或 `ct migrate`；`T a[]`、`Box`、`CharStr`、`lib/std` → `lib/core`
的迁移/弃用窗口见 [spec §1.2](docs/language-spec.md)。
<!-- ct-compat: not-c-superset claim=v1.0-not-c-superset spec=1.2 -->

已完成的能力与后续阶段见 [docs/roadmap.md](docs/roadmap.md)，术语见 [docs/glossary.md](docs/glossary.md)。

---

### 0. 真实用法展示

下面每条都解决一个具体问题；代码块后的命令与输出是 v0.88.3 的实测结果（`cc` 用系统 C 编译器）。

#### 0.1 HTTP 请求：完整路径的目标形态与当前可跑的静态宿主

完整路径的目标形态是一条链：字符串起手 → `char *` 上的 factory 返回 trait 定义的对象 →
配置方法返回同一接口类型 → `send()` 换响应接口。调用点只写这一条：

```c
int status = "https://api.example.com/users"
                 .method("GET")
                 .header("Accept", "application/json")
                 .timeout(3000)
                 .send()
                 .status();
```

v0.88.3 的实测边界：

| 形态 | 命令与结果 | 结论 |
| --- | --- | --- |
| 接口值落变量后逐跳 | `Counter d = c.tap(1);` 再 `d.status()`：编译并运行，输出 `1`，rc=0 | 可用（SH-72 / SH-74） |
| 同一形状压成一行链 | `c.tap(1)->status()` → `error: method receiver must be a variable, an element, a call or a field chain`，rc=1 | **当前不支持**；[SH-110](issues/selfhost/sh110-dynamic-dispatch-chain-fix.md)（deferred，待修复） |
| 返回局部接口值 | `ct build test/ast/239_local_iface_return/prog.ct` → `0 201`，rc=0 | 可用（SH-75） |
| 静态宿主链 | `ct build examples/47_chain_factory/src/main.ct -o /tmp/http47` 再跑 → `200 {"users":3}`，rc=0 | 可用；宿主是 struct，不是 trait 对象 |

**不要按“完整路径已支持”宣传**：上表第二行就是缺口，跟踪卡是
[SH-110](issues/selfhost/sh110-dynamic-dispatch-chain-fix.md)（deferred，待修复）；合入后本表与
[spec §4.10.1](docs/language-spec.md#4101-链式构建器范式权威定义与两档路径) 一起更新。
当前可运行版 [examples/47](examples/47_chain_factory/src/main.ct) 是**静态宿主形态**：宿主在映射
单元内部是 struct，使用者代码里看不到它，也没有 vtable 与装箱。`send()` 是 stub，接真 curl 只换
[examples/47 的 shim](examples/47_chain_factory/src/http/http.shim.h)。

#### 0.2 字符串切分：轻量路径

没有状态、只有一种实现时，不要把转换包成对象：把方法直接挂在 `char *` 上，方法返回 `char *`
就能继续链。调用点只有一行：

```c
int n = "alpha,beta,gamma".split_once(',').split_once(',').len();
```

完整映射单元、shim 与实跑输出见 [examples/48_string_steps](examples/48_string_steps/src/main.ct)：
`ct build examples/48_string_steps/src/main.ct -o /tmp/text48 && /tmp/text48` → `gamma 5`。
这一档没有 vtable、没有装箱；需要多实现时再走 0.1 的完整路径。

#### 0.3 异构对象：一张表里放不同形状

新增一种形状只加一个 `impl`，`foreach` 里的 `item.area()` 不用改；容器里存接口值，调用点不出现
`enum kind` 或 `switch`。

```c
//@ct-requires: ct-ast
#include <stdio.h>

trait Shape { int area(); }
struct Rect { int w; int h; } use Shape;
struct Circle { int r; } use Shape;

impl Shape for Rect { int area() { return self->w * self->h; } }
impl Shape for Circle { int area() { return 3 * self->r * self->r; } }

int main(void)
{
    Vec<Shape> shapes;
    struct Rect r = { 3, 4 };
    struct Circle c = { 5 };
    int total = 0;

    shapes.h = 0;
    shapes.push(r);
    shapes.push(c);
    foreach (shapes) {
        total = total + item.area();
    }
    printf("%d %d %d\n", r.area(), c.area(), total);
    shapes.release();
    return 0;
}
```

`ct build` 实测输出 `12 75 87`；完整的多实现样例见
[examples/02_market](examples/02_market/market.ct)。

#### 0.4 词频统计：`Map` 按插入序出报告

`Map<char *, int>` 直接表达「词 → 次数」，`get` 命中就加一，不命中就 `put`；`foreach` 给出插入序，
报告顺序稳定，不需要额外的索引表。核心循环如下（完整程序见
[examples/25_wordcount](examples/25_wordcount/wordcount.ct)）：

```c
Map<char *, int> counts;
counts.h = 0;
foreach (words) {
    int *slot = counts.get(item);
    if (slot != 0) {
        *slot = *slot + 1;
    } else {
        counts.put(item, 1);
    }
}
foreach (counts) {
    printf("%s=%d\n", item.key, item.value);
}
counts.release();
```

`ct build` 实测输出 `go=3` / `ct=2` / `rust=1`。

#### 0.5 新句柄速览：ref/out、切片、String/Str、box/new、ADT/match

v0.78–v0.84 的五条新能力各有最小可跑样例，都不依赖 shim；完整程序在 `examples/50…53` 与
tutorial 对应章节。

| 能力 | 最小样例 | 实跑输出 |
| --- | --- | --- |
| `ref` / `out` | [examples/50_ref_out](examples/50_ref_out/prog.ct) | `2 3 4` |
| 切片 `T[]` | [examples/51_slice](examples/51_slice/prog.ct) | `14 5 5` |
| `String` / `Str` | 下段 | `hello, ct` |
| `box<T>` / `new` | [examples/52_box_new](examples/52_box_new/prog.ct) | `4 4` |
| ADT / `match` | [examples/53_match_adt](examples/53_match_adt/prog.ct) | `hi` |

`String` 拥有、`Str` 借用，判据只有一条：这份数据过了这行还要活着 → `String`；只看一眼 → `Str`。

```ct
String greet(Str name)
{
    return str_concat("hello, ", name);
}

int main(void)
{
    String who = "ct";
    String msg = greet(who.as_str());
    printf("%s\n", msg.cstr());
    msg.release();
    return 0;
}
```

`ct build` 实测 `hello, ct`。逐章解释见 tutorial §15（`ref`/`out`）、§17（`box`/`new`，`at()` 借用与
`release()`）、§18（穷尽 `match` 与 owning payload 显式释放）、§22（`String`/`Str`）、§23（切片）。
运行任一 example：`ct build examples/50_ref_out/prog.ct -o /tmp/e50 && /tmp/e50`。

### 1. 快速开始

0.1 的静态宿主链就是本仓库的第一个完整样例：

```sh
ct build examples/47_chain_factory/src/main.ct -o /tmp/http47
/tmp/http47
# 200 {"users":3}
```

安装完整编译器，或只构建 L0 种子跑单文件程序：

```bash
# 安装（下载源码 → 本地四级自举 → 装到 ~/.local/bin）
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh

# 或者不安装，只用 L0 种子（单文件、核心语法；没有 ct，下面用 ./ctc）
gcc selfhost/l0/ctc.c -o ctc

# 编译 .ct 到 .c（只有 .h.ct 输入才同时写同名 .h）
ct compile examples/01_greeter/greeter.ct -o /tmp/greeter.c
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

预编译 Linux x64 产物与构建细节见 [docs/dist.md](docs/dist.md)。新用户从这里开始：
[docs/tutorial.md](docs/tutorial.md)——逐章教程，每条命令都可直接粘贴。

### 2. 常用命令

| 命令 | 作用 |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；只接受单文件单元，`import` 需改用 `ct build` |
| `ct build <in.ct>… [-o <exe>]` | 多文件构建：生成物默认放 `.ctbuild/`，再调用 C 编译器产出可执行文件；`--emit-c` 只发 `.c`/`.h`，`--runtime-checks` 在接口派发前检查空 vtable（默认关闭） |
| `ct check <in.ct>` | 只跑受限语义检查、不写 `.c`；有发现以 `error:` 报告并退出 `1`，干净退出 `0` |
| `ct check --types <in.ct>` | opt-in 类型检查（PH-68/69 + PH-70/71 的 CFG/own 走 `--semantics`）；与 `ct build --check-level=warn` 同判定、同文案 |
| `ct build --check-level=off\|warn\|error` | 把 B 的检查接进构建路径；SH-115 起默认 `warn`，只报 `warning:`、生成物与 `off` 逐字节相同；`error` 在写产物前失败 |
| `ct … --emit-map <file\|->` | 写出反向映射表 JSON（trait / struct / 函数 / impl → 生成的 C 符号）；`--emit-model` 写模型 JSON |
| `ct index verify [<file>] [--json] [-q]` | 只读校验索引：六字段、`tag == v<version>`、`sha256`、重复行；退出码 0/1/2 |
| `ct get` / `ct update` / `ct install` / `ct verify` / `ct migrate` | 包管理：拉包进共享 store、写 v2 `ct.lock`；`ct build` 自动读 lock。S7 后不再读写 `vendor/`，旧工程用 [`ct migrate`](docs/package-guide.md#8-v1-迁移ct-migrate) 一次性迁入 |
| `ct -v` / `ct -h` | 版本 / 用法 |

退出码：成功 `0`，语法或 I/O 错误 `1`（`ct check` 有任何语义发现，或 `ct build` 遇到 impl 签名漂移，
也是 `1`）。源码诊断格式为 `文件:行:列: error: 描述`；驱动层错误以 `ctc:` 开头。完整开关
（`-I` / `--std` / `--line` / `--diagnostics` / `--ns-root` / `--freestanding` / `--lib`）见
[教程 §11](docs/tutorial.md#11-命令行速查)。

`ct get` 走系统 `git`，是包管理里唯一联网步骤：clone / fetch 失败或超时在写 `ct.lock` **之前**以非零
退出，旧锁逐字节不变（`CT_GIT_TIMEOUT` 默认 180s，`GIT_TERMINAL_PROMPT=0`）。

### 3. 能力一览

- **两档写法：轻量路径 vs 完整路径**：轻量路径把方法直接挂在基本类型上（方法返回自身类型即可链），不引入 trait 对象；完整路径是字符串 → factory → 由 trait 定义的对象类型 → 接口链。判断依据与当前接口链边界见 [language-spec §4.10.1](docs/language-spec.md) <!-- cap:paths -->
- **trait**：`trait` / `impl` / `use`，方法派发，trait 当类型（接口值 / 数组 / 字段 / 装箱），trait 默认方法 <!-- cap:traits -->
- **内存**：`Drop` / `delete`、`own`（AutoDrop）、块级 `defer`（Phase 38）、路径敏感泄漏告警、`borrow` + `Handback` <!-- cap:memory -->
- **参数糖与切片**：`ref` / `out` 形参（Phase 78；`out` 有定值分析，owning 实参须先初始化）、`T[]` 切片（Phase 79；长度随指针走，越界检查由内建 helper 承担），见 spec §4.68 / §4.69 <!-- cap:params-slices -->
- **字符串句柄**：`String` 拥有（引用计数，字面量 immortal）、`Str` 借用视图（`{ptr,len}`，零拷贝）；`String` 可作字段，`Str` 不可作字段或 `Map` 键，见 spec §4.70 <!-- cap:strings -->
- **模块**：`namespace` / `import` / `pub` / 多文件 `ct build` / 目录 = namespace <!-- cap:modules -->
- **映射**：`map trait T for instance …`、`.m.ct` 零成本静态映射、伴生 C shim、`test/bindings/` 声明式 C 库对接 <!-- cap:mapping -->
- **透传**：`#ct-raw` / `#ct-endraw` 原样块（宏与手写 C 逐字节进入生成的 `.c`） <!-- cap:passthrough -->
- **诊断与工具**：`#line` 溯源、`--diagnostics=json|text`、多错误恢复、增量缓存、`ct get` / `ct install`
- **泛型函数**：`T name<T>(…)` + `name<int>(…)`，编译期单态化（Phase 26）；**约束泛型** `T name<T: Trait>(…)`（Phase 28） <!-- cap:generic-fn -->
- **泛型 struct 与内置容器**：`struct Name<T, U>` + `impl<T> Name<Args>` 静态派发（Phase 29）；`Vec<T>` / `Map<K,V>` 免 import，`foreach` 按插入序遍历 `Map` <!-- cap:generic-struct --> <!-- cap:containers -->
- **泛型 trait**：`trait Iter<T>` / `impl Iter<int> for S` / `T: Iter<int>` 约束，实例按实参编码单态化（Phase 35） <!-- cap:generic-trait -->
- **标准结果类型**：`Option<T>` / `Result<T, E>` 内建于 `lib/core`，`is_some` / `is_ok` / `unwrap` 等为固有方法（Phase 34） <!-- cap:option-result -->
- **单对象句柄**：`box<T>`（16 字节句柄 + 8 字节 `{refs,aux}` 头）、`new T { ... }`（上下文关键字，仅具名 struct）、`b.f` 自动解引用、`retain` / `release` 与 `at()` 借用（Phase 81） <!-- cap:box -->
- **ADT 与 `match`**：`enum` 成员带负载即 ADT，`match` 穷尽所有变体或末位 `_`；值是 `{tag, union}`，无 vtable、无隐藏分配（Phase 84），见 spec §4.73 <!-- cap:adt -->
- **C ABI 静态库**：`ct build --lib` 把根 `.h.ct` 的 C 兼容 `pub` 函数导出为 `.abi.h` + `lib<base>.a`（Phase 39） <!-- cap:abi -->
- **原子并发**：`atomic int` / `atomic long` / `atomic bool` / `atomic void *` + `ct_atomic_load` / `ct_atomic_store` / `ct_atomic_cas`（seq_cst，C11；`ct build` 自动切 `-std=c11`）（Phase 41） <!-- cap:atomics -->
- **方法级 `pub`**：`impl` 固有方法默认私有（不进 `.h`、`static`）；写 `pub` 才跨单元公开；trait impl / `pub impl` 硬错（Phase 42） <!-- cap:method-pub -->
- **`return err:` 载荷契约**：`err:` 载荷必须可赋给函数返回类型；不一致 L43-1 硬错，四入口一致，不写坏 C（Phase 43） <!-- cap:return-err -->
- **后缀 `?` 错误传播**：`expr?` 把 `Result` 失败以 `Outer::err` 返回，成功取 `value`；L44-1/2/3；`?:` 消歧（Phase 44） <!-- cap:try -->
- **明确不做**：继承、默认编译路径的全量类型检查（`ct check` 只做受限检查）、优化（语言在 `1.0.0` 才定稿）

每条语法的展开规则以 [docs/language-spec.md](docs/language-spec.md) 为准（ADT/`match` 见 §4.73）；
惯用优先级见 [docs/idioms.md](docs/idioms.md)；写法范例见 [docs/patterns.md](docs/patterns.md)
（`kind` 判别改写见 §6）；教程见 [docs/tutorial.md](docs/tutorial.md)（ADT 见 §18）；
内存约定见 [docs/memory-guide.md](docs/memory-guide.md)。

**范式与边界的详读**：本页 §0.1–§0.5 是可运行展示；**权威定义与两档判断依据只在
[docs/language-spec.md](docs/language-spec.md) §4.10.1**，其余文档只引用；可运行样例
[examples/47](examples/47_chain_factory/src/main.ct) 与
[examples/48](examples/48_string_steps/src/main.ct) 由 `check-warnings.sh` 的 build-mode 段跑。

### 4. 仓库结构

`selfhost/` 是自举链：`l0/`（C 种子）→ `l1/`（冻结）→ `l2/`（回归 oracle）→ `ct-ast/`（主线，提供
`ct` 安装入口）；`test/` 是测试与 golden；`docs/` 是文档；标准库是独立的 ct-pkg 包 `ct/std`
（`ct get ct/std` 获取，不随仓库发布）；`test/bindings/` 是声明式 C 库 binding；`issues/` 是审查
台账；`AGENTS.md` 是改动规约。目录级说明见 [selfhost/README.md](selfhost/README.md)、
[test/README.md](test/README.md) 与 [docs/architecture.md](docs/architecture.md)。

### 5. 文档与测试

- 文档导航：[docs/README.md](docs/README.md)
- 测试：`bash selfhost/check-all.sh` 跑 12 道硬门禁；分层地图见 [test/README.md](test/README.md)
- 改动代码前先读 [AGENTS.md](AGENTS.md)

### 6. 许可

GPL-3.0-or-later（编译器本体，见 [LICENSE](LICENSE)）；生成的 `.c`/`.h` 与你的 `.ct` **不受 GPL
约束**（[LICENSE.EXCEPTION](LICENSE.EXCEPTION)）；`examples/`、`test/`、`editors/` 为 MIT。

For commercial licensing or exceptions, contact: samxxu@gmail.com

### 7. 联系

作者 Sam X. Xu · samxxu@gmail.com · 问题与建议优先开
[Issue](https://github.com/samxxu/ct-lang/issues)。

- **C 边界**（Phase 65）：外部代码默认 strict——`.ct/.h.ct` 禁直接 `#include`、`#ct-raw`、`extern`
  与函数式宏，出口是 `<base>.shim.h` 或 `.m.ct`；包用 `ct.pkg` 的 `c-boundary`、命令用
  `--c-boundary=strict|allow`。
- **libc I/O 例外**（Phase 66）：`printf`/`scanf`/`puts` 族按调用补头（`<stdio.h>`），宽字符组补
  `<wchar.h>`；没有调用不带系统头，`--freestanding` 下不补。
