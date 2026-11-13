# 需求池

> **位置与字段**：按 `AGENTS.md` §6.1 / P-3。`what` / `why` / `priority` / `status` / `owner` /
> `last-touched` 七项必填；`block` 为空表示未阻塞。
> **状态词**：`open` / `planned` / `in-phase` / `dormant` / `rejected` / `done`（P-4）。
> **纪律**：条目只写「做什么、为什么、优先级」，不写实现方案；实现方案在
> `docs/design/phase*-draft.md`，排期在 `docs/roadmap.md`。

## REQ-L1 — 自定义类型的 `[]` 下标语法

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-L1` |
| `what` | 允许自定义 struct 在 `impl` 中声明签名匹配的 `get` / `set` 后使用 `obj[key]` / `obj[idx]` 下标语法，由编译器展开为对应方法调用；类型未声明该协议时是编译期硬错，错误信息必须指名类型。 |
| `why` | Agent 内核与 Rill DSL 的 JSON/参数表需要在自定义容器上写 `env["key"]`、`args[i]`；今天只有 `Vec` / `Map` 有下标糖，用户类型只能写 `env.get("key")`，把宿主语言的容器习惯泄漏进上层 DSL，也让「换容器实现」变成调用点改写。该语法只做方法调用的语法糖，零运行时，符合 Z1/Z3。 |
| `priority` | `P0` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-13 |
| `block` | 空（未阻塞） |

### 验收判据（每条带命令）

| # | 判据 | 命令 / 锚点 |
| --- | --- | --- |
| A1 | 非泛型 struct 定义 `int get(int)` 后，`b[1]` 发射为 `b.get(1)`，生成 C 可编译并运行 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    233_custom_index_read"` |
| A2 | 泛型实例 `Box<int>` 定义 `get` 后同样展开，错误/产物不残留 `Box_int` 之外的模板名 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    235_custom_index_generic"` |
| A3 | `void set(int, int)` 存在时，语句 `b[1] = 9;` 发射为 `b.set(1, 9)`，且 `b[1]` 读回 `9` | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    234_custom_index_write"` |
| A4 | 未声明 `get` 的 struct 下标是编译期硬错，文案指名类型，且不落 `.c` | `./selfhost/check-ast.sh 2>&1 \| grep -F "L1_1_no_get"` |
| A5 | `get` 存在但 `set` 缺失时，写形态是编译期硬错，文案指名类型与缺失方法 | `./selfhost/check-ast.sh 2>&1 \| grep -F "L1_2_no_set"` |
| A6 | `Vec` / `Map` 既有下标语义与 L31-3/L31-4 文案零变化 | `./selfhost/check-ast.sh 2>&1 \| grep -F "L31_3_vec_assign"` |
| A7 | C 数组与指针下标语义不变（`int a[3]; a[0]`、`int *p; p[0]`） | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    236_custom_index_c_passthrough"` |
| A8 | 全量门禁零失败、自举 fixpoint 通过 | `./selfhost/check-ast.sh 2>&1 \| tail -3` |

### 负例（必须各有一条独立夹具）

| 编号 | 输入 | 预期红 |
| --- | --- | --- |
| L1-1 | `struct X { int n; }`，读写 `x[0]`，无 `get` / `set` | 编译期硬错，指名 `X` |
| L1-2 | 只有 `get`，写 `x[0] = 1;` | 编译期硬错，指名 `X` 与缺失的 `set` |
| L1-3 | `get` / `set` 参数个数不匹配 | 编译期硬错，指名 `X` 与期望参数个数 |
| L1-4 | `get` / `set` 声明为 `static` | 编译期硬错，指明必须是实例方法 |
| L1-5 | `x[0] += 1;`、`x[0]++;`、`&x[0]` | 编译期硬错，提示只支持 `=` / 不能取地址 |
| L1-6 | 右值是 `own` / `borrow` 变量：`x[0] = own_v;` | 编译期硬错，禁止把所有权/借用值交给自定义 `set` |
| L1-7 | 接收者是右值：`make()[0] = 1;` | 编译期硬错，写形态要求左值接收者与语句位置 |

### 范围外（本条目不做）

- 不做 `+` / `==` / `()` 等其他运算符重载；只做 `[]`。
- 不改 `Vec` / `Map` 的布局、生成代码或既有诊断。
- 不放宽 L29-11（容器不装 `own` / `borrow` 值）与 L29-13（容器不装带 vptr 的实体）。
- 不接受 trait 提供的 `get` / `set`；只认 `impl` 的固有方法。
- 不做 `set`-only 类型：读形态是写形态的解析前置，v1 要求 `get` 存在。
- 不做参数/返回类型的完整兼容检查；v1 只校验方法名、参数个数、非 `static`，类型错误仍由 C 编译器兜底（与 `ct check` 的 opt-in 边界一致）。
- 不做文件作用域/常量初始化器里的自定义下标。

### 来源

外部提案 L1（Agent 内核 + Rill DSL，2026-11-13 研判）。同批 L2/L6/L11/L12 走文档，
L4 走契约，L7/L10/L8 拒绝或后置；本池只登记 L1。

### 方案草案

- [custom-index-protocol.md](../proposals/custom-index-protocol.md)（未立项；PH-40 已由 errdefer 占用，等待 AN 与排期）。

## REQ-ABI-1 — 用 ABI 哈希做导出面校验（评估后不采纳）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-ABI-1` |
| `what` | 评估「新增只读子命令：重算导出面 FNV-1a，与此前生成的 `.abi.h` 里的 `<BASE>_ABI_HASH` 比对」这一消费端校验方案。 |
| `why` | 结论**不采纳**。`<BASE>_ABI_HASH` 只折叠导出函数名（[Emitter.h.ct:5321-5329](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5321-L5329)），返回类型 / 参数类型 / 参数个数 / `const` 变化都不改变其值；名字直接首尾相接、没有分隔符，存在构造性碰撞。真正拦住导出面变更的是 `.abi.h` 与 golden 的逐字节比对，已在硬门禁内（[check-ast.sh:3600-3605](../../selfhost/check-ast.sh#L3600-L3605) → [r3_probe.sh:32-37](../../test/modules/p39_lib/r3_probe.sh#L32-L37)）。 |
| `priority` | `P2` |
| `status` | `rejected` |
| `owner` | REQ（2026-11-14 评估） |
| `last-touched` | 2026-11-14 |
| `block` | 空（未阻塞） |

### 结论

- 不新增子命令，不占相号。
- 需要比对导出面时用「重新生成头文件 + 归一化 diff」：两次 `.abi.h` 逐行 diff，忽略 banner 里的版本号行。

## REQ-ABI-2 — `ABI_HASH` 的折叠对象改为签名

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-ABI-2` |
| `what` | 把 `<BASE>_ABI_HASH` 的折叠对象从「导出函数名」改为「返回类型 + 函数名 + 参数类型」。 |
| `why` | 现状只哈希名字（[Emitter.h.ct:5321-5329](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5321-L5329)），签名变化不可见；改为签名后，返回类型 / 参数类型 / 参数个数 / `const` 变化都能改变哈希值。改动约 10 行 + 1 个 golden。**仅当需要下游用 `#if` 做编译期 pin 时才做**，否则以 `REQ-ABI-1` 的「重新生成 + 归一化 diff」为准。 |
| `priority` | `P2` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 空（未阻塞；触发条件 = 出现下游 `#if` 编译期 pin 需求） |

## REQ-ABI-3 — 枚举类型作形参导出时 `.abi.h` 构建失败

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-ABI-3` |
| `what` | `--lib` 生成 `.abi.h` 时，导出签名里出现的枚举标签没有声明，消费方编译该头文件失败；需要为枚举形参补上等价的前置声明（`enum X;` 一类的写法需按 C 标准确认）。 |
| `why` | 前置声明循环只识别 `struct ` 前缀（[Emitter.h.ct:5347](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5347)），`enum` 形参被跳过。实测 `void f(enum E e);` 在 clang 下只给 `-Wvisibility`（标签只在参数表内可见），换 gcc / 开 `-Werror` 时构建失败；枚举按值传参必须完整类型。 |
| `priority` | `P2` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 空（未阻塞） |

## REQ-ABI-4 — `union *` 形参缺前置声明

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-ABI-4` |
| `what` | 导出签名里出现 `union *` 形参时，`.abi.h` 没有对应的 `union X;` 前置声明。 |
| `why` | 同一处前缀判断只认 `struct `（[Emitter.h.ct:5347](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5347)），`union` 被跳过。实测 `void f(union U *p);` 在 clang 下给 `-Wvisibility`，参数表内的标签与消费方的实际 `union U` 不是同一标签，调用点会出现不兼容指针诊断。 |
| `priority` | `P3` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 空（未阻塞） |
