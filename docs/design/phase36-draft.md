# Phase 36 — 所有权与字符串：泛型 `Drop` + 带长度字符串

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：**依赖落地后的提交**（Phase 31/33/34 收口并推送后确定），不预钉 `v0.30.0` 或 `bd91bfe`；S0 在**实现提交的父提交**上重建二进制并复跑 §2.2 探针，红证必须记录 `baseline: <sha>`。
> **文档形态**：`phase36-draft.md`；design window 12/12，**每次转正归档当时最老的一张**。
> **前置**：[phase31.md](phase31.md)（元素 `retain`/`release` 协议）、[phase33.md](phase33-draft.md)（泛型 struct）、[phase34.md](phase34-draft.md)（`Option`/`Result`、跨单元方法）。**三者均为硬前置**。
> **定位**：泛型 `Drop` 是所有权轴的收口；带长度字符串是它的第一个真实消费者。

## 1 目标与范围

### 1.1 一句话目标

让泛型 struct 能递归释放字段，并交付一个不依赖 NUL 结尾的带长度字符串 `Str`：`impl<T> Drop for Box<T>` 可用，`Vec<Str>` 在**显式 `release()`** 时逐元素释放，`own Str *` 走既有 AutoDrop；编译器侧按 §10 的切片求和计，字符串库代码单列。

### 1.2 范围（O1–O2）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 泛型 `Drop` | `impl<T> Drop for Box<T>`；无显式 impl 时按**声明顺序**递归字段 glue；有显式 impl 时编译器**不生成**字段 glue；复用 Phase 31 的 `__ct_elem_retain`/`__ct_elem_release` |
| O2 | 带长度字符串 | `lib/std/Str.h.ct`：`struct Str { char *data; int len; } use Drop`；`str_from`/`str_from_len`/`str_len`/`str_slice`/`str_concat`/`str_compare`/`str_c_str`/`str_release`；不依赖 NUL，保留内嵌 `\0` |

### 1.3 非目标（本相明确不做）

- 不做 GC、引用计数、COW、字符串驻留、Unicode 规范化、格式化/插值语法。
- 不做 `String` 可变增长缓冲（`StrBuf`，T36-1）；`Str` 只做不可变视图/拥有值。
- **不做结构体值的移动语义**：`own` 今天只支持 `own T *p = malloc|calloc(...)`，本相沿用；`own Str`（值）列为新语言特性（T36-5）。
- **不做容器/`Option` 的块尾自动释放**：容器一律显式 `release()`；新增自动释放轴（T36-6）。
- 不做 `char *` ↔ `Str` 的类型诊断：本相没有完整类型检查，误用由 cc 报错；若要诊断，归 Phase 32 的 `ct check` 扩展。
- 不做泛型 `Drop` 的 trait 对象/接口 payload 特化；不做 `Option`/`Result` 的 pattern/`?`。
- 不改变非泛型 `Drop` 的既有行为与产物；不改 Phase 31 的容器布局。
- 不新增 `MAX_*`；不触碰冻结层 `l0/l1/l2`。

### 1.4 依赖链

`Phase 31（元素协议）→ Phase 33（泛型 struct）→ Phase 34（Option/Result）→ Phase 36`。

- `Vec<Str>` 的元素释放走 Phase 31 的**结构性协议**：元素类型同时声明 `retain` 与 `release`（`retain` 返回自身类型），`Vec::release` 逐元素调用；不依赖泛型 `Drop`。
- `Option<Str>` 的 payload 在本相**不自动释放**：`Option<T>` 的方法体不能泛型地调用 `T` 的 `release`。要自动释放，用 `own Option<Str> *` + `delete`（触发泛型 Drop glue），或由调用方显式释放。
- 若 P31 的元素协议未落地，`Vec<Str>` 推迟，本相不开工。

## 2 现状与基线

### 2.1 门禁基线

参考值（最近一次全绿，Phase 31 开工前）：`check-ast` 1073/0、`test/run` 141/0、`check-warnings` 353/0、`check-docs` OK（1070 links / 185 files，v0.30.0，11 hard gates）、`design window 12/12`。S0 必须重测并回填。

### 2.2 红证探针（2026-11-11 实测）

| 探针 | 命令 | 基线输出 |
| --- | --- | --- |
| `impl<T> Drop for Box<T>` | `ct-ast /tmp/p36_drop2.ct` | `5:14: error: unexpected token` |
| `impl<T> Box<T> use Drop` | `ct-ast /tmp/p36_drop.ct` | `5:20: error: impl of an unknown trait` |
| `own Str s`（结构体值） | `ct-ast /tmp/p36_own.ct` | `5:1: error: 'own' requires a malloc or calloc initialiser` |
| `struct Str` | `grep -r "struct Str" lib/std` | 无此类型 |

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| 非泛型 Drop 语法/发射 | `Parser.h.ct` impl 解析；`Emitter.h.ct:2329-2365` |
| 无显式 impl 的字段 glue | `Emitter.h.ct:2344-2362`：按**声明顺序** `fi = 0..n-1` 递归 |
| 有显式 impl 时不生成 glue | `Emitter.h.ct:2336-2339`（`has` 为真则 `continue`） |
| `delete` 释放路径 | `Emitter.h.ct:2909-2925`（`X_Drop_drop(p); free(p); p = 0`） |
| `own` 规则 | `backend/mem/Memory.h.ct:76-115`（必须是 malloc/calloc + struct 指针 + struct `use Drop`）；`Memory.h.ct:89` 数组拒绝 |
| 泛型 impl 解析 | `Parser.h.ct:2671-2760` |
| Phase 31 元素协议 | [phase31.md](phase31.md) §3.2.1：`__ct_elem_retain`/`__ct_elem_release` 按元素类型方法集生成 |
| 容器 release | `lib/std/Vec.h.ct:164`（`refs` 归零后逐元素 `release`） |

## 3 语义设计

### 3.1 O1 泛型 `Drop`

#### 3.1.1 声明与实例化

- 允许 `struct Box<T> { … } use Drop;` + `impl<T> Drop for Box<T> { void drop(void) { … } }`。
- Drop impl 与实例一一对应：`Box<int>`/`Box<Str>` 各生成一份 glue；实例归属单元沿用 P33（消费方按需 `static`）。
- 无显式 impl 时，glue 递归字段中所有 `use Drop` 的字段；**顺序为声明顺序**（与 `Emitter.h.ct:2344` 的既有路径一致）。
- 有显式 impl 时，编译器**完全不生成**字段递归 glue（既有行为）；方法体自行负责全部释放。
- 非泛型 Drop 路径不变。

#### 3.1.2 释放顺序与双重释放

- 泛型与泛型的无 impl 路径统一为**声明顺序**；容器元素按既有正序释放。**不引入逆序**，避免与非泛型路径分叉。
- `drop` 方法体内对同一字段出现两次 `delete self->f` → L36-1（同一方法体、同一字段的语法级重复检测；不做流分析）。
- 没有显式 impl 时的自动 glue 只负责"字段递归"，不负责容器的 `release`。

#### 3.1.3 与容器/接口

- `Vec<T>` 的 `release()` 对每个元素调用 `__ct_elem_release`；`T` 同时声明 `retain`/`release` 时该助手非空，否则为空（Phase 31 既有协议）。
- `Option<T>` 自身在本相**不声明**自动 payload 释放；`Option<Str>` 若要自动释放，用 `own Option<Str> *` + `delete`。
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
- **拥有式分配沿用既有 `own` 规则**：`own Str *p = malloc(sizeof(struct Str));` 然后 `str_init(p, ...)`；`delete p` 先跑 `Str_Drop_drop` 再 `free` 并把指针置 0。
- 栈上的 `Str` 值不自动释放；用 `str_release(s)` 或放进容器后 `release()`。
- `retain` 为深拷贝（返回独立 `Str`），`release` 释放数据并把 `data` 置 0、`len` 置 -1；两者满足 Phase 31 的元素协议，`Vec<Str>` 因此可用。
- `slice(start, len)` 返回**拥有值**（深拷贝），避免借用逃逸分析（T31-5）；零拷贝视图见 T36-3。

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
| `str_release(Str s)` | 释放并置 `data=0, len=-1`；`Drop` 与容器元素释放共用同一内部函数 |

- 全部为 `pub` 函数或 `Str` 的固有方法，复用 P34 的跨单元能力；库代码不占编译器预算。
- 与 `char *` 不隐式互转；`printf("%s")` 需显式 `str_c_str`。

#### 3.2.3 字符语义

- 按 UTF-8 字节处理，不做 Unicode 规范化/大小写/字素簇；`len` 是字节数。
- 内嵌 `\0` 在 `str_from_len`/`slice`/`concat` 中保留；`str_c_str` 遇到内嵌 `\0` 会截断，文档必须警告。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D36-1 | 泛型 Drop 复用 Phase 31 元素协议 | 一套寿命规则，避免容器/struct 两套 |
| D36-2 | 字段按**声明顺序**释放，非泛型路径不变 | 与 `Emitter.h.ct:2344` 既有 glue 一致，不分叉 |
| D36-3 | 有显式 impl 时不生成字段 glue，方法体自负全责 | 既有实现事实；注入会自动双重释放 |
| D36-4 | `Str` 不要求 NUL 结尾，保留内嵌 `\0` | 带长度字符串的核心价值 |
| D36-5 | `Str` 按 UTF-8 字节处理，不做 Unicode 规范化 | 控制范围；后续可加 |
| D36-6 | `slice` 返回深拷贝 | 不引入借用逃逸分析（T31-5） |
| D36-7 | 容器一律显式 `release()`，无块尾自动释放 | 自动释放是新轴（T36-6），不在本相偷跑 |
| D36-8 | `own Str *` 走既有 AutoDrop；不做结构体值移动 | `own` 只接受 malloc/calloc 指针；值移动是新特性（T36-5） |
| D36-9 | 不给 `char *` ↔ `Str` 新增诊断 | 无类型检查；误用由 cc 报错，归 P32 |
| D36-10 | 跨单元 `Str` 只保证同一编译器版本内 | 依赖 P34；不做 ABI 承诺 |
| D36-11 | 不新增 `MAX_*`；不 bump、不打 tag | 与 31–35 纪律一致 |

## 5 Battle 记录

### B36-1 泛型 Drop 的字段释放顺序
采纳**声明顺序**，与既有非泛型 glue（`Emitter.h.ct:2344`）一致。逆序会让泛型与非泛型两条路径分叉，需要同时改旧路径并重生成 golden；本相不做。

### B36-2 显式 `drop` 体与自动字段释放
保持"显式 impl 自行负责全部释放"。实测 `Emitter.h.ct:2336-2339`：有显式 impl 时编译器直接 `continue`，不生成字段 glue；"先跑 drop 体再自动释放字段"与实现矛盾，且会双重释放。

### B36-3 `slice` 深拷贝 vs 借用视图
深拷贝。借用视图需要逃逸/别名分析（T31-5），会把本相拖入流分析；T36-3 保留零拷贝视图。

### B36-4 `Str` 的所有权形态
采纳 `own Str *`（指针 + malloc），不采纳 `own Str`（值移动）。实测 `own Str s` 报 `'own' requires a malloc or calloc initialiser`；值移动需要新的所有权语义，列为 T36-5。

### B36-5 容器/`Option` 的自动释放
本相不做。`Vec<Str>` 显式 `release()`；`Option<Str>` 用 `own Option<Str> *` + `delete` 或调用方显式释放。块尾自动释放列为 T36-6。

### B36-6 泄漏判据
11 道硬门禁不含 ASAN，`check-sanitizers.sh` 不跑 `test/modules/**` 且 `detect_leaks=0`。因此泄漏/双重释放**不作门禁判据**；门禁改为可观测的计数器输出 + 产物 grep，ASAN 只作人工证据，单列记录。

## 6 实现切片（每片 ≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 依赖落地后的父提交上重建、复跑 §2.2 | 无源码改动 | 0 |
| S1a | `impl<T> Drop for Box<T>` 解析 + 实例注册 | `Parser.h.ct` / `Symbols.h.ct` | 60–100 |
| S1b | `drop` 体内同字段重复释放检测（L36-1） | `Parser.h.ct` / `Stmt.h.ct` | 40–80 |
| S2a | 泛型 drop glue 发射（声明顺序、递归 `use Drop` 字段） | `Emitter.h.ct` / `Init.h.ct` | 90–140 |
| S2b | 容器元素协议接入与实例归属核对 | `Emitter.h.ct` / `lib/std/**` | 60–100 |
| S3 | 泛型 Drop 夹具（计数器可观测） | `test/ast/**` | 90–140 |
| S4 | `Str.h.ct` 库（**不计编译器预算**） | `lib/std/Str.h.ct` | 200–400 |
| S5 | `Str` 夹具：长度/切片/拼接/比较/内嵌 `\0` | `test/ast/**` | 90–140 |
| S6 | `own Str *` + 双重释放负例 | `test/ast/**` | 60–100 |
| S7 | 样例 `examples/40_str_ownership` | `examples/40_*` | 80–130 |
| S8 | 文档 + 全量门禁 | `docs/**` | 100–160 |

## 7 退出判据（E36-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E36-1 | `struct Box<T> use Drop` + `impl<T> Drop for Box<T>` 编译；`Box<int>`/`Box<Str>` 各生成 `Box_*_Drop_drop` | `ast/221_generic_drop` + 产物 grep | `check-ast` | 当前 `5:14: unexpected token` |
| E36-2 | 无显式 impl 时字段按声明顺序递归；有显式 impl 时不生成字段 glue；运行时计数器输出逐字节正确 | `ast/222_drop_order` | `check-ast` | 当前无泛型 Drop |
| E36-3 | `Vec<Str>` 显式 `release()` 逐元素调用 `Str_release`；`Vec<Probe>` 的计数器打印 3 次 | `ast/223_vec_str_release` + 产物 grep | `check-ast` | 当前无 `Str` |
| E36-4 | `own Option<Str> *` + `delete` 触发 `Option_Str_Drop_drop` → `Str_Drop_drop`；计数器可观测 | `ast/224_option_str_drop` + 产物 grep | `check-ast` | 当前无 `Str` |
| E36-5 | `drop` 方法体内重复释放同一字段 → L36-1 | `errors/double_drop.ct` | `check-ast` | 当前无泛型 Drop |
| E36-6 | `str_from_len` 保留内嵌 `\0`；`str_len` 返回字节数 | `ast/225_str_embedded_nul` | `check-ast` | 当前无 `Str` |
| E36-7 | `str_slice`/`str_concat`/`str_compare` 输出正确（含空串、全 `\0`、UTF-8 多字节） | `ast/226_str_ops` | `check-ast` | 当前无 `Str` |
| E36-8 | `own Str *p = malloc(...)` + `delete p` 编译运行；`delete` 后指针被置 0（产物 grep `p = 0`） | `ast/227_str_own_pointer` + 产物 grep | `check-ast` | 当前无 `Str` |
| E36-9 | 非泛型 `Drop` 产物与基线逐字节相同；既有 Drop 夹具零回退 | 全量 | `check-ast` | S0 实测 |
| E36-10 | 跨单元 `Str`（P34）在同一版本内工作；生成 `.h` 仅类型 | `test/modules/p36_str` | `check-ast` modules 段 | 当前无 `Str` |
| E36-11 | 样例 `examples/40_str_ownership` 进入 `test/run.sh`，golden 人工核对 | `examples/40_*` | `test/run` | 当前不存在 |
| E36-12 | language-spec/tutorial/glossary/roadmap 写清泛型 Drop、声明顺序、显式 impl 自负全责、`Str` 无 NUL/内嵌 `\0`/UTF-8 字节语义 | `docs/**` | `check-docs` | 当前无表述 |
| E36-13 | `check-all.sh` 11 道硬门禁全绿；计数不回退；不 bump、不打 tag | 全量 | `check-all` | 基线见 §2.1 |
| E36-14 | ASAN 人工证据：`test/ast` 的 `221`–`227` 在 `check-sanitizers.sh` 下无 double-free/UAF 报告（`detect_leaks=0`，不判泄漏） | 上述夹具 | 人工证据（**非门禁**） | 当前无此路径 |

## 8 负例台账（L36-n）

| 编号 | 触发 | 夹具 | 文案要点 |
| --- | --- | --- | --- |
| L36-1 | `drop` 方法体内重复释放同一字段 | `errors/double_drop.ct` | `field '<name>' is released twice in drop` |

只保留有夹具、有断言的一条；`own` 误用、`char *` 混用等既有/不存在的诊断不入台账。

## 9 样例计划

- **`examples/40_str_ownership`**：构造 `Str`、切片、拼接、比较；放入 `Vec<Str>` 并显式 `release()`；用 `own Str *` 演示 `delete`；输出确定。
- 负例：`drop` 体内重复释放。
- 编号：35 = P32，36–37 = P33，38 = P34，39 = P35，**40 = P36**。

## 10 估算（= 各切片求和）

| 区 | 组成 | 行数 | 文件数 |
| --- | --- | --- | --- |
| 编译器 | S1a+S1b+S2a+S2b | **250–420** | 4–6 |
| 夹具 | S3+S5+S6 | 240–380 | 9–16 |
| 样例 | S7 | 80–130 | 1–2 |
| 文档 | S8 | 100–160 | 4–6 |
| **编译器外合计** | 夹具 + 样例 + 文档 | **420–670** | 14–24 |
| 库代码（S4，**不计编译器预算**） | `lib/std/Str.h.ct` | 200–400 | 1–3 |

编译器 250–420 = 60+40+90+60 与 100+80+140+100，与 §6 逐片一致。

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R36-1 | 释放顺序分叉 | D36-2 统一声明顺序；E36-2 锁顺序 |
| R36-2 | 显式 impl 与自动 glue 双重释放 | D36-3 不生成 glue；E36-2 产物断言 |
| R36-3 | `Str` 内嵌 `\0` 与 `str_c_str` 截断 | E36-6 + 文档警告 |
| R36-4 | `own Str` 值移动被误当作既有能力 | D36-8 + §2.2 探针；T36-5 |
| R36-5 | 跨单元 `Str` ABI 漂移 | 只保证同一编译器版本；E36-10 |
| R36-6 | 泄漏/双重释放不可门禁 | B36-6；计数器 + 产物 grep；ASAN 人工证据 |
| R36-7 | `Option<Str>` 自动释放被误承诺 | D36-7；E36-4 只走 `own` + `delete` |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T36-1 | `StrBuf` 可变增长缓冲 | `Str` 稳定一个发布周期 |
| T36-2 | `Option`/`Result` 自动 payload 释放 | 有 Drop bound 的泛型方法体 |
| T36-3 | 零拷贝 `slice` 视图 | 有借用视图/逃逸分析设计 |
| T36-4 | Unicode 规范化/字素簇 | 有独立字符串设计卡 |
| T36-5 | 结构体值移动语义（`own Str`） | 有值移动/别名分析设计 |
| T36-6 | 容器/结构体块尾自动释放 | 有作用域析构设计（含容器） |
| T36-7 | 接口 payload 的泛型 Drop 特化 | 有 vptr + Drop 组合需求 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S2 的实现与诊断。
- `lib/std/Str.h.ct`、`lib/std/README.md` 去重说明。
- `test/ast/221–227_*`、`test/ast/errors/*`、`test/modules/p36_str`。
- `examples/40_str_ownership/` + golden。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`、`roadmap.md`。

## 13 收口与纪律

- **T-7 先红后绿**：S0 在实现提交的父提交上复跑探针并提交 `test(ownership): P36 红`（含 `baseline: <sha>` 与原始输出）。
- 每片 ≤3 文件、净增 ≤150 行；仓库任何时刻可构建。
- 不改判据宽度、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；不碰其他会话文件。
