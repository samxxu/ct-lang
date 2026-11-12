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
| O1 | 泛型 `Drop` | `impl<T> Drop for Box<T>`；无显式 impl 时按**声明顺序**递归字段 glue；有显式 impl 时编译器**不生成**字段 glue（泛型需先按实例登记，§3.1.1 ③）；复用 Phase 31 的 `__ct_elem_retain`/`__ct_elem_release` |
| O2 | 带长度字符串的**编译器契约** | `Str` 由 ct-pkg `std/string` 提供，是 shim 的不透明句柄（`pub struct Str { CStr *h; }`）；本相只交付它依赖的编译器机制（泛型 `Drop`、`own Str *`、`Vec<Str>` 元素协议）与一个本地夹具 `Str`（伪 `CStr`）验证协议；**不在 `lib/std` 重写 buffer** |

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
- `Option<T>` 的方法体不能泛型地调用 `T` 的 `release`；本相改为在 `Option<T>`/`Result<T,E>` 上加 `use Drop`，由字段递归 glue 负责 payload，`own Option<T> *` + `delete` 触发。块尾自动释放不做（T36-6）。
- 若 P31 的元素协议未落地，`Vec<Str>` 推迟，本相不开工。

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，Phase 31 开工前）：`check-ast` 1073/0、`test/run` 141/0、`check-warnings` 353/0、`check-docs` OK（1070 links / 185 files，v0.30.0，11 hard gates）、`design window 12/12`。这些数字**不是判据**；S0 必须重测并替换本节。

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
| 泛型实例与 `uses_drop` | `Symbols.h.ct:861-864`（实例行 `is_inst=1`）；`Expr.h.ct:1931-1962`（`add_struct_inst` 只复制字段与 `use`，不复制 `uses_drop`）；`Parser.h.ct:2179-2180`（模板行置 `uses_drop=1`）；`Emitter.h.ct:2333-2339`（循环不跳 `is_template`） |

## 3 语义设计

### 3.1 O1 泛型 `Drop`

#### 3.1.1 声明与实例化

- 允许 `struct Box<T> { … } use Drop;` + `impl<T> Drop for Box<T> { void drop() { … } }`。
- **① 实例化复制 `uses_drop`**：模板行在 `Parser.h.ct:2179-2180` 置 `uses_drop=1`，而 `Expr.h.ct:1931-1962` 的 `add_struct_inst` 只复制字段与 `use` 列表；不补这一步，无显式 impl 的 `Box<int>` 实例行 `uses_drop=0`，自动字段 glue 根本不会生成。
- **② glue 循环跳过模板**：`Emitter.h.ct:2333-2339` 只查 `uses_drop` 与 `N_IMPL.aux == si`，不看 `is_template`；模板行 `uses_drop=1`，会发射无效的 `Box_Drop_drop`。加 `if (is_template) continue;`。
- **③ 泛型 Drop impl 按实例登记（复用既有两向回填，不做 emit 期 post-scan）**：在 `StructDef` 的 `has_handback_impl` 旁加 `int has_drop_impl;`，并在 `add_struct`（`Symbols.h.ct:834-843`）清零。复用既有两处 build-wide 回填：实例晚于 impl 走 `Expr.h.ct:1963-1970`，impl 晚于实例走 `Parser.h.ct:2770-2779`；命中 `use == "Drop"` **且 `find_trait("Drop") < 0`（内建）** 且 `ct_impl_matches` 时只置 `has_drop_impl = 1`，不调 `adopt_use`、不把 `Drop` 加进 `use[]`；若用户声明了 `trait Drop`（`find_trait >= 0`），两处照常 `adopt_use`，`impl_emit_one` 也照常发 vtable——与 S1a 用**同一个谓词**。两处都是全局单例表，无 unit 作用域。
- glue 循环不再按“当前 unit 是否见过该 `N_IMPL`”判定：保留非泛型的既有 `N_IMPL.aux == si`，泛型侧直接对**全局** `ct_impls()` 求值（`strcmp(use,"Drop")==0 && ct_impl_matches(ij, ct_inst_find(structs[si].name))`），`has_drop_impl` 只是同一判定的缓存；条件为 `if (structs[si].is_template || has) continue;`。E36-2 的顺序夹具用同单元即可：`ct_impl_matches` 在发射期对全局表求值，晚出现的 impl 覆盖早先实例，不必改成跨单元形态。
- 无显式 impl 时，glue 递归字段中所有 `use Drop` 的字段；**顺序为声明顺序**（与 `Emitter.h.ct:2344` 的既有路径一致）。
- 有显式 impl 时，编译器**完全不生成**字段递归 glue；该结论对泛型 struct 成立的前提是 ③。方法体自行负责全部释放；非泛型 Drop 路径不变。

#### 3.1.2 释放顺序与双重释放

- 泛型与泛型的无 impl 路径统一为**声明顺序**；容器元素按既有正序释放。**不引入逆序**，避免与非泛型路径分叉。
- **编译器没有运行时计数器/释放钩子**：只有静态 `leak_*` 分析。所有"释放发生了几次"的可观测性来自**夹具里自定义的 `Probe`**（`struct Probe { int id; } use Drop;` + 夹具全局计数 + `retain`/`release` 打印），不是编译器或库新增的设施。
- `drop` 方法体内对同一字段调用两次 `release()` → L36-1（同一方法体、同一字段的语法级重复检测；不做流分析）。`delete` 会把指针置 0，重复 `delete` 是生成代码里的 no-op，不在检测范围；自动 glue 只负责字段递归，不负责容器 `release`。

#### 3.1.3 与容器/接口

- `Vec<T>` 的 `release()` 对每个元素调用 `__ct_elem_release`；`T` 的**固有方法集**同时声明 `retain` 与 `release`（且 `retain` 返回自身类型）时该助手非空，否则为空（Phase 31 既有协议）。
- `Option<T>` 在 P34 没有 `use Drop`。本相在 `lib/std/Option.h.ct` 与 `Result.h.ct` 的声明上加 `use Drop`（库改动，计入 S4c1/S4c2），实例因此获得字段递归 glue；`none()`/`ok()`/`err()` 必须**零初始化未使用的 payload**（`{0}`）。
- **glue 无条件 drop payload**（既有发射器行为，不做条件 drop）：`has == 0` 时仍会调一次 `T_Drop_drop`。因此空 payload 必须是"可安全 drop 的零状态"：`Str` 零状态为 `data=0, len=0`（drop 只 `free(NULL)` 并置 `len=-1`）；`Probe` 以 `id=0` 表示 empty，`Probe_Drop_drop` 遇到 `id==0` 直接返回、不计数。若要求"empty 不调用 drop"，必须给 `Option` 写显式条件 Drop，本相不做（T36-8）。
- 各实例的 glue 行为必须逐个说清：

| 实例 | payload 字段 | glue 行为 | 释放方式 |
| --- | --- | --- | --- |
| `Option<Str>` | `Str`（`use Drop` + 显式 Drop） | 调 `Str_Drop_drop` | `own Option<Str> *` + `delete` |
| `Option<Probe>` | `Probe`（夹具 `use Drop`） | 调 `Probe_Drop_drop`（`id==0` no-op） | 同上；E36-4 用计数观测 |
| `Option<Show>` | `struct Show_iface`（无 Drop） | 空 glue | 无 payload 资源可放；显式处理 |
| `Option<Vec<int>>` | `Vec_int`（只有显式 `release`，无 Drop） | 空 glue | **必须显式 `v.release()`**，否则泄漏 |

- `Option<Str>` 的 glue 路径与 `Option<Probe>` 相同；E36-4 用 `Option<Probe>` 计数观测，`Option<Str>` 只做产物 grep。
- 接口 payload（`Show`）没有泛型 Drop 特化；本相不做。

### 3.2 O2 带长度字符串 `Str`

#### 3.2.1 表示与所有权

`Str` 的规范位置是 ct-pkg `std/string`（shim 所在包），**不是 `lib/std`**。它是对 shim 的不透明句柄，只负责语言侧的方法与所有权，buffer 由 shim 拥有：

```c
pub struct Str { CStr *h; } use Drop;

impl Str {
    Str retain();          /* 返回可独立 release 的新句柄 */
    int release();         /* 返回剩余引用数；0 表示已释放 */
    int len();
    Str slice(int start, int n);
    Str concat(Str other);
    int compare(Str other);
    const char *c_str();   /* 有效期到 release 为止 */
}
```

- `CStr` 是 shim 的不透明类型；`cstr_retain` / `cstr_release` / `cstr_len` / `cstr_slice` / `cstr_concat` / `cstr_compare` / `cstr_c_str` 由 `std/string` 的 `.shim.h` 提供。
- `retain` 的契约是“返回一个可独立 `release` 的句柄”，**不规定实现**：shim 自带引用计数就是 O(1)；没有就由适配层深拷贝。CT 层不假设哪一种。
- `release` 返回剩余引用数，与 `Vec.release()` 的形态一致；`Drop` 只做 `cstr_release(self->h)`，不直接 `free`。
- `len` 是字节数；不要求 NUL 结尾，允许内嵌 `\0`；`c_str` 由适配层保证 NUL 结尾，遇到内嵌 `\0` 会截断，文档警告。
- `slice` v1 返回独立 `Str`（复制或引用计数视图由适配层决定），不做借用逃逸分析（T31-5）。
- **按值拷贝不自动 `retain`**：`Str b = a;` 与 `Vec` 一样只是复制句柄；要两个独立句柄必须写 `Str b = a.retain();`，否则两次 `release` 是双重释放。文档与样例必须按这个写法示范。
- `retain` / `release` 必须是**固有方法**（`impl Str { … }`），否则 Phase 31 的元素协议不生效；这要求 P34 的非泛型固有方法先落地。
- `own` 边界不变：`own Str *p = malloc(sizeof(Str));` 然后 `p->h = …;`；工厂函数返回的 `Str *` 不能直接 `own`（`'own' requires a malloc or calloc initialiser`），用显式 `release`，P38 后用 `defer`。
- **`lib/std` 不定义 `Str`**：内建层保持零外部依赖；本相夹具用一个本地 `struct Str { int *h; }` + 伪 `CStr` 验证 `Vec<Str>` 的 retain/release 与 `own`。

#### 3.2.2 API（最小集，由 ct-pkg `std/string` 提供）

| 函数/方法 | 语义 |
| --- | --- |
| `str_from(const char *s)` | 从 NUL 结尾 C 串构造（复制进 shim） |
| `str_from_len(const char *p, int n)` | 从指针 + 长度构造（复制，保留内嵌 `\0`） |
| `str_len(Str s)` | 返回字节数 |
| `str_slice(Str s, int start, int n)` | 返回新 `Str`（复制或引用计数视图，由适配层定） |
| `str_concat(Str a, Str b)` | 拼接，返回新 `Str` |
| `str_compare(Str a, Str b)` | 按字节字典序，返回 -1/0/1 |
| `str_c_str(Str s)` | 返回 NUL 结尾指针，**有效期到 `s.release()`**，调用方不释放 |
| `s.retain()`（固有方法） | 返回可独立 `release` 的新句柄；满足元素协议的 `retain` 形态 |
| `s.release()`（固有方法） | 释放本句柄，返回剩余引用数；与 `Drop` 走同一个 `cstr_release` |

- 元素协议只认固有方法 `retain`/`release`；自由函数 `str_retain`/`str_release` 可作为包装，但**不能让协议生效**。
- 全部为 `pub` 函数或 `Str` 的固有方法，复用 P34 的跨单元能力；**正式库代码在 ct-pkg，不占本相编译器预算**。
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
| D36-12 | `Str` 归 ct-pkg `std/string`，`lib/std` 不定义；本相只交付 Drop/元素协议/`own` 机制 + 本地夹具 | 内建层零外部依赖；避免与已存在的 shim 实现重复 |
| D36-13 | `Str` 是 shim 的不透明句柄 `{ CStr *h }`；`retain` 契约是“可独立 release 的新句柄”，引用计数或深拷贝由适配层决定 | CT 层不假设 shim 是否 refcount；两种实现都成立 |
| D36-14 | 工厂函数返回的 `Str *` 不走 `own`；用显式 `release`，P38 后用 `defer` | `own` 只接受 malloc/calloc 初始化，不为 `Str` 单独放宽 |

## 5 Battle 记录

### B36-1 泛型 Drop 的字段释放顺序
采纳**声明顺序**，与既有非泛型 glue（`Emitter.h.ct:2344`）一致。逆序会让泛型与非泛型两条路径分叉，需要同时改旧路径并重生成 golden；本相不做。

### B36-2 显式 `drop` 体与自动字段释放
保持"显式 impl 自行负责全部释放"。非泛型路径实测 `Emitter.h.ct:2336-2339`：有显式 impl 时编译器直接 `continue`，不生成字段 glue；"先跑 drop 体再自动释放字段"与实现矛盾，且会双重释放。泛型路径必须先完成 §3.1.1 的 ③（按实例登记），否则实例行 `has` 为假，自动 glue 与显式 `Box_int_Drop_drop` 并存。

### B36-3 `slice` 深拷贝 vs 借用视图
深拷贝。借用视图需要逃逸/别名分析（T31-5），会把本相拖入流分析；T36-3 保留零拷贝视图。

### B36-4 `Str` 的所有权形态
采纳 `own Str *`（指针 + malloc），不采纳 `own Str`（值移动）。实测 `own Str s` 报 `'own' requires a malloc or calloc initialiser`；值移动需要新的所有权语义，列为 T36-5。

### B36-5 容器/`Option` 的自动释放
本相不做。`Vec<Str>` 显式 `release()`；`Option<Str>` 用 `own Option<Str> *` + `delete` 或调用方显式释放。块尾自动释放列为 T36-6。

### B36-6 泄漏判据
11 道硬门禁不含 ASAN，`check-sanitizers.sh` 不跑 `test/modules/**` 且 `detect_leaks=0`。编译器也没有运行时计数器，只有静态 `leak_*` 分析。因此泄漏/双重释放**不作门禁判据**；门禁改为"夹具内 `Probe` 的计数输出 + 产物 grep"，ASAN 只作人工证据、单列记录。

### B36-7 `Str` 的位置与表示（2026-11-12 决定）

三个方案：

1. **`lib/std` 内联值** `{char *data; int len}` + `retain` 深拷贝（原草案）。**否决**：与已存在的 shim 重复实现，且每次 `Vec<Str>` push 都复制整串，长会话消息历史会退化成 O(n²) 字节。
2. **`lib/std` 句柄包 shim**。**否决**：内建层要 `#include` 外部 shim 并链接它的 `.c`，破坏 `lib/std` 的零外部依赖（Z2）。
3. **ct-pkg `std/string` 不透明句柄** `{ CStr *h }`，`retain` 委托 shim。**采纳**：一个类型、零重复 buffer、内建层不依赖外部包；shim 有引用计数则 `retain` 是 O(1)，没有则由适配层深拷贝。

边界：多一层指针与一次句柄分配；`c_str` 依赖适配层保证 NUL；工厂句柄不能直接 `own`（D36-14）；正式库不在本相，本相只用夹具验证协议。

## 6 实现切片（每片 ≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 依赖落地后的父提交上重建、复跑 §2.2 | 无源码改动 | 0 |
| S1a | **新增** `impl<T> Drop for Box<T>` 的 `for` 解析到 `parse_impl_inst`（今天 `for` 处报 `unexpected token`、`use` 形态报 `impl of an unknown trait`，都是新代码；`Drop`/`Handback` 在 `find_trait(name) < 0` 时按内建登记、不要求 trait 行，用户自声明 `trait Drop` 走既有路径，~25–40 行）+ **Drop/Handback 内建旁路**：`impl_emit_one`（`Emitter.h.ct:1618-1640`）在 `use` 为 `Drop`/`Handback` **且 `find_trait(use) < 0`** 时跳过整个 vtable 分支（只发方法，不引用 `struct <Use>_vtbl`、不初始化 `*_vtable`，~10–15 行） | `Parser.h.ct` / `Emitter.h.ct` | 60–100 |
| S1b | `drop` 体内同字段重复释放检测（L36-1） | `Parser.h.ct` / `Stmt.h.ct` | 40–80 |
| S2a1 | 实例化复制 `uses_drop` + glue 循环跳过 `is_template`（§3.1.1 ①②） | `Expr.h.ct` / `Parser.h.ct` / `Emitter.h.ct` | 60–100 |
| S2a2a | 复用两向回填登记：`StructDef.has_drop_impl` + `add_struct` 清零 + `Expr.h.ct:1963-1970`/`Parser.h.ct:2770-2779` 置位（§3.1.1 ③） | `Symbols.h.ct` / `Expr.h.ct` / `Parser.h.ct` | 25–45 |
| S2a2b | 泛型 drop glue 发射（声明顺序、递归 `use Drop`）+ glue 循环对全局 `ct_impls()` 求值判 `has` | `Emitter.h.ct` / `Init.h.ct` | 25–45 |
| S2b1 | 编译器侧实例归属核对（`nm --defined-only` 每实例恰一份；模板行用生成 C 定义行 grep == 0，不用 `nm`） | `Emitter.h.ct` | 30–60 |
| S2b2 | 库侧元素协议接入（`Vec`/`Option`/`Result` 与 `retain`/`release`），**不计编译器预算** | `lib/std/**` | 20–40 |
| S3 | 泛型 Drop 夹具（夹具内 `Probe` 计数可观测） | `test/ast/**` | 90–140 |
| S4a | 夹具：本地 `Str` 句柄 + 伪 `CStr`（`.shim.h`/`.shim.c`），验证 `retain`/`release`、`Vec<Str>` 释放与 `own` 边界，**不计编译器预算** | `test/modules/p36_str_shim/**` | 80–130 |
| S4b | ct-pkg `std/string` 正式实现：**不在本相**，只登记依赖（P34 固有方法 + P36 Drop/元素协议） | ct-pkg | 0 |
| S4c1 | 库片：`Option.h.ct` 加 `use Drop` + `none()` 零初始化 payload | `lib/std/Option.h.ct` | 20–40 |
| S4c2 | 库片：`Result.h.ct` 加 `use Drop` + `ok()`/`err()` 零初始化未使用 payload | `lib/std/Result.h.ct` | 20–40 |
| S5 | `Str` 夹具：长度/切片/拼接/比较/内嵌 `\0` | `test/ast/**` | 90–140 |
| S6 | `own Str *` + 双重释放负例 | `test/ast/**` | 60–100 |
| S7 | 样例 `examples/40_str_ownership` | `examples/40_*` | 80–130 |
| S8a | 收口片：文档（不产编译器代码） | `docs/**` | 60–100 |
| S8b | 收口片：全量门禁与收口记录（不产编译器代码） | 无源码改动 | 40–60 |

## 7 退出判据（E36-n；夹具 225–227、229–232，228 属 P34 本相不占用）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E36-1 | `struct Box<T> use Drop` + `impl<T> Drop for Box<T>` 编译；夹具对 `Box<int>`/`Box<Str>` 各 `delete` 一次（保证 glue 被发射、不被优化掉）。**断言**：`nm --defined-only`（不加 `-g`；macOS 符号带 `_` 前缀）匹配 ` [tT] _?Box_int_Drop_drop$` 与 ` [tT] _?Box_Str_Drop_drop$` 各恰 1 条；生成 C 的定义行（**同时接受 `static void` 与 `static __attribute__((unused)) void` 两种拼写**；文件内声明+定义共 2 行，此处只数定义行，期望 1）`grep -cE '^static .*Box_int_Drop_drop\(void \*self\) \{' == 1`，`Box_Str` 同理；模板 `Box_Drop_drop` 用**生成 C 定义行** `grep -cE '^static .*Box_Drop_drop\(void \*self\) \{' == 0`（未引用的 static 在 `nm` 里恒为 0，不能用 `nm`） | `ast/225_generic_drop` + 产物 grep/`nm` | `check-ast` | 当前 `5:14: unexpected token`；`Box_Str` 半条须 P36 落地后 |
| E36-2 | 无显式 impl 时字段按声明顺序递归；有显式 impl 时自动字段 glue 为零（`nm --defined-only` 中 `Box_int_Drop_drop`/`Box_Str_Drop_drop` 无第二份、链接无重复符号）；**顺序夹具（同单元）**：`impl<T> Drop for Box<T>` 写在 `Box<int>` 首次使用之后仍生效（`ct_impl_matches` 在发射期对全局 `ct_impls()` 求值）；夹具内 `Probe` 的全局计数输出逐字节正确（`Probe` 是夹具代码，不是编译器/库设施） | `ast/226_drop_order` | `check-ast` | 当前无泛型 Drop |
| E36-3 | `Vec<Probe>` 的 `release()` 逐元素调用 `Probe_release`（容器调 `T_release`，不会调 `T_Drop_drop`），计数打印 3 次；`Vec<Str>` 产物 grep 到 `Str_release(` 调用 | `ast/227_vec_element_release` + 产物 grep | `check-ast` | 当前无 `Str` |
| E36-4 | P36 给 `Option<T>` 加 `use Drop` 后：`own Option<Probe> *` + `delete` 触发 `Option_Probe_Drop_drop` → `Probe_Drop_drop`；**期望计数：1 个 `id!=0` 的 payload 计 1，`none<Probe>()` 计 0**；`none()`/`ok()`/`err()` 零初始化未使用 payload；`Option<Str>` 产物 grep `Str_Drop_drop(&_self->value)` | `ast/229_option_probe_drop` + 产物 grep | `check-ast` | 当前无 `Str`/`Option` Drop |
| E36-5 | `drop` 方法体内对同一字段调用两次 `release()` → L36-1 | `errors/double_drop.ct` | `check-ast` | 当前无泛型 Drop |
| E36-6 | `str_from_len` 保留内嵌 `\0`；`str_len` 返回字节数 | `ast/230_str_embedded_nul` | `check-ast` | 当前无 `Str` |
| E36-7 | `str_slice`/`str_concat`/`str_compare` 输出正确（含空串、全 `\0`、UTF-8 多字节） | `ast/231_str_ops` | `check-ast` | 当前无 `Str` |
| E36-8 | **复用既有 `own`/`delete` 机制的回归（`Str` 是新类型）**：`own Str *p = malloc(...)` + `delete p` 编译运行；`delete` 后指针被置 0（产物 grep `p = 0`）；`Str_Drop_drop` 体内含 `free(_self->data)`、`_self->data = 0` 与 `_self->len = -1`（glue 参数名是 `_self`，或夹具分配计数归零） | `ast/232_str_own_pointer` + 产物 grep | `check-ast` | 当前无 `Str` |
| E36-9 | 非泛型 `Drop` 产物与基线逐字节相同；既有 Drop 夹具零回退 | 全量 | `check-ast` | S0 实测 |
| E36-10 | 跨单元 `Str`（P34）在同一版本内工作；生成 `.h` 仅类型 | `test/modules/p36_str` | `check-ast` modules 段 | 当前无 `Str` |
| E36-11 | 样例 `examples/40_str_ownership` 进入 `test/run.sh`，golden 人工核对 | `examples/40_*` | `test/run` | 当前不存在 |
| E36-12 | language-spec/tutorial/glossary/roadmap 写清泛型 Drop、声明顺序、显式 impl 自负全责、`Str` 无 NUL/内嵌 `\0`/UTF-8 字节语义 | `docs/**` | `check-docs` | 当前无表述 |
| E36-13 | `check-all.sh` 11 道硬门禁全绿；计数不回退；不 bump、不打 tag | 全量 | `check-all` | 基线见 §2.1 |
| E36-14 | ASAN 人工证据：`test/ast` 的 `225`–`232`（跳过属于 Phase 34 的 `228`）在 `check-sanitizers.sh` 下无 double-free/UAF 报告（`detect_leaks=0`，不判泄漏） | 上述夹具 | 人工证据（**非门禁**） | 当前无此路径 |

## 8 负例台账（L36-n）

| 编号 | 触发 | 夹具 | 文案要点 |
| --- | --- | --- | --- |
| L36-1 | `drop` 方法体内对同一字段调用 `release()` 两次（`delete` 已置 0，重复 `delete` 是 no-op，不在范围） | `errors/double_drop.ct` | `field '<name>' is released twice in drop` |

只保留有夹具、有断言的一条；`own` 误用、`char *` 混用等既有/不存在的诊断不入台账。L36-1 只检测**固有方法形态**的重复 `release()`；自由函数包装（`str_release(s)`）不在本相检测范围。

## 9 样例计划

- **`examples/40_str_ownership`**：用本地最小 `Str`（伪 `CStr`）构造、切片、拼接、比较；放入 `Vec<Str>` 并显式 `release()`；用 `own Str *` 演示 `delete`；输出确定。正式 `Str` 在 ct-pkg，不进本仓库。
- 负例：`drop` 体内重复释放。
- 编号：35 = P32，36–37 = P33，38 = P34，39 = P35，**40 = P36**。

## 10 估算（= 各切片求和）

| 区 | 组成 | 行数 | 文件数 |
| --- | --- | --- | --- |
| 编译器 | S1a+S1b+S2a1+S2a2a+S2a2b+S2b1 | **240–430** | 4–7 |
| 夹具 | S3+S4a+S5+S6 | 320–510 | 10–18 |
| 样例 | S7 | 80–130 | 1–2 |
| 文档 | S8a+S8b | 100–160 | 4–6 |
| **编译器外合计** | 夹具 + 样例 + 文档 | **500–800** | 15–26 |
| 库代码（S2b2+S4c1+S4c2，**不计编译器预算**） | `lib/std/Vec.h.ct`、`Option.h.ct`、`Result.h.ct` | 60–120 | 2–4 |

编译器 240–430 = 60+40+60+25+25+30 与 100+80+100+45+45+60，与 §6 逐片一致；库 60–120 = 20+20+20 与 40+40+40，不占编译器预算；S4a 的夹具 80–130 归入夹具预算；**S4b 正式 `Str` 库在 ct-pkg `std/string`，本相计 0 行**。相对第四轮 250–420/220–380，本相把 `Str` 的 buffer 实现整体移出仓库，只保留协议夹具，因此库预算从 240–420 降到 60–120。

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R36-1 | 释放顺序分叉 | D36-2 统一声明顺序；E36-2 锁顺序 |
| R36-2 | 显式 impl 与自动 glue 双重释放 | D36-3 不生成 glue + §3.1.1 ③ 按实例登记；E36-1/E36-2 产物断言 |
| R36-3 | `Str` 内嵌 `\0` 与 `str_c_str` 截断 | E36-6 + 文档警告 |
| R36-4 | `own Str` 值移动被误当作既有能力 | D36-8 + §2.2 探针；T36-5 |
| R36-5 | 跨单元 `Str` ABI 漂移 | 只保证同一编译器版本；E36-10 |
| R36-6 | 泄漏/双重释放不可门禁 | B36-6；夹具 `Probe` 计数 + 产物 grep；ASAN 人工证据 |
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
| T36-8 | `Option`/`Result` 的"empty 不调用 drop"条件 Drop | 有显式条件析构设计（本相 glue 无条件 drop 零状态 payload） |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S2 的实现与诊断。
- `test/modules/p36_str_shim/**`（伪 `CStr` 适配层与本地 `Str` 夹具）；`lib/std/README.md` 增加“`Str` 在 ct-pkg `std/string`，不在内建层”的说明。
- `test/ast/225–232_*`（228 归 Phase 34 的 `228_pub_generic_fn`，本相跳过）、`test/ast/errors/*`、`test/modules/p36_str_shim`。
- `examples/40_str_ownership/` + golden（用本地最小 `Str` 演示协议，不导入 ct-pkg）。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`、`roadmap.md`。

## 13 收口与纪律

- **T-7 先红后绿**：S0 在实现提交的父提交上复跑探针并提交 `test(ownership): P36 红`（含 `baseline: <sha>` 与原始输出）。
- 每片 ≤3 文件、净增 ≤150 行；仓库任何时刻可构建。
- 不改判据宽度、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；不碰其他会话文件。
