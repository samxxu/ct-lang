# Phase 41 — 原子并发能力（`atomic T` 与内建原子操作）

> **状态：草案**（2026-11-13，待评审；未立项）。
> **基线**：PH-40 收口提交（`v0.40.0`）；若 PH-40 尚未收口，S0 在 `v0.39.0` 上重建并在本节写明实际基线 sha。
> **文档形态**：`phase41-draft.md`；design window 7/12（门禁只数 `phaseN.md`，草案不计数）。
> **前置**：[phase40-draft.md](phase40-draft.md)（收口基线）、[phase32-draft.md](phase32-draft.md)（表达式静态类型求值）、[phase39-draft.md](phase39-draft.md)（导出面与产物）。
> **关联**：[language-spec.md](../language-spec.md) §4、[bindings-and-patterns.md](../bindings-and-patterns.md) 的「C11 原子」节、[modern-oo-gap.md](../modern-oo-gap.md)。
> **评审**：两席对抗评审（2026-11-13）结论已定：CAS 只收地址形态、发射走「剥基类型 + 自带运行头」、名字进语言层但实现不进。
> **规模**：编译器 340–610；夹具 160–260；门禁脚本 40–80；文档 60–100；合计 **600–1050**（±40%）。
> **纪律**：收口时 bump `v0.41.0`；tag/push 按 `AGENTS.md` 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-41 |
| 目标 | 语言层实现 `atomic T` 修饰符与保留名 `atomic_load` / `atomic_store` / `atomic_cas`（seq_cst，4 类型）；解析期做类型检查，发射走 CT 自带的 `static inline` 运行头；`atomic own` 与 by-value CAS 编译期报错 |
| 范围 | O1/O2/O3；不做 `memory_order` 参数、不做 `atomic struct`、不做 `_Generic` 分派、不注入 `<stdatomic.h>` |
| 交付物 | `Expr.h.ct` / `Stmt.h.ct` / `Emitter.h.ct`；`selfhost/check-tsan.sh`；`test/ast/p41_*` 与 `test/ast/errors/p41_*`；`examples/44_atomic_counter`；文档 |
| 任务清单 | §4.1（R1–R9） |
| 退出判据 | E41-1…E41-10（§5） |
| 依赖 | PH-40 收口 `v0.40.0`；`cc` 支持 `__atomic_*`（GCC ≥ 4.7 / clang ≥ 3.1）与 `_Atomic`；规范 1.9.0 |
| 规范版本 | 1.9.0 |
| version-minor | 41 |
| 已知风险 | R41-1…R41-9（§7） |

## 1 需求与边界

### 1.0 AN-41（四段）

| 段 | 内容 |
| --- | --- |
| 问题 | 11 道硬门禁没有任何并发检查；`atomic int x;` 今天 rc=0 并**原样发射非法 C**；绑定层的 by-value CAS 能在零告警下构建、运行时段错误，语言层没有解析期诊断 |
| 范围 | `atomic T` 修饰符（4 类型）+ 保留名 `atomic_load` / `atomic_store` / `atomic_cas`（seq_cst）+ `static inline` 运行头 + 诊断 + 真门禁夹具 + TSan 门禁 + 内存模型书面约定 |
| 验收 | E41-1…E41-10 全部可在 `check-ast.sh` / `check-warnings.sh` / `check-docs.py` / `check-tsan.sh` 上机械核对 |
| 依赖与风险 | 不依赖线程运行时；风险集中在保留名破坏面、`__atomic_*` 的平台面、CAS 的出参形态 |

### 1.1 一句话

**名字进语言层，实现不进**：`atomic_load` / `atomic_store` / `atomic_cas` 是保留名，解析期做类型检查并拒绝 by-value CAS；发射统一成 `_Atomic(T)` 拼写，并调用 CT 自带的一小段 `static inline` 运行头，一律 seq_cst。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | 类型修饰符：`atomic int` / `atomic long` / `atomic void *` / `atomic bool`；可用于局部、字段、参数、全局；其它基类型 L41-1 | 无；`atomic int x;` 走「未知类型名直通」，发射 `atomic int x;` 非法 C（rc=0） |
| O2 | 保留名操作：`atomic_load(&x)`、`atomic_store(&x, v)`、`atomic_cas(&x, &expected, desired) -> bool`；seq_cst；解析期类型检查；实现不在语言层 | 只能裸用 `<stdatomic.h>` 宏；绑定层的 by-value CAS 零告警构建、运行时 rc=139（§2.2） |
| O3 | 诊断、夹具与门禁：`atomic own` 硬错、by-value CAS 硬错、取消标志 + 引用计数进 `check-ast`、新增 `check-tsan.sh` | 无并发夹具；`check-sanitizers.sh` 只跑 ASAN/UBSAN |

### 1.3 非目标

- 不做 `atomic struct` / `atomic` 容器元素 / `atomic T` 作为返回类型（T41-1）。
- **不做 by-value CAS**：`atomic_cas(&x, 0, 1)` 是编译期错误 L41-5（§3.5 事实 1）。
- 不做内存序参数（`relaxed` / `acquire` / `release`）与 `atomic_load_explicit` 一类封装；只有 seq_cst（D41-6）。
- 不注入 `#include <stdatomic.h>`，不要求用户走 `.m.ct` / `ct build`；单文件 `ct compile` 体验必须保留。
- 不用 `_Generic` 做类型分派（§3.5 事实 2）。
- 不做锁、线程、`pthread` 封装；线程仍由用户 `#include <pthread.h>` 裸用。
- 不做平台抽象层（不做 MSVC / `Interlocked*` 路径；Windows 不在范围）。
- 不做编译器侧的 happens-before / 数据竞争静态分析（那是 T41-2）。
- 不改 `ctc.c`、不改 L1/L2；全部落 ct-ast。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D41-1 | `atomic` 是 `parse_type` 内与 `_Atomic` 并列的**新分支**，不是重写既有分支；`_Atomic(…)` 保持逐字直通 | 裸 C11 仍要能用；重写既有分支会改变既有输出 |
| D41-2 | **拼写统一 `_Atomic(T)`**（`.c` 与 `.h` 同形）：`_Atomic(int)` / `_Atomic(long)` / `_Atomic(_Bool)` / `_Atomic(void *)`；不注入 `<stdatomic.h>` | 关键字形式无需头文件，`.h` 的「只放类型、不 include」契约不破；实测零告警 |
| D41-3 | 三个名字是**保留名**，由解析期做类型检查；实现不在语言层 | 绑定层给不出解析期诊断（§3.5 事实 1）；「调用点更短」不是收益，不写进理由 |
| D41-4 | 发射物是 CT 自带的一小段 `static inline` 运行头：4 类型 × 3 操作 = 12 个助手，内部**剥掉 `_Atomic` 基类型**后调 `__atomic_*`；指针实参在调用点只求值一次 | Clang 21 拒绝对 `_Atomic(T) *` 直接调 `__atomic_load_n`（§3.5 事实 2）；剥基类型后四类全通 |
| D41-5 | CAS 只收 `atomic_cas(atomic T *p, T *expected, T desired)`；失败把实际值写回 `*expected`；by-value 第二参数 L41-5 | 指针类型的 `0` 被当空指针常量，零告警构建、运行 rc=139（§3.5 事实 1） |
| D41-6 | 一律 `__ATOMIC_SEQ_CST`；序是契约不是约束——编译器不校验用户混用裸 C11 的行为 | 与 C11 默认一致；显式内存序是 T41-3 |
| D41-7 | `own` 仍是**语句级**前缀（在类型之前），`atomic` 在类型内；`atomic own T *p` 与 `own atomic T *p` 都硬错，文案指向 Drop 约束 | `own` 的语义是 AutoDrop（`Memory.h.ct:76` 要求 struct 有 Drop），与原子标量不相容 |
| D41-8 | `atomic int x;` 由「非法 C 直通」变成合法规范发射；`atomic <其它>` 与 `atomic` 裸用是硬错 | 这是本相必须清零的既有 bug；`time_t` 一类未知 C typedef 的直通**不改** |
| D41-9 | TSan 是独立脚本 `selfhost/check-tsan.sh`，接 nightly CI，**不作为第 12 道硬门禁** | ASan/UBSan 与 TSan 不能同进程；`check-docs` 钉死 11 道门禁；部分宿主无 TSan |
| D41-10 | `atomic T *` 表示「指向原子 T 的指针」，唯 `atomic void *` 表示「原子空指针」；`atomic_cas` 第一形参就是前者 | 与请求的类型映射一致；两者在 §3.1 明写，避免猜 |

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，v0.39.0）：`check-ast` 1338/0、`check-warnings` 600/0、`test/run` 152、`check-docs` 946 links / 197 files、design window 7/12。S0 在 PH-40 收口提交上重建 `ct` 并实测替换本节。

### 2.2 红证探针

| 探针 | 命令 | 结果 | 依据 |
| --- | --- | --- | --- |
| `atomic int x;` 静默发坏 C | `ct check` + 读生成的 `.c` | rc=0；输出 `atomic int x;`，`cc` 阶段报 `unknown type name 'atomic'` | `Expr.h.ct:1777` 未知类型名直通 + `Expr.h.ct:1612` `parse_type` |
| `_Atomic` 分支已存在 | 读 `parse_type` | `_Atomic(…)` / 裸 `_Atomic` 逐字进类型拼写 | `Expr.h.ct:1631-1651` |
| 同名函数撞宏 | CT 里定义 `int atomic_load(int *)` 后编译 | `expected parameter declarator` | `<stdatomic.h>` 的宏展开 |
| **by-value CAS 静默构建** | 绑定层 `ct_atomic_cas_int(&n, 0, 2)` | **零告警构建成功，运行 rc=139 段错误**（指针位置的 `0` 被当空指针常量） | 实测（2026-11-13） |
| **by-value CAS 重试循环卡死** | 绑定层值形态 CAS 重试 | `stuck after 5 spins`，时间线不推进 | 实测（2026-11-13） |
| **地址形态正常推进** | 同时间线的 `&expected` 形态 | 循环正常收敛 | 实测（2026-11-13） |
| **Clang 21 拒 `_Atomic(T) *`** | macOS/arm64 对 `_Atomic(int) *` 直接调 `__atomic_load_n` | 12 个错误、rc=1：`address argument to atomic operation must be a pointer to integer or pointer` | 实测（2026-11-13，Clang 21） |
| **剥基类型后全通** | `__atomic_load_n((int *)(p), …)` | 四类全通、`cc` 零告警、指针只求值一次 | 实测（2026-11-13） |
| **`_Generic` 不可用** | 分派宏编译 | 未选中分支仍报 `-Wpointer-to-int-cast`，`check-warnings` 不过 | 实测（2026-11-13） |
| `own` 要求 Drop | 读 `mark_owned` | 非数组、`malloc`/`calloc` 初始化、struct 必须 `uses_drop` | `Memory.h.ct:76` |
| 无并发门禁 | 读 `check-sanitizers.sh` / `check-all.sh` | 只有 ASAN/UBSAN；11 道门禁无并发用例 | `selfhost/check-sanitizers.sh:32`、`selfhost/check-all.sh:100-103` |

上表由实测与代码锚点给出；S0 仍需用同一命令复跑并把原始输出贴回本表。

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| 类型词表 / `parse_type` / `_Atomic` 分支 | `selfhost/ct-ast/frontend/parse/Expr.h.ct:1496` / `:1612` / `:1631-1651` |
| 未知类型名直通（`atomic int` 的现状根因） | `Expr.h.ct:1777-1802` |
| 块内声明起点判定 | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:1482`（`is_decl_start`） |
| 字段解析（`atomic` 进字段的入口） | `selfhost/ct-ast/frontend/parse/Parser.h.ct` 的 `parse_field_def` |
| 语句级 `own` / 文件级 `own` 拒绝 | `Stmt.h.ct:2077` / `Parser.h.ct:785` |
| `own` 的 Drop 约束 | `selfhost/ct-ast/backend/mem/Memory.h.ct:76` |
| 调用点发射（内建改写处） | `selfhost/ct-ast/backend/emit/Emitter.h.ct:4757`（`N_CALL`） |
| 前导块样式（运行头的样板） | `Emitter.h.ct:1266-1270`（`__ct_vt_guard` 的 `fputs`） |
| 模块头「只放类型」 | `selfhost/ct-ast/frontend/module/Module.h.ct:1863`（`write_unit_header`） |

## 3 语义与落码

### 3.1 修饰符与形态映射

语法：`atomic <base>`，`<base>` ∈ `int` / `long` / `void *` / `bool`。位置与 `own` 的关系：

```c
own Box *b = malloc(sizeof(Box));   /* own 是语句级标记，在类型之前 */
atomic int hits;                    /* atomic 是类型的一部分 */
atomic void *slot;                  /* 原子空指针 */
```

| CT 写法 | 生成 C（`.c` 与 `.h` 同形） | 说明 |
| --- | --- | --- |
| `atomic int` | `_Atomic(int)` | 无需任何 include |
| `atomic long` | `_Atomic(long)` | 同上 |
| `atomic bool` | `_Atomic(_Bool)` | 不依赖 `<stdbool.h>` |
| `atomic void *` | `_Atomic(void *)` | 原子空指针 |
| `atomic int *` | `_Atomic(int) *` | 指向原子 int 的普通指针（D41-10） |

`atomic` 可用于局部变量、struct / union 字段、函数参数、文件作用域全局、`.h.ct` 的 `pub struct` 字段。裸 `atomic`、`atomic` 作返回类型、`atomic` 元素进容器、`atomic` 进 typedef 别名均硬错（L41-1 / L41-6 / L41-9）。

不采用「`.c` 用 `atomic_int`、`.h` 用 `_Atomic(int)`」的双拼写：统一 `_Atomic(T)` 后两边同形、零 include，也去掉 `#include <stdatomic.h>` 的注入（D41-2）。

### 3.2 内建调用与运行头

CT 侧调用（保留名，解析期检查）：

| 调用 | 发射（以 `atomic int` 为例） | 语义 |
| --- | --- | --- |
| `atomic_load(&x)` | `__ct_atomic_load_int(&x)` | 返回 `x` 的原子读；结果类型 = 基类型 |
| `atomic_store(&x, v)` | `__ct_atomic_store_int(&x, v)` | 原子写，表达式为 `void` |
| `atomic_cas(&x, &expected, desired)` | `__ct_atomic_cas_int(&x, &expected, desired)` | 成功返回 `_Bool` 真并写 `x`；失败把实际值写回 `expected` |

运行头是 CT 自带的一小段 `static inline`（首次用到原子操作时整块发射进生成的 `.c`，`.h` 不含）：

```c
/* 只示例 int；long / _Bool / void * 同形，共 4 类型 × 3 操作 = 12 个 */
static inline int __ct_atomic_load_int(_Atomic(int) *p)
{
    return __atomic_load_n((int *)p, __ATOMIC_SEQ_CST);
}
static inline void __ct_atomic_store_int(_Atomic(int) *p, int v)
{
    __atomic_store_n((int *)p, v, __ATOMIC_SEQ_CST);
}
static inline _Bool __ct_atomic_cas_int(_Atomic(int) *p, int *expected, int desired)
{
    return __atomic_compare_exchange_n((int *)p, expected, desired, 0,
                                       __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}
```

- **剥基类型是硬要求**：直接对 `_Atomic(int) *` 调 `__atomic_load_n` 在 Clang 21（macOS/arm64）上是 12 个错误（§2.2）。
- **指针只求值一次**：实参在调用点求值一次后进形参，函数体不复用原表达式。若将来引入宏形态，用
  `#define __ct_base(p) __typeof__((void)0, *(p))`，形如 `__atomic_load_n((__ct_base(p) *)(p), __ATOMIC_SEQ_CST)`；不得用 `_Generic`。
- 未使用的 `static inline` 不触发 `-Wunused-function`，整块发射不影响零告警门禁。
- 一级实参必须是可寻址的原子左值（`N_VAR` / `N_MEMBER` / `N_ARROW` / `N_INDEX` / `N_DEREF`），否则 L41-7。
- 结果类型取实参的静态 C 类型并剥一层 `_Atomic(…)`；判不出基类型时硬错，不猜（D41-4）。
- 三个名字是保留名，用户声明同名函数 L41-4；生成代码不写它们的原型，也不写 `__atomic_*` 原型。

### 3.3 与既有 `_Atomic` 分支、`<stdatomic.h>` 的关系

- `_Atomic(int)` / `_Atomic(void *)` / 裸 `_Atomic` 今天逐字进类型拼写（`Expr.h.ct:1631-1651`），本相**不动**该分支。
- 新 `atomic` 分支在 `parse_type` 内先于未知类型名直通（`:1777`）命中，产出 `_Atomic(T)`；复用 `type_append`，不新增节点。
- **不注入 `<stdatomic.h>`**：生成的 `.c` 与 `.h` 都只用关键字形式；没有原子类型时不产生任何新行，产物零变化。
- 裸 C11 仍可用：`_Atomic(int)`、`#include <stdatomic.h>` 后的 `atomic_int`、`atomic_load_explicit` 等经用户自己 include 照旧直通。代价是 `<stdatomic.h>` 里的 `atomic_load` / `atomic_store` / `atomic_compare_exchange_*` 宏名与保留名重叠，见 R41-3。

### 3.4 诊断（L41-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L41-1 | `atomic` 后不是 `int` / `long` / `void *` / `bool` | `atomic supports only int, long, void * and bool` |
| L41-2 | `atomic own …`（顺序反了） | `'own' must precede the type; an owned pointer cannot be atomic` |
| L41-3 | `own atomic …` | `an owned value cannot be atomic: 'own' needs a struct that uses Drop` |
| L41-4 | 声明/定义 `atomic_load` / `atomic_store` / `atomic_cas` | `'atomic_load' is an atomic operation and cannot be declared` |
| L41-5 | `atomic_cas` 第二实参是值而不是地址 | `pass &expected: a CAS needs the address of 'expected' to write the observed value back` |
| L41-6 | 裸 `atomic`、`atomic` 作返回类型、`atomic` 元素进容器 / typedef | `atomic needs a scalar base type; an atomic value cannot be <returned/stored/...>` |
| L41-7 | 一级实参不是可寻址的原子左值 | `the first argument of 'atomic_load' must be the address of an atomic variable` |
| L41-8 | 同一类型同时写 `atomic` 与 `_Atomic` | `use one atomic spelling, not both` |
| L41-9 | `atomic` 出现在非类型位置（`atomic;`、`atomic *p;`） | `atomic needs a base type: atomic int / long / void * / bool` |

### 3.5 为落地必须做的三处形态调整

以下三条不是阻碍，而是本相要落的方案；依据为 §2.2 的实测。

**（1）名字进语言层，实现不进：保留名 + 解析期类型检查。**
绑定层无法在解析期诊断：`ct_atomic_cas_int(&n, 0, 2)` 里指针位置的 `0` 被当空指针常量，**零告警构建成功、运行 rc=139 段错误**；值形态的重试循环实测 `stuck after 5 spins`，同一时间线的地址形态正常推进。只有语言层能在解析期拦住「第二参数是值不是地址」并给出可读错误。因此 `atomic_load` / `atomic_store` / `atomic_cas` 是保留名，解析器按原子基类型检查实参；**唯一的真实收益是编译期诊断**，不是调用点更短。实现仍留在 C 侧（下面的运行头），不把语义搬进编译器。

**（2）发射物：剥基类型 + 自带 `static inline` 运行头，不用 `_Generic`。**
Clang 21（macOS/arm64）对 `__atomic_load_n` 传入 `_Atomic(int) *` 直接拒绝：`address argument to atomic operation must be a pointer to integer or pointer`，12 个错误、rc=1——旧草案「直接对 `_Atomic(T) *` 调 `__atomic_*`」在 macOS 上根本编不过。改为先剥掉 `_Atomic` 再传基类型指针后，四类全通、`cc` 零告警，且指针表达式只求值一次（`__typeof__((void)0, *(p))` 的形态或函数形参都满足）。`_Generic` 被否掉：未选中的分支仍会报 `-Wpointer-to-int-cast`，过不了 `check-warnings`。运行头随生成的 `.c` 发射，不注入用户头文件、不要求 `.m.ct` / `ct build`，单文件 `ct compile` 的体验不变。

**（3）CAS 只收地址形态。**
签名固定为 `bool atomic_cas(atomic T *p, T *expected, T desired)`，失败把实际值写回 `*expected`。by-value 形态**不做**，解析期 L41-5 并加一条负例夹具；理由是 §2.2 的 rc=139 与 `stuck after 5 spins`——值形态不是「少一个 `&`」，而是会在运行时丢观测值、甚至把 0 当空指针。地址形态的重试循环：

```c
int seen = atomic_load(&hits);
while (!atomic_cas(&hits, &seen, seen + 1)) {
    /* seen 已被写回为实际值 */
}
```

### 3.6 内存模型书面约定

- CT 只发 seq_cst；不提供其它序，也不推断用户裸 C11 代码的序。
- `atomic` 只保护它自己；相邻的非原子读写仍需用户自己加锁。
- 编译器不做数据竞争分析、不插入屏障以外的任何东西；可见性完全由 C11 实现承担。
- 同一原子对象在多线程下的 `load` / `store` / `cas` 均有定义；`atomic` 与非原子别名混用是未定义行为，文档明写。

## 4 任务清单

开工前 **S0（不占任务行）**：在 PH-40 收口提交上重建 `ct`、复跑 §2.2、写 §2.1 与 `baseline.sha`；不产提交。

R1–R7 每项先提 `test(atomic): <task-id> 红`，实现提交随后转绿；R8 为纯文档 `no-test:`（6.6 T-7 例外），R9 为等价性证据 `no-test:`（3.9 test-fix），两者须评审签字。

### 4.1 冻结任务表

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | `atomic` 修饰符与 4 类型校验（`Expr.h.ct` 的 `parse_type` / `is_type_word`、`Stmt.h.ct` 的 `is_decl_start`）；旧直通缺口补负例 | `p41/atomic-types`：4 正例 + 4 负例（L41-1/6/8/9）全绿 | M | revert |
| R2 | 统一 `_Atomic(T)` 拼写 + 12 个 `static inline` 运行头（`Emitter.h.ct` 类型拼写与 `:1266` 前导区） | `p41/spelling`：`.c` / `.h` 期望逐字节，且无 `#include <stdatomic.h>`；`check-warnings.sh` 零告警 | M | revert |
| R3 | `atomic_load` / `atomic_store` 解析期类型检查与发射（`Emitter.h.ct` `:4757`） | `p41/load-store`：读/写/返回值语义、非左值 L41-7 | M | revert |
| R4 | `atomic_cas` 地址形态与重试循环；by-value 硬错（`Emitter.h.ct` `:4757`） | `p41/cas`：成功、失败回写、循环递增 | M | revert |
| R5 | 诊断与保留名 L41-2/3/4/5/7（`Expr.h.ct` / `Parser.h.ct` / `Emitter.h.ct`） | `p41/errors`：5 负例（L41-2/3/4/5/7）+ 2 正例全绿 | M | revert |
| R6 | 真门禁夹具：取消标志、引用计数（`test/ast/p41_cancel_flag` / `p41_refcount` + `examples/44_atomic_counter`）；`check-ast.sh` 的 p41 段链接带 `-pthread` | `check-ast.sh` 的 `p41/runtime` 段 2/2；程序输出与 `prog.expected.out` 逐字节 | M | revert |
| R7 | TSan 门禁（`selfhost/check-tsan.sh` + `test/ast/p41_tsan.list` + nightly CI 一步；`-fsanitize=thread -pthread`） | `bash selfhost/check-tsan.sh` exit 0，stderr 无 `WARNING: ThreadSanitizer` | M | revert |
| R8 | 文档：`language-spec` 的 `atomic` 语法、`bindings-and-patterns` 原子节改写、`tutorial` 一段、内存模型约定 | `python3 test/docs/check-docs.py` exit 0；`ok p41/docs`；`no-test:` 纯文档 | S | revert |
| R9 | 零回归（全量门禁 + `p41/regression`） | `bash selfhost/check-all.sh` 11/11；非原子夹具的 `--emit-c` 产物 sha256 与 `baseline.sha` 逐行相同；`no-test:` 只做等价性证据 | M | revert |

映射：R1→E41-1；R2→E41-2；R3→E41-3；R4→E41-4；R5→E41-5；R6→E41-6；R7→E41-8；R8→E41-9；R9→E41-7 / E41-10。**每项至多覆盖 1 条退出判据**（6.6 T-5）。

## 5 退出判据（E41-n）

所有 p41 断言挂在既有 `selfhost/check-ast.sh` 内；TSan 由独立脚本执行；不新增硬门禁编号。

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E41-1 | 四种基类型的 `.c` / `.h` 拼写与 §3.1 表逐字一致，两处同形；非法基类型与旧直通形状 rc≠0 | `ok p41/atomic-types`，8/8；两份期望文件逐字节 | `test/ast/p41_atomic_types` |
| E41-2 | `atomic int x;` 编译、零告警、运行输出正确；无 `#include <stdatomic.h>` | `ok p41/spelling`；`-Wall -Wextra` 零输出；stdout 逐字节 | `test/ast/p41_spelling` |
| E41-3 | `atomic_load` / `atomic_store` 读写语义；结果类型与基类型一致；运行头为 `static inline` | `ok p41/load-store`，1/1 | `test/ast/p41_load_store` |
| E41-4 | CAS 地址形态：成功替换、失败回写 expected、重试循环收敛 | `ok p41/cas`，1/1 | `test/ast/p41_cas` |
| E41-5 | 5 条诊断（L41-2/3/4/5/7）各 rc≠0、恰一条 `文件:行:列: error:`；2 条正例 rc=0 | `ok p41/errors`，7/7 | `test/ast/errors/p41_*` |
| E41-6 | 取消标志：N 线程轮询、单一 setter；引用计数：N 线程 × M 次增减后计数精确 | `ok p41/runtime`，2/2；连跑 5 次结果相同 | `test/ast/p41_cancel_flag`、`test/ast/p41_refcount` |
| E41-7 | 非原子/既有 `_Atomic` 产物零变化 | `ok p41/regression`；`--emit-c` 产物 sha256 与 `baseline.sha` 逐行相同 | 全量 |
| E41-8 | TSan 无数据竞争报告 | `bash selfhost/check-tsan.sh` exit 0；日志无 `WARNING: ThreadSanitizer` | `test/ast/p41_tsan.list` |
| E41-9 | 文档可执行：`language-spec` 片段原样编译；`bindings-and-patterns` 按新语法改写 | `python3 test/docs/check-docs.py` exit 0；`ok p41/docs` | `docs/**` |
| E41-10 | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §4.1，9/9 exit 0；收口对照表逐行贴原始输出 | §4.1 |

承诺映射：O1→E41-1 / E41-2；O2→E41-3 / E41-4；O3→E41-5 / E41-6 / E41-8。E41-7 / E41-9 / E41-10 守边界、文档与任务粒度。

## 6 负例台账（L41-n）

| 编号 | 触发 | 夹具（`test/ast/errors/`） |
| --- | --- | --- |
| L41-1 | `atomic char` / `atomic float` / `atomic struct S` | `p41_atomic_bad_base/` |
| L41-2 | `atomic own Box *b` | `p41_atomic_own_order/` |
| L41-3 | `own atomic int *p` | `p41_own_atomic/` |
| L41-4 | 定义 `atomic_load` | `p41_atomic_reserved/` |
| L41-5 | `atomic_cas(&x, 0, 1)`（by-value expected） | `p41_cas_byvalue/` |
| L41-6 | 裸 `atomic` / `atomic` 作返回类型 / 容器元素 | `p41_atomic_shape/` |
| L41-7 | `atomic_load(p)`（传指针值而非地址） | `p41_atomic_lvalue/` |
| L41-8 | `atomic _Atomic(int) x;` | `p41_atomic_double/` |
| L41-9 | `atomic;` / `atomic *p;`（旧直通形状） | `p41_atomic_misuse/` |
| L41-1w（正例） | `atomic int` / `atomic long` / `atomic void *` / `atomic bool` 各一 | `p41_atomic_types/` |
| L41-6a（正例） | 用户写 `_Atomic(int)` 与裸 `atomic_int` 照旧 | `p41_atomic_raw/` |

9 负例 + 2 正例 = 11 条，各断言一次。`atomic int x;` 的旧 bug 由「正例 `p41_atomic_types` + 负例 `p41_atomic_misuse`」双侧钉住：合法形态必须编译运行，直通形态必须报错而不是发坏 C。

## 7 风险与开放项

| 编号 | 风险 | 触发信号 / 处置 |
| --- | --- | --- |
| R41-1 | `atomic` 成为保留字，用户同名类型/变量失效 | 全仓 grep 0 命中；文档 breaking note；与 `own`/`borrow` 同列在 §1.3 |
| R41-2 | `__atomic_*` 的平台面（Clang 对 `_Atomic(T) *` 直接调用会拒） | 运行头统一剥基类型；CI 的 ubuntu-gcc、macos-clang 双跑；Windows 显式不在范围 |
| R41-3 | **保留名破坏面**：今天合法的 `int atomic_load(int *)` 会被 L41-4 拒；`_Atomic(struct S)` 配 `<stdatomic.h>` 的 `atomic_load` 宏可用面受影响（struct 原子不在本相） | 这是**已知功能取舍**，写进迁移说明：绑定层改名或改走地址形态；struct 原子走裸 C11 的用户需换宏名（`__atomic_*` 或自定义包装） |
| R41-4 | `<stdatomic.h>` 宏与保留名/运行头重名 | 运行头只用 `__ct_atomic_*` 前缀；用户 include 的宏不会与生成代码重名；L41-4 拦用户重复声明 |
| R41-5 | 绑定层用户迁到语言层时撞 by-value 硬错 | L41-5 文案给出 `&expected` 的修法；文档附重试循环示例 |
| R41-6 | 宿主无 TSan 时门禁形同虚设 | 本地 skip 必须打印一行 `SKIP: tsan unsupported by <cc>`；CI 的两个 Linux/macOS 镜像必须实际跑起来（nightly job 里 TSan 不可用即红），E41-8 以 CI 为准 |
| R41-7 | PH-40 同改 `Emitter.h.ct` / `Expr.h.ct`，冲突面大 | **建议 PH-40 先收口，PH-41 串行**；R1 只动解析器，可在 40 未收口时先落 |
| R41-8 | p41 夹具进了 `test/ast/**`，所有扫该目录的门禁都会链接它 | `check-sanitizers.sh` 与 `check-tsan.sh` 的链接命令补 `-pthread`；`check-warnings.sh` 只 `-c` 不链接，无需改 |
| R41-9 | 每个用到原子的 `.c` 多出 12 个 `static inline` | 未使用的内联函数不生成代码、不触发告警；产物增量可忽略，E41-2 的零告警钉住 |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T41-1 | `atomic struct` / 原子容器元素 / 原子返回类型 | 有真实用例，且 C11 侧能安全按值传递 |
| T41-2 | 数据竞争静态分析 | 有独立的并发模型设计，不与本相混 |
| T41-3 | 显式内存序（`memory_order` 参数或 `atomic_load_relaxed`） | 有性能敏感的包，且语义可机械校验 |
| T41-4 | 原子类型进 `--lib` 导出面 | p39 的 ABI 规则扩展；当前 L39-1 会拒绝 |
| T41-5 | Windows / MSVC 的 `Interlocked*` 后端 | 目标平台变更 |

## 8 估算与收口

- 编译器 340–610 = R1 60–110 + R2 80–150 + R3 60–100 + R4 60–100 + R5 50–90 + R9 30–60；夹具 160–260；门禁脚本 40–80；文档 60–100。
- 开工前 S0：PH-40 收口提交上重建 `ct`（`ct -v` = v0.40.0）、复跑 §2.2、写 §2.1 与 `baseline.sha`；不占任务行。
- 收口动作：11 道门禁绿、`p41/*` 全绿、`check-tsan.sh` 绿、`version-minor=41`、五处 `CTC_VERSION` 与全部版本落点同步到 `v0.41.0`、phase-log 与对照表落盘；tag/push 按 0.3 等用户批准。
- 每个实现任务 ≤3 个源码文件；每个实现提交的父提交是它的 `test(atomic): <task-id> 红`；仓库任何时刻可构建。
- 与 PH-42 的关系：两相都改 `Emitter.h.ct` 的方法/类型发射，**串行执行**（41 → 42）。PH-40 也要改 `Emitter.h.ct`，建议 40 先收口；只做 R1（解析器）时可与 40 并行。
