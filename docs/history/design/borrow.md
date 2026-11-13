# `borrow` 关键字与 `Handback` trait（设计提案）

> 中文
>
> **状态：已实现（阶段一 / 阶段二，仅 ct-ast）。**
> 锚点 `8b047f5`（`v0.16.0`）。适用编译器：**ct-ast**（`selfhost/ct-ast/**`）；L0 / L1 / L2 不动。
> 本文件只承载设计：语法、语义、生成规则、约束、限制、阶段与决策。**不含实现计划，也不含任务清单。**
>
> 关联：`docs/language-spec.md` §4.9（AutoDrop）与 §4.40（`borrow` / `Handback`）；
> [SH-33](../../../issues/selfhost/sh33-autodrop-return-no-inject.md)（AutoDrop 在 `return` 前不注入、
> 不置空的既有缺陷），**已于 2026-11-01 修复**，本设计的前提因此成立。

---

## 中文

### 1. 目标

`own` + `Drop` 已覆盖独占所有权，但仍有三个结构性缺口：

| 缺口 | 现状 | 后果 |
| --- | --- | --- |
| 借用语义无表达 | 参数是不是借用，靠注释约定 | 误 `delete` 借用指针 → double free |
| 借用指针被存进更长寿位置 | 编译器不做跨过程分析 | 悬垂指针，无告警 |
| 共享工厂对象无归还机制 | 靠命名约定（`*_get` vs `*_open`） | 池槽位泄漏或误释放 |

`borrow` + `Handback` 不引入新内存模型，只把既有约定变成**编译器可检查的事实**：
出口注入一次“归还”调用——与 `own` 出口注入“销毁”调用同构。

### 2. 与提案前提的差异（事实订正）

1. **`own` 的出口形态（历史前提，已于 2026-11-01 失效）。** 提案写 `T_Drop_drop(p); free(p); p = 0;`；
   ct-ast 早期版本**不置空**，且只在块闭合 `}` 注入、**不在 `return` 前注入**，含 `return` 的函数里
   `own` 静默泄漏并留下死代码（SH-33）。该缺陷修复后，`own` 与 `borrow` 共用同一套出口注入：
   `}` 与**每个 `return` 之前**都注入，并同时置空（见 §5）。
2. **提案里的池示例不可编译。** `Conn_Drop_drop(&self->slots[i])` 是生成符号；源码里显式写
   `drop()` 会被拒绝（实测 `no method 'drop' for type 'struct Box *'`，值与指针皆然）。
   池的销毁只能经源码直通的普通 C 辅助函数（`static void conn_close(struct Conn *c)`）。
3. **`borrow` 已被用作标识符**（`test/modules/leak_call/prog.ct:17` 的函数名 `borrow`），
   故只能与 `own` 一样做**上下文关键字**；冲突面限于“语句首个 token”。

### 3. 语法

```c
/* 阶段一：参数注解 */
void render(borrow Request *r)

/* 阶段二：变量声明，出口自动归还 */
borrow Conn *c = pool.acquire("host");
/* → if (c) { Conn_Handback_handback(c); c = 0; } */
```

池与 trait（按 §2.2 订正）：

```c
struct Conn {
    int              fd;
    int              in_use;
    struct ConnPool *owner;
} use Handback, Drop;

impl Handback for Conn {
    void handback() { self->in_use = 0; }      /* 归还：对象仍活着 */
}

impl Drop for Conn {
    void drop() { close(self->fd); }           /* 销毁：只在池销毁时 */
}

struct ConnPool {
    struct Conn slots[8];
} use Drop;

static void conn_close(struct Conn *c);

impl Drop for ConnPool {
    void drop() {
        int i;
        for (i = 0; i < 8; i++) conn_close(&self->slots[i]);
    }
}
```

### 4. 语义与归属

- `Handback` 为**内建 trait**，照 `Drop` 处理（无 vptr、无 vtable，只发 `<S>_Handback_handback`）；
  用户无需自己声明 `trait Handback`（与 `use Drop` 同为内建）。
- 实现在**被借出的对象**上，而非工厂上：出口时编译器手里只有 `Conn *c`，归还动作必须从该指针
  出发（靠对象内的 `owner` 回指）。与 `Drop` 的处理方式一致。
- `use Handback` **必须**有 `impl Handback for S`（不提供默认空体），否则“归还”会变成静默空操作。

### 5. 代码生成规则

| | `own`（L2 / 目标形态） | `borrow` |
| --- | --- | --- |
| 出口调用 | `<S>_Drop_drop(p)` | `<S>_Handback_handback(p)` |
| 释放内存 | `free(p)` | 无 |
| 置空 | `p = 0` | `p = 0` |
| 条件包装 | `if (p)` | `if (p)` |
| 顺序 | 与 `borrow` 混排时按声明**逆序**（共用一张表） | 同 |

置空是硬要求：归还后对象仍在池里，可能被他人借走改写。
类型解析失败时**必须硬报错**，禁止回退为 `free`（那会释放池化对象）。

### 6. 约束与编译期检查

初始化：`own` 必须 `malloc` / `calloc`；`borrow` 允许任意表达式（但须为结构体指针）。两套校验**不可共用**。

| 检查 | 触发 | 级别 |
| --- | --- | --- |
| `borrow` 对象上 `delete` | `delete c;` / `delete r;` | 错误 |
| 赋给全局或更外层（更长寿）变量 | `g = r;` / 外层局部 `x = r` | 错误 |
| 类型未 `use Handback` | 声明处 | 错误 |
| `use Handback` 但无 `impl` | 声明处 | 错误 |
| 非结构体指针 / 数组 / `static` / 文件作用域 / `switch` 内 | 声明处 | 错误 |
| `}` 不在行首 | 注入失败 | 错误（与 `own` 同源） |
| `return c;`（局部 borrow 逃逸） | — | 警告 + 取消注入 |
| `return r;`（borrow 参数逃逸） | — | 警告 |
| `goto` 跨过声明 | — | 静默失效（与 `own` 相同） |

诊断文本（英文、小写、无句号、标识符单引号）：

```text
'borrow' is only allowed inside a function body
'borrow' requires a struct pointer parameter
'borrow' requires an initialiser of struct pointer type
struct '<S>' does not use trait 'Handback'
struct '<S>' uses trait 'Handback' but this unit has no impl
a borrowed pointer cannot be deleted
a borrowed pointer cannot be reassigned
a borrowed pointer cannot be stored in '<name>' (its scope outlives the borrow)
'borrow' is not supported inside a switch
'borrow' does not support arrays
a static local cannot be 'borrow'
warning: a borrowed pointer escapes through 'return'
```

### 7. 已知限制（必须诚实标注）

1. 不消除所有悬垂：能拦 `g = r`，拦不住 `store(r)`（除非其参数也标 `borrow`）；ct-ast 不做跨过程分析。
   **禁止宣称“有了 borrow 就不会悬垂”。**
2. 字段级生命周期不检查：`s->p = r`（`s` 比 `r` 长寿）看不见。
3. `goto` 跨过声明静默失效（与 `own` 相同）。
4. 不区分池对象与栈对象：`borrow Conn *c = &stack_conn;` 合法，`handback` 是否有效由 impl 负责。
5. 池淘汰 / `in_use` 约定是库的责任；语言只保证“不会误删”。
6. 提案的“归还后继续使用可静态警告”删去：语言里没有显式 `handback` 语句，注入只在出口执行，
   该检查没有可触发的语法位置。
7. **`impl Handback for S` 必须与 `borrow` 同单元**：结构体表按翻译单元重建，没有跨单元 impl 表，
   借用一个只在其导出单元里实现了 `Handback` 的结构体会报
   `struct '<S>' uses trait 'Handback' but this unit has no impl`（与 `Drop` 的跨单元限制同源）。
8. 借用句柄不可重新赋值、不可存入 `static` 局部或文件作用域变量——这三条都会在编译期报错，
   以免静默丢失归还动作。

### 8. 阶段与出口

| 阶段 | 内容 | 代码生成变化 | 出口 |
| --- | --- | --- | --- |
| 一 | 参数注解 + 禁止 `delete` + 禁止存入更长寿变量 | 无 | 九关全绿；正例生成物与不加注解逐字节一致；负例消息被门禁钉死 |
| 二 | 变量声明 + 出口自动 `handback` | 有 | 同上 + 人工核对生成 C（ct-ast 无字节 oracle，TEST-7） |

阶段二与 SH-33 的修复同批落地：两者共用同一条出口注入通道（`}` 与每个 `return` 之前），
归还与销毁都同时置空。建议与官方池 / Arena 库同期设计。
不做：返回值 borrow 传播、跨过程逃逸。

### 9. 兼容性

新增上下文关键字，opt-in；不写 `borrow` 行为不变。现存唯一冲突为
`test/modules/leak_call/prog.ct:17` 的函数名 `borrow`（函数名位置不受影响），需在升级说明中列出。

### 10. 测试要点

| 用例 | 期望 |
| --- | --- |
| 基本归还 | 出口注入 `handback` + 置空 |
| 嵌套作用域 | 逆序、正确嵌套 |
| `return` 逃逸（局部） | 取消注入，不误还 |
| `delete` on borrow / 存全局 / 存外层局部 | 编译错误 |
| 未 `use Handback` / 无 `impl` / 非结构体 / 数组 / `static` / 文件作用域 / `switch` | 编译错误 |
| 参数注解正例 | 生成物与不加注解逐字节一致 |
| `goto` 跨越 | 记录现状（静默失效） |

### 11. 决策

| # | 问题 | 决策 | 状态 |
| --- | --- | --- | --- |
| D1 | 阶段二是否等 SH-33 修复后再开工 | 是 | **已落实**（2026-11-01，探针 `test/ast/61_autodrop_return`） |
| D2 | `Handback` 内建 vs 用户声明 | 内建（照 `Drop`） | 已落实 |
| D3 | 方法名 `handback` vs `release` | `handback` | 已落实 |
| D4 | `use Handback` 是否强制 `impl` | 强制（同单元） | 已落实 |
| D5 | `return` 借用参数的逃逸：警告 vs 错误 | 警告 | 已落实 |
| D6 | `own` 侧是否随 SH-33 恢复 `p = 0` | 是（与 L2 / README / language-spec 一致） | **已落实**（`test/ast/61_autodrop_return`） |

### 12. 实现说明（与设计的差异）

阶段一 / 阶段二均已落地于 `selfhost/ct-ast/**`，门禁 `selfhost/check-ast.sh` 以新增断言钉住；
探针为 `test/ast/61_autodrop_return/`（SH-33）与 `test/ast/62_borrow_handback/`（本特性）。

| # | 差异 | 说明 |
| --- | --- | --- |
| E-A | 借用检查与借用记账未放进 trait | L2 的 `MAX_MAP_IMPLS 256` 是跨单元全局上限；`check_borrow_param` / `check_borrow_delete` / `check_borrow_store` / `mark_borrow` / `borrow_escape` 都是文件作用域 `static`，`Memory` 只新增 `own_kind[]` 数据字段 |
| E-B | `has_handback_impl` 按翻译单元记录 | 结构体表按单元重建，没有跨单元 impl 表：导入结构体 + 导出单元写 `impl Handback` 会误报「no impl」，与 `Drop` 的 `uses_drop` 同源（已知限制） |
| E-C | 不复制 L2 在 `own + return` 上的 `potential leak` 警告 | L2 已插入释放仍告警，属其保守分析噪声；ct-ast 释放后静默 |
| E-D | 出口注入复用 SH-33 修好的通道 | 释放链挂在 `N_RET.b`，`N_DELETE.aux` 区分 `own`（0，`drop` + `free`）与 `borrow`（1，只 `handback` + 置空）；两者共用一张 `own_decl[]` 表，天然逆序 |

支持的形态：函数参数、trait 方法参数、`impl` 方法参数三类参数列表都识别 `borrow`；声明期检查覆盖
非结构体指针 / 数组 / 无初始化式 / 未 `use Handback` / 无 `impl` / `static` / `switch` 内 / 文件作用域。
