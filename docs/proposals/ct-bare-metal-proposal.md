# 提案 · 裸机（freestanding）生成契约与静态初始化修复

| 项 | 值 |
| --- | --- |
| 性质 | 使用方提案；已由 CT 项目组受理并按 PH-64 交付。本文保留为提案、依据与验收追溯 |
| 状态 | **已采纳并交付（PH-64，v0.63.0）**；后续变更按 CT 卡与规范走 |
| 事实基线 | v0.62.0（`485129c9`），L0→L1→L2→ct-ast 全链现编；探针均在 `/tmp`，未改仓库 |
| 落点 | **PH-64 → v0.63.0（已收口）**；交付核对见 [phase64 卡](../history/design/phase64.md)（`--freestanding` / 按需单元 / `--alloc` / const vtable） |
| 关联 | 新 SH 条目（数组初值坏 C）、[SH-60](../../issues/selfhost/sh60-mct-signature-types-decorative.md)、[SH-75](../../issues/selfhost/sh75-local-iface-return-dangling.md)、[SH-25](../../issues/selfhost/sh25-typedef-alias-drops-dims.md)、[lib/std/Vec.h.ct](../../lib/core/Vec.h.ct) |
| 定性 | **1 个静默坏 C 补丁 + 3 份生成物契约**；不新增语言特性（`layout(plain)` 列为可裁项） |

> 交付状态（2026-11-20 核对）：PH-64 已按本提案收口（v0.63.0），生成物契约四项均已落地；
> 真实板卡 pilot 仍属 `HW-1`（外部依赖，无硬件不阻塞，见 roadmap）。

> 本文只从“生成物能不能进 MCU 工程”立论，不评价 CT 的语言表达力。文中所有“实测”都有命令与原始输出；
> 所有“读码”都给了 `file:line`，未运行的部分明确标注。

---

## 0. 一分钟版

今天把 CT 用在裸机上，只有一个问题是**必须立刻修的缺陷**，其余都是**契约缺失**：

1. **`T arr[n] = {…}`（T 带 `use Trait`）会生成编不过的 C，`ct` 仍返回 0**。这是“接口实现表 / 驱动表”
   的标准写法，属于静默坏 C，应先按 patch 止血。
2. 文件作用域**数组**的 vptr 初始化走 `__attribute__((constructor))`；连接池/驱动表这类全局数组一多，
   裸机启动不调 `__libc_init_array` 就是空 vptr。标量全局已经是静态初始化，不受影响。
3. 生成物在用到堆特性时会写 `malloc`/`free`（装箱、`own`/`delete`、`Vec`/`Str`），且 `ct build`
   默认把 `Vec/Option/Result/Str` 四个单元一起塞进链接——其中 `Option`/`Result` 是纯值、不碰堆，
   但四个 `.o` 一起进场，`-nostdlib` 工程会因 `malloc` 未定义而红。
4. vtable 是**可写**的 `static struct …_vtbl`；即使对象进了 `.rodata`，vtable 仍占 SRAM。

建议：**先发 P0 patch（1）**；再开 PH-64 做（2）（3）（4）与门禁。不要在 patch 里顺手改 vtable 的
`const` 或 `--freestanding` 语义，那会把一次止血变成一次产品级变更。

---

## 1. 要解决什么

三个真实场景，今天分别卡在不同位置：

```ct
/* A. 静态接口表：传感器/驱动表 */
trait Sensor { int read(); }
struct Temp { int ch; } use Sensor;
impl Sensor for Temp { int read() { return self->ch; } }

struct Temp table[2] = { { .ch = 0 }, { .ch = 1 } };   /* ← 今天生成坏 C */
```

```ct
/* B. 常量表进 Flash */
trait Named { int id_of(); }
struct Cfg { int id; } use Named;
impl Named for Cfg { int id_of() { return self->id; } }

const struct Cfg cfgs[2] = { { .id = 1 }, { .id = 2 } };   /* ← 今天 vptr 静默为 0 */
```

```ct
/* C. 无堆驱动：只用 trait + borrow + 静态对象 */
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn { void handback() { self->in_use = 0; } }
```

目标不是“让 CT 变成一个 RTOS”，而是让 A/B/C 三种写法在 `cc -ffreestanding -nostdlib` 下
**要么编过且行为正确，要么在 `ct` 阶段硬错**；不允许“`ct` 绿、`cc` 红”或“上电 HardFault”。

---

## 2. 现状实测（v0.62.0）

### 2.1 数组带初值：静默坏 C（P0）

```ct
trait Greeter { char *who(); }
struct Person { char *name; int age; } use Greeter;
impl Greeter for Person { char *who() { return self->name; } }

Person ps[2] = { { .name = "a", .age = 1 },
                 { .name = "b", .age = 2 } };

int main(void) { return ps[0].who() != 0; }
```

```text
$ ct ps.ct -o ps.c ; echo $?
0
$ cc -std=c99 -Wall -Wextra -c ps.c
ps.c:21:46: error: field designator cannot initialize a non-struct, non-union type 'struct Person[2]'
```

生成物在数组初值后追加了**顶层**字段指定初始化式：

```c
struct Person ps[2] = { { .name = "a", .age = 1 }, { .name = "b", .age = 2 }
                      , .__greeter_vptr = &Person_Greeter_vtable};
```

根因：`emit_raw_init` 只判断“初值以 `}` 结尾”，不看声明是否还有数组维度
（[Emitter.h.ct:3613](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3613) →
[Init.h.ct:91](../../selfhost/ct-ast/backend/emit/Init.h.ct#L91)）。**局部数组与文件作用域数组都中招**；
无初值的数组反而正常（逐元素写 / 走 constructor）。

同一族的 [SH-25](../../issues/selfhost/sh25-typedef-alias-drops-dims.md) 是 `typedef` 别名漏拷 `dims`，
已修；本条是“声明本身带数组维度 + 显式初值”，是另一个入口，现有夹具没覆盖。

### 2.2 `const`：vptr 静默不写

```ct
const Person ps[2] = { { .name = "a", .age = 1 }, { .name = "b", .age = 2 } };
```

`ct` 返回 0，生成物里**一个 vptr 指定初始化式都没有**。今天因为 `const` 接收者被拒
（`no method 'who' for type 'const struct Person'`）而不会当场崩，但这意味着：

- “常量表 + 方法”今天不可用；
- 一旦 SH-60 的 const 接收者落地，这段代码会直接空指针派发。

### 2.3 文件作用域数组：走 constructor

```ct
Person ps[2];    /* 无初值 */
```

```c
static void __ct_init(void) __attribute__((constructor));
static void __ct_init(void) {
    unsigned long __ct_i;
    for (__ct_i = 0; __ct_i < 2; __ct_i++) {
        ps[__ct_i].__greeter_vptr = &Person_Greeter_vtable;
    }
}
```

实测该符号进入 `__mod_init_func` / `.init_array`。裸机 `Reset_Handler` 只做 `.data` 拷贝与 `.bss`
清零、直接 `bl main` 时，这段不会执行。**注意**：标量全局不是这样，它已经是静态指定初始化

```c
struct Person single = { .__greeter_vptr = &Person_Greeter_vtable };
```

（[Emitter.h.ct:3620](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3620)）。所以问题范围是
“文件作用域**数组**”，不是“所有全局对象”。

### 2.4 堆与内置层

- `own`/`delete`、`Drop` 的释放路径直接发射 `free(`（[Emitter.h.ct:4035](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4035)、
  [:4049](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L4049)）；
- 块作用域 struct 装箱为接口时发射 `extern void *malloc(__SIZE_TYPE__);` 与 `malloc(...)`
  （[Emitter.h.ct:3939](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L3939)）；
- `Vec`/`Str` 的分配在 `lib/std`（CT 源码，[Vec.h.ct:72](../../lib/core/Vec.h.ct#L72)），不在发射器里；
- `ct build` 默认把 `Vec/Option/Result/Str` 四个单元一并发射、一并交给 `cc`（实测 `--emit-c` 产物目录
  固定含这四个 `.c`）。

### 2.5 vtable 可写

```c
static struct Greeter_vtbl Person_Greeter_vtable __attribute__((unused)) = { … };
struct Person { … struct Greeter_vtbl *__greeter_vptr; };
struct Greeter_iface { void *self; struct Greeter_vtbl *vt; };
```

vtable 不是 `const`，`__vptr` / `vt` 也不是 `const` 指针。对象即使 `const`，vtable 仍在 `.data`。

### 2.6 已经很好、不用改的部分（避免误伤）

- `impl Name { … }` 固有方法：零 vtable、零布局改动，packed 3 字节帧结构仍是 3
  （[language-spec.md:2404](../language-spec.md#L2404)）；
- `.m.ct` 静态映射：`cstr.length()` 直接发 `strlen((cstr))`，无 vtable/vptr
  （[language-spec.md:628](../language-spec.md#L628)），**但静态 trait 不能被 struct adopt**
  （[Parser.h.ct:2604](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2604)）；
- `borrow` + `Handback`：块尾按逆序发 `Conn_Handback_handback(...)` 并置空，实测不依赖堆；
- `#include` 直通（ct 不解析厂商头）、函数指针 typedef/字段、`volatile`、`__attribute__` 直通、
  顶层 `#ct-raw` 包 `__asm__ volatile`：均实测可过。

**结论：CT 不缺“底层 C 的表达力”，缺的是“生成物的裸机契约”。**

---

## 3. 提案

### 3.1 P0（patch，建议 v0.62.1）：修数组/const 的 vptr 静态初始化

范围只做一件：**带初值的 trait-carrying 数组，生成合法且零告警的 C；`const` 数组同样写 vptr。**

要求：

1. 局部/文件作用域一致；`[n]` 与 `[]` 都支持；
2. 被零初始化的尾部元素也要有 vptr（`[n]` 已知长度时）；
3. 多维数组 + trait：P0 **硬错**，不允许“生成坏 C 再说”；
4. 既有 golden 不动（现有夹具不覆盖该形态；新增夹具才产生新 golden）；
5. `-Wall -Wextra` 零告警。**不要**用“顶层 `[i].__x_vptr = …` 追加”了事——那会触发
   `-Wmissing-field-initializers`；要么注入元素花括号内，要么尾部用顶层 designator、已初始化元素用内嵌。

验收见 §4 B1–B7。这是一次纯 `fix`，按 D-005 的“静默坏 C 一律判 bug、走 PATCH”执行，不占 MINOR。

### 3.2 PH-64（建议）：`--freestanding` + `--alloc` + const vtable

#### S1 `--freestanding`（compile / build / check 同一开关）

语义只三条，够用即可：

1. **内置层按需拉，带堆的禁用**：build 模式不再无条件发射四个单元；`Option`/`Result`
   （纯值、无堆）用到才拉，仍可用；`Vec`/`Map`/`Str`（`Vec.h.ct` 与 `Str.h.ct`）一律硬错
   （`--alloc` 也不能把它们带回来——要容器就走托管模式）。
2. **凡是生成物会写 `malloc`/`calloc`/`free` 的构造，一律硬错**（除非同时给了 `--alloc`）：
   `own` + `delete`、块作用域 struct 装箱。
3. **不发射 `__attribute__((constructor))`**：文件作用域数组若无初值，硬错并给出可照抄的初值形态
   （`Person ps[2] = { … };`），不生成“上电不跑”的静默空 vptr。

`ct build --freestanding` 额外把 `-ffreestanding` 传给 `cc`；**链接仍由用户负责**（裸机用 `--emit-c`）。

#### S2 `--alloc <alloc>,<free>`

不改发射器的调用点，改为在**每个生成单元 prologue 的 `#include` 之后**注入 `#define malloc <alloc>` /
`#define free <free>`（与今天 `#define` 直通同一机制）。这样 `lib/std` 的 `Vec`/`Str` 也一并被改写，
不需要逐个容器加钩子。

已实测今天用 `#define malloc/free` + `extern` 伴生 `.c` 可以跑通；用 `cc -Dmalloc=pool_alloc`
编生成的 `Vec.c`，未定义符号会变成 `pool_alloc`/`pool_free`。`--alloc` 只是把这条既有能力变成
**文档化契约**（`ct build --cflags` 只是把同一组参数交给 `cc`）。

约束：`--alloc` 不与 `--freestanding` 互斥（托管环境换分配器同样有用）；给了 `--alloc` 就允许
`own`/`delete`/装箱，否则 freestanding 下硬错。`Vec`/`Str` 在 freestanding 下仍不可用（第 1 条）；
托管模式 + `--alloc` 时它们照常被改写。

#### S3 const vtable（建议一次改到底，不做双形态）

```c
static const struct Greeter_vtbl Person_Greeter_vtable = { … };
struct Person { … const struct Greeter_vtbl *__greeter_vptr; };
struct Greeter_iface { void *self; const struct Greeter_vtbl *vt; };
```

理由：vtable 本来就不该被写；双形态（`--freestanding` 才 const）会让 `.h` 的接口类型随模式变化，
跨模式链接对不上。代价是全部 golden 重生成，差异应当**只有** `const` 这三处；用这一点做收口判据。

#### S4 门禁与文档

`check-ast.sh` 增 baremetal 段（F2/F3/F4 各一条），README 增“裸机”一节，language-spec 增
`--freestanding` / `--alloc` / const vtable 三小节。门禁是这条提案唯一能防止回退的东西：
只写文档、不加断言，下一相很容易把 constructor 或 `malloc` 带回来。

#### S5 布局守卫（可裁）

加 `struct Name layout(plain) { … }`：该 struct 一旦 `use Trait` 即编译错。镜像 C 头的帧/寄存器/报文
结构体用它，防止有人为了语法糖把 vptr 塞进 wire format。尺寸对齐仍用 `#ct-raw` 的
`_Static_assert(sizeof(struct Frame) == 8, …)`（今天已可用），本项不新造尺寸语法。

若维护者认为语法成本高，S5 可整片裁掉，不影响 S1–S4 的价值；但“镜像结构体不许 adopt trait”
这条规则至少要写进文档。

---

## 4. 验收判据

### P0

| # | 判据（可执行） |
| --- | --- |
| B1 | §2.1 的 `Person ps[2] = {…}` 局部与文件作用域各一条夹具；`ct` rc=0 且 `cc -Wall -Wextra -c` rc=0，运行输出正确 |
| B2 | `Person ps[] = {…}` 推导长度同样过 B1 |
| B3 | `const Person ps[2] = {…}` 生成物含 2 个 vptr 指定初始化式；`cc` 零告警；`sizeof` 比不带 trait 的版本多一个指针宽度（64 位宿主为 8） |
| B4 | 带初值的数组不再出现 `__ct_init`；无初值数组仍走原路径（回归） |
| B5 | 部分初始化：`Person ps[4] = { {…}, {…} }` 的 `ps[1]`–`ps[3]` 调方法不崩 |
| B6 | 多维 `Person g[2][2] = …` 在 `ct` 阶段硬错，文案指明多维数组与 trait 的组合不受支持；不生成 C |
| B7 | `check-all` 11/11；既有 golden 零变化 |

### PH-64

| # | 判据（可执行） |
| --- | --- |
| F1 | `ct --freestanding` 编 `Vec<int>`：rc≠0，文案含 `Vec` 与 `--freestanding` |
| F2 | freestanding 的 trait+局部对象夹具（不含任何 `#include <…>`）：产物无 `malloc|calloc|free|__ct_init|constructor`；`cc -std=c99 -ffreestanding -nostdlib -fno-stack-protector -c` rc=0 且 `nm -u` 为空 |
| F3 | freestanding + 文件作用域 `Person ps[2];`：rc≠0，文案给出带初值的修正形态 |
| F4 | 托管模式 `ct build --alloc pvPortMalloc,vPortFree --emit-c -o dir` 的 `Vec` 程序：`cc -c dir/Vec.c` 后 `nm -u` 是这两个符号，`malloc/free` 零命中 |
| F5 | `--alloc` + `own`/`delete` 在 freestanding 下可编、可跑；不给 `--alloc` 则 rc≠0（S1 第 2 条） |
| F6 | 生成 C 中 vtable 定义均带 `static const`，`__vptr`/`vt` 均为 `const … *`；`-Wall -Wextra` 零告警；golden 差异只有这三处 |
| F7 | （可选 S5）`layout(plain)` + `use Trait` rc≠0；不 adopt 时零影响 |
| F8 | 文档：README 增“裸机”一节，language-spec 增 `--freestanding`/`--alloc`/const vtable 三小节；`check-docs` 绿 |
| F9 | 门禁：`check-ast.sh` 增 baremetal 段（F2/F3/F4），`check-all` 11/11 |

---

## 5. 任务清单（若开卡）

| # | 任务 | 交付物 | 验收 | effort |
| --- | --- | --- | --- | --- |
| P0 | 数组/const 静态初始化（**独立 patch，先发**） | `Init.h.ct` + `Emitter.h.ct` + 夹具 | B1–B7 | M |
| S1 | `--freestanding` 三语义 | Driver/Module/Emitter 分支 + 负例 | F1–F3 | M |
| S2 | `--alloc` 顶层 `#define` 注入 | Driver 选项 + 跨单元夹具 | F4/F5 | S |
| S3 | const vtable 与 const 指针 | Emitter + golden 重生成 | F6 | M |
| S4 | baremetal 门禁段 + 文档 | `check-ast.sh`、README、spec | F8/F9 | M |
| S5 | （可选）`layout(plain)` | Parser/Emitter + 负例 | F7 | M |

P0 独立成立，不依赖 PH-64；每项独立提交、独立回滚。S3 的 golden 重生成不得与 S1 混在同一提交。

---

## 6. 不做

- **不**在本提案里删 `__<trait>_vptr` 字段（见 §7）；那是另一相的设计变更。
- **不**做 IAR/Keil 的 `__attribute__` 兼容层；arm-none-eabi-gcc / armclang 已可用，ICCARM 需单独立项实测。
- **不**改 `_iface` 的 `{void *self; vtbl *vt;}` 形状（除 const）。
- **不**解决 const 接收者（SH-60）、`map` 签名类型（SH-60 1a）等既有条目。
- **不**把 `Vec` 改成静态分配容器；本提案只保证“不用它就不拉它 / 用了能换分配器”。

---

## 7. 远期：vptr 字段本身值得单独研判

`_iface` 已经是胖指针（`{void *self; vtbl *vt;}`），而具体类型变量上的 `p.m()` 静态可定；
`Drop`/`Handback` 更是刻意不占字段（[Parser.h.ct:2614](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2614)）。
对象内的 `__x_vptr` 与 `_iface.vt` 承担同一件事。若把它删掉、在装箱点填 `_iface`，可一次性消掉
`sizeof` 污染、数组初始化 bug、const/Flash 限制，以及“C 代码创建的结构体 vptr 为 0”的 FFI 隐患。

但这是 ABI 级变更，**不建议塞进 PH-64**。建议先出设计记录，满足三条才开相：

1. 每个 `.` 调用点的接收者类型要么具体、要么 `_iface`（无第三种）；
2. 跨单元 trait impl 的方法可导出为非 `static` 包装，且与 vtable 槽一一对应；
3. `map trait … for instance` 的装箱不依赖对象内 vptr（今天用的是 `&uart1_<Trait>_vtable`，看起来不依赖）。

三条都成立，P0（数组初始化）会自然消失；不成立，就保留字段，P0 是长期补丁。

---

## 8. 需要维护者裁定

1. **版本位**：AGENTS §0.3 写“PH-62 起恢复 `d=0`”，但同段又写 `PH-62 → v0.61.0`（`d=1`），
   且 [phase63.md](../history/design/phase63.md) 实算 `d=1`。按现有相位表，PH-64 应为 **v0.63.0（`d=1`）**。
   开卡前请修正该句，否则 `g1-version` 与卡片会互相打架。
2. **P0 编号**：建议新立一条 SH（下一个空位，当前到 SH-82），只装 §2.1/§2.2 两条静默坏 C；
   不与 SH-25 合并（入口不同，合并会让回归面失控）。
3. **PH-64 是否受理**：若只接受 P0，也请明确——P0 独立成立，不依赖 PH-64。
4. **const vtable**：接受“一次改到底 + golden 全量重生成”，还是先只在 `--freestanding` 下 const？
   我建议前者；后者会让 `.h` 类型随模式变化，跨模式链接出问题。
5. **S5 `layout(plain)`**：保留还是裁掉？裁掉的话，至少把“镜像结构体不得 adopt trait”写进文档。

---

## 9. 复现方式

```bash
# 现编 ct-ast（与 check-ast.sh 前四步一致）
W=/tmp/ct-bare; mkdir -p "$W"/{l2src,astsrc}
cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$W/ctc"
"$W/ctc" selfhost/l1/ctc.ct -o "$W/l1.c"
cc -Wall -Wextra -std=c99 "$W/l1.c" -o "$W/l1"
"$W/l1" build selfhost/l2/driver.ct -o "$W/l2src"
cc -Wall -Wextra -std=c99 "$W/l2src"/*.c -o "$W/l2"
"$W/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$W/astsrc"
cc -Wall -Wextra -std=c99 "$W/astsrc"/*.c -o "$W/ct"
```

§2 的每条探针都是单文件 `.ct`，用 `"$W/ct" x.ct -o x.c` 复现；`cc` 用宿主默认即可。
所有探针只读仓库、只写 `/tmp`。
