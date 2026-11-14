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

## REQ-TYPE-1 — 默认路径全量类型检查（本期不做）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-TYPE-1` |
| **现象** | `--types` 只对 `ct check` 有效；`ct build` / `ct compile` 不进入 §4.53 的三类判定，`ct compile` 可以 rc=0 写出 `cc` 拒收的 C。把它做成默认不是开关问题：CLI 语义、严重级、全部 golden 与 archive ratchet 会一起变。 |
| **证据锚点** | [language-spec.md:2206-2207](../language-spec.md#L2206-L2207)（「`ct build` / `ct compile` 不进入这些判定」）；[check-goldens.sh:1-26](../../selfhost/check-goldens.sh#L1-L26)（逐字节 golden）；[check-archive.sh:1-20](../../selfhost/check-archive.sh#L1-L20)（归档 oracle 逐字节 compare）；已知假阳性 `examples/18_generic_string_table/generic_string_table.ct:103`（由 `docs/design/phase45.md` S1 先修）。 |
| **影响** | 461 语料 rc 与 `test/cases/*.expected.c` 全量重生成；`check-archive` 的 ratchet 口径变化；仓库方法论从「opt-in 检查」改为「默认严格」。 |
| **建议做法** | 等 `docs/design/phase45.md` S1 落地、`--types` 在 40 个 example 上干净后，再按「CLI / 严重级 / golden 重生成 / 语料平价」拆 3–5 个切片评估；不在 43 / 45 内夹带。 |
| **当前判定** | **本期不做**。 |
| `priority` | `P2` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 依赖 `docs/design/phase45.md` 收口与用户对默认策略的单独签字 |

## REQ-MEM-1 — 基于 CFG 的所有权 / 资源数据流分析（本期不做）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-MEM-1` |
| **现象** | 提案方向的「CFG + 数据流所有权」在仓库里没有承载物：无 CFG、无 IR、无基本块、无独立 pass 框架，判定全部内联在递归下降解析器与符号表里；泄漏诊断走 `check-archive` 的逐字节比对。 |
| **证据锚点** | 全仓 `cfg / basic block / dominator / dataflow` 只命中一处无关注释 [Expr.h.ct:3044](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3044)；[check-ast.sh:34-38](../../selfhost/check-ast.sh#L34-L38)（泄漏与错误恢复两段与 L2 逐字节比对）；[check-ast.sh:13](../../selfhost/check-ast.sh#L13)（通用等价判据明确「不比诊断」）；[Memory.h.ct:44-60](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L44-L60)（`own_decl` / `own_base` 表）；[language-spec.md:1285](../language-spec.md#L1285)（值位置赋值绕过记账）。 |
| **影响** | 任何新分析要么输出与老实现完全一致的文本，要么改 golden——后者等于推翻「golden 是 oracle」；量级 5,000 行以上（AST→CFG、流敏感状态机、跨过程摘要、夹具与门禁四块）。 |
| **建议做法** | 不建新框架。先把已判得出的错误接到默认出口（PH-43），再做 `REQ-MEM-2` 的单元内一层摘要；CFG 只作为「触发条件出现后再评估」的储备。 |
| **当前判定** | **本期不做**；量级 5,000+ 行，超过任一已收口相。 |
| `priority` | `P3` |
| `status` | `dormant` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 触发条件：出现必须靠流敏感分析才能抓的真实用户缺陷 |

## REQ-MEM-2 — borrow 经未标注 C 调用或结构体字段逃逸

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-MEM-2` |
| **现象** | `borrow` 只是作用域 / 参数级注解，不是生命周期类型：`store(c)`（实参未标 `borrow`）与 `s->p = c` 不检查；`goto` 跨过声明会静默失效；不区分池对象与栈对象。 |
| **证据锚点** | [language-spec.md:1497-1498](../language-spec.md#L1497-L1498)（文档自认「不要宣称『有了 borrow 就不会悬垂』」）；[Memory.h.ct:44-60](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L44-L60)；[Stmt.h.ct:284-324](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L284-L324)（`retire_before_return` / jump 出口注入）。 |
| **影响** | 栈地址写进全局或字段时 `check` / `--types` 均 rc=0；ASAN 默认配置也看不见（见 `REQ-CI-2`）。 |
| **最小可行形态** | 单元内、**一层调用**的写入摘要：被调函数若把某个形参写入全局 / 字段 / 容器，则该形参必须标 `borrow`，否则调用点硬错；函数指针与递归走保守放行；不做跨单元、不做完整生命周期。量级 300–600 行 + 夹具。 |
| **为什么不进 43 / 45** | PH-43 只判 `return err:` 载荷可赋值；PH-45 只做闭包 `return` 跳过与指针基类型 / 层数判据。二者都不引入「写入摘要」这一新判定族，也不需要新符号表；硬塞会把两个小相扩成类型系统相。 |
| **建议做法** | 等 43 / 44 / 45 收口后单独立项；先只做单元内一层摘要，跨单元与完整 lifetime 继续留在池里。 |
| **当前判定** | **待定**（本期不立项）。 |
| `priority` | `P2` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 依赖 43 / 44 / 45 收口；不做跨单元 |

## REQ-CI-1 — `nightly.yml` 缺 TSan job，与脚本 / 卡片口径不一致

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-CI-1` |
| **现象** | `check-tsan.sh` 与 PH-41 卡都写「nightly Linux job 会跑」，但 `nightly.yml` 只有 `sanitizers` 与 `fuzz` 两个 job，没有 tsan。二者必须择一对齐：补 job，或改脚本 / 卡措辞。 |
| **证据锚点** | [nightly.yml:12-33](../../.github/workflows/nightly.yml#L12-L33)（仅 sanitizers + fuzz）；[check-tsan.sh:6-7](../../selfhost/check-tsan.sh#L6-L7)（「The nightly workflow runs it on Linux」）；[phase41-draft.md:240](../design/phase41-draft.md#L240)、[phase41-draft.md:324](../design/phase41-draft.md#L324)（R7「nightly Linux job」）。 |
| **影响** | TSan 实际未在 CI 执行；文档与 CI 事实不一致，读者会误以为并发回归有人守。 |
| **建议做法** | 二选一：① 在 `nightly.yml` 增加 ubuntu + `-fsanitize=thread` 的 tsan job；② 把脚本与 PH-41 卡改成「TSan 仅本地手动跑」。**本轮只记录，不动 CI / 不动脚本 / 不改卡。** |
| **当前判定** | **待定**（口径一致性修复，P1；需用户就「补 job 还是改口径」二选一）。 |
| `priority` | `P1` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 需用户选择处置方向；不阻塞 43 / 44 / 45 |

## REQ-CI-2 — ASAN 默认配置看不到栈上悬垂（`detect_stack_use_after_return`）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-CI-2` |
| **现象** | `check-sanitizers.sh` 只设 `ASAN_OPTIONS=detect_leaks=0`，没有 `detect_stack_use_after_return=1`；把栈地址写进全局的逃逸程序在默认 ASAN 下正常跑完，只有打开该选项才报 `stack-use-after-return`。 |
| **证据锚点** | [check-sanitizers.sh:14-24](../../selfhost/check-sanitizers.sh#L14-L24)（Leak 关闭说明，无栈逃逸选项）；[language-spec.md:1497-1498](../language-spec.md#L1497-L1498)（borrow 逃逸未覆盖）。 |
| **影响** | 「CI 有 ASAN」不等于「栈悬垂有人管」；提案最担心的那类悬垂目前只有手工开选项才可见。 |
| **建议做法** | 先在 nightly 加一个独立 job / 步骤，固定 `ASAN_OPTIONS=detect_stack_use_after_return=1:detect_leaks=0` 跑现有语料，评估噪声与耗时；稳定后再决定是否并入 `check-sanitizers.sh`。 |
| **当前判定** | **待定**（门禁增强项，不进 11 道硬门禁）。 |
| `priority` | `P2` |
| `status` | `open` |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-14 |
| `block` | 需先测噪声；本轮只记录，不动 CI |
