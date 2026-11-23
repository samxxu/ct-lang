# 提案 v2：指针退场（预 v1.0 语言方向）


> **状态：当前版**（2026-11-20；取代 [archive/pointer-free-v1.md](archive/pointer-free-v1.md)）。
> **裁定链**：[D-011](../decisions/D-011.md) 为当前 ADR；[battle pointer-free-1](../../battle/pointer-free-1/verdict.md)
> 为历史证据，卡头已标 `superseded-by: D-011`。
> **2026-11-20 追加裁定**：字符串编码、字面量与下标规则见[附录 C](#附录-c--2026-11-20-追加裁定字符串与下标)；
> 与附录 B 冲突时以附录 C 为准。
> **不是施工卡**：J-6 证据门槛未过前，不开任何 phase 卡；本文件只冻结方向、契约与证据任务。

## 0. 一句话

把日常指针的五类用途收进**四个机制家族**，指针保留为逃生通道：

| 家族 | 成员 | 作用 |
| --- | --- | --- |
| 借用视图 | 切片 `T[]`、`Str` | 只“看”不拥有，四位置白名单 |
| 引用计数句柄 | `Vec<T>`、`Box<T>`、`String` | 拥有 + retain/release + 借用视图 |
| 参数语法糖 | `ref` / `out` | 源码无 `&`/`*`，发射指针 |
| 签名语法糖 | 函子 `(A,B) => R` | 延后 Wave 2，不占本轮机制 |

`new` 是 `Box` 的语法糖，与 `Box` 同进退，不单列机制；`T a[]` 废弃是迁移规则，不是新机制。

## 1. 目标与非目标

**目标**

- 日常 `.ct` 代码不写指针、`own`、`defer`、`errdefer`；
- 五类场景各有值类型/句柄入口：单对象、多返回、数组传递、字符串、回调；
- 借用视图的悬垂路径可数、可文档化、直接形态可机检；
- 指针、`own`、`defer`、`errdefer` 永远合法，不因本提案被禁止。

**非目标**

- 借用检查器、别名分析、并发证明、生命周期标注；
- 环检测 / tracing GC / 弱引用；
- 禁止或硬限制指针；
- 构造函数语法、GC、惰性迭代器；
- `new` 的数组/容器形态。

## 2. 机制

### 2.1 借用视图（切片 + `Str`）

表示：`T[] = {T *ptr; int len;}`；`Str = {char *ptr; int len;}`（`Str` 是 `char[]` 的 nominal 特化）。
空视图 `{0,0}`，不引入 null；`len==0` 即空。

**四位置白名单（承重墙）**：

> 借用类型只能出现在：函数参数、局部变量、表达式临时量、返回值。
> 作为字段/全局/静态/接口值/`Box`/`Option`/`Result`/容器元素/数组元素/泛型实参/闭包捕获，
> 一律类型错误（编译期硬错）。

**返回值契约**：谁返回借用视图，谁负责底层数据在调用方使用期间存活；与 `String.as_str()` 同水位。
编译器只对直接形态做 lint；经函数/方法/`out` 透传的路径由作者负责，明文写进契约。

### 2.2 引用计数句柄（`Vec` / `Box` / `String`）

统一头（数据区前，句柄 16 字节不变）：

```c
struct ct_handle_hdr { int refs; int aux; };   /* 8 字节；aux 类型专属 */
```

- 无 `drop_fn`：句柄是 nominal 类型，release 按静态类型分发；
- `header_size(T) = round_up(8, _Alignof(T))`；`String` 的 `char` 数据 8 字节，`Box<T>` 按 T 对齐；
- 空 `String` 用 immortal 静态空串：`refs = -1`，`release` 首行 `if (refs < 0) return;`；
- refcount 是普通 `int`，**非原子**；句柄非线程安全，跨线程共享由作者同步（见 §4）；
- `_Static_assert(sizeof(String_handle)==16)` 与数据区对齐断言进 golden 头。

复制/Drop：

| 位置 | 行为 |
| --- | --- |
| 按值传参 / 按值返回 | 调用侧 retain，作用域 exit release |
| struct 字段 | 随宿主 Drop glue：宿主 release 时字段 release |
| 容器元素（`Vec<String>`） | 内建层 glue：拷贝元素 retain，容器 release 遍历时元素 release |
| 局部句柄 `return` | move（不 retain，作用域不重复 release） |
| 非局部 owning `return` | 安全序列：retain → return → release；不引入新 move 语法 |
| 重新赋值 | 先 retain 右值 → release 旧值 → 写入（自赋值安全） |
| 自赋值 | `if (a.h != b.h)` guard 后走正常顺序 |

### 2.3 `ref` / `out`

上下文关键字，只在形参表生效；`int out;`、`time_t *ref;` 继续合法。

- `out`：callee 必须在每条退出路径赋值；调用方变量未初始化 → 硬错（复用 `--types` 定值检查）；
  赋值点先 release 旧值再写入；赋值后走错误出口，新值归调用方，不撤销赋值；
- `ref`：可读写；`s = other` 允许，走同一顺序；禁止显式 `release` / Drop（硬错/lint）；
- 参数边界零所有权语义：`ref/out` 本身不 retain/release，所有清理发生在赋值点或调用方句柄协议；
- 逃逸：类型系统无法阻止存入字段/全局/闭包；直接形态（参数值直接存字段/全局/直接 return）lint，
  透传形态由作者负责（契约级）。

### 2.4 `Box<T>` / `new`

- `Box<T>`：单元素句柄，与 `Vec`/`String` 共用头与静态 release；借用视图/失效检测复用；
- `new`：完全关键字；`new T { ... }` 只接受**具名 struct**，花括号语法与 `T x = {...};` 共享；
- `new String` 不允许（字面量 + `to_string()` 覆盖）；`new` 不接受数组/容器/内建句柄；
- `T` 若含借用字段（切片/`Str`），在 struct 声明层已硬错，`new T` 不重复检查；
- 顺序：`Box/new` 放最后，等 `String` 验证句柄协议后再做。

### 2.5 函子

`(A,B) => R` 延后到 Wave 2；PH-75 已让闭包进方法实参，签名糖不阻塞其余家族。

## 3. `String` / `Str` 定稿

### 3.1 类型与布局

- `String`：owning，16 字节句柄 `{char *data; int len;}`，refcount 在数据前头里；
- `Str`：借用 `{char *ptr; int len;}`，无 Drop；字面量默认类型；
- `String` 内建化，迁出 std；`std::str` 保留为 `char *` 逃生层的方法映射。

### 3.2 转换与 C 边界

- `Str → String`：显式 `to_string()`（深拷贝）；
- `String → Str`：显式 `as_str()`（借用，逃逸责任归调用者）；
- `.data` 只读，**对 `String` 与 `Str` 都不保证 NUL 结尾**（内部补 NUL 不算契约）；
- `cstr()` 是 C 边界唯一出口（复制 + 补 NUL）；`printf` 场景一律 `cstr()`；
- `char *` ↔ `String`/`Str` 全部显式；`.m.ct`、shim、`.h.ct`、`extern` 继续用 `char *`。

### 3.3 `str_slice` 与旧 API

- 新 `str_slice` 返回借用 `Str` 视图；
- 深拷贝语义保留为显式 `str_dup()`；
- 旧 owning `Str` 在兼容窗口内仅以限定名 `std::str::Str` 存在；裸名 `Str` 从第一天起就是新借用类型；
- 窗口结束删除旧类型；`import std::str::Str` 的消费者窗口期内改限定名引用，零语义变化。

### 3.4 线程模型

refcount 非原子；`String`/`Box`/`Vec` 句柄非线程安全。跨线程共享必须经用户同步；
类型层不禁止，lint 只对直接存入共享全局的形态告警。CT 提供 `atomic T`，不提供 Arc 级句柄。

## 4. 兼容承诺

CT **不再是 C 超集**，重述为：

> CT 兼容 C 的表达式、语句、类型核心与 C 边界形态（shim / `.m.ct` / `extern` / raw 块 / C 头文件）；
> 在 CT 单元内，`new` 是关键字、`T a[]` 废弃、字面量默认 `Str`。

豁免区：C 头文件、`.m.ct`、shim、raw 块、`extern` 全部按 C 原样。
迁移窗口：v0.x 内 deprecation + 自动修复，v1.0 硬切。README/spec/roadmap 三处同步改，
作为 S5b 的 release-blocking 文档项，缺一处不合入。

## 5. 借用视图契约（定稿）

> 1. 视图不拥有底层存储；底层数据生命周期由创建者可证明的作用域决定。
> 2. 借用类型只能出现在四个位置：参数、局部变量、表达式临时量、返回值；作为复合类型组成部分
>    一律类型错误。
> 3. 谁返回借用视图，谁负责底层数据在调用方使用期间存活。
> 4. 编译器不做跨过程分析；只对直接逃逸形态做 lint（`return 局部数组切片`、
>    `return 局部 String.as_str()`、`out` 直接写局部切片）。透传形态由作者负责。
> 5. `ref/out` 是参数别名，不可类型级禁止存储；直接形态 lint，透传形态由作者负责。
> 6. 与 C# Span 的差异：C# 有 ref-safety 逃逸分析；CT 只做位置限制 + 直接 lint，
>    透传残留是明确接受的契约水位。

## 6. 风险与作者责任

| 风险 | 处理 |
| --- | --- |
| 引用环泄漏 | 作者责任；文档写死「引用环 = 泄漏」；`--debug-leaks` 只报未配对 alloc/release 计数，不做环检测 |
| 借用视图透传悬垂 | 契约 + 直接 lint；ASan/UBSan CI 兜底 |
| `ref/out` 被存储 | 契约 + 直接 lint；类型系统不阻止 |
| 跨线程共享句柄 | 非原子 refcount；作者同步；lint 只抓直接共享全局 |
| 切片越界 | `s[i]` 是带检查 place，越界 trap；`get` 软访问；构造切片边界硬错 |
| C 兼容下降 | `new` 关键字、`T a[]` 废弃、字面量默认 `Str`；C 边界豁免区按 C 原样 |

## 7. 施工顺序与版本

| phase | 内容 | 版本 |
| --- | --- | --- |
| PH-78 | S2 `ref/out` | v0.78.0（拟） |
| PH-79 | S3 切片 | v0.79.0（拟） |
| PH-80 | S5 `String/Str`（S5a/S5b） | v0.80.0（拟） |
| PH-81 | S1 `Box/new` | v0.81.0（拟） |
| v1.0 | AST-only 收口（顺延） | v1.0.0 |
| v1.1 | 语法现代化 + A strict；Wave 2 函子 | v1.1.0 |

- 顺序：**S2 `ref/out` ∥ S3 切片 → S5 `String/Str` → S1 `Box/new`**；S4 函子延后 Wave 2；
- 版本：PH-78 起严格 `phase = MINOR`，无偏移表；
- v1.0 顺延发布，范围仍 AST-only；v1.1 继续行为保持 + Wave 2；
- S5 分 S5a（内建层 + 旧 `Str` 并存）/ S5b（删旧 `Str` + 外部迁移 + 文档三处同步）。
- 详细入口/退出/回滚见 [pointer-free-phase-plan](../planning/pointer-free-phase-plan.md)。

## 8. 施工前证据门槛

J-6 最低原型集：**S2 全量 + S3 全量 + S5 最小垂直切片**（String 句柄 + 字面量 `Str`，不做
`cstr`/迁移/旧 `Str`）。通过后开第一张正式卡（S2）；S5 全量原型在 S5 施工卡开工前补齐。
详见附录 A。

## 附录 A · 证据任务清单

> 目的：把 J-6 从 B 升 A。所有任务默认 `todo`；每条证据按 E1–E5 提交。

### A.0 证据格式

| 项 | 要求 |
| --- | --- |
| E1 | 命令 + 原始输出 + 退出码 + 基线 sha/二进制版本/环境 |
| E2 | `file:line` 锚点；至少一条对己方不利 |
| E3 | 可证伪预测：什么结果出现则任务失败 |
| E4 | 代价量化：文件/行/夹具/ABI 字节 |
| E5 | 失败时的替代解释或收缩方案 |

### A.1 P-1 语料测量（J-6a）

| ID | 任务 | 产出/判据 |
| --- | --- | --- |
| P-1.1 | 固定基线 | 含字面量 649、`char *` 494、`T a[] =` 36、数组形参 2；注明扫描范围 |
| P-1.2 | 按特性分类 | 每文件标：字面量/`char *` 形参/`T a[]` 形参/`T a[] =`/`ref/out` 标识符/`new` 标识符 |
| P-1.3 | 自动化率 | lint dry-run 的「可自动/需人工/语义需确认」三档百分比 |
| P-1.4 | 快照回放 | 基线 tarball + 复跑命令；计数一致 |

### A.2 P-2 语法/解析（J-6b）

| ID | 任务 | 判据 |
| --- | --- | --- |
| P-2.1 | `new` 完全关键字 | 正例 `new Record {...}`；负例 `int new;`、`r.new` |
| P-2.2 | `ref/out` 上下文关键字 | 形参表内标注；形参表外仍是标识符 |
| P-2.3 | `T[]` 唯一拼写 | `T[] a`、`T a[N]`；`T a[]` 告警→v1 硬错；`T a[] = {...}` 迁移 |
| P-2.4 | 花括号共享解析 | `new T {...}` 与 `T x = {...};` 位置式/指定式/嵌套同路径 |
| P-2.5 | 旧语料 parse | 全量 parse 通过；golden 变化逐条 |

### A.3 P-3 String/Str ABI（J-6c）

| ID | 任务 | 判据 |
| --- | --- | --- |
| P-3.1 | 16 字节句柄 + 8 字节头 | `_Static_assert`；`header_size(T)` 对齐 |
| P-3.2 | 复制/Drop 协议 | 参数/返回/字段/`Vec<String>`/`Box<String>` refcount 轨迹；ASan |
| P-3.3 | 字面量视图 | 字面量 `Str` 无 Drop；`String` 有 Drop；immortal 空串 `refs=-1` |
| P-3.4 | `.data`/`cstr()` | `.data` 只读、不保证 NUL；子视图 `cstr()`；`printf` 负例 |
| P-3.5 | C 边界 | `.m.ct`/shim/`.h.ct` 全部 `char *`；无隐式转换 |
| P-3.6 | 跨仓 dry-run | `std::str::Str` 限定名并存；消费者清单；std 新版本 |

### A.4 P-4 借用位置矩阵（J-6d）

| ID | 任务 | 判据 |
| --- | --- | --- |
| P-4.1 | 存储位置硬错 | 字段/全局/接口/Box/Option/Result/容器/数组元素/泛型实参/闭包捕获 |
| P-4.2 | 复合类型递归 | `Vec<int[]>`、`Map<Str,int>`、`struct { Str s; }` 硬错 |
| P-4.3 | 返回值契约 | 直接 `return 局部切片/as_str()` 可 lint；参数/字面量视图正例 |
| P-4.4 | 诊断质量 | 错误指向具体字段/泛型实参/闭包捕获 |
| P-4.5 | 残留风险 | 透传路径文档化 |

### A.5 P-5 ref/out 所有权（J-6e）

| ID | 任务 | 判据 |
| --- | --- | --- |
| P-5.1 | `out` 未初始化 | 硬错或零初始化；无 UB |
| P-5.2 | 旧值释放/别名 | retain 右值 → release 旧值 → 写入；无 UAF |
| P-5.3 | `ref` 赋值 vs 显式 release | 赋值允许；显式 release 硬错 |
| P-5.4 | `out` 错误路径 | 赋值即生效；PH-70 保证至少一次 |
| P-5.5 | `out/ref` 借用类型 | `out Str`/`ref int[]` 白名单 + 底层契约 |
| P-5.6 | 泄漏/双释放 | ASan + `__ct_allocs/__ct_frees` |

### A.6 P-6 跨仓迁移（J-6f）

| ID | 任务 | 判据 |
| --- | --- | --- |
| P-6.1 | 消费者清单 | `import std::str::Str` 全部有迁移动作 |
| P-6.2 | 包版本/索引 | std 新 MINOR；索引行；旧锁不破坏 |
| P-6.3 | 迁移 dry-run | 典型工程 `Str`→`String` 可编译、行为等价 |
| P-6.4 | 发布前检查 | README/spec/roadmap 三处同步（S5b blocking） |

### A.7 P-7 原型门槛

| ID | 原型 | 判据 |
| --- | --- | --- |
| P-7.1a | S2 自由函数全量 | A.5 六项；独立回滚 |
| P-7.1b | S2 方法/trait 原型 | 方法/默认体/impl 签名同一规则 |
| P-7.2 | S3 切片全量 | A.4；`get(i)`；构造边界硬错；返回 lint |
| P-7.3 | S5 最小垂直切片 | String 句柄 + 字面量 `Str`；A.3.1–A.3.3 |
| P-7.4 | S5 全量（施工前） | A.3 全绿；跨仓 dry-run |
| P-7.5 | S1 `Box/new`（最后） | 句柄协议复用；`new` 仅具名 struct |

### A.8 升 A 条件

J-6 → A：P-1…P-6 证据包齐全；P-7.1a/P-7.1b/P-7.2/P-7.3 原型可编译可运行并通过对应负例；
任一项失败则 J-6 维持 B，不以设计推理替代实测。

## 附录 B · 30Q 裁定汇总（2026-11-20）

| Q | 结论 |
| --- | --- |
| Q1 | A1；v0.x phase=MINOR，PH-78 → v0.78.0，无偏移表；v1.0 顺延、范围不变 |
| Q2 | `Box`/`new` 保留但移末位；不砍，砍则 `new` 同退 |
| Q3 | 顺序 S2 ∥ S3 → S5 → S1；S2 最小首切片；S5 不能单独回滚，分 S5a/S5b |
| Q4 | 统一头 `{int refs; int aux;}` 8 字节；`header_size(T)=round_up(8,_Alignof(T))`；immortal 空串 `refs=-1` |
| Q5 | 局部句柄 return = move；非局部 owning return = retain→return→release；重新赋值先 retain 右值再 release 旧值 |
| Q6/Q27 | refcount 普通 int，非原子；句柄非线程安全；作者同步；不做 Arc |
| Q7 | `str_slice` 返回借用 `Str`；深拷贝改名 `str_dup()` |
| Q8 | `.data` 只读且不保证 NUL；`cstr()` 是 C 边界唯一出口；`as_str()` 整串/子视图规则相同 |
| Q9 | 裸名 `Str` 从第一天是借用；旧 owning 仅 `std::str::Str` 限定名；窗口结束删除 |
| Q10 | 取消推断长度；`T a[] = {...}` → `T a[N]`；`T[]` 不允许初始化器；柔性数组改显式指针 + 长度 |
| Q11 | `{ptr,len}`；空 `{0,0}`；构造越界硬错；`a[1..]` 半开；不提供 `s[i]`，元素访问走 `s.get(i)` |
| Q12 | `Str` 是 `char` 切片的 nominal 特化；`char[]/char[N] → Str` 显式 `as_str()`；`Vec<Str>` 禁、`Vec<String>` 允许 |
| Q13 | `out` 未初始化硬错；赋值顺序 retain→release→写；`ref` 赋值允许；`out` 错误路径新值归调用方 |
| Q14/Q18 | `ref/out` 契约级；直接形态 lint；透传由作者负责 |
| Q15 | 一套头 + 静态分发释放；去掉 `drop_fn` |
| Q16 | `new` 只接受具名 struct；`new String`/数组/容器/内建句柄硬错 |
| Q17 | 借用视图契约见 §5 |
| Q19 | lint 边界可接受；ASan/UBSan + `--debug-leaks` 兜底 |
| Q20 | J-6 原型 = S2 全量 + S3 全量 + S5 最小垂直切片；S1 可缺席 |
| Q21 | 成本表：编译器/std/测试/迁移/性能/工时六项；迁移数 649/494/36/2 |
| Q22 | 依赖图无环；S5a/S5b 分期；外部迁移为 S5b release-blocking |
| Q23 | ADR 为当前裁定；battle 历史保留；卡头 `superseded-by`；结构校验双向一致 |
| Q24 | 新正文 `docs/proposals/pointer-free-v2.md`；旧文 `docs/proposals/archive/pointer-free-v1.md` |
| Q25 | J-6 三原型通过后开第一张卡（S2）；J-7 成本表并行 |
| Q26 | CT 不再是 C 超集；C 边界豁免；README/spec/roadmap 三处同步为 S5b blocking |
| Q28 | `out/ref` 与错误传播/Drop 按 Q13 规则；`defer/errdefer` 按普通变量可见 |
| Q29 | 借用类型只活在四位置；owning 类型随意；组合规则见 §2.1 |
| Q30 | 不做第七项机制；残留风险统一进「作者责任」契约章 |

## 附录 C · 2026-11-20 追加裁定（字符串与下标）

> 本附录**替代附录 B 中 Q4/Q5/Q8/Q9/Q11/Q12 的冲突表述**；附录 B 保留为历史。
> 核心原则：C 数组归 C；`var[i]` 只讨论容器/视图；`String` 不可变（JS 值语义）；
> UTF-8 与 UTF-16 双类型，转换走显式工厂。

### C.1 字面量与自动构建

```ct
String s = "string";                 /* OK：UTF-8 字面量 → String；L1 immortal 静态句柄 */
Str    v = "str";                    /* OK：UTF-8 字面量 → Str 视图 */
U16String u = U16String.from_utf8("str"); /* OK：UTF-16 只走工厂 */
/* U16String x = "str"; */           /* error：不隐式转 UTF-16 */

struct Record { String tag; }
Box<Record> r = new Record { 7, "x" };  /* OK："x" 按字段类型构造成 String */
struct Bad { Str tag; }                  /* error：借用字段禁止 */
```

- `String` 字面量用 **L1 immortal**：`refs = -1`，指向只读区，Drop 不释放；
- `Str` 字面量是借用视图，无 Drop；
- `char *` 目标只在 C 边界/逃生层允许；
- 无期望类型时默认 `Str`；函数重载 `f(String)` / `f(Str)` 遇字面量不得静默择一，需显式转换。

### C.2 数组与切片下标

```ct
int a[] = {1, 2, 3};       /* OK：推断长度数组（C 存储） */
int[] s = a;               /* OK：切片视图 */

int x = s[1];              /* 带边界检查的 place：读 */
s[1] = 9;                  /* 可写切片：写回底层 */
int y = s[9];              /* 越界 → trap/abort */

int *p = s.get(9);         /* 软访问：越界 → 0，不 trap */
```

- C 数组 `T[N]` / `T a[] = {...}`：C 下标，不检查；编译器可探知越界时报警；
- `T[]`：带边界检查的 place；`s[i]` 读/写/借用都作用于底层元素；
- `T[]` 可写；`const T[]` 只读；`String`/`U16String` 永远不可写；
- `T a[]` 作为无初始化器声明或形参：v0.x 告警、v1 硬错；迁移到 `T[]`；
- `s[0] = x` 对 owning 元素按赋值协议 release 旧值、retain 新值。

### C.3 编码与 API

| 能力 | `String` / `Str`（UTF-8） | `U16String` / `U16Str`（UTF-16） |
| --- | --- | --- |
| 长度 | `len()` 字节；`char_len()` 码点 | `len()` code unit（JS `length`） |
| 单元素读 | `s[i]` → 单码点 `Str` 视图，只读 | `s[i]` → 单 code unit `U16Str` 视图，只读 |
| 字节/code unit | `byte_at(i)`、`byte_slice`、`byte_index_of` | `char_code_at(i)` |
| 码点 | `codepoint_at(i)`、`char_at(i)` | `code_point_at(i)`、`char_at(i)` |
| 查找/切片 | `index_of`、`last_index_of`、`includes`、`starts_with`、`ends_with`、`slice`、`substring` | 同名；code unit 索引 |
| 内容变化 | `concat`、`replace`、`replace_all`、`to_upper_case`、`to_lower_case`、`repeat`、`pad_start`、`pad_end` 返回新 `String` | 同名，返回新 `U16String` |
| 分割 | `split` → `Vec<String>`；零拷贝用 `for_each_split` 回调 | `split` → `Vec<U16String>` |

- **UTF-8 用户接口用码点下标**；`byte_*` 单独提供字节级 O(1) API；
- `String` 不可变：没有 `s[i] = ...`；内容变化返回新值；
- `String.slice` 返回新 `String`；`Str.slice` 返回 `Str` 视图；
- `Vec<Str>` 仍禁止（借用元素不能进容器）；零拷贝分割走回调；
- `U16String` 首轮只做 JS **核心子集**（长度、char_at、char_code_at、code_point_at、at、
  index_of、last_index_of、includes、starts_with、ends_with、slice、substring、concat、split、
  replace、replace_all、to_upper_case、to_lower_case、trim、trim_start、trim_end、repeat、
  pad_start、pad_end）；
- `match` / `match_all` / `search` / `locale_compare` / `normalize` / `substr` 不进内建：
  需要时用 `ct-pkg` 包 + `.m.ct` / shim 静态映射（PCRE2 / ICU 等），不把正则/Unicode 表塞进编译器；
- 双编码共享一份 Unicode 表；跨编码只走显式工厂：
  `String.from_utf16`、`U16String.from_utf8`、`to_utf8`、`to_utf16`。

### C.4 `Box` 环与线程的报警边界

- 通用环检测在编译期不可判定；只能对直接形态 lint（明显自赋值/直接成环），不是保证；
- 线程安全需要 `Send`/`Sync` 或所有权类型系统，属第七项机制，已否决；
  因此编译期只能对「直接存入共享全局」等形态 lint，跨线程共享由作者同步；
- `--debug-leaks` 仍只报未配对 alloc/release 计数，不是环检测。

### C.5 追加证据任务

| ID | 任务 | 判据 |
| --- | --- | --- |
| P-3.7 | `U16String`/`U16Str` 类型与工厂 | `from_utf8`/`from_utf16`/`to_utf8`/`to_utf16`；`len` code unit；示例可编译 |
| P-3.8 | `U16String` 核心方法集 | snake_case 方法表；越界/负下标/`Option` 返回与 JS 语义对照 |
| P-4.6 | 切片 place 语义 | `s[i]` 读写、越界 trap、`get` 软访问；`const T[]` 写硬错 |
| P-5.7 | 字符串下标与不可变 | `String[i]` 单码点只读；`U16String[i]` 单 code unit 只读；写操作硬错 |
| P-8.1 | shim 扩展 | `match`/`normalize` 等经 `.m.ct`/shim 包接入，不改编译器 |

### C.6 与附录 B 的取代关系

| 附录 B 项 | 处理 |
| --- | --- |
| Q4 | 头布局/immortal 仍有效；字面量 L1 优先级补充 |
| Q5 | 局部 move / 非局部 retain→return→release 仍有效 |
| Q8 | `.data` 不保证 NUL、`cstr()` 规则仍有效；增加 `String[i]` 只读单码点 |
| Q9 | 旧 `Str` 限定名并存仍有效；新增 `U16String` 双类型 |
| Q11 | 切片不提供 `s[i]` **作废**；改为带检查的 place；数组仍 C 下标 |
| Q12 | `Str` 是 `char` 切片特化仍有效；新增 UTF-16 特化 |

