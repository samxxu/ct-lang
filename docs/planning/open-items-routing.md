# 未完成条目分流评估（2026-11-15，窄范围版）

| 项 | 值 |
| --- | --- |
| 状态 | **评估完成，待派工**；只落文档，不改实现 |
| 基线 | `v0.53.1`（`3337ac7a`）；写作时 HEAD `fe16bfe3`（LANG-5 方法形态已提交、未 bump） |
| 规则 | [D-005](../decisions/D-005.md)：bug 走 patch，新特性走 phase，拒绝只补文档，缺证据补夹具 |
| 本轮窄范围 | **只讨论内置 `Vec` / `Map` 上的 `[]` 与 `?.` 两类访问形态**；JSON 只是消费者，不作论证前提 |
| 工作树 | 其它会话正在改 `TypeCheck` / `Emitter` / `main` / `Driver` / `Pkg` / `test/pkg` / `test/ast/263`；本评估未触碰 |

## 0 顺序（钉死）

| 顺序 | 队列 | 说明 |
| --- | --- | --- |
| **1** | **PATCH 清零** | `0.53.2` 起连续发；先静默错值 / 静默坏 C，再诊断，再工具缺陷；不攒批 |
| **2** | **PH-53 可选链** | patch 清完后才进 S0；仓库卡面显示 `v0.53.0` 已完成，若重开则从 S0 重走（见 §5.1） |
| **3** | **PH-54 包机制** | 不插队；按 §4 判断为 PH-54 内工作分解 |
| **4** | **PH-55+ 新特性** | 只保留经批准的容器点访问 / 自定义 `get` 协议 / 限定名 / 诊断；排在包机制之后 |

---

## 1 主表：`[]` / `?.` 在 `Vec` / `Map` 上

判定口径：**已具备**（给出可用写法）/ **A bug**（当前做错或静默坏 C）/ **B 新特性**（全新语法糖）/ **C 拒绝**（语义不安全或无必要）。

### 1.1 `[]` 取值

| # | 写法（最小样例） | 实测 | 判定 | 依据 / PH-53 覆盖 | 落点 |
| --- | --- | --- | --- | --- | --- |
| 1 | `Vec<int> v = {10,20}; int x = v[0];` | rc=0，生成 `int x = Vec_int_get(&v, 0);` | **已具备** | `Vec::get` 返回值；越界返回零值（[Vec.h.ct:96-104](../../lib/std/Vec.h.ct#L96-L104)） | — |
| 2 | `Vec<int> v; if (v.has(0)) x = v[99];` | rc=0；`has(99)=0`，`v[99]` 仍返回零值 | **已具备（需 `has`/`at`）** | D50-1：`get` 零值语义不变；`has`/`at` 是并行入口（[std/README:54-59](../../lib/std/README.md#L54-L59)） | — |
| 3 | `Vec<struct P> v; v.push(p); int x = v[0].x;` | rc=0 | **已具备** | `Vec::get` 返回值类型 `T` | — |
| 4 | `Vec<Vec<int>> vv; vv.push(inner); int x = vv[0][1];` | rc=0 | **已具备** | `Vec` 值可继续 `[]` | — |
| 5 | `Map<char *, int> m; m.put("a",7); int *p = m["a"];` | rc=0，生成 `Map_char_p_int_get(&m,"a")`（`int *`） | **已具备** | `Map::get` 返回 `V *`；缺键 `0`（[Vec.h.ct:285](../../lib/std/Vec.h.ct#L285)） | — |
| 6 | `if (m.has("a")) x = *m["a"];` | rc=0；缺键 `m["zzz"] == 0` | **已具备（需 `has`/`*`）** | `Map::has` / `get` 契约 | — |
| 7 | `Map<char *, struct P> m; int x = m["a"].x;` | **rc=1**：`member reference type 'struct P *' is a pointer; did you mean to use '->'?`；ct 先 rc=0 | **A bug** | `[]` 结果是 `P *`，`.x` 未自动解引用，静默发射坏 C；与 LANG-5 字段形态同根 | **0.53.2**（并入 LANG-5） |
| 8 | `Map<char *, Map<char *, int>> m; int x = m["a"]["b"];` | **rc=1**：`array subscript is not an integer`；生成 `Map_get(&m,"a")["b"]`；ct 先 rc=0 | **A bug** | `m["a"]` 是 `Map *`，plain `[]` 未解引用；与 LANG-13 链式物化同族 | **0.53.4**（并入 LANG-13 链式修复） |
| 9 | `m["a"]["b"]["c"]`（三层嵌套 Map） | 同上，plain `[]` 链 rc=1 | **A bug** | 同 #8；`?.`/`?[` 安全形态已可用 | **0.53.4** |
| 10 | `m["a"]?["b"]` | rc=0，生成 `(t = get(&m,"a")) ? get(t,"b") : 0` | **由 PH-53 覆盖** | PH-53 `m?["k"]` + `m["k"]?.c`（[phase53:13-25](../design/phase53.md#L13-L25)） | — |
| 11 | `m["a"]?["b"]?["c"]` | rc=0 | **由 PH-53 覆盖** | 同上 | — |
| 12 | `Vec<T> *p; p?[i]` | PH-53 卡面明确收录 | **由 PH-53 覆盖** | `p?[i]`（[phase53:23](../design/phase53.md#L23)） | — |

> #1/#2 的「越界静默零值」不是 bug：D50-1 明确 `get` 零值语义不变，并要求用 `has`/`at` 区分。
> 若要求 `[]` 本身返回「缺席」而不是零值，那是**新特性**（checked index / Option），不是当前承诺；
> 本轮不排，记为旁注 B-1。

### 1.2 `?.` 取值

| # | 写法（最小样例） | 实测 | 判定 | 依据 / PH-53 覆盖 | 落点 |
| --- | --- | --- | --- | --- | --- |
| 13 | `Map<char *, struct V> m; int n = m["a"]?.n;` | rc=0；生成 `(t = get(&m,"a")) ? t->n : 0` | **由 PH-53 覆盖** | `m["k"]?.c`，`V` 为值类型（[phase53:22](../design/phase53.md#L22)） | — |
| 14 | `m["missing"]?.n` | rc=0；缺键 → `0` | **由 PH-53 覆盖** | 缺键 `get` 返回 `0`，三目短路 | — |
| 15 | `m["a"]["x"]?.y`（plain 内层 `[]`） | **rc=1**：`array subscript is not an integer` | **A bug / 用 `?[` 绕** | plain `[]` 链是 #8 的 bug；安全形态 `m["a"]?["x"]?.y` rc=0（#16） | 0.53.4 |
| 16 | `m["a"]?["x"]?.y` | rc=0 | **由 PH-53 覆盖** | `?[` + `?.` 组合（[phase53:23](../design/phase53.md#L23)） | — |
| 17 | `Map<char*, struct V>` 且 `V.obj` 是 `Map*`；`m["a"]?.obj?["x"]` | rc=0 | **由 PH-53 覆盖** | 字段指针 + `?[`；与 `m["a"]?.b?.c` 同族 | — |
| 18 | `Vec<struct P> v; v[0]?.x` | **rc=1**：`optional chain '?.' requires a pointer receiver; a struct value has no empty state` | **C 拒绝（正确）** | 结构固定、`Vec::get` 返回值，无缺席态 | — |
| 19 | `v.at(0)?.x` | rc=0 | **已具备** | `at` 返回 `T *`，有缺席态（[Vec.h.ct:121](../../lib/std/Vec.h.ct#L121)） | — |
| 20 | `v.has(0) ? v[0].x : -1` | rc=0 | **已具备** | 先判存在，再取值 | — |

### 1.3 `Map` 点访问（`doc.server.host`）

| # | 写法 | 语义 | 判定 |
| --- | --- | --- | --- |
| 21 | `Map<char *, V> m; m.server.host` | `.server` 若等价 `get("server")`，返回 `V *`；缺键为 `NULL`；再 `.host` 解引用空指针 → **未定义** | **C 拒绝（plain dot 不安全）** |
| 22 | `m.server?.host` | 可选点：缺键 → `0`；等价于 `m["server"]?.host` | **B 条件（仅容器语法糖）**，但**冗余**；本轮不排 |
| 23 | `struct Doc doc; doc.server.host` | 静态 struct 值，无缺席态；`doc.server` 是真实字段，字段不存在即 C 错误 | **C 拒绝（沿用 struct 值不做 `?.` 的裁定）** |

**结论：**

- Map 点访问在语义上**可以定义**，因为 Map 有缺键态；但 **plain `m.server.host` 必须拒绝**：
  缺键时 `m.server` 是空指针，再 `.host` 是空指针解引用，语言无法给出「报错 / 空 / 未定义」之外的
  安全默认值。唯一安全的点是 **`m.server?.host`**，而它已经等价于 `m["server"]?.host`（rc=0，PH-53 覆盖）。
- 因此 Map 点访问是**冗余语法糖**，不是容器基本可用性；判 **C（不排期）**。
  若主控坚持，最小形态是「只对 `Map` 的 `.name` 脱糖为 `get("name")`，且必须与 `?.` 连用」；
  这是 **PH-56 可选草案**，只开容器语法糖，**不与静态 struct 属性访问共用协议**（见 §3.2 代价）。
- 此前「struct 值类型不该有 `?.`」的裁定**不直接约束 Map**：Map 的缺席态在键查找，不在 struct 形状；
  但它**约束了 `Vec<struct P>`**：`v[0]?.x` 被正确拒绝，替代写法是 `v.at(0)?.x` 或 `v.has(0) ? v[0].x`。

---

## 2 旁注（降级，不占主表）

| 条目 | 现状 / 实测 | 判定 | 落点 |
| --- | --- | --- | --- |
| 同名重载 / 按键类型分派（REQ-JSACCESS-1） | **不是 Vec/Map 的问题**：`Vec` 只有 `get(int)`，`Map<K,V>` 只有 `get(K)`；两类容器各自按 K 分派，无同名冲突。`get(char*)` + `get(int)` 并存只发生在**用户自定义包装类型**上（实测 `conflicting types for 'J_get'`） | **B 新特性**（自定义容器协议）；对 Vec/Map 本身**已具备** | **PH-55 可选**，P3；不阻塞容器访问 |
| 自定义 `get` 类型不匹配静默空值（LANG-4） | 自定义类型上 `get(char*)` 收 `int` 实参，静默走缺键分支；Vec/Map 无此问题 | **A bug**（自定义协议，非 Vec/Map 基本可用性） | **0.53.3** |
| 运算符与格式化协议 | `Map<char*,int>` 的 `m["k"]` 是 `int *`；`*m["k"] + 1` 可用；`m["k"] + 1` 是指针算术；`printf("%s", m["k"])` 类型不符 | **C 拒绝**（不引入运算符重载；`[]` 已文档化为 `get`，需显式 `*`） | 不排期 |
| 字面量→`Str` | `Map<char *, V>` 直接 `m["host"]`；`Map<Str,V>` 需 `str_from("host")` | **已具备** / 隐式转换 **C 拒绝** | 不排期 |
| 容器迭代 | `foreach (Vec)` / `foreach (Map)` rc=0；`for (e in arr)` 是 D27-4 拒绝 | **已具备** / `for-in` **C 拒绝** | 不排期 |
| 静态 struct 属性访问 | `doc.server` 是字段访问；不存在字段由 `cc` 报错；无属性协议 | **C 拒绝**（无规范承诺） | 不排期 |
| 三级链 / 临时值接收者（自定义类型） | LANG-13 声称已修（夹具缺失）；LANG-5 方法形态已提交未 bump | **A + D** | 0.53.2 / 0.53.4 |
| `char *` → `Str` 诊断级别 | LANG-14 声称已修（夹具缺失） | **A + D** | 0.53.5 |
| `5.method()` | LANG-8 | **A bug** | 0.53.7 |
| MAX_CALLS 1024 | LANG-3 | **A bug** | 0.53.9 |
| struct 字段 ABI | LANG-9 | **A bug** | 0.53.10 |
| 机器可读诊断 / debug | LANG-10 + 无 issue 的 debug 便利性 | **B 新特性** | PH-58 |
| 限定名 / namespace 常量 | SH-18 + 条目 1c/2 | **B 新特性** | PH-57 |

---

## 3 新 phase 草案（只保留窄范围相关）

### 3.1 PH-55 · 自定义容器 `get` 协议（可选，P3）

| 项 | 草案 |
| --- | --- |
| 范围 | `REQ-JSACCESS-1` + `REQ-INDEX-1`：用户自定义包装类型上多 `get` 并存、按键类型分派、`v[k] = x` 写形态 |
| 为什么不是 patch | 新语义 + 符号表 + C 名 mangling + ABI；Vec/Map 本身不需要；只有自定义容器需要 |
| 判据草案 | E55-1 两版 `get` 并存，`j["k"]`/`j[0]` 各命中；E55-2 单版时另一形态硬错并列出候选（接 0.53.3）；E55-3 既有单 `get` ABI 不破；E55-4 trait 动态派发边界不变；E55-5 写形态是否实现二选一并写清 |
| 与静态 struct | **不共用**属性协议；只做 `get` 重载，不动字段访问 |
| 优先级 | P3；容器基本访问不依赖它 |

### 3.2 PH-56 · Map 点访问（条件草案，默认不做）

| 项 | 草案 |
| --- | --- |
| 范围 | 只对 `Map` 的 `.name` 脱糖为 `get("name")`，且**必须**与 `?.` 连用：`m.server?.host`；缺键 → `0` |
| 现状 | `m["server"]?.host` 已 rc=0（PH-53 覆盖）；点访问是冗余糖 |
| 为什么默认 C | plain `m.server.host` 无法安全定义（空指针解引用）；可选点没有新增能力 |
| 若做（仅容器） | 解析器/类型推断识别 Map 接收者；不改符号表 / ABI；S–M；不碰静态 struct 字段 |
| 若与静态 struct 共用 | 需要字段存在性 / 类型解析 + 与 C 字段访问冲突 + struct 无缺席态；M–L；**不推荐** |
| 判据草案 | E56-1 `m.server?.host` 返回预期值；E56-2 缺键 → `0`；E56-3 `m.server.host` 硬错；E56-4 静态 struct 字段零变化；E56-5 `m["server"]?.host` 零回归 |
| 关系 PH-53 | PH-53 已覆盖安全形态；PH-56 只在主控明确要语法糖时开，且排在 PH-53 后 |

### 3.3 PH-57 · 限定名与 namespace 常量（保留）

`SH-18` 类型位置 `A::B`；`LANG-15` 值位置 `Type::Member`（`FsErrCode::FS_ERR_OUT_OF_BOUNDS`）；
enum 类型作用域 `E::M`；namespace 内 `pub extern` 头声明 + `.ct` 定义。
判据：`FsErrCode::FS_ERR_NOT_FOUND` 可用、`ns::Type` 类型位置可用、`.h.ct` 声明 + `.ct` 定义可链接、
C 库 `extern` 零回归、诊断区分类型/值位置（不把 `Type::Member` 当命名空间变量）。依赖 LANG-11 patch。

### 3.4 PH-58 · 诊断与调试（保留）

`LANG-10` 剩余部分：**字段级 `line/col`**（7c，`Field` 加模型字段）+ debug 便利性
（`--keep-c` / `-g` 透传 / 源码行映射）。机器可读**警告**通道已实现，只补夹具；
**解析错误**的 JSON 走 patch 0.53.14，不占本 phase。
判据：`Field` 诊断能指到字段行列、JSON 覆盖字段级诊断、默认文本零变化、`--keep-c` 可定位、
`-g` 可用、行号指向 `.ct`、ABI 零变化。

---

## 4 包机制归属（PH-54）

| 项 | 判断 |
| --- | --- |
| 分类 | **phase**，不是 patch：`ns-root` 取代「包根 = 单元根」、发布方身份、共享 store、v2 lock，是工具契约变更 |
| 编号 | **PH-54**（已在实施 S0，不另起号） |
| 与 S0–S7 | **推荐 A：PH-54 一个 phase，S0–S7 作为 phase 内工作分解，只保留 `v0.54.0` 一个 MINOR**。符合 AGENTS V-1；现 roadmap 的 `v0.54–v0.60` 是混合写法，需在 PH-54 收口前改为「S 工作分解 + 单一版本位」 |
| 备选 B | 若每片独立发版，则 S0–S7 提升为 PH-54…PH-60；语言新特性顺延 PH-61+，且要重排 S4/S6 版本位 |
| PKG-3…8 | 全部随 PH-54 S1/S2/S4；PKG-5 列为 S1 首任务；PKG-7 是需求缺口（B），其余是 bug 但依赖新模型（D-005 §2.4 例外） |
| 顺序 | PH-53 之后；不插队 |

---

## 5 Patch 清单（窄范围相关优先）

### 5.0 2026-11-15 第二批：十项复核与归属

| # | 条目 | 实测（HEAD `v0.53.1` 重建） | 分类 | 落点 |
| --- | --- | --- | --- | --- |
| 1 | 带 namespace 的静态固有方法 | 跨单元 `Box.make(3)`、同单元无 `pub` 两探针均 rc=0；夹具 `261` 通过 | **已修**（LANG-2，v0.53.1） | 无；若仍红需附 `ct -v` 与原文 |
| 2 | `MAX_CALLS=1024` 整次构建累计 | 1030 个 `f();` → `calls.ct:1024:8: error: too many calls`；文案无上限/口径/建议 | **A**（LANG-3） | **0.53.11**；补诊断判据 D1–D4 |
| 3 | `.h.ct` 里 `errdefer` | 复现 rc=0；夹具 `260` 通过 | **已修**（LANG-1，v0.53.1） | 无；若仍红需附 `ct -v` |
| 4 | `ABI_HASH` 判不出签名漂移 | `int`→`long`，`.abi.h` 原型变、哈希仍 `0x6cdaf7f5` | **C 设计**（D39-12 名字级哈希） | 不排期；[SH-77](../../issues/selfhost/sh77-abi-hash-name-only.md) 记档 + 文档 |
| 5 | `--lib` 导出面只收自由函数 | `pub struct` + `impl` 的 `pub` 方法 → `no exported functions`；加自由函数后 rc=0 | **C 设计**（D39-2 / D42-10） | 不排期；[SH-78](../../issues/selfhost/sh78-lib-export-free-functions-only.md) + 文档 |
| 6 | `build --lib --emit-map` 不写文件 | rc=0，`map.json` 不存在；compile 模式同参数写出 1558 字节 | **A**（SH-79） | **0.53.8**；显式支持或硬错 |
| 7a | 警告通道 JSON | `--diagnostics=json` 输出 `{"warnings":[…]}` | **D**（已实现，缺夹具） | 并进 0.53.14 回归 |
| 7b | 解析错误 JSON | `parse.ct:1:1: error: unexpected token`（纯文本） | **A**（LANG-10 子项） | **0.53.14** |
| 7c | 字段级位置 | `Field{name,type,dims}` 无 `line/col`（`Symbols.h.ct:232-238`） | **B** | **PH-58** |
| 8 | `Type::Member` 限定名取值 | `FsErrCode::FS_ERR_OUT_OF_BOUNDS` → `no variable of that name in that namespace` | **B**（LANG-15） | **PH-57**（与 SH-18 同 phase，入口不同） |
| 9 | `char *` → `Str` 只 warning | LANG-14 已在序列；声称已修、夹具待补 | **A + D** | **0.53.5**（复用编号） |
| 10 | `ct install` 只发 `-I vendor/<包>` | PH-54 已收 `ns-root` 与包根契约 | **B**（工具能力） | **PH-54**（复用编号，不重开） |

**1/3/4 是否同一类问题**：

- **1 与 3 同类**：都是「已在 v0.53.1 修好、报告基于旧二进制」；HEAD 重建后两条复现均 rc=0，
  夹具 `261` / `260` 在跑。没有新根因，不开新号。
- **4 不同类**：不是「已实现的东西不可见」，而是冻结设计把哈希限定为**导出名**；签名漂移由
  `.abi.h` 原型逐行体现（D42-10 明确不以哈希单独作证据）。因此判 C，不按 bug 修。
- 与 1/3 表面相似（都像「不可见」），但 1/3 是实现回归、4 是契约范围，修复动作完全不同。

| PATCH | 收哪条 | 必须加的回归 | 依赖 / 串行 |
| --- | --- | --- | --- |
| **0.53.2** | LANG-5：方法形态（`fe16bfe3` 补版本）+ `m["a"].x` 字段形态守卫 | `262_inherent_mcall_receiver` 转绿；新增 `index_result_field` 负例（`m["a"].x` 硬错或自动 `->`、不落坏 C）；`temp_receiver_trait_chain` 仍硬错 | 无前置；**必须最先**（当前 fix 未 bump） |
| **0.53.3** | LANG-4：自定义 `get` 类型不匹配 | 只有 `get(char*)` 时 `v[0]` 硬错、列候选、不写 `.c`；`v["k"]` 零回归 | 依赖 0.53.2 |
| **0.53.4** | LANG-13：三级链 + `m["a"]["b"]` plain 链 | `doc["a"]["b"]["c"]` 与 `m["a"]?["b"]?["c"]` 通过；plain `m["a"]["b"]` 要么自动解引用、要么硬错并提示 `?[`；`test/ast/263` + 负例 | 依赖 0.53.2/0.53.3 |
| **0.53.5** | LANG-14：`char *`→`Str` 诊断 | `take("k")` rc=1、不落 `.c`；`int*`↔`char*` 仍 warning；`str_from` 通过 | 依赖 0.53.2 |
| **0.53.6** | LANG-11：同名 `.h.ct`/`.ct` 产物冲突 | 两单元工程 rc=0；每个 `.c` 只出现一次；`extern` 链接 | 独立（Pkg/Driver） |
| **0.53.7** | SH-76：内置层缺失误诊为 `expected a field name`（安装相对探测 + 明确诊断） | 四条探针在无 cwd `lib/std` 时 rc=0；`B`/`H` 仍过；compile/build 结论一致；隐层负例点名 `CT_STD_DIR`、不写 `.c`；裸 `Map *` 仍报类型实参缺失 | 与 0.53.6 同为 `Driver/Module` 族，**必须串行**；若一并改 `Expr` 诊断，再排到 0.53.12 之后 |
| **0.53.8** | SH-79：`build --lib --emit-map` 静默不写文件 | 文件存在且 JSON 可解析；与 compile 模式键集合一致；无开关时零产物；若改硬错则诊断含 `--emit-map` | 与 0.53.6/0.53.7 同 `Driver/Module` 族，**串行**；根因不同不合并 |
| **0.53.9** | LANG-8：`5.method()` 词法 | `5.method()`、`5.0`、`5..6` 三组 | 独立（Lexer） |
| **0.53.10** | LANG-7：未声明变量诊断（先复验） | 指向变量名、行号正确；若已由 LANG-2 覆盖则关闭 | 与 Expr/Parser 族串行 |
| **0.53.11** | LANG-3：MAX_CALLS 上限与诊断 | 1024 通过、1025 命中 D1–D4（含上限/累计/建议/位置）；两单元 500+600 位置正确；不写 `.c` | 与 Expr/Parser 族串行（`:55`、`Parser:3759`） |
| **0.53.12** | LANG-9：struct 字段 ABI | 私有字段不进头；`pub` 字段进头；跨单元访问硬错 | **单独发**，冻结其它 header/Emitter 改动 |
| **0.53.13** | SH-65（+SH-67 若同根） | 闭包字面量 / 先绑变量两种入口 rc=0 且 `cc` 过 | 依赖 0.53.4 |
| **0.53.14** | LANG-10（7b）：解析错误走 JSON 通道 | `--diagnostics=json` 下解析错误输出可解析对象；默认文本逐字节不变；警告 JSON 补夹具（7a） | 与 Driver/Diag 族串行（0.53.8 之后） |
| **0.53.15** | SH-60 1a/1b（条件） | 视 D-60-1 裁定；未裁定不发 | 条件 |

**SH-76 判定（新并入）**：v0.53.0 实测「无 `lib/std` / 未设 `CT_STD_DIR`」时 compile 与 build
**同样**报 `1:15 expected a field name`，设上 `CT_STD_DIR` 或 cwd 放 `lib/std` 后**同样** rc=0——
所以不是「L0 与 L2 两套解析器结论相反」。随附 `ctc` 是 `ct` 的符号链接，compile / build 共用
`frontend/parse`；真正的分叉是冻结种子 `l0/ctc.c` 与 ct-ast 代际（L0 不依赖模板表）。根因是
内置层探测只有 `CT_STD_DIR` / cwd / 输入同级三路，缺「安装相对」候选，且找不到时静默继续解析。
与 LANG-11 同改 `Driver.h.ct` 但根因不同，**不合并**，只串行。

**合并规则：** 只有同一 issue / 同一根因可合并。`LANG-5` 方法 + 字段 → 0.53.2；
`SH-67` 若确认与 SH-65 同根 → 并入 0.53.13；`LANG-10` 的 7a 夹具并入 0.53.14；其余一个 PATCH
一条，按 V-3 不攒批。SH-77 / SH-78 是设计口径，不进 patch。
**可并行开发：** LANG-8（Lexer）与 `Emitter/header`（LANG-9）文件族独立；发版仍串行。
**必须串行：**
LANG-5 → LANG-4 → LANG-13 → LANG-14 → LANG-7 / LANG-3 → SH-65（TypeCheck/Expr/Parser/Emitter/golden）；
LANG-11 → SH-76 → SH-79 → LANG-10（Driver/Module/Diag）。
LANG-9 单独发，期间冻结其它 header/Emitter 改动。

---

## 6 风险与未决

1. **PH-53 状态冲突**：卡面已完成 `v0.53.0`，指令要求 patch 后开 S0；本表保留槽位，若重开需在卡上追加「重开理由 + S0 范围」。
2. **LANG-5 版本漂移**：`fe16bfe3` 未 bump；0.53.2 必须先补版本，否则 PATCH 号不成立。
3. **LANG-13/14 夹具缺失**：只按「声称已修」引用，不能记绿；补齐后若仍红，继续按 bug 修。
4. **Map plain `[]` / `.field`**：当前静默发射坏 C；安全替代是 `?[` / `?.`，但 plain 形态仍应「可用或硬错」，不能留在 `cc`。
5. **PH-54 版本位**：A 方案要改 roadmap 的 `v0.55–v0.60`；本轮只登记，不改 roadmap。
6. **并行会话**：`TypeCheck` / `Emitter` / `main` / `Driver` / `Pkg` / `test/pkg` / `test/ast/263` 未触碰。
7. **SH-76 索引行待补**：`issues/README.md` 当前有并行会话未提交的改动，本轮不写该文件；
   SH-76 的索引行由并行改动落地后一并补，避免把别人的半成品带进本提交。
8. **SH-76 环境证据**：现场「`ctc` 失败 / `ct build` 正常」在 v0.53.0 同 cwd 下不可复现；
   已按「内置层找不到」复现两条路径。报告方需补 `ctc -v`、`ct -v`、`pwd`、`CT_STD_DIR` 才能定位其环境差异。
9. **LANG-1 / LANG-2 报告差异**：HEAD `v0.53.1` 重建后两条均 rc=0（夹具 `260` / `261`）；
   报告若仍红，先核对二进制版本与 cwd，不要按「未修」重开，避免把旧版本现象当新缺陷。
10. **LANG-10 已部分实现**：`--diagnostics=json` 的警告通道在跑；报告「完全没有机器可读诊断」
    会高估工作量，按 7a/7b/7c 拆开后只有 7b 进 patch、7c 进 phase。

---

## 7 落库

- 规则：[D-005](../decisions/D-005.md)；AGENTS §6.8 引用。
- 本评估：`docs/planning/open-items-routing.md`。
- 新条目：[SH-76](../../issues/selfhost/sh76-builtin-layer-missing-misdiagnosis.md)（内置层缺失误诊）、
  [SH-77](../../issues/selfhost/sh77-abi-hash-name-only.md)（ABI_HASH 仅名字，拒绝）、
  [SH-78](../../issues/selfhost/sh78-lib-export-free-functions-only.md)（`--lib` 只导出自由函数，拒绝）、
  [SH-79](../../issues/selfhost/sh79-build-lib-emit-map-silent.md)（`build --lib --emit-map` 静默）、
  [LANG-15](../../issues/lang/lang-15-qualified-enum-member-value.md)（`Type::Member` 取值，PH-57）。
- 复用编号：LANG-1 / LANG-2（已修复核）、LANG-3（补诊断判据）、LANG-10（拆三块）、LANG-14（已在序列）、
  SH-18（类型位置）、PH-54（包机制）。
- 不改 `docs/roadmap.md`、`docs/design/phase53.md`、`docs/design/phase54.md`、发版契约、`selfhost/**`。
- 只本地提交，不 push、不打 tag。
