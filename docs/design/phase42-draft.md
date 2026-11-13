# Phase 42 — `impl` 方法可见性（方法级 `pub`，默认私有）

> **状态：草案**（2026-11-13，待评审；未立项）。
> **基线**：PH-41 收口提交（`v0.41.0`）；若 PH-41 顺延，则在 PH-40 收口提交上开工并在 S0 改写本节。
> **文档形态**：`phase42-draft.md`；design window 7/12（门禁只数 `phaseN.md`，草案不计数）。
> **前置**：[phase34-draft.md](phase34-draft.md)（`pub struct` / 固有方法）、[phase39-draft.md](phase39-draft.md)（导出面与 `ABI_HASH`）、[phase41-draft.md](phase41-draft.md)（收口基线）。
> **关联**：[language-spec.md](../language-spec.md) 的 `pub` 节、[bindings-and-patterns.md](../bindings-and-patterns.md)、[modern-oo-gap.md](../modern-oo-gap.md)。
> **规模**：编译器 320–560；迁移 80–150；夹具 140–230；文档 50–90；合计 **590–1030**（±40%）。
> **纪律**：收口时 bump `v0.42.0`；tag/push 按 `AGENTS.md` 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-42 |
| 目标 | `impl` 方法默认私有，写 `pub` 才公开；私有 = 不进 `.h` + 发 `static` + 跨单元调用硬错；判定收敛到一处 |
| 范围 | D2/D3/D4；不做方法级兼容警告、不做迁移工具、不做块级 `pub impl`、不做字段级可见性 |
| 交付物 | `Parser.h.ct` / `Symbols.h.ct` / `Emitter.h.ct` / `Expr.h.ct`；`test/modules/p42_visibility/**`；`lib/std` 迁移；文档 |
| 任务清单 | §4.1（R1–R9，R5 拆 a/b） |
| 退出判据 | E42-1…E42-9（§5） |
| 依赖 | PH-41 收口 `v0.41.0`；PH-34 `impl` 语法；PH-39 `--lib` 导出面；规范 1.9.0 |
| 规范版本 | 1.9.0 |
| version-minor | 42 |
| 已知风险 | R42-1…R42-7（§7） |

## 1 需求与边界

### 1.0 AN-42（四段）

| 段 | 问题 → 内容 |
| --- | --- |
| 问题 | `pub struct` 的 `impl` 内方法**无条件公开**；可见性判定散在 4 处；「不进头」不等于私有（定义仍外链、消费方解析器在全局 arena 仍能解析到）；`ct check` 把任何 warning 当 rc=1，兼容期在技术上不存在 |
| 范围 | 方法级 `pub`（默认私有）+ 三段式私有语义 + 判定收敛一处 + 52 条迁移 + header-diff 不变式 |
| 验收 | E42-1…E42-9 全部可在 `check-ast.sh` / `check-warnings.sh` / `check-docs.py` / `check-all.sh` 上机械核对 |
| 依赖与风险 | 模板 foreign-element 实例由消费方重发方法体；`use Drop` 的 `drop` 与 trait impl 方法另有规则；自举链的 std 调用必须在翻默认前补 `pub` |

### 1.1 一句话

`impl S { … }` 里的方法默认私有；写 `pub` 才进 `.h`、才保持外部链接、才允许跨单元调用。私有不是「不发射」——模板与 foreign-element 的副本仍要发射，只是发成 `static`。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | 方法级 `pub`：`pub int len()` 公开；无 `pub` 私有；trait impl 方法不适用 | `pub` 在 impl 里被 `parse_type` 当未知类型名吞掉（生成 `pub int len(...)` 级坏 C）；私有方法全公开 |
| O2 | 判定收敛：一处谓词（方法节点标记）替换 4 处 `decl_is_pub(N_STRUCT)` / 模板 `is_pub` 判断 | 判定散在 `Emitter.h.ct` 的 `:1957`、`:2847`、`:3385`、`:1604`+`:2054` |
| O3 | 迁移与不变式：`lib/std` 43 条 + 其它 9 条 = 52 条；迁移前后冻结 `.h.ct` 的导出原型集合逐字相同 | 无方法级标记，无不变式 |

范围编号对应：D1（文档修正）已由另一会话的 `ec806f59` 覆盖，本卡不重复排期（§8 末）；D2（原型面 / 符号面观测）= O2 + E42-2 / E42-6 / E42-8（接 `ABI_HASH` 与 `expected.internal`）；D3 原为块级 `pub impl`，现由 §3.5 否掉、改为方法级 `pub`（O1）；D4（迁移与 header-diff）= O3 + §3.6。

### 1.3 非目标

- 不做块级 `pub impl S { … }`（考虑过，见 §3.5；块级对 52 条迁移最省事，但会让「一个块里混公私」永远不可表达）。
- 不做兼容警告 / `--legacy-visibility` / 双模式开关：`ct check` 任何 warning 即 rc=1，窗口不存在（D42-4）。
- 不做迁移工具（`ct migrate-visibility` 一类）：52 条一次改完，工具成本高于手改。
- 不做字段级可见性：struct 字段仍随 struct 的 `pub` 走。
- 不改 trait / struct / 全局变量的 `pub` 语义。
- 不改 trait impl 方法（`impl T for S`）与 `Drop` / `Handback` 的可见性规则。
- 不改 `ctc.c`、L1、L2。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D42-1 | **默认私有，`pub` opt-in** | 与类型/字段的「默认随 struct」相反，但方法是最小暴露单元；std 的 43 条正好把公开面显式化 |
| D42-2 | 私有 = 三段式：不进 `.h` + 定义 `static` + 跨单元调用**硬错** | 只做前两段会发射 implicit declaration 级坏 C（§2.2 事实 3）；硬错让问题在本单元暴露 |
| D42-3 | 判定收敛：`Symbols.h.ct` 新增 `ct_method_is_pub(node)`（读 `N_METHOD.d`），4 处调用点全部替换 | 一处判定才能保证头面、符号面、诊断面同时一致 |
| D42-4 | **clean break**：无警告窗口、无双模式、无迁移工具 | `ct check` 任何 warning 即 rc=1；「旧行为 + 警告」在技术上不可用 |
| D42-5 | 迁移分两步提交：先补 `pub`（行为不变），再翻默认 | 任一步结束时仓库都可构建、自举链都绿（R42-1） |
| D42-6 | 保留名豁免 10 条：`retain` / `release` / `drop` / `handback` 一类由生成代码按名调用的方法无条件视为 `pub` | `__elem_retain` / `delete` / vtable 发射按保留名跨单元调用（`Emitter.h.ct:1957`） |
| D42-7 | 模板实例方法：`pub` 决定 `exported`；foreign-element 的消费方副本**恒为 `static`**，但仍发射 | 「私有」不能写成「不发射」，否则容器实例在消费单元链接失败 |
| D42-8 | trait impl 方法、`use Drop` / `use Handback` 的 `drop` / `handback` 不参与方法级判定 | 它们的可见性由 `pub trait` + `pub struct` 的 vtable 导出规则决定（P34/P39） |
| D42-9 | 静态（receiverless）方法与实例方法同规则 | `Vec::from` 一类同样只按需公开 |
| D42-10 | 不改 `.h` 的「只放类型 + 原型」契约；私有方法连原型都不进头 | 与 D34-2 / P39 的 ABI 边界一致 |

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，v0.40.0）：`check-ast` 1340±、`check-warnings` 600±、`test/run` 152、`check-docs` 950± links、design window 7/12。S0 在 PH-41 收口提交上重建 `ct` 并实测替换本节。

### 2.2 红证探针

| 探针 | 命令 | 结果 | 依据 |
| --- | --- | --- | --- |
| `pub` 方法今天不被识别 | `ct check` 一个带 `pub int len()` 的 impl | rc=0；`pub` 被当作未知类型名进入返回类型拼写，发射非法 C | `Parser.h.ct:3116` 直接 `parse_type(ret)`，未消费 `pub` |
| 块级 `pub impl` 被静默接受 | `ct check` 一个 `pub impl S { … }` | rc=0，无任何效果 | `Parser.h.ct:670` 记录 `decl_pub`，`:811` 的 impl 分支不读它 |
| 「不进头」≠ 私有 | 两单元夹具：单元 A 的 `impl S` 有私有方法，单元 B 调用 | 今天解析、链接、运行都成功 | 定义外链（`Emitter.h.ct:2847`）；`Expr.h.ct:3420` 扫描整个 arena |
| 只丢原型就坏 | 手改生成 `.h` 去掉原型后再构建 | `cc` 报 implicit declaration，链接失败 | 一单元一 TU；`Module.h.ct:1863` 只写头 |
| `ct check` 有 warning 即失败 | `ct check` 触发任意 warn | rc=1 | 语义门禁既有行为 |
| 迁移面 | `lib/std/*.h.ct` 的 impl 方法统计 | 43 条（Vec 22 / Result 11 / Option 8 / Str 2） | 统计脚本见 §6.1；全仓口径 52 条，差额 9 条在 `examples/**` / `test/modules/**` 的 `.h.ct`，S0 冻结清单 |

上表由代码锚点与已核事实推导；S0 必须用同一命令实跑并把原始输出贴回本表（红证），不得沿用本表的文字结论。

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| `pub` 记录与 impl 分支 | `selfhost/ct-ast/frontend/parse/Parser.h.ct:670` / `:811` |
| 固有 impl 解析（方法节点，无 `pub`） | `Parser.h.ct:3116`（`parse_impl_inherent`） |
| 模板 impl 解析 | `Parser.h.ct` 的 `parse_impl` / `parse_impl_inst` |
| 方法查找（全局 arena，跨单元可见） | `selfhost/ct-ast/frontend/parse/Expr.h.ct:3420`（`inst_inherent_method`）、`:3470` 一带（`inst_static_method`） |
| 判定点 1：`retain` / `release` 原型 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:1957` |
| 判定点 2：固有方法定义 `static` | `Emitter.h.ct:2847` |
| 判定点 3：固有方法头原型 | `Emitter.h.ct:3385`（`emit_inherent_protos`） |
| 判定点 4：模板实例方法 `exported` | `Emitter.h.ct:1604`（`impl_emit_method`）+ `:2054`（header 分支） |
| 结构 / trait / 全局的可见性判定 | `Emitter.h.ct:3282`（`decl_is_pub`） |
| 模块头写入 | `selfhost/ct-ast/frontend/module/Module.h.ct:1863` |
| `ABI_HASH`（导出面指纹） | `Emitter.h.ct:5187` |

## 3 语义与落码

### 3.1 语法与默认

```c
impl Counter {
    static Counter make(int start) { ... }   // 私有：不进头、static、跨单元不可调
    pub int get() { ... }                    // 公开：进头、外链、可跨单元
    pub static Counter zero() { ... }        // 静态方法同规则
}
```

- `pub` 只允许出现在方法声明的最前面（`static` 之前或之后都接受：`pub static` / `static pub`）。
- 同一个方法重复 `pub` → L42-1。
- trait impl（`impl T for S`）里写 `pub` → L42-2（可见性跟 trait，不跟方法）。
- 块级 `pub impl S` 从本相起 **L42-3 硬错**：今天静默接受（§2.2），继续接受会让作者误以为整块生效。
- 方法节点的标记落在 `N_METHOD.d`（0 私有、1 公开），与现有 `N_FUNC.d` 的 `pub` 语义同构。

### 3.2 三段式私有语义

| 段 | 行为 | 不做的后果 |
| --- | --- | --- |
| 不进 `.h` | `write_unit_header` / `emit_inherent_protos` / `emit_struct_impls(header=1)` 都不发该原型 | 头里出现消费者可调的名字，契约撒谎 |
| 定义 `static` | `emit_impls` 侧给定义加 `static __attribute__((unused))` | 符号仍外链，`nm -g` 能看见，等价于公开 |
| 跨单元硬错 | 消费方解析到该方法且归属单元 ≠ 当前单元时，`file:line:col: error:`，文案指向声明处并建议加 `pub` | 只删原型会落到 implicit declaration 级坏 C，错误信息与真实原因脱节 |

归属判定用 `N_IMPL.text3`（impl 块所属单元路径）与当前单元比较；模板实例另用 `StructImpl.owner` / `StructInst.owner`。诊断必须在**解析期**给出（`Expr.h.ct` 的两个方法查找入口），不留给 `cc`。

### 3.3 判定收敛到一处

| 现判定点 | 今天读什么 | 收敛后 |
| --- | --- | --- |
| `Emitter.h.ct:1957` 保留名原型 | `decl_is_pub(N_STRUCT, base)` | `ct_method_is_pub(m) \|\| is_reserved_name(name)` |
| `Emitter.h.ct:2847` 固有方法定义 | `decl_is_pub(N_STRUCT, …)` | `ct_method_is_pub(m)` |
| `Emitter.h.ct:3385` 固有方法头原型 | `decl_is_pub(N_STRUCT, …)` | `ct_method_is_pub(m)` |
| `Emitter.h.ct:1604+2054` 模板实例方法 | 模板 `is_pub` | `ct_method_is_pub(m)`（foreign-element 仍强制 0） |
| `Parser.h.ct` / `Expr.h.ct` 跨单元检查（新增） | — | 同一个 `ct_method_is_pub(m)` + 归属比较 |

`ct_method_is_pub` 放在 `Symbols.h.ct`（build-wide，解析与发射都能读），不放进任一侧的私有头。验收用源码断言：4 个调用点不得再出现按 struct / template 判方法可见性的写法（E42-4）。

### 3.4 迁移与保留名

- 总量 52 条 = 42 条手工加 `pub` + 10 条保留名豁免。
- `lib/std` 43 条：`Vec.h.ct` 22、`Result.h.ct` 11、`Option.h.ct` 8、`Str.h.ct` 2；其余 9 条在 `examples/**` 与 `test/modules/**` 的 `.h.ct`。
- 保留名 10 条：`retain` / `release` / `drop` / `handback`；由 `__elem_retain`、`delete`、vtable 发射按名字跨单元调用（`Emitter.h.ct:1957` 一带），因此无条件公开。
- 顺序：**R5a 先补 `pub`（行为不变）→ R5b 再翻默认 + 跨单元硬错**。`selfhost` 调用 std 方法（`Vec::len` / `Map::get` / `Option::unwrap` 等），std 不补 `pub` 自举链会红；两步分开保证每个提交都可构建。
- 迁移只加 `pub`，不改方法体、不改签名、不改 `.h` 契约，因此 header-diff 不变式可机械校验（§3.6）。

### 3.5 考虑过但不采用：块级 `pub impl`

`pub impl S { … }` 今天已被解析器静默接受（`decl_pub` 无消费者），零语法新增，且能把迁移从 52 条注解降为 10 个块。**不采用**，理由：

- 一个 struct 的公开面通常是「几个方法」，不是「整块」，块级强迫作者把公私方法拆成多个 impl 块；
- 块级与 trait impl 的可见性规则（跟 trait）冲突：`impl T for S` 里没有可写的 `pub` 位置；
- 与 P34 已收口的「`pub struct` 决定 impl 符号链接」形成两套心智模型，迁移期最容易出错；
- 本相已有 clean-break 前提，块级省下的手工量（52 → 10）不足以抵消上面的语义损失。

若日后出现「整块公开」的真实诉求，按 T42-2 另立卡，不与本相合并。

### 3.6 header-diff 不变式

迁移前后，对 S0 冻结的 `.h.ct` 清单（`lib/std` 4 个 + `examples/**` 与 `test/modules/**` 中含 impl 的 `.h.ct`，S0 写进 `header.list`）执行：

1. 逐单元构建，取生成的 `<base>.h`；
2. 抽取原型行（以字母/下划线开头、含 `(`、以 `);` 结尾），排序；
3. 与迁移前的清单逐字比较（sha256）。

迁移只添加 `pub`，方法本来就公开，所以**原型集合必须完全相同**；任何差异说明顺手改了签名或漏标。命令落在 `test/modules/p42_visibility/header_manifest.sh`，E42-6 用它。

### 3.7 诊断（L42-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L42-1 | 同一方法重复 `pub` | `duplicate 'pub'` |
| L42-2 | trait impl 方法上写 `pub` | `a trait impl method follows the trait's visibility` |
| L42-3 | 块级 `pub impl` | `'pub' on an impl block is not supported; mark the methods` |
| L42-4 | 跨单元调用私有实例方法 | `'<S>_<m>' is private to <unit>; add 'pub' to the method` |
| L42-5 | 跨单元调用私有静态方法 | 同 L42-4（`<S>::<m>` 拼写） |
| L42-6 | 保留名被显式写成私有（`priv retain` 一类不存在，故指「保留名之外」的生成代码调用） | `'<S>_<m>' is called by generated code and cannot be private` |

## 4 任务清单

开工前 **S0（不占任务行）**：在 PH-41 收口提交上重建 `ct`、复跑 §2.2、生成 `header.list` 与迁移前 `header-manifest.sha`，写 §2.1；不产提交。

R1–R7 每项先提 `test(visibility): <task-id> 红`，实现提交随后转绿；R8 为纯文档 `no-test:`（6.6 T-7 例外），R9 为等价性证据 `no-test:`（3.9 test-fix），两者须评审签字。

### 4.1 冻结任务表

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | 方法级 `pub` 解析与节点标记（`Parser.h.ct` 的 `parse_impl_inherent` / `parse_impl` / `parse_impl_inst`） | `p42/parse`：4 正例 + L42-1/2/3 三负例全绿 | M | revert |
| R2 | 单一谓词与 4 处收敛（`Symbols.h.ct` + `Emitter.h.ct`） | `p42/one-judge`：4 个调用点全部走 `ct_method_is_pub`；`p42/visibility` 头面正确 | M | revert |
| R3 | 私有定义 `static` + 头面零泄漏（`Emitter.h.ct`） | `p42/symbols`：`nm -g` 无私有符号；`.h` 无私有原型 | M | revert |
| R4 | 跨单元硬错（`Expr.h.ct` 的方法查找入口） | `p42/private-call`：L42-4/5 各 1 负例，rc≠0、恰一条 error、指向声明行 | M | revert |
| R5a | 迁移 `lib/std` 43 条加 `pub`（行为不变，无判定切换） | `p42/std-annotated`：`ct build` 全绿；`header-manifest.sha` 与 S0 相同 | M | revert |
| R5b | 翻默认私有 + 跨单元硬错全量生效（自举链同提交转绿） | `p42/default-private`；`check-ast.sh` 的 self-hosting fixpoint 绿 | M | revert |
| R6 | 其余 9 条迁移 + 夹具/示例（`examples/**`、`test/modules/**`、`examples/45_private_methods`） | `p42/fixtures`：示例可跑；`check-ast.sh` 相关段全绿 | S | revert |
| R7 | header-diff 不变式（`test/modules/p42_visibility/header_manifest.sh` + `header.list` + `baseline.sha`） | `p42/header-diff`：冻结清单的原型集合 sha256 与迁移前相同 | M | revert |
| R8 | 文档：`language-spec` 的 `pub` 节、`bindings-and-patterns`、`tutorial` 一段 | `python3 test/docs/check-docs.py` exit 0；`no-test:` 纯文档 | S | revert |
| R9 | 零回归（全量门禁 + `p42/regression` + `ABI_HASH` 不变） | `bash selfhost/check-all.sh` 11/11；`p39` 夹具的 `.abi.h` 与 `ABI_HASH` 逐字相同；`no-test:` 只做等价性证据 | M | revert |

映射：R1→E42-1；R2→E42-4；R3→E42-2；R4→E42-3；R5a/R5b→E42-5 / E42-7；R6→E42-8；R7→E42-6；R8→E42-9；R9→E42-9 + 全量。**每项至多覆盖 1 条退出判据**（6.6 T-5）。

## 5 退出判据（E42-n）

所有 p42 断言挂在既有 `selfhost/check-ast.sh` 内；不新增硬门禁编号。

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E42-1 | `pub` 方法进头、无 `pub` 不进头；静态方法同规则 | `ok p42/parse`，7/7；`.h` 原型行集合逐行相同 | `test/modules/p42_visibility/parse_*/` |
| E42-2 | 私有方法定义是 `static`，`nm -g` 不出现；符号面仍等于导出集合 ∪ `expected.internal` | `ok p42/symbols`；`nm` 归一化后 grep 私有符号命中 0；`p39_lib/r5_probe.sh` 的并集比较不新增条目 | 同上 |
| E42-3 | 跨单元调用私有方法/静态方法 rc≠0、恰一条 `文件:行:列: error:`、不产产物 | `ok p42/private-call`，2/2 | `test/modules/errors/p42_*` |
| E42-4 | 判定收敛：4 个调用点全部读方法标记 | `ok p42/one-judge`；源码断言计数 4/4 | `Emitter.h.ct` |
| E42-5 | 迁移完整：52 = 42 手工 + 10 保留名；`lib/std` 43 | `ok p42/migration`；统计脚本输出 42/10/43 | `lib/std/**`、`.h.ct` |
| E42-6 | header-diff 不变式：冻结清单原型集合逐字相同 | `ok p42/header-diff`；sha256 相同 | `header.list` / `header-manifest.sha` |
| E42-7 | 自举链与模板实例：fixpoint 绿；foreign-element 副本仍发射且 `static` | `check-ast.sh` 的 self-hosting 段绿；`ok p42/foreign-elem` | `check-ast.sh` 既有段 |
| E42-8 | ABI 面不变：`--lib` 的 `.abi.h` 与 `ABI_HASH` 与迁移前相同；`expected.internal` 不变 | `ok p42/abi`；`p39_lib` 期望文件逐字节；`test/modules/p39_lib/expected.internal` 差异为空 | `test/modules/p39_lib` |
| E42-9 | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §4.1，10/10 exit 0；收口对照表逐行贴原始输出 | §4.1 |

承诺映射：O1→E42-1 / E42-2 / E42-3；O2→E42-4；O3→E42-5 / E42-6 / E42-8。E42-7 / E42-9 守自举链与任务粒度。

## 6 负例台账（L42-n）

| 编号 | 触发 | 夹具（`test/modules/errors/`） |
| --- | --- | --- |
| L42-1 | 同一方法重复 `pub` | `p42_dup_pub/` |
| L42-2 | trait impl 方法上写 `pub` | `p42_trait_pub/` |
| L42-3 | 块级 `pub impl` | `p42_block_pub/` |
| L42-4 | 跨单元调用私有实例方法 | `p42_private_call/` |
| L42-5 | 跨单元调用私有静态方法 | `p42_private_static/` |
| L42-6 | 保留名之外、由生成代码按名调用的方法被标私有 | `p42_reserved_name/` |

### 6.1 迁移清单（S0 冻结）

```sh
# lib/std 的 impl 方法数（当前实测 43：Vec 22 / Result 11 / Option 8 / Str 2）
python3 - <<'EOF'
import re, glob
for f in sorted(glob.glob('lib/std/*.h.ct')):
    inside, n = False, 0
    for line in open(f):
        if re.match(r'^(pub )?impl\b', line): inside = True; continue
        if inside and re.match(r'^}\s*$', line): inside = False; continue
        if inside and re.match(r'^    (?:static )?\S.*\(', line): n += 1
    print(f, n)
EOF
```

S0 用同一脚本冻结 `test/modules/p42_visibility/migration.list`：42 条待加 `pub` + 10 条保留名（`retain` / `release` / `drop` / `handback`）。

## 7 风险与开放项

| 编号 | 风险 | 触发信号 / 处置 |
| --- | --- | --- |
| R42-1 | 迁移漏标导致自举链红 | 先 R5a 后 R5b；R5a 的验收就是「行为零变化」，R5b 才切换判定 |
| R42-2 | 模板 foreign-element 实例被误当「不发射」 | D42-7：副本仍发射、恒 `static`；E42-7 专测 |
| R42-3 | 保留名漏豁免，`__elem_retain` 链接失败 | D42-6 + E42-5 计数；`p41` 的容器夹具连带跑 |
| R42-4 | 消费方仍能解析到私有方法，落到 implicit declaration | 解析期硬错（D42-2 第三段），E42-3 两条负例 |
| R42-5 | header-diff 漂移被误当作无关差异 | E42-6 的 sha256 比较；差异必须逐行解释 |
| R42-6 | `use Drop` 的 `drop` 被误判私有 | D42-8：trait impl 与内置 trait 不参与方法级判定 |
| R42-7 | 与 PH-41 同改 `Emitter.h.ct`，冲突面大 | 串行（41 → 42）；R1/R4 只动解析器，可在 41 收口前先落 |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T42-1 | 字段级可见性（`pub` 字段 / 只读字段） | 有包需要「结构公开、字段私有」 |
| T42-2 | 块级 `pub impl`（本相否掉的备选） | 出现整块公开的真实诉求，且能说清与 trait impl 的关系 |
| T42-3 | 包内可见（`pub(pkg)` 一类） | ct-pkg 多单元协作提出稳定需求 |
| T42-4 | 迁移工具 / lint（提示「该方法无调用方且未 `pub`」） | 迁移量再次超过 100 条 |

## 8 估算与收口

- 编译器 320–560 = R1 50–90 + R2 60–110 + R3 50–90 + R4 60–110 + R5b 40–80 + R9 30–60（R7 夹具 20–40 计入夹具）；迁移 80–150 = R5a 50–90 + R6 30–60；夹具 140–230；文档 50–90。
- 开工前 S0：PH-41 收口提交上重建 `ct`（`ct -v` = v0.41.0）、复跑 §2.2、生成 `header.list` / `migration.list` / `header-manifest.sha`、写 §2.1；不占任务行。
- 收口动作：11 道门禁绿、`p42/*` 全绿、`version-minor=42`、五处 `CTC_VERSION` 与全部版本落点同步到 `v0.42.0`、phase-log 与对照表落盘；tag/push 按 0.3 等用户批准。
- 每个实现任务 ≤3 个源码文件；每个实现提交的父提交是它的 `test(visibility): <task-id> 红`；仓库任何时刻可构建。
- 文档修正说明：`pub` 可见性表述的既有漂移已由另一会话的提交 `ec806f59` 覆盖（`docs/` 三处），**不重复排期**；本卡 R8 只补「方法级 `pub` / 默认私有」的新语法与迁移说明。实施 R8 前先确认那些文件已在主干落定，避免与在途改动冲突。
