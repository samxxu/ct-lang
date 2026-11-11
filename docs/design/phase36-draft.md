# Phase 36 — 所有权与字符串：泛型 `Drop` + 带长度字符串

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：`v0.30.0` @ `bd91bfe`；不 bump 版本、不打 tag。
> **文档形态**：`phase36-draft.md`；design window 12/12（phase20–31），32–36 共 5 张全部转正时按最老顺序归档 phase20–24。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡约 270 行，需需求提出方签字保留单卡。
> **前置**：[phase31.md](phase31.md)（元素 `retain`/`release` 助手）、[phase33.md](phase33-draft.md)（泛型 struct / 消费方发射）、[phase34.md](phase34-draft.md)（`Option`/`Result`、跨单元方法）。
> **定位**：两项能力共用 Phase 31 的元素寿命地基；泛型 `Drop` 是所有权轴的收口，带长度字符串是它的第一个真实消费者。

## 1 目标与范围

### 1.1 一句话目标

让泛型容器/泛型 struct 能**自动释放**元素，并交付一个不依赖 NUL 结尾的带长度字符串 `Str`：`impl<T> Drop for Box<T>` 可用，`Vec<Str>`/`Option<Str>` 在块尾正确释放，ASAN 干净。编译器侧 600–1,500 行；字符串库代码单列。

### 1.2 范围（O1–O2）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 泛型 `Drop` | `impl<T> Drop for Box<T>`；字段/元素按规则递归释放；复用 Phase 31 的 `__ct_elem_retain`/`__ct_elem_release`；无双重释放 |
| O2 | 带长度字符串 | `lib/std/Str.h.ct`：`struct Str { char *data; int len; }`，`own Str` 移动语义，构造/切片/拼接/比较/长度/释放；不依赖 NUL，保留内嵌 `\0` |

### 1.3 非目标（本相明确不做）

- 不做 GC、引用计数、COW、字符串驻留、Unicode 规范化、格式化/插值语法。
- 不做 `String` 可变增长缓冲（`StrBuf`）——保留 T36-1；本相 `Str` 只做不可变视图/拥有值。
- 不做 `char *` ↔ `Str` 的隐式转换；显式 `str_from`/`str_c_str`（若提供）。
- 不做跨单元 `Str` 的 ABI 兼容承诺（依赖 P34 的跨单元方法；只保证同一编译器版本内）。
- 不做泛型 `Drop` 的 trait 对象/接口 payload 特化；`Drop` 与 `Show` 等 trait 的组合留给后续。
- 不做 `Option`/`Result` 的自动 Drop 之外的 pattern/`?`。
- 不改变非泛型 `Drop` 的既有行为与产物；不改 Phase 31 的容器布局。
- 不新增 `MAX_*`；不触碰冻结层 `l0/l1/l2`。

### 1.4 依赖链

`Phase 31（元素助手）→ Phase 33（泛型 struct / 消费方发射）→ Phase 34（Option/Result、跨单元）→ Phase 36`。

- O1 直接复用 Phase 31 的 `__ct_elem_retain`/`__ct_elem_release`；不得为泛型 `Drop` 另写一套元素寿命规则。
- `Vec<Str>` 依赖 Phase 31 的容器与 P33 的实例归属；`Option<Str>` 依赖 P34 的库类型。
- 若 P31 的元素助手未落地，O1 只能覆盖非容器泛型 struct，`Vec<Str>` 推迟。

## 2 现状与基线

### 2.1 门禁基线（`bd91bfe`）

`check-ast` 1073 / `test/run` 141 / `check-warnings` 353 / `check-docs` OK（1048 links，11 gates，window 12/12）。

### 2.2 红证探针

| 探针 | 命令 | 基线 |
| --- | --- | --- |
| `impl<T> Drop for Box<T>` | `/tmp/ct-ast check /tmp/p36_drop.ct` | `5:14: error: unexpected token` |
| `struct Str { char *data; int len; }` | `grep -r "struct Str" lib/std` | 无此类型 |
| `Vec<Str>` 块尾释放 | S0 新建探针 | 当前无 `Str`；泛型 Drop 不可用 |
| `own Str` 移动 | S0 新建探针 | 当前无 `Str` |

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| 非泛型 Drop 语法/发射 | `examples/tour/15_memory/drop_loop_break/prog.ct`；`Parser.h.ct` impl 解析、`Emitter.h.ct` Drop 发射 |
| 泛型 impl 解析 | `Parser.h.ct:2694-2746` |
| Phase 31 元素助手 | `__ct_elem_retain`/`__ct_elem_release`（Phase 31 卡 §3；实现后以产物为准） |
| 容器实现 | `lib/std/Vec.h.ct`、内置 `Vec`/`Map`（Phase 29） |
| `own` 规则 | `TypeCheck.h.ct`、`Memory.h.ct`（借用/释放诊断） |
| `Option`/`Result` | Phase 34 的 `lib/std/Option.h.ct`、`Result.h.ct` |

## 3 语义设计

### 3.1 O1 泛型 `Drop`

#### 3.1.1 声明与实例化

- 允许 `struct Box<T> { … } use Drop;` + `impl<T> Drop for Box<T> { void drop(void) { … } }`。
- Drop impl 与泛型 struct 的实例一一对应：`Box<int>`/`Box<Str>` 各生成一份 drop glue；实例归属单元沿用 P33 的规则（消费方按需 `static`）。
- `drop` 方法体内可访问 `self` 与 `T` 的字段；若 `T` 自身 `use Drop`，glue 递归调用 `T` 的 drop。
- 非泛型 `Drop` 路径不变；新增的只是 `impl<T>` 形态。

#### 3.1.2 释放顺序

- 泛型 struct 的字段按**声明逆序**释放（C++/Rust 习惯），容器元素按**逆序**释放；`Vec`/`Map` 的既有释放顺序不变，只在元素类型有 `Drop` 时调用元素 drop。
- 显式 `drop` 方法体先于自动字段释放执行；方法体内不得再次释放同一字段（双重释放 → L36-1）。
- 非泛型 `Drop` 保持现有顺序与产物，不因本相改变。

#### 3.1.3 与容器/接口

- `Vec<T>` 在 `T` 有 `Drop` 时，`clear`/`release` 对每个元素调用 drop；复用 Phase 31 的 `__ct_elem_release`。
- `Option<T>` 在 `T` 有 `Drop` 时，`release` 调用 drop；`Option` 自身不自动 Drop（P34 的 `release` 是显式入口），T36-2 讨论自动 Drop。
- 接口 payload（`Show`）没有泛型 Drop 特化；本相不做。

### 3.2 O2 带长度字符串 `Str`

#### 3.2.1 表示与所有权

```
struct Str {
    char *data;
    int len;
} use Drop;
```

- `Str` 拥有 `data`（堆分配），`len` 为字节数；不要求 NUL 结尾，允许内嵌 `\0`。
- `own Str` 可移动；移动后源不可用（沿用现有 `own` 规则）。
- `copy` 为深拷贝；`slice(start, len)` 返回借用视图还是拥有值？本相选择**返回拥有值**（深拷贝），避免借用逃逸分析（T31-5）；T36-3 讨论零拷贝视图。

#### 3.2.2 API（最小集）

| 函数/方法 | 语义 |
| --- | --- |
| `str_from(char *s)` | 从 NUL 结尾 C 串构造（复制） |
| `str_from_len(char *p, int n)` | 从指针 + 长度构造（复制，保留内嵌 `\0`） |
| `str_len(Str s)` | 返回字节数 |
| `str_slice(Str s, int start, int n)` | 返回新 `Str`（深拷贝） |
| `str_concat(Str a, Str b)` | 拼接，返回新 `Str` |
| `str_compare(Str a, Str b)` | 按字节字典序，返回 -1/0/1 |
| `str_c_str(Str s)` | 返回临时 NUL 结尾副本（调用方负责释放；文档写明） |
| `str_release(Str s)` | 释放；`Drop` 也可自动释放 |

- 全部为 `pub` 泛型/非泛型函数或 `Str` 的固有方法，复用 P34 的跨单元能力；库代码不占编译器预算。
- 与 `char *` 不隐式互转；`printf("%s")` 需显式 `str_c_str`。

#### 3.2.3 字符语义

- 按 UTF-8 字节处理，不做 Unicode 规范化/大小写/字素簇；`len` 是字节数。
- `str_compare` 是字节序，不承诺语言排序。
- 内嵌 `\0` 在 `str_from_len`/`slice`/`concat` 中保留；`str_c_str` 遇到内嵌 `\0` 会截断，文档必须警告。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D36-1 | 泛型 Drop 复用 Phase 31 元素助手 | 一套寿命规则，避免容器/struct 两套 |
| D36-2 | 字段/元素逆序释放 | 与 C++/Rust 一致；文档写明；非泛型不变 |
| D36-3 | `slice` 返回深拷贝 | 不引入借用逃逸分析（T31-5） |
| D36-4 | `Str` 不要求 NUL 结尾，保留内嵌 `\0` | 带长度字符串的核心价值 |
| D36-5 | `Str` 按 UTF-8 字节处理，不做 Unicode 规范化 | 控制范围；后续可加 |
| D36-6 | `char *` ↔ `Str` 不隐式转换 | 避免所有权歧义 |
| D36-7 | `Option`/`Result` 本相不自动 Drop，保留显式 `release` | 自动 Drop 需要与 P34 的库 API 对齐；T36-2 |
| D36-8 | 跨单元 `Str` 只保证同一编译器版本内 | 依赖 P34；不做 ABI 承诺 |
| D36-9 | 不新增 `MAX_*` | 控制结构体膨胀 |
| D36-10 | 不 bump、不打 tag | 与 31–35 纪律一致 |

## 5 Battle 记录

### B36-1 泛型 Drop 的字段释放顺序
采纳**逆序**。C++/Rust 的销毁顺序是声明逆序；容器元素逆序释放可让“后构造先释放”成立。非泛型 Drop 不变，避免既有 golden 漂移；文档需明确两种路径的差异，若评审要求统一，另立迁移。

### B36-2 `slice` 深拷贝 vs 借用视图
采纳**深拷贝**。借用视图需要逃逸/别名分析（T31-5），会把本相拖入流分析；深拷贝语义简单、可 ASAN 验证。T36-3 保留零拷贝视图。

### B36-3 `Str` 是否自动 `Drop`
采纳**自动**（`Str` 自身 `use Drop`）；`Option<Str>`/`Vec<Str>` 的元素释放走 Phase 31 助手。`Option`/`Result` 容器自身不自动 Drop（D36-7），避免与 P34 的显式 `release` 双路径冲突。

### B36-4 与 `char *` 的互操作
不隐式转换。`str_c_str` 提供显式 NUL 副本，内嵌 `\0` 会截断并在文档警告；这是带长度字符串与 C 互操作的已知边界。

## 6 实现切片

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | `bd91bfe` 重建二进制，复跑 §2.2 探针（红证） | 无源码改动 | 0 |
| S1 | `impl<T> Drop` 解析 + 实例注册 + L36-1 | `Parser.h.ct` / `Symbols.h.ct` | 100–180 |
| S2 | drop glue 发射 + 逆序字段/元素 + 复用元素助手 | `Emitter.h.ct` / `Init.h.ct` | 180–350 |
| S3 | `Vec<T>`/`Option<T>` 的元素 drop 集成 | `Emitter.h.ct` / `lib/std/**` | 80–160 |
| S4 | 泛型 Drop 夹具 + ASAN 矩阵 | `test/ast/**` / `test/leaks/**` | 100–180 |
| S5 | `Str.h.ct` 库（不计编译器预算） | `lib/std/Str.h.ct` | 200–400 |
| S6 | `Str` 夹具：长度/切片/拼接/比较/内嵌 `\0` | `test/ast/**` | 100–180 |
| S7 | `own Str` 移动 + 双重释放负例 + L36-2/3 | `test/ast/errors/**` | 60–120 |
| S8 | 样例 `examples/40_str_ownership` + 文档 + 全量门禁 | `examples/40_*` / `docs/**` | 150–280 |

依赖：S1→S2→S3→S4；S5 可与 S1–S4 并行；S6/S7 依赖 S5；S8 最后。每片 ≤3 文件、净增尽量 ≤150 行。

## 7 退出判据（E36-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E36-1 | `struct Box<T> use Drop` + `impl<T> Drop for Box<T>` 编译；`Box<int>`/`Box<Str>` 各生成 drop glue | `ast/221_generic_drop` | `check-ast` | 当前 `5:14: unexpected token` |
| E36-2 | 字段按逆序释放，显式 `drop` 先于自动字段释放；输出顺序逐字节正确 | `ast/222_drop_order` | `check-ast` + `test/run` | 当前无泛型 Drop |
| E36-3 | `Vec<Str>` 块尾释放每个元素，ASAN 无泄漏/双重释放 | `test/leaks/vec_str` | ASAN job | 当前无 `Str` |
| E36-4 | `Option<Str>` 的 `release` 调用元素 drop；ASAN 干净 | `test/leaks/option_str` | ASAN job | 当前无 `Str` |
| E36-5 | `drop` 方法体内重复释放同一字段 → L36-1，不生成双重释放代码 | `errors/double_drop.ct` | `check-ast` | 当前无泛型 Drop |
| E36-6 | `Str` 的 `str_from_len` 保留内嵌 `\0`；`str_len` 返回字节数 | `ast/223_str_embedded_nul` | `check-ast` | 当前无 `Str` |
| E36-7 | `str_slice`/`str_concat`/`str_compare` 输出正确（含空串、全 `\0`、UTF-8 多字节） | `ast/224_str_ops` | `check-ast` + `test/run` | 当前无 `Str` |
| E36-8 | `own Str` 移动后源不可用；误用 → 既有 own 诊断（L36-2） | `errors/str_move.ct` | `check-ast` | 当前无 `Str` |
| E36-9 | `char *` ↔ `Str` 不隐式转换；混合使用给明确错误（L36-3） | `errors/str_implicit.ct` | `check-ast` | 当前无 `Str` |
| E36-10 | 非泛型 `Drop` 产物与基线逐字节相同；既有 Drop 夹具零回退 | 全量 | `check-ast` | 基线 1073 |
| E36-11 | 跨单元 `Str`（P34）在同一版本内工作；生成 `.h` 仅类型 | `test/modules/p36_str` | `check-ast` | 当前无 `Str` |
| E36-12 | 样例 `examples/40_str_ownership` 进入 `test/run.sh`，golden 人工核对 | `examples/40_*` | `test/run` | 当前不存在 |
| E36-13 | language-spec/tutorial/glossary/roadmap 写清泛型 Drop、释放顺序、`Str` 无 NUL/内嵌 `\0`/UTF-8 字节语义 | `docs/**` | `check-docs` | 当前无表述 |
| E36-14 | `check-all.sh` 11 道硬门禁全绿；计数不回退；不 bump、不打 tag | 全量 | `check-all` | 基线见 §2.1 |

## 8 负例台账（L36-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L36-1 | `drop` 方法体内重复释放字段 / 双重释放 | `field '<name>' is released twice in drop` |
| L36-2 | `own Str` 移动后使用 | 沿用既有 own 诊断，不新增文案 |
| L36-3 | `char *` 与 `Str` 隐式互转 | `no implicit conversion between 'char *' and 'Str'` |
| L36-4 | 泛型 Drop 与非泛型 Drop 同名实例冲突 | 沿用重复定义诊断 |
| L36-5 | `Str` 长度超过 `int` 可表示范围 | `string length exceeds the supported range` |
| L36-6 | 对无 `Drop` 的元素调用 `__ct_elem_release` | 内部断言/硬错，不静态发射空调用 |

## 9 样例计划

- **`examples/40_str_ownership`**：构造 `Str`、切片、拼接、比较；放入 `Vec<Str>`/`Option<Str>`；块尾自动释放；输出确定。
- 负例：双重释放、`own` 移动后使用、`char *` 隐式转换。
- 编号：35 = P32，36–37 = P33，38 = P34，39 = P35，**40 = P36**。

## 10 估算

| 区 | 行数 | 文件数 |
| --- | --- | --- |
| 编译器（S1–S4、S7） | **600–1,500** | 5–8 |
| 夹具（S4、S6–S7） | 250–450 | 12–20 |
| 文档 + 样例（S8） | 150–280 + 样例 | 5–8 |
| 库代码（S5，**单列**） | 200–400 | 1–3 |
| **编译器合计（不含库）** | **1,000–2,230** | **22–36** |

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R36-1 | 双重释放/释放顺序错 | E36-2/3/4 ASAN 矩阵 + E36-5 静态负例 |
| R36-2 | 泛型 Drop 与非泛型 Drop 规则分叉 | 复用元素助手；E36-10 锁旧产物 |
| R36-3 | `Str` 内嵌 `\0` 与 `str_c_str` 截断 | E36-6 + 文档警告 |
| R36-4 | `own Str` 移动与借用规则冲突 | 沿用现有 own 诊断；E36-8 |
| R36-5 | 跨单元 `Str` ABI 漂移 | 只保证同一编译器版本；E36-11 |
| R36-6 | 与 P34 的 `Option` release 双路径 | D36-7 明确：本相不自动 Drop `Option` 容器 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T36-1 | `StrBuf` 可变增长缓冲 | `Str` 稳定一个发布周期 |
| T36-2 | `Option`/`Result` 自动 Drop | 与 P34 的 `release` API 统一后 |
| T36-3 | 零拷贝 `slice` 视图 | 有借用视图/逃逸分析设计 |
| T36-4 | Unicode 规范化/字素簇 | 有独立字符串设计卡 |
| T36-5 | 接口 payload 的泛型 Drop 特化 | 有 vptr + Drop 组合需求 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S3、S7 的实现与诊断。
- `lib/std/Str.h.ct`、`lib/std/README.md` 去重说明。
- `test/ast/221–224_*`、`test/leaks/**`、`test/ast/errors/*`。
- `examples/40_str_ownership/` + golden。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`、`roadmap.md`。

## 13 收口与纪律

- **T-7 先红后绿**：S0 复跑探针并提交 `test(ownership): P36 红证`；随后按片实现。
- 每片 ≤3 文件、净增尽量 ≤150 行；仓库任何时刻可构建。
- 不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；不碰其他会话文件。
