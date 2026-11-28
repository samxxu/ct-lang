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
| `status` | `done`（v0-PH-52 方案 A，v0.52.0；只主张单层字符串键，`v[0]` 的已知洞见 `REQ-JSACCESS-1` 与 `REQ-INDEX-1`） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-15 |
| `block` | 空（未阻塞） |

> **落地口径（2026-11-15 回填）**：v0-PH-52 按方案 A 交付，夹具以 `p52_*` 命名（`p52_read` / `p52_generic` /
> `p52_write` / `p52_c_passthrough` / `p52_str_only` / `p52_private` / `p52_subscript.sh`），下表 A1–A7 里
> `233_*` / `L1_*` 的旧命名未采用；判据内容由 `test/ast/p52_*` 与 `check-ast.sh` 的对应断言覆盖。
> `v[0]` 不在方案 A 的验收面内，已拆到 `REQ-JSACCESS-1` 与 `REQ-INDEX-1`。

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

- [custom-index-protocol.md](../proposals/custom-index-protocol.md)（未立项；v0-PH-40 已由 errdefer 占用，等待 AN 与排期）。

## REQ-JSACCESS-1 — 自定义下标的参数类型匹配（支持 `v[0]`）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-JSACCESS-1` |
| `what` | 自定义下标的协议匹配从「方法名 + 参数个数」扩展到「方法名 + 参数类型」：同一类型可并存 `get(char *)` 与 `get(int)`，`v["k"]` 与 `v[0]` 各选其版；无匹配时编译期硬错并列出候选签名。 |
| `why` | 「JS 风格访问」长期目标（`doc["a"]["b"]`、`doc[0]["k"]`）的组成部分。v0-PH-52 的方案 A 只覆盖单层字符串键；实测 `v[0]` 会展开成 `get(0)` 并静默返回空（v0-PH-52 D52-6）。用户 2026-11-15 明确：等语言特性更新完成后要完整实现该目标，**不得砍掉**。 |
| `priority` | `P1` |
| `status` | `planned`（`v1-PH-2` S2） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无（已排 `v1-PH-2` S2；须先于 `REQ-INDEX-1`） |

### 验收判据（实现后生效）

| # | 判据 | 命令 / 锚点（实现后可用） |
| --- | --- | --- |
| A1 | 同类型并存 `get(char *)` / `get(int)`：`v["k"]` 与 `v[0]` 各展开为对应版本 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    jsaccess_overload_both"` |
| A2 | 只有 `get(char *)` 时 `v[0]` 是编译期硬错（不再是静默空） | `./selfhost/check-ast.sh 2>&1 \| grep -F "JSACCESS_1_no_int_get"` |
| A3 | 实参类型无匹配时硬错，并列出候选签名 | `./selfhost/check-ast.sh 2>&1 \| grep -F "JSACCESS_2_no_candidate"` |
| A4 | v0-PH-52 的单层字符串键（`v["k"]`）零回归 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    24x_custom_index_read"` |
| A5 | 多级连写 `v["a"]["b"]` 仍由包层承担，本条不主张 | 文档句 + `p52` 夹具不回归 |

### 范围外

- 多级连写、指针接收者进协议、其他运算符重载。
- 跨单元导出面的重载可见性（另案）。
- 不占相号：排期时另立，不得在 v0-PH-52 内扩面。

### 来源

裁决记录 U-1 A（2026-11-15 签字）+ 用户原话「等 Ct 完成了语言特性的更新之后，要完整实现这个目标」。
v0-PH-52 的 D52-6 指向本条。

## REQ-INDEX-1 — 用户类型下标运算符：把「名 + 参数个数」的糖补成完整协议

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-INDEX-1` |
| `what` | 用户类型在固有 `impl` 中声明 `V get(K)` / `void set(K, V)`（或借用形态 `V *get(K)`）后，`x[k]` 读、`x[k] = v` 写、`*x[k] = v` 借写三种形态都由编译器静态展开为方法调用；同类型可并存不同参数类型的 `get`，实参类型决定选哪一版；`+=` / `++` / `&x[k]` 要么明确支持、要么明确硬错。语言只规定「协议」，不规定缺失/越界语义（由包用 `NULL` 或 `Option<V>` 表达）。 |
| `why` | v0-PH-52 交付的方案 A 只按「名 + 参数个数 + 非 static」匹配，于是 `char *get(char*)` 存在时 `x[0]` 会静默展开成 `get(0)` 并返回空（D52-6）。下游 ct-json 的 `doc[0]["k"]`、rill-dsl 的容器下标都卡在这一层，今天只能提供 `get_idx(i)` 过渡方法，把容器的调用习惯泄漏进上层 DSL。用户 2026-11-15 拍板「方向是必须支持」。 |
| `priority` | `P1` |
| `status` | `planned`（`v1-PH-2` S2） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无（`v1-PH-2` S2；`REQ-JSACCESS-1` 先落地）；实现于 LIR |

### 验收判据（实现后生效）

| # | 判据 | 命令 / 锚点 |
| --- | --- | --- |
| A1 | 同类型并存 `int get(int)` 与 `char *get(char *)`：`x[0]` / `x["k"]` 各选其版，产物可编译运行 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    index_overload_both"` |
| A2 | 只有 `char *get(char *)` 时 `x[0]` 是编译期硬错，文案列出候选签名 | `./selfhost/check-ast.sh 2>&1 \| grep -F "INDEX_1_no_candidate"` |
| A3 | 借用形态 `int *get(int)`：`*x[0] = 7;` 发射为对返回指针的解引用赋值，运行读到 `7` | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    index_borrow_write"` |
| A4 | `x[k] += 1` / `x[k]++` / `&x[k]` 的行为二值化：要么全支持（借用形态下等价于 `set` / 解引用），要么全部硬错且文案一致 | `./selfhost/check-ast.sh 2>&1 \| grep -F "INDEX_L"` |
| A5 | 写在值位置、右值接收者、`static`、参数个数不符仍是硬错，文案与 v0-PH-52 的 L52-* 逐字不回归 | 既有 `test/ast/p52_*` 与 `p52_subscript.sh` 全绿 |
| A6 | `Vec` / `Map` 内建下标零回归（`v[0]`、`m["k"]` 与写保护文案逐字不变） | 既有 `p52_str_only` / L31 负例全绿 |
| A7 | 全量门禁零失败 | `bash selfhost/check-all.sh 2>&1 \| tail -3` |

### 范围外

- 不放宽 L29-11 / L29-13（容器不装 `own` / `borrow` 值、不装带 vptr 的实体）。
- 不做其它运算符重载（`+` / `==` / `()`）。
- 不做 `x[k].field` / `x[k].m()` 的成员跳转（仍落 `cc`；见 `docs/proposals/user-index-operator.md` §5）。
- 不做接口值（trait 对象）上的下标派发；见同文档 §3 议题 A 的裁定。
- 不新增运行期语义：协议只做方法调用的静态糖。

### 来源

用户裁决（2026-11-15，「Ct 要增加用户类型可定义下标运算符的语言能力，方向是必须支持」）+ ct-json 复评实测。
承接 `REQ-L1`（v0-PH-52 方案 A 已交付）与 `REQ-JSACCESS-1`（参数类型匹配）。
设计草案：[user-index-operator.md](../proposals/user-index-operator.md)。

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
| `block` | 触发式：出现下游 `#if` 编译期 pin 需求才做；`v1-PH-2` 不排 stage |

## REQ-ABI-3 — 枚举类型作形参导出时 `.abi.h` 构建失败

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-ABI-3` |
| `what` | `--lib` 生成 `.abi.h` 时，导出签名里出现的枚举标签没有声明，消费方编译该头文件失败；需要为枚举形参补上等价的前置声明（`enum X;` 一类的写法需按 C 标准确认）。 |
| `why` | 前置声明循环只识别 `struct ` 前缀（[Emitter.h.ct:5347](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5347)），`enum` 形参被跳过。实测 `void f(enum E e);` 在 clang 下只给 `-Wvisibility`（标签只在参数表内可见），换 gcc / 开 `-Werror` 时构建失败；枚举按值传参必须完整类型。 |
| `priority` | `P2` |
| `status` | `done`（`v1-PH-2` S0，2026-11-25；[SH-121](../../issues/selfhost/sh121-abi-enum-forward.md) verified） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无（缺陷；S0 可独立切 `v1.1.1`） |

## REQ-ABI-4 — `union *` 形参缺前置声明

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-ABI-4` |
| `what` | 导出签名里出现 `union *` 形参时，`.abi.h` 没有对应的 `union X;` 前置声明。 |
| `why` | 同一处前缀判断只认 `struct `（[Emitter.h.ct:5347](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5347)），`union` 被跳过。实测 `void f(union U *p);` 在 clang 下给 `-Wvisibility`，参数表内的标签与消费方的实际 `union U` 不是同一标签，调用点会出现不兼容指针诊断。 |
| `priority` | `P3` |
| `status` | `done`（`v1-PH-2` S0，2026-11-25；[SH-122](../../issues/selfhost/sh122-abi-union-forward.md) verified） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无（缺陷；与 REQ-ABI-3 同批） |

## REQ-PKG-1 — 发布 lint 归 ct-pkg，`ct pkg check` 只做过渡

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-PKG-1` |
| `what` | 把 `ct pkg check` 当前的 4 条发布前 lint（ct.pkg 可读、name/publisher/version/ns-root 必填、ns-root 形状/存在、包树无绝对 `-I`）及其扩展（version/tag、namespace 目录、dep/requires、c-boundary）迁到 ct-pkg 的 shell 工具；`package.sh` 不再调用 `ct pkg check`；Ct 侧保留一个过渡版本后删除。`ct get/install` 的消费者校验不删。 |
| `why` | 发布 lint 属于包治理，不应反向依赖已安装的 `ct`；`package.sh` 当前靠 `ct pkg check` 才能跑，CI/维护者环境被编译器绑定。Ct 只应保留消费者必须的 manifest/identity/store/lock/digest/dep 校验。 |
| `priority` | `P1` |
| `status` | `planned`（外部前置；唤醒即做） |
| `owner` | REQ（ct-pkg 协调；Ct 侧只做 deprecation） |
| `last-touched` | 2026-11-25 |
| `block` | ct-pkg 先实现 shell `check` 并让 `package.sh` 脱离 `ct`；否则 Ct 不立 phase、不删 `ct pkg check`；不占 `v1-PH-2` stage |

### 验收判据（草案）

| # | 判据 | 命令 / 锚点 |
| --- | --- | --- |
| A1 | ct-pkg `check` 覆盖当前 4 条 + version/tag、namespace、dep/requires、c-boundary | ct-pkg CI 夹具；与 Ct 旧 4 条逐条对照 |
| A2 | `package.sh` 不再调用 `ct pkg check`，无 `ct` 安装的 CI 也能跑 | `grep -n 'ct pkg check' package.sh` 零命中；干净 CI |
| A3 | `ct pkg check` 过渡期保留并打印 deprecation；删除后 `ct pkg` 仍保持 install/check 语义 | 过渡夹具；删除提交 |
| A4 | `ct get/install` 的 identity/store/lock/digest/dep 校验不变 | 现有 `test/pkg` 全绿 |

### 落点

- **当前不占 phase**；这是跨项目需求，先入池。
- 若必须占 Ct phase，候选 **`v0-PH-72`**（类型检查 68–71 之后、v1.0 之前），但只装 Ct 侧 deprecation/删除；ct-pkg 的 shell check 不在 Ct phase 内。
- 触发条件：ct-pkg 受理并给出 shell `check` 的验收；否则保持现状。

## REQ-TYPE-1 — 默认路径全量类型检查

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-TYPE-1` |
| **现象** | `--types` 只对 `ct check` 有效；`ct build` / `ct compile` 不进入 §4.53 的三类判定，`ct compile` 可以 rc=0 写出 `cc` 拒收的 C。把它做成默认不是开关问题：CLI 语义、严重级、全部 golden 与 archive ratchet 会一起变。 |
| **证据锚点** | [language-spec.md:2206-2207](../language-spec.md#453-可选类型检查-ct-check---typesphase-32)（「`ct build` / `ct compile` 不进入这些判定」）；`check-goldens.sh`（已随 L1/L2 退役）（逐字节 golden）；`check-archive.sh`（已随 L1/L2 退役）（归档 oracle 逐字节 compare）；已知假阳性 `examples/18_generic_string_table/generic_string_table.ct:103`（由 `docs/phases/v0-PH-45/card.md` S1 先修）。 |
| **影响** | 461 语料 rc 与 `test/cases/*.expected.c` 全量重生成；`check-archive` 的 ratchet 口径变化；仓库方法论从「opt-in 检查」改为「默认严格」。 |
| **建议做法** | 等 `docs/phases/v0-PH-45/card.md` S1 落地、`--types` 在 40 个 example 上干净后，再按「CLI / 严重级 / golden 重生成 / 语料平价」拆 3–5 个切片评估；不在 43 / 45 内夹带。**同一要求另有一半已被覆盖**：默认路径不得以 rc=0 写出 `cc` 拒收的 C、`--types` 判得出的错必须与默认路径同判据——这是对 v0-PH-43 收口（`v0.43.0`）复查后确认的既有事实，`err:` 分支已硬错；剩余面是普通赋值 / `return` / 容器的全量判定。见 `docs/phases/v0-PH-45/card.md` §0.3。 |
| **当前判定** | **已排 `v1-PH-2` S7**；先取得 FP=0 证据，再分切片推进。 |
| `priority` | `P2` |
| `status` | `planned`（`v1-PH-2` S7） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 依赖 `--types` 在 40 个 example 上的 FP=0 证据；默认策略需用户单独签字；不依赖 IR。**证据基线**见 [s7-evidence-baseline](s7-evidence-baseline.md)（2026-11-26：`--types` 新增 0 条，11 个非零文件全是既有 check 诊断） |

## REQ-MEM-1 — 基于 CFG 的所有权 / 资源数据流分析

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-MEM-1` |
| **现象** | 提案方向的「CFG + 数据流所有权」在仓库里没有承载物：无 CFG、无 IR、无基本块、无独立 pass 框架，判定全部内联在递归下降解析器与符号表里；泄漏诊断走 `check-archive` 的逐字节比对。 |
| **证据锚点** | 全仓 `cfg / basic block / dominator / dataflow` 只命中一处无关注释 [Expr.h.ct:3044](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3044)；[check-ast.sh:34-38](../../selfhost/check-ast.sh#L34-L38)（泄漏与错误恢复两段与 L2 逐字节比对）；[check-ast.sh:13](../../selfhost/check-ast.sh#L13)（通用等价判据明确「不比诊断」）；[Memory.h.ct:44-60](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L44-L60)（`own_decl` / `own_base` 表）；[language-spec.md:1285](../language-spec.md#434-表达式里的赋值ct-ast)（值位置赋值绕过记账）。 |
| **影响** | 任何新分析要么输出与老实现完全一致的文本，要么改 golden——后者等于推翻「golden 是 oracle」；量级 5,000 行以上（AST→CFG、流敏感状态机、跨过程摘要、夹具与门禁四块）。 |
| **建议做法** | 不建新框架。先把已判得出的错误接到默认出口（v0-PH-43），再做 `REQ-MEM-2` 的单元内一层摘要；CFG 只作为「触发条件出现后再评估」的储备。 |
| **当前判定** | **`v1-PH-2` S7 只复评，不承诺实施**；量级 5,000+ 行。 |
| `priority` | `P3` |
| `status` | `dormant`（`v1-PH-2` S7 只复评） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 触发条件：出现必须靠流敏感分析才能抓的真实用户缺陷；`v1-PH-2` S7 只复评，不承诺实施 |

## REQ-MEM-2 — borrow 经未标注 C 调用或结构体字段逃逸

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-MEM-2` |
| **现象** | `borrow` 只是作用域 / 参数级注解，不是生命周期类型：`store(c)`（实参未标 `borrow`）与 `s->p = c` 不检查；`goto` 跨过声明会静默失效；不区分池对象与栈对象。 |
| **证据锚点** | [language-spec.md:1497-1498](../language-spec.md#440-borrow-与-handbackphase-5-续仅-ct-ast)（文档自认「不要宣称『有了 borrow 就不会悬垂』」）；[Memory.h.ct:44-60](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L44-L60)；[Stmt.h.ct:284-324](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L284-L324)（`retire_before_return` / jump 出口注入）。 |
| **影响** | 栈地址写进全局或字段时 `check` / `--types` 均 rc=0；ASAN 默认配置也看不见（见 `REQ-CI-2`）。 |
| **最小可行形态** | 单元内、**一层调用**的写入摘要：被调函数若把某个形参写入全局 / 字段 / 容器，则该形参必须标 `borrow`，否则调用点硬错；函数指针与递归走保守放行；不做跨单元、不做完整生命周期。量级 300–600 行 + 夹具。 |
| **为什么不进 43 / 45** | v0-PH-43 只判 `return err:` 载荷可赋值；v0-PH-45 只做闭包 `return` 跳过与指针基类型 / 层数判据。二者都不引入「写入摘要」这一新判定族，也不需要新符号表；硬塞会把两个小相扩成类型系统相。 |
| **建议做法** | 等 43 / 44 / 45 收口后单独立项；先只做单元内一层摘要，跨单元与完整 lifetime 继续留在池里。 |
| **当前判定** | **已排 `v1-PH-2` S7**（单元内一层写入摘要）。 |
| `priority` | `P2` |
| `status` | `planned`（`v1-PH-2` S7） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无（用 S1 的清理 CFG 做单元内一层写入摘要；跨单元不做）。**用例矩阵**见 [s7-evidence-baseline](s7-evidence-baseline.md) §5（P1–P6 / N1–N6 / D1–D2） |

## REQ-CI-1 — `nightly.yml` 缺 TSan job，与脚本 / 卡片口径不一致

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-CI-1` |
| **现象** | `check-tsan.sh` 与 v0-PH-41 卡都写「nightly Linux job 会跑」，但 `nightly.yml` 只有 `sanitizers` 与 `fuzz` 两个 job，没有 tsan。二者必须择一对齐：补 job，或改脚本 / 卡措辞。 |
| **证据锚点** | [nightly.yml:12-33](../../.github/workflows/nightly.yml#L12-L33)（仅 sanitizers + fuzz）；[check-tsan.sh:6-7](../../selfhost/check-tsan.sh#L6-L7)（「The nightly workflow runs it on Linux」）；[phase41-draft.md:240](../phases/v0-PH-41/card.md#L240)、[phase41-draft.md:324](../phases/v0-PH-41/card.md#L324)（R7「nightly Linux job」）。 |
| **影响** | TSan 实际未在 CI 执行；文档与 CI 事实不一致，读者会误以为并发回归有人守。 |
| **建议做法** | 二选一：① 在 `nightly.yml` 增加 ubuntu + `-fsanitize=thread` 的 tsan job；② 把脚本与 v0-PH-41 卡改成「TSan 仅本地手动跑」。**本轮只记录，不动 CI / 不动脚本 / 不改卡。** |
| **当前判定** | **已排 `v1-PH-2` S0**；默认补 TSan job（另一选项为改口径），待所有者确认。 |
| `priority` | `P1` |
| `status` | `planned`（`v1-PH-2` S0；纯 CI 不 bump） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 默认补 TSan job（另一选项为改口径）；需所有者确认；不占版本位 |

## REQ-CI-2 — ASAN 默认配置看不到栈上悬垂（`detect_stack_use_after_return`）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-CI-2` |
| **现象** | `check-sanitizers.sh` 只设 `ASAN_OPTIONS=detect_leaks=0`，没有 `detect_stack_use_after_return=1`；把栈地址写进全局的逃逸程序在默认 ASAN 下正常跑完，只有打开该选项才报 `stack-use-after-return`。 |
| **证据锚点** | [check-sanitizers.sh:14-24](../../selfhost/check-sanitizers.sh#L14-L24)（Leak 关闭说明，无栈逃逸选项）；[language-spec.md:1497-1498](../language-spec.md#440-borrow-与-handbackphase-5-续仅-ct-ast)（borrow 逃逸未覆盖）。 |
| **影响** | 「CI 有 ASAN」不等于「栈悬垂有人管」；提案最担心的那类悬垂目前只有手工开选项才可见。 |
| **建议做法** | 先在 nightly 加一个独立 job / 步骤，固定 `ASAN_OPTIONS=detect_stack_use_after_return=1:detect_leaks=0` 跑现有语料，评估噪声与耗时；稳定后再决定是否并入 `check-sanitizers.sh`。 |
| **当前判定** | **已排 `v1-PH-2` S0**（nightly 独立 job）；先测噪声，不占硬门禁。 |
| `priority` | `P2` |
| `status` | `planned`（`v1-PH-2` S0；纯 CI 不 bump） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 先测噪声，nightly 独立 job；不占版本位 |

## REQ-FUNCTOR-1 — 函子签名糖 `(A,B) => R`

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-FUNCTOR-1` |
| `what` | 为函数/方法参数提供 `(A,B) => R` 的签名糖，等价于现有的函数指针或闭包类型；只做签名书写，不新增调用语义与运行期机制。 |
| `why` | 指针退场 S4 的最后一档：v0-PH-75 已让闭包进方法实参，但回调签名仍要写完整函数指针类型；S4 因此从 v0 推迟，并在 v1.1 排期文本里失去承接（“v1.1+ Wave 2”）。2026-11-25 所有者裁定并入 `v1-PH-2`。 |
| `priority` | `P2` |
| `status` | `planned`（`v1-PH-2` S3） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无；须先出 ADR（与 trait/闭包关系、类型语法、ABI、IDE 展开）；独立于 ADT/检查器，在 LIR 上实施 |

## REQ-ADT-PATTERN-1 — ADT 模式扩展（字面量 / 嵌套 / 结构体 / or / 守卫 / 泛型 ADT）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-ADT-PATTERN-1` |
| `what` | 在 v0-PH-84 最小 ADT 与 LANG-29 B1–B5 之上，扩展 `match` 模式：字面量模式、嵌套模式、结构体模式、or 模式、守卫，以及泛型 ADT（`enum Option<T>` / `Result<T,E>`）。 |
| `why` | 这些形态从 v0-PH-84 起就是明确非目标（D3-A），LANG-21 / LANG-29 也再次登记为“v1.1+ 增量提案”；v1.1 只补了递归布局、ADT 方法/下标、payload retain、`map binding` 与表达式 `match`，模式文法与泛型 ADT 仍是欠账。 |
| `priority` | `P2` |
| `status` | `planned`（`v1-PH-2` S4–S6） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无；顺序固定为 S4 字面量/嵌套/结构体 → S5 or/守卫 → S6 泛型 ADT；泛型 ADT 最后做，需复核布局与 `Box`/`Vec` 互操作 |

## REQ-CAP-1 — 容量上限动态化（L0 遗留）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-CAP-1` |
| `what` | 把 L0 留下的“固定上限 + 越界硬报错”全部收到形式上限：49 个 `Limits.h.ct` 常量 + 8 个单元内本地常量 + 14 处硬编码；计数类动态倍增到 `CAP_LIMIT=65536`，文本/路径按需到 `TEXT_LIMIT=65536`，arena 到 `NODE_LIMIT=16777216`；只保留深度/错误恢复保护。 |
| `why` | L0 的固定上限（如 `MAX_METHODS` 64、`MAX_TEXT` 160）会挡住新增方法与长文本，是编译器实现债、不是语言规则；S1a-0 已把计数表改为初始值 + 倍增到形式上限，文本按需到 `TEXT_LIMIT`。策略见 [capacity-limits](capacity-limits.md)。 |
| `priority` | `P1` |
| `status` | `planned`（`v1-PH-2` S1a-0） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无；ADT 形态与泛型元数（C3）同批收到形式上限，spec §7 / stable-subset 与实现同一提交 |

## REQ-DOGFOOD-1 — selfhost 源码狗粮化（用最新特性压缩 .ct）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-DOGFOOD-1` |
| `what` | 用已落地的语言特性压缩 `selfhost/ct-ast/**/*.ct`：自由函数方法化（329）、手写 realloc/并行数组容器化（82）、错误路径 `?`/`errdefer`、命名构建 `snprintf`→`String`（选域）、已 ADT 域用 `match`、函子签名。生成 C 只要求可读，不要求变短。 |
| `why` | 语言特性已存在，但自举代码仍以 C 风格为主：397 处 `kind` 判别、300 条 `else if`、1,377 处 `snprintf`；源码 59,038 行，压缩空间在样板与手工内存管理。 |
| `priority` | `P2` |
| `status` | `planned`（`v1-PH-2` S8b） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-26 |
| `block` | 无；依赖 S3 函子与 S4–S6 ADT 模式；排在 S8 之后、S9 之前；节点池 `kind` 不改 ADT |

## REQ-STRICT-1 — 全局默认 strict（V1 欠账）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-STRICT-1` |
| `what` | 把 C 边界默认从“Ct 仓四目录 allow、外部 strict”改为**全局 strict**：`selfhost/`、`lib/core/` 迁到 `.m.ct` / shim 边界并零 allow；`examples/`、`test/` 能迁则迁，C 互操作用例显式 allow；manifest 无 `c-boundary` 键改为 strict，`ct migrate` 为旧包写 `c-boundary = allow`；CLI `--c-boundary=allow` 保留。 |
| `why` | v0-PH-65 的四目录豁免是 pre-1.0 临时安排；selfhost 已不再以 L2 语法为基础，不应直接 `#include` C 库；spec 的“不再自称 C 超集”不等于“Ct 仓永久 allow”。2026-11-25 所有者裁定：这是 V1 欠账，不是 v1.2 新增的颠覆性变更。 |
| `priority` | `P1` |
| `status` | `planned`（`v1-PH-2` S9） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 无；依赖 S1 的 LIR（迁移在 LIR 上）与 S7 的类型检查证据。**现数输入**见 [strict-include-audit](strict-include-audit.md)（2026-11-26：819 文件 / 1,078 行，M1–M5） |

## REQ-PRINT-1 — `Str` / `String` 的直接打印入口

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-PRINT-1` |
| `what` | 给借用视图加零分配输出入口：`Str.print()` / `Str.println()`，`String` 同名转发到 `as_str()`；按字节写 stdout，不调用 `cstr()`、不分配；`cstr()` 保留为 C 互操作出口。 |
| `why` | `Str` / `String` 目前没有直接输出入口，`cstr()` 会分配并要求调用方 `free`。于是 examples 里 26 个文件（[pointer-free-exemptions](pointer-free-exemptions.md) 的 E3 类）只能用 `printf("%s", s.cstr())`，「去指针」变成「多一次分配」，S8c 的指针清零目标无法达成。 |
| `priority` | `P2` |
| `status` | `accepted`（2026-11-27 所有者批准方案 A；**交付窗口 = v1.2，不顺延**；施工卡 [lang30-str-print-construction](../design/lang30-str-print-construction.md) 已交 DEV） |
| `owner` | DEV（实施）；REVIEW（ADR 签收）；REQ（验收） |
| `last-touched` | 2026-11-27 |
| `block` | 前置 ADR `D-030` 与 spec §4.78（与实现同批提交）；`fwrite` 声明走 `.m.ct` / shim（与 S9 同方向）。不依赖 IR；**必须在 S8c 收口前完成**（E-V3-9c 的 E3 清零依赖它），不接受顺延到 v1.3 |

## REQ-INDEXFOLD-1 — 常量键折叠 `p["x"]` → `p.x`

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-INDEXFOLD-1` |
| `what` | 字符串**字面量**键在编译期解析到结构体字段并折叠为字段访问；未知字段/非字面量键/非结构体接收者硬错；字段优先、并存 `get(char *)` 时给歧义诊断；只做读形态。 |
| `why` | 来稿 RFC-0000 的核心卖点（静态零开销下标），Ct 目前只有运行期 `get`；动态键已经可用，缺的只是“编译期已知的键”。 |
| `priority` | `P2` |
| `status` | `planned`（**v1.2 必做，2026-11-28 撤回 deferred**；与 I2 共用 D-028 的下标解析表） |
| `owner` | DEV（实施）；REVIEW（ADR 签收）；REQ（验收） |
| `last-touched` | 2026-11-28 |
| `block` | 前置 ADR `D-031` + spec 新节（施工卡已交）；按所有者 2026-11-28 裁定随 1.2 交付，1.2.0 的 tag 推迟到本项与 I2 落地后 |

## REQ-I2-1 — 接口值下标（I2）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-I2-1` |
| `what` | 接口值（trait 对象）支持 `o[k]`：在 trait 的 `get(K)` 签名后标 `index` 即表示该 `get` 是 `[]` 的解析目标，经 vtable 槽调用；单 trait、无独立标记 trait；读形态先行，写形态第二。 |
| `why` | 让同一段下标代码既能用于静态 struct（I1 / D-028），也能用于多实现的接口值；来稿 RFC-0000 的统一访问动机之一。Ct 目前只认固有 impl，接口值只能显式 `o.get(k)`。 |
| `priority` | `P2` |
| `status` | `planned`（四问已裁定 2026-11-28：Q1 立项、Q2 方法级 `index`、Q3 两阶段、Q4 暂不承诺 ABI；等 `D-034`） |
| `owner` | ARCH（ADR 设计）；DEV（实施）；REVIEW（复核）；REQ（验收） |
| `last-touched` | 2026-11-28 |
| `block` | 前置 ADR `D-034`（ARCH 起草）；不得破坏 D-028 的固有 impl 路径；`v1.2.0` 的 tag 推迟到 I1 与 I2 两阶段落地后。排期见 [I2-C1 §9](../design/i2-interface-subscript-construction.md)：`D-034` → I2-1 → I2-2（只读）→ I2-3 → I2-4（写入）→ I2-5；I1 的 `T1`/`T2` 先于 I2-2 改同一张解析表 |

> **四问裁定**：Q1 立项（随 1.2）；Q2 合并为方法级 `index`，取消 `Indexable`；
> Q3 阶段一只读、阶段二写入（同属 1.2）；Q4 暂不承诺 vtable 槽 ABI，语言稳定后统一发布。
> 样例与 D-028 边界（具体类型只认固有 impl，接口值走 trait 的 `index get`）见
> [RFC 评估 §3.1](../../docs/reviews/2026-11-27-indexable-rfc-evaluation.md)；
> 施工卡见 [I2-C1](../../docs/design/i2-interface-subscript-construction.md)。

## REQ-POINTERFREE-1 — 日常代码的指针退场

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-POINTERFREE-1` |
| `what` | 让日常 `.ct` 代码不再直接写指针：堆单对象、多返回、数组传递、字符串、回调五类场景各有值类型/句柄入口；指针、`own`、`defer`、`errdefer` 保留为逃生通道，不被禁止。 |
| `why` | 五类日常用途仍要求用户直接管指针与生命周期，和 Ct 的句柄/值类型方向不一致；希望把悬垂与泄漏路径收窄到可文档化、可机检的借用视图契约。 |
| `priority` | P1 |
| `status` | `planned`（主体已交付；P-1.3 迁移 lint 已于 2026-11-28 落库） |
| `owner` | REQ（待指派） |
| `last-touched` | 2026-11-25 |
| `block` | 本仓段 J-6 已 29 通过 / 0 缺失 / 0 部分；P-1.3 迁移 lint 三档 dry-run 已落库；外部 5 项归 std 包 |

> 方向与契约见 [pointer-free-v2](../proposals/pointer-free-v2.md)，裁定见 [D-011](../decisions/D-011.md)，
> phase 排期见 [pointer-free-phase-plan](pointer-free-phase-plan.md)。实现方案不在本池展开。

## REQ-STD-COVER-1 — 消费者无需为空 shim 付费（std 覆盖）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-STD-COVER-1` |
| `what` | `ct-pkg/std` 补齐日常任务所需能力（打印、字符串比较与查找、内存与缓冲、文件读写、时间/环境），使普通消费者在 strict C 边界下完成常见任务时**不需要写 `.shim.h`、也不需要直接调 libc**。 |
| `why` | strict 的本意是让"直接调 C"留痕，而不是让每个消费者为 `printf`/`strcmp`/`fopen` 各写一个空 shim。2026-11-28 排查 selfhost 时确认：63/66 个 shim 只有 `#include`；同样的成本会落在消费者身上。编译器侧的豁免只解决 selfhost（[D-032](../decisions/D-032.md)），消费者侧的答案是 std 覆盖，而不是放宽 strict。 |
| `priority` | P2 |
| `status` | `planned`（待 CTPKG 评估；已随 D-032 提出） |
| `owner` | CTPKG（包侧实施）；REQ（需求验收） |
| `last-touched` | 2026-11-28 |
| `block` | 需先在包仓列出"常见任务 → 现有 std 能力 → 缺口"清单；不阻塞本仓 v1.2 收口 |

> 边界：本条只主张**能力覆盖**，不主张新增语言语法；`#include` 的 strict 默认不变，
> 补头集合（spec §4.67）也不因本条扩张。缺口清单与 API 形态由 CTPKG 提包提案。

## REQ-SPELL-1 — emitter 的"拼写表"迁入 `LModulePlan`（S8 剩余）

| 字段 | 值 |
| --- | --- |
| `id` | `REQ-SPELL-1` |
| `what` | 把 emitter 生成 C 名与类型文本时对符号表的直接读取（`sym->funcs[i].cname`、参数/返回类型文本、trait 方法返回类型等）改为消费 `LModulePlan` 的"拼写表"；`write_abi_header`、`emit_drop_defs`、map prologue 不再查 `Symbols`。 |
| `why` | S8 已把"选择"（哪些导出、哪些 Drop、哪些 map）迁入 plan，"拼写"仍是最后一条 emitter→Symbols 依赖；它挡住 emitter 的独立复用与多后端演进，也让 S8 的"emitter 只消费 LModule"无法真正成立。无用户可见收益，属架构债。 |
| `priority` | P3 |
| `status` | `planned`（所有者 2026-11-28 裁定立项；未排入当前窗口） |
| `owner` | ARCH（ADR 设计）；DEV（实施）；REV（复核） |
| `last-touched` | 2026-11-28 |
| `block` | 需新 ADR（拟 `D-033`）定义拼写表字段与不变量；排期建议在 S8B-REM-1 R8（同属 `backend/emit`）之后，避免同文件集冲突 |

> 现状与边界见 [S8 差异清单](../reviews/2026-11-27-s8-ir2-diff-list.md) §3d 第 1 条、§3f；
> 立项不等于开工，开工前先出 ADR，不改 E-V3-9 已签的边界。
