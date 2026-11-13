# Phase 42 — `impl` 方法可见性（方法级 `pub`，默认私有）

> **状态：已冻结（2026-11-13；battle p42-1 C；v0.41.0 基线；实施中）。**
> **基线**：PH-41 收口提交 `de9ce1ab` / `v0.41.0`；S0 在该提交上冷构建并记录 `baseline: de9ce1ab`。
> **文档形态**：`phase42-draft.md`；design window 7/12（门禁只数 `phaseN.md`，草案不计数）。
> **前置**：[phase34-draft.md](phase34-draft.md)（`pub struct` / 固有方法）、[phase39-draft.md](phase39-draft.md)（导出面与 `ABI_HASH`）、[phase41-draft.md](phase41-draft.md)（收口基线）。
> **关联**：[language-spec.md](../language-spec.md) 的 `pub` 节、[bindings-and-patterns.md](../bindings-and-patterns.md)、[modern-oo-gap.md](../modern-oo-gap.md)、[battle/p42-1](../../battle/p42-1/verdict.md)。
> **规模**：编译器 320–560；迁移 80–150；夹具 140–230；文档 50–90；合计 **590–1030**（±40%）。
> **纪律**：收口 bump `v0.42.0`；phase tag 按 6.7 V-7 随收口自动创建并推送；分支推送按 6.5 等用户指令。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-42 |
| 目标 | `impl` 方法默认私有，写 `pub` 才公开；私有 = 不进 `.h` + 发 `static` + 跨单元调用硬错；判定收敛到一处 |
| 范围 | O1/O2/O3；不做块级 `pub impl`、兼容警告、迁移工具、字段级可见性、保留名自动公开 |
| 交付物 | `Parser.h.ct` / `Symbols.h.ct` / `Emitter.h.ct` / `Expr.h.ct`；`test/modules/p42_visibility/**`；`lib/std` 迁移；文档 |
| 任务清单 | §4.1（R1–R8，共 8 项） |
| 退出判据 | E42-1…E42-8（§5） |
| 依赖 | PH-41 收口 `v0.41.0`；PH-34 `impl` 语法；PH-39 `--lib` 导出面；规范 1.9.0 |
| 规范版本 | 1.9.0 |
| version-minor | 42 |
| 已知风险 | R42-1…R42-7（§7） |
| 冻结 | 2026-11-13；用户指令 PH-42 定稿后自动进入；battle p42-1 C |

## 1 需求与边界

### 1.0 AN-42（四段）

| 段 | 内容 |
| --- | --- |
| 问题 | `pub struct` 的 `impl` 方法**无条件公开**；可见性判定散在 5 处；「不进头」不等于私有（定义仍外链、消费方解析器在全局 arena 仍能解析到）；`ct check` 把任何 warning 当 rc=1，兼容期在技术上不存在 |
| 范围 | 方法级 `pub`（默认私有）+ 三段式私有语义 + 判定收敛一处 + 52 条迁移（std 43 + 其它 9）+ 消费方 header-diff |
| 验收 | E42-1…E42-8 全部可在 `check-ast.sh` / `check-warnings.sh` / `check-docs.py` / `check-all.sh` 上机械核对 |
| 依赖与风险 | PH-41 未收口则不开工；模板 foreign-element 实例由消费方重发方法体；`use Drop`/`Handback` 的 `drop`/`handback` 是 trait impl/static，另有规则 |

### 1.1 一句话

`impl S { … }` 里的固有方法默认私有；写 `pub` 才进 `.h`、才保持外部链接、才允许跨单元调用。私有不是「不发射」——模板与 foreign-element 的副本仍要发射，只是发成 `static`。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | 方法级 `pub`：`pub int len()` 公开；无 `pub` 私有；trait impl 方法不适用；`.ct` 单元或私有 struct 上写 `pub` 硬错 | `pub` 在 impl 里被 `parse_type` 当未知类型名吞掉（生成 `pub int len(...)` 级坏 C）；`pub struct` 的方法全公开 |
| O2 | 判定收敛：`N_METHOD.d` 一处标记 + `ct_method_is_pub(int)` 一处谓词，替换 5 处 struct 可见性判断；查找返回 `(method, owner)` | 判定散在 `Emitter.h.ct` 的 `:1957`、`:2847`、`:3385`、`:1604`+`:2054`；查找 owner-blind |
| O3 | 迁移与不变式：`lib/std` 43 条 + 其它 9 条 = 52 条**全部显式 `pub`**；迁移前后冻结 `.h.ct` 的导出原型集合逐字相同 | 无方法级标记，无 header-diff；8 条协议方法不自动公开 |

范围编号对应：D1（文档修正）已由 `ec806f59` 覆盖，本卡不重复排期；D2（原型面 / 符号面观测）= O2 + E42-2 / E42-5 / E42-6；D3 原为块级 `pub impl`，现由 §3.1 否掉、改为方法级 `pub`；D4（迁移与 header-diff）= O3 + §3.4。

### 1.3 非目标

- 不做块级 `pub impl S { … }`（§3.1 硬错；块级会让「一个块里混公私」永远不可表达）。
- 不做兼容警告 / `--legacy-visibility` / 双模式开关：`ct check` 任何 warning 即 rc=1（D42-4）。
- 不做迁移工具：52 条一次改完。
- 不做字段级可见性：struct 字段仍随 struct 的 `pub` 走。
- 不改 trait / struct / 全局变量的 `pub` 语义；不改 trait impl 方法（`impl T for S`）与 `Drop` / `Handback` 的可见性规则。
- **不做保留名自动公开**：`retain`/`release`/`drop`/`handback` 都不按名字特判；元素协议方法必须显式 `pub`（battle p42-1 C）。
- 不改 `ctc.c`、L1、L2。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D42-1 | **默认私有，`pub` opt-in** | 方法是最小暴露单元；std 的 52 条正好把公开面显式化 |
| D42-2 | 私有 = 三段式：不进 `.h` + 定义 `static` + 跨单元调用**硬错** | 只做前两段会发射 implicit declaration 级坏 C；硬错让问题在本单元暴露 |
| D42-3 | 判定收敛：`N_METHOD.d` 由 parser 写；`Symbols.h.ct` 的 `ct_method_is_pub(int d)` 只读该标记；5 处调用点全部替换；方法查找返回 `(method, owner)` | 一处判定才能保证头面、符号面、诊断面同时一致；`Symbols` 不直接访问 arena |
| D42-4 | **clean break**：无警告窗口、无双模式、无回退开关 | `ct check` 任何 warning 即 rc=1；「旧行为 + 警告」不可用 |
| D42-5 | 迁移顺序：R1 解析 → R2/R3 补 `pub`（行为不变）→ R4 切换/翻默认 → R5/R6 诊断与泛型 | 任何一步结束仓库都可构建、自举链都绿；不保留 `|| struct_pub` 临时回退 |
| D42-6 | **52 条全部显式 `pub`**；`retain`/`release` 不自动公开；跨单元/foreign 元素调用未 `pub` 时报 L42-6 | battle p42-1：J-1「未写 `pub` 不得 public」是否决项；自动 8 条仍违反 opt-in |
| D42-7 | 模板：`exported = 模板 pub && 属主 `.h.ct` && 方法 pub`；只对固有模板 impl；foreign-element 副本恒 `static`；`use Trait` 块不受方法级规则影响 | 保留 P29/P33/P34 的三个合取；避免 `pub` 方法在非 pub 模板上外链 |
| D42-8 | trait impl 方法、`use Drop`/`Handback` 的 `drop`/`handback` 不参与方法可见性；它们恒 `static`/trait 路径 | 与 P36/P39 的 vtable/Drop 语义一致；`drop`/`handback` 无固有定义 |
| D42-9 | `pub` 只允许在 `.h.ct` 单元的、`pub struct` 的固有 `impl` 方法上；`.ct` 单元、私有 struct、文件作用域一律 L42-1 | `.ct` 的 `pub` 不能被 import；私有 struct 的方法进头会造出不可命名类型 |
| D42-10 | header-diff 用冻结消费夹具（`Vec<int>`/`Map<char*,int>`/`Option<int>`/`Result<int,char*>`）；ABI 用含固有 `impl` 的 `--lib` 夹具；不以 `ABI_HASH` 单独作证据 | 泛型方法无实例时不在 `.h`；`ABI_HASH` 只覆盖自由函数 |

## 2 现状与基线

### 2.1 门禁基线

参考值（历史量级）：`check-ast` 1329/0、`check-warnings` 600/0、`test/run` 148、`check-docs` 900+ links、design window 7/12。S0 在 PH-41 收口提交上冷构建 `ct` 并实测替换本节；不沿用 PH-40 的基线。

### 2.2 设计探针（2026-11-13，v0.40.1）

| 探针 | 命令 | 结果 |
| --- | --- | --- |
| `pub` 方法被当类型 | `ct-ast p1.ct` | rc=0，生成 `static … pub int Counter_len(…)` |
| 块级 `pub impl` | `ct-ast p2.ct` | rc=0，与去掉 `pub` 逐字节相同（除 banner） |
| `pub struct` 方法全公开 | `nm -g` / `.h` | `Counter_secret` 为 `T`，头里有原型 |
| 私有 struct 方法 | `nm` | 已是 `static`/`t` |
| `ct check` 任意 warning | 签名漂移夹具 | rc=1，warning 升为 error |
| 方法总数 | 剥注释、跳过 trait impl | std 43 + 其它 9 = 52；名字匹配 10，协议 8 |
| `ABI_HASH` | `lib.abi.h` | 只含自由函数；方法不在 ABI 面 |
| `expected.internal` | `test/modules/p39_lib` | 只有 `Str_retain`/`Str_release`；该夹具无 `impl` |

### 2.3 代码锚点（v0.40.1 `1b14b63a`）

| 主题 | 位置 |
| --- | --- |
| `pub` 顶层声明 | `frontend/parse/Parser.h.ct:670` |
| `pub impl` 入口 | `frontend/parse/Parser.h.ct:802` |
| 固有方法解析 | `frontend/parse/Parser.h.ct:3120`，`parse_type` 在 `:3145` |
| 方法查找 | `frontend/parse/Expr.h.ct:3423`（实例）、`:3462`（静态） |
| 元素协议判定 | `backend/emit/Emitter.h.ct:1778`（`elem_has_life`） |
| 方法发射/静态 | `backend/emit/Emitter.h.ct:2847`、`:3375`（头原型）、`:2017`/`:2023`/`:2026`（elem retain/release） |
| 模板方法头/体 | `backend/emit/Emitter.h.ct:1604`、`:2054` |
| `ABI_HASH` | `backend/emit/Emitter.h.ct:5207` 起（只遍历 funcs） |

## 3 语义与落码

### 3.1 `pub` 语法与适用范围

```c
pub int len() { … }              // 实例方法
pub static Counter make() { … }  // 静态方法；`static` 可在 `pub` 前/后
```

- `pub` 在方法返回类型之前；`pub static` 与 `static pub` 等价；重复 `pub` 报错。
- 只允许：`.h.ct` 单元、`pub struct` 的固有 `impl`（`impl S` 或 `impl<T> S<T>`，无 `use Trait`）。
- 禁止：`.ct` 单元、私有 struct、文件作用域 → L42-1；错误位置在 `pub`。
- 禁止：`impl T for S` 的方法写 `pub` → L42-2；块级 `pub impl` → L42-3。
- `pub` 仍只是标识符/类型名；`pub` 出现在其它位置按既有解析规则处理。

### 3.2 私有语义

- 私有方法：不进 `.h`；定义 `static __attribute__((unused))`；方法体照常发射（模板/foreign-element 副本也发射）。
- 同单元调用：允许；跨单元调用：L42-4（实例）/ L42-5（静态）。
- 元素协议 `retain`/`release`：不自动公开；当生成代码在**跨单元/foreign** 元素调用点发现方法未 `pub` 时 L42-6；单单元私有元素不报。
- `drop`/`handback`：trait impl / static，不参与；没有「保留名」概念。
- 字段可见性仍随 struct；`pub` 方法不会让私有 struct 进 `.h`。

### 3.3 模板、trait 与 foreign-element

- 固有模板 `impl<T> S<T>`：方法 `pub` 只影响实例方法的 `exported`；公式保留三个合取：`tps[tmpl].is_pub && owner_is_hdr && method_is_pub`。
- `use Trait` 块：方法沿用 `<Inst>_<Trait>_<method>` 与 vtable 路径；方法级 `pub` 不参与（L42-2 只对 `impl T for S` 的源码 `pub`）。
- foreign-element 副本：恒 `static`，仍发射；消费方头不声明；`inst_elem_foreign` 规则不改。
- 方法查找必须带 owner：同一 `S` 在多个单元有同名固有方法时，优先当前单元；否则 L42-7（歧义），不再按 arena 首匹配。

### 3.4 迁移与不变式

- 迁移集合：std 43（Option 8 / Result 11 / Str 2 / Vec 22）+ 其它 9 = 52；**全部加方法级 `pub`**。
- 计数脚本必须剥注释、跳过 `impl … for …`（trait impl）；输出三行：`std 43`、`other 9`、`all 52`。S0 冻结 `migration.list` 与逐行 sha。
- 迁移后构造冻结消费夹具（`Vec<int>`/`Map<char*,int>`/`Option<int>`/`Result<int,char*>`），比对整套 `.h` 原型集合与属主 `.o` 的 `nm`；不能用「只编 `Vec.h.ct`」的空头。E42-5 在 R4 翻默认后复跑；R2/R3 的 header sha 是迁移前基线。
- D34-2 的「生成 `.h` 仍只放类型」已被 P34 S5b 的消费者原型覆盖；本相沿用 S5b。
- `--lib` ABI：含固有 `impl` 的夹具断言 `nm -g` 无私有方法、`expected.internal` 不变；`ABI_HASH` 只作辅助。
- 公开方法仍不是 C ABI 导出（`visibility("default")` 只对根单元自由函数）；D42-2 的「外链」指模块内跨单元，不是 `--lib` 导出。

### 3.5 诊断（L42-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L42-1 | `.ct`/私有 struct/文件作用域上的方法 `pub` | `a pub method needs a pub struct in a .h.ct unit` |
| L42-2 | trait impl 方法写 `pub` | `a trait impl method cannot be pub` |
| L42-3 | 块级 `pub impl` | `a pub impl block is not supported; mark methods` |
| L42-4 | 跨单元调用私有实例方法 | `method '<m>' is private to its unit` |
| L42-5 | 跨单元调用私有静态方法 | `static method '<m>' is private to its unit` |
| L42-6 | 跨单元/foreign 元素协议方法未 `pub` | `element protocol method '<m>' must be pub` |
| L42-7 | 多个单元声明同名固有方法，无法定 owner | `inherent method '<m>' is ambiguous across units` |

## 4 任务清单

开工前 **S0（不占任务行）**：PH-41 收口后在该提交上冷构建 `ct`、复跑 §2.2、生成 `migration.list` / `header-manifest.sha`、写 §2.1 与 `baseline.sha`；不产提交。

### 4.1 冻结任务表

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | `pub` 解析 + `N_METHOD.d` + L42-1/2/3（`Parser.h.ct`） | `p42/pub-syntax`：3 正例 + 3 负例全绿 | M | revert |
| R2 | std 43 条补 `pub`（`lib/std/*.h.ct`） | `p42/migration`：std 43/43；header sha 不变 | M | revert |
| R3 | 其它 9 条补 `pub` + 消费夹具（`examples/38_*`、`test/modules/*`） | `p42/migration`：other 9/9、all 52/52；消费 `.h`/`nm` 不变 | M | revert |
| R4 | 谓词 + 翻默认 + L42-6（`Symbols.h.ct` / `Emitter.h.ct`） | `p42/private`：私有 static/无原型/元素 L42-6；1/1 | M | revert |
| R5 | 跨单元 L42-4/5/7 + owner-aware 查找（`Expr.h.ct`） | `p42/cross-unit`：3 负例 + 歧义 1 负例；1/1 | M | revert |
| R6 | 模板/trait/foreign 规则（`Emitter.h.ct`） | `p42/generic`：`exported` 三合取、foreign static；1/1 | M | revert |
| R7 | 零回归 + ABI（`test/modules/p42_visibility/**`、`check-ast.sh`） | `p42/regression` + `p42/abi`：私有不在 `nm`、`expected.internal` 不变 | M | revert |
| R8 | 文档与编辑器（`language-spec` / `tutorial` / `README` / tmLanguage / example） | `p42/docs` + `check-grammar.py` 168/168；`no-test:` 纯文档/编辑器 JSON | S | revert |

映射：R1→E42-1；R2/R3→E42-5；R4→E42-2；R5→E42-3；R6→E42-4；R7→E42-6；R8→E42-7。**每项至多覆盖 1 条退出判据**（6.6 T-5）；E42-8 为固定条，不占任务。

## 5 退出判据（E42-n）

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E42-1 | `pub` 三形式（实例/`pub static`/`static pub`）解析；L42-1/2/3 硬错 | `ok p42/pub-syntax`，6/6 | `test/modules/p42_visibility/parse_*` |
| E42-2 | 默认私有：无原型、`static`、同单元可用；L42-6 仅跨单元/foreign 元素 | `ok p42/private`，1/1；`nm` 无私有 `T` | `test/modules/p42_private` |
| E42-3 | 跨单元私有实例/静态调用 L42-4/5；歧义 L42-7；当前单元优先 | `ok p42/cross-unit`，1/1 + 3/3 负例 | `test/modules/errors/p42_*` |
| E42-4 | 模板 `exported` 三合取；`use Trait` 不受方法级影响；foreign 副本 `static` | `ok p42/generic`，1/1 | `test/ast/147`、`222`、`p42_generic` |
| E42-5 | 52 条全 `pub`；消费夹具 `.h` 原型与 `nm` 不变；R4 翻默认后复跑 | `ok p42/migration`，52/52；header sha 相同 | `p42_migration` + 消费夹具 |
| E42-6 | 既有 defer/own/ABI/C 产物零变化；`--lib` 私有方法不在 `nm` | `ok p42/regression` + `ok p42/abi`，1/1；`expected.internal` 相同 | 全量 + `p42_lib` |
| E42-7 | 文档可执行 + 编辑器覆盖 | `check-docs.py` exit 0；`check-grammar.py` 168/168；`ok p42/docs` | `docs/**`、`editors/**` |
| E42-8 | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §4.1，8/8 exit 0；收口对照表逐行贴输出 | §4.1 |

承诺映射：O1→E42-1；O2→E42-2/3/6；O3→E42-5；E42-7 守文档；E42-8 守任务粒度。

## 6 负例台账（L42-n）

| 编号 | 触发 | 夹具（`test/modules/errors/`） |
| --- | --- | --- |
| L42-1 | `.ct`/私有 struct 上方法 `pub` | `p42_pub_scope/` |
| L42-2 | trait impl 方法 `pub` | `p42_pub_trait_impl/` |
| L42-3 | 块级 `pub impl` | `p42_pub_block/` |
| L42-4 | 跨单元私有实例调用 | `p42_private_call/` |
| L42-5 | 跨单元私有静态调用 | `p42_private_static/` |
| L42-6 | 跨单元/foreign 元素方法未 `pub` | `p42_element_unpub/` |
| L42-7 | 多单元同名固有方法 | `p42_ambiguous/` |

## 7 风险与开放项

| 编号 | 风险 | 触发信号 / 处置 |
| --- | --- | --- |
| R42-1 | 迁移漏标一条 → 翻默认后自举/夹具红 | E42-5 52/52 + header-diff；R2/R3 必须全量 |
| R42-2 | 跨单元同名方法，owner 判定错 | R5 返回 `(method, owner)`；L42-7 |
| R42-3 | 模板/foreign 副本被误发 external | D42-7 三合取；E42-4 |
| R42-4 | 私有 struct/`.ct` 的 `pub` 被静默接受 | D42-9 / L42-1；E42-1 |
| R42-5 | `drop`/`handback` 被误当保留名 | D42-8；不进入迁移清单；探针确认 static |
| R42-6 | 元素协议漏 `pub` 留给 cc | L42-6（仅跨单元/foreign）；E42-2 |
| R42-7 | PH-41 未收口即开工，基线/版本跳号 | 卡状态待 41 收口；S0 不在 40 上开工 |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T42-1 | 字段级可见性（`pub` 字段 / 只读字段） | 有包需要「结构公开、字段私有」 |
| T42-2 | 块级 `pub impl`（本相否掉的备选） | 整块公开的真实诉求，且能说清与 trait impl 的关系 |
| T42-3 | 包内可见（`pub(pkg)` 一类） | ct-pkg 多单元协作提出稳定需求 |
| T42-4 | 迁移工具 / lint | 迁移量再次超过 100 条 |

## 8 估算与收口

- 编译器 320–560 = R1 50–90 + R4 60–110 + R5 60–110 + R6 50–90 + R7 60–100 + 迁移 80–150（R2 50–90 + R3 30–60）；夹具 140–230；文档 50–90。
- 开工前 S0：PH-41 收口提交上冷构建 `ct`（`ct -v` = v0.41.0）、复跑 §2.2、生成 `migration.list` / `header-manifest.sha`、写 §2.1；不占任务行。
- 收口动作：11 道门禁绿、`p42/*` 全绿、`version-minor=42`、五处 `CTC_VERSION` 与全部版本落点同步到 `v0.42.0`、phase-log 与对照表落盘；tag 按 6.7 V-7，分支推送按 6.5。
- 每个实现任务 ≤3 个源码文件；每个实现提交的父提交是它的 `test(visibility): <task-id> 红`；仓库任何时刻可构建。
- 文档修正说明：`pub` 可见性表述的既有漂移已由 `ec806f59` 覆盖（`docs/` 三处），**不重复排期**；本卡 R8 只补「方法级 `pub` / 默认私有」的新语法、`pub impl` 收紧的迁移说明与 README 适用编译器标注。
