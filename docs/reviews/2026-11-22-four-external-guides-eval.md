# 对外部四份 Ct 文档的评估（速览 / 内存 / 性能 / 惯用卡）

> 评估对象（均为外部修订稿，未入库）：
> ①《Ct 语言速览（v1.0 预备版 · 修订终版）》；②《给 C 程序员的 Ct 内存指引（修订终版）》；
> ③《C 程序员的 Ct 性能调优指南（修订终版）》；④《Ct 惯用优先级卡（归档终版）》。
> 核对基线：本仓 `main`（v0.88.3），方法为逐条对照 spec §1.2 / §4.3 / §4.51 / §4.69–§4.73，
> 并用 `ct v0.88.3` 跑最小探针；不改仓库代码。

## 1. 结论表

| 文档 | 结论 | 主要问题 |
| --- | --- | --- |
| ① 速览 | **不能按现状发布** | 4 个示例跑不通（ADT 语法/递归负载/box API/`#include`），3 处布局或语义写错，若干口径已过期 |
| ② 内存指引 | **修 4 处后可用** | String 拷贝写成“深拷贝”、局部视图写成“编译错”、`Str` 可存储性前后矛盾、`trim` 长度算错 |
| ③ 性能指南 | **修 4 处后可用** | `std::Arena` 命名空间错、`v.at()` 缺下标、`slice` 参数语义错、`bench/` 不存在 |
| ④ 惯用卡 | **已归档，不应再引用** | “C 超集”、`CStrOps` 命名、`decode/encode` 三项过期；仓库 [idioms.md](../idioms.md) 才是权威 |

四份的共同优点：判据式写法（“数据过了这行还要活吗”）、三层内存地图、调优阶梯、惯用优先级表，
方向和仓库既有文档一致，适合做**对外教程的骨架**；问题集中在“示例没跑过”和“版本口径没跟上”。

## 2. 速览：硬错误（示例跑不通）

| # | 原文 | 实测/规范 | 修法 |
| --- | --- | --- | --- |
| 1 | `enum Expr { Int(int val); … }` | ADT 变体用**逗号**分隔；分号报 `unexpected token` | 全文 ADT 示例改逗号 |
| 2 | `match` 分支写 `Int(v)` / `Circle(r)` | 规范要求限定名 `Shape.Circle(r)`（D84-3） | 分支与构造统一 `Type.Variant` |
| 3 | `Add(Expr lhs, Expr rhs)` 递归值负载 | `.ct` 能过，但生成的 C 是 `struct Expr { union { struct Expr lhs; … } }`，`cc` 报 `field has incomplete type` | 递归节点改成指针/arena 索引；否则示例只能是非递归 `Shape` |
| 4 | `String` 布局写成 `{ ct_str_hdr *h; T *ptr; }` | `String` 是 `char *ptr + int len`（16 字节），8 字节头在 `ptr - 8`；双指针 `{hdr*,T*}` 是 `box` 布局 | 按 spec §4.70 改 |
| 5 | `r.get().id = 8`（box） | `box` 没有 `get`；只有 `at()`（返回 `T *`）与 `b.f` 自动解引用。`r.at().id` 还会报 `use '->id'` | 写 `r.at()->id` 或 `r.id` |
| 6 | “下标 `v[i]` 只读，写用 `set`” | 内置容器下标可写：`v[i] = x` 发射 `Vec_*_set`（探针编译通过） | 改为“读写都可，越界/缺键得零值” |
| 7 | “trait 可带默认方法；impl 必须实现全部方法” | 默认方法可省略，只有抽象方法必须实现（spec §4.39） | 改为“抽象方法必须实现” |
| 8 | “impl 与 vtable 永远 static，本单元私有” | `pub` trait + `pub` struct 时 vtable 外部链接（spec §4.3 / §4.11） | 加例外说明 |
| 9 | §19 `#include <stdio.h>` | strict C 边界默认禁止 `.ct` 直接 `#include`；`printf` 由内建 I/O 例外自动补头 | 删 `#include` |
| 10 | §19 期望 `total 87` | 修正语法后可运行，输出是 `total 24`（`3*2*2 + 3*4`） | 改期望值 |
| 11 | `"42".to_int()` 无 import | 方法来自 std 包映射；需 `import std::str::CharStr`（0.19 及以前叫 `String`） | 补 import 或标“需 std 包” |
| 12 | `decode<T>` / `encode<T>` 列在速查表 | 尚未实现，属 [LANG-26](../../issues/lang/lang-26-binding-site-conversion.md) / [PKG-24](../../issues/packages/pkg-24-json-node-arena.md) 的未来能力 | 标“提案/未实现” |

**口径漂移（不阻塞，但要改）**：
“单趟编译”不准确——ct-ast 是全 AST、先收集后发射；“v1.0 计划 CLI 默认 `warn`”已改为
**下一 v0.x 默认 `warn`**（[SH-115](../../issues/selfhost/sh115-b-plus-strengthening.md)）；
“SH-110 修复中”卡面是 `deferred`；“官方包 hal / hal-posix / std”只有 `ct/std` 在官方 pin 表。

## 3. 内存指引：4 处事实错误

| # | 原文 | 实际 | 修法 |
| --- | --- | --- | --- |
| 1 | “String 实参拷贝即**深拷贝**” | 按值拷贝是 **retain**（共享堆、`refs+1`）；独立副本用 `.to_string()` | 删“深拷贝”，改成“拷贝=retain” |
| 2 | “返回局部视图 = **编译错**” | 默认是 **warning**（SH-106），`ct check` 的 strict 规则才升 error | 改为“warning（strict 可升 error）” |
| 3 | “`Str` / `T[]` … **不可存储**（字段/Map 键硬错）” | 对 `Str` 过宽：字段/Map 键硬错，但 `Vec<Str>` / `Option<Str>` / ADT 负载 / 全局**可编译**（存视图）。同文 §3.2 已写对，§5 表格自相矛盾 | 按 §3.2 统一；`T[]` 仍按白名单（字段/全局等硬错） |
| 4 | `return s.slice(1, s.len - 1)` 称“去掉首尾” | `slice(start,n)` 的第二个参数是**长度**不是终点；该写法只去掉首字符 | 改 `s.slice(1, s.len - 2)`，或说明用两个切片拼接 |

另有一处表述风险：结尾“默认值就是安全的”“基础档不懂指针也安全”是**过度承诺**。同文 §6 已列
引用环、跨线程 refcount、跨过程视图逃逸；建议改成“默认不暴露 malloc/free，但仍不是内存安全语言”。

**值得保留**：三层地图（日常/逃生/圈禁）、String/Str 判据、三条生命周期纪律、迁移三场景，
都与 spec §4.69–§4.71 的口径一致。

## 4. 性能指南：4 处需修

| # | 原文 | 实际 | 修法 |
| --- | --- | --- | --- |
| 1 | `std::Arena ar = std::Arena::init(...)` | [std-catalog](../std-catalog.md) 的规范名是 `std::arena::Arena`；`init/alloc/free_all` 未在仓内文档出现 | 改成 `std::arena::Arena`，API 以 std 包为准；未核实就标“示例 API，以包为准” |
| 2 | `v.at()` 拿借用视图 | `Vec.at(int) -> T *`，必须带下标；`get(int) -> T` 才是取值 | `v.at(i)` |
| 3 | `s.slice(i,j)` 表示子段 | `Str.slice(start,n)` 的第二参是长度；按“终点”理解会多切 | 写 `s.slice(i, j - i)` 或说明 `n` 是长度 |
| 4 | “性能进独立 `bench/` 目录手动跑” | 仓内没有 `bench/` | 改成“未来 bench 目录”或不写具体路径 |
| 5 | “foreach 发射质量与手写等同”“match 判别更高效” | 仓库没有基准数字 | 标为待测，不作效率承诺；与 GrokBot 报告“无基准”一致 |

`String.concat` 也未在 spec §4.70 的 UTF-8 String 方法表出现（`concat` 在 UTF-16 与 std::str
映射里）；建议先确认包 API 再写。

**值得保留**：先测量后降级、生成 C 可 diff 计 retain/malloc 次数、每阶一个 commit、ASan 常跑，
这些方法论与仓库“生成可读 C”的定位吻合。

## 5. 惯用卡：已归档，不要再用

卡片首行已声明“内容已入库 `docs/idioms.md`，本文件不再维护”。对照后仍有 3 处过期断言：

| 原文 | 问题 |
| --- | --- |
| “Ct 是 **C 的超集** + 更好的默认” | v1.0 起正式撤回 C 超集承诺（spec §1.2、README 同步）；仓库 [idioms.md](../idioms.md) 已改 |
| “`char *` 方法走 `std::str::CStrOps`（旧名 `std::str::String`）” | 规范名是 `std::str::CharStr`；`CStrOps` 是 0.19.0 的旧映射 trait，不是新名 |
| `decode<T>` / `encode<T>` 列为惯用写法 | 尚未实现，属 LANG-26 / PKG-24 提案 |
| “基础档（不懂指针也安全）” | 过度承诺；引用环、跨线程 refcount、跨过程逃逸仍在 |

处理：**保持归档状态，不合并、不引用**；对外只指向 [docs/idioms.md](../idioms.md)。

## 6. 命名 “Ct”

四份文档统一改用“Ct”作散文名，但仓库没有这条决议：spec 标题、README、glossary 都用 **CT**，
且 glossary 明确禁止把语言叫 `ct-lang`/`ctlang`。在所有者拍板前，建议继续用 **CT**；
若确实要改名，需要一次全仓术语变更（glossary、README、spec 页首、check-docs 的术语断言）。

## 7. 处置建议

1. **速览不直接入库**：先按 §2 的 12 条修完，并用 `ct v0.88.3` 跑通每个示例；ADT 递归例子
   要么改成非递归 `Shape`（已验证输出 `24`），要么改成指针/arena 表示。
2. **内存指引、性能指南**：各修 4–5 处后可作为 `docs/guide-for-c-programmers.md` 的补充篇；
   性能指南当前没有仓内对应文档，若要入库需要 REQ 卡与 `docs/README` 索引。
3. **惯用卡**：归档即可；不要把它当作 `docs/idioms.md` 的替代品。
4. **不建议现在开新 issue**：四份都是外部文稿，问题集中在示例未跑与版本漂移；
   等所有者决定是否入库，再按 DOC 卡登记验收（每条示例必须可复跑）。
