# Phase 53 — 可选链 `?.`（指针 / map；值上取到的指针或 map 跳）

> **状态：完成（2026-11-15；v0.53.0；S1–S6 全绿）**
> **归属**：本仓库维护规格与判据；实现由外部 harness 交付（[手册](phase46-52-handoff.md)）。
> **基线**：PH-52 收口提交 `43b8c992`（`v0.52.0`）。
> **规模**：250–450 行（估；按 PH-52 的 250–470 行量级校准，S0 核对后回填）。
> **版本**：`v0.53.0`；`version-minor: 53`。
> **依据**：[第二轮 battle](../reviews/phase53-optional-chain-battle.md)、
> [设计记录](../proposals/phase53-optional-chain-draft.md)、[立项草案](../proposals/phase53-scope-draft.md)。

## 0 一句话目标

把 `p?.f`、`a.b?.c`、`m["k"]?.c`、`p?[i]`、`m?["k"]` 在编译期展开成短路三目；
缺失结果 `0`/NULL；接收者只求值一次；struct 值接收者硬错；不引入新运行时、不改 ABI。

## 1 本卡做 / 本卡不做

| 做 | 不做 |
| --- | --- |
| 指针接收者字段：`p?.f` → `(p ? p->f : 0)` | `T?` / `Maybe<T>` / 任何新的可空类型 |
| 值上取到的指针：`a.b?.c` → 临时量 + `(t ? t->c : 0)` | struct 值接收者（`a?.b`，`a` 为值） |
| map 值类型：`m["k"]?.c` → 单次 `get` + 判空 | 可选方法调用 `a?.m()`（接收者求值次数未定义） |
| 指针下标：`p?[i]` → `(p ? p[i] : 0)` | struct 值结果（字段/元素为 struct/union/Drop 类型） |
| map 指针下标：`m?["k"]` → `(m ? m->get(k) : 0)` | 赋值/取址：`p?.b = 1`、`&p?.b`、`p?[i] = x` |
| 链式短路：`a?.b?.c`、`m["a"]?.b?.c` | 用户类型 `get` 的指针接收者协议扩展 |
| `c?.5 : 1.0` 保持三目（切词策略） | 新的 `.expected.c` golden（本卡不建） |

## 2 前置依赖

PH-44（后缀 `?` 与三目消歧）、PH-51（`.` 作用于指针接收者）、PH-52（`[]` 与 `Map` 透传）、
PH-50（`Map::get` 返回 `V*`）。无新运行时依赖。

## 3 现状（实测，`ct v0.44.1`）

```text
# T1: c?.5 : 1.0
ct_rc=0
generated: double d = (c ? .5 : 1.0);
run_rc=0

# N1: a?.b，a 为 struct 值
ct_rc=1
error: '?' needs a Result operand
no .c

# P1: a.b?.c，b 为 struct B *
ct_rc=1
error: '?' needs a Result operand
no .c          # ?. 尚未实现，正例当前走不通

# P2: a.m["k"]?.c，m 为 Map<char *, B >*
ct_rc=1
error: '?' needs a Result operand
no .c
```

同一语义用显式三目今天可编译运行：`a.b ? a.b->c : 0`（输出 `present=7 missing=0`）；
`Map<char *, B>` 的 `get` + 三目同样 rc=0。**缺的是 `?.` 语法、接收者判定与单次求值，不是类型能力。**

代码锚点：`.5` 整体扫成 `T_NUM`（`selfhost/ct-ast/frontend/lex/Lexer.h.ct:244-271`）；
`?` 走单字符 `T_PUNCT`（`:356`）；后缀 `?` 诊断在 `Expr.h.ct:6414-6421`、
`Emitter.h.ct:4786-4791`。S0 核对后按实际行号回填。

## 4 语义（冻结）

### 4.1 适用类型

| 形态 | 接收者 | 结果 | 展开 |
| --- | --- | --- | --- |
| `p?.f` | `T *` | 字段类型（指针/标量） | `(p ? p->f : 0)`；`p` 是简单标识符时不落临时量 |
| `a.b?.c` | `B *`（值上取到的指针字段） | 字段类型（指针/标量） | `((t = a.b) ? t->c : 0)` |
| `f()?.b` | 调用返回的指针 | 字段类型（指针/标量） | `((t = f()) ? t->b : 0)` |
| `m["k"]?.c` | `V *`（`Map<K, V>`，`V` 为值类型） | 字段类型（指针/标量） | `((t = m.get(k)) ? t->c : 0)`；`get` 只一次 |
| `p?[i]` | `T *` | 元素类型（指针/标量） | `(p ? p[i] : 0)` |
| `m?["k"]` | `Map<K, V> *` | `V *` | `(m ? m->get(k) : 0)` |
| `a.b?[i]` / `a.m?["k"]` | 值上取到的指针 | 同上 | 先落临时量，再按上两行展开 |
| `a?.b?.c` | 每跳都必须是上表接收者 | 最后一跳的指针/标量 | 嵌套三目；前跳失败时后续不求值 |

`Map<K, V>` 的 `V` 必须是值类型。`V` 为指针时 `get` 返回 `V**`，`m["k"]?.c` 不成立（L53-5）。

### 4.2 求值次数与短路

- 接收者表达式只求值一次：简单标识符直接使用；其余（字段链、调用、map 查找）先落隐藏临时量。
- 临时量在所属块声明，名字由发射器生成，保证不冲突；不使用运行时 helper、不使用语句表达式扩展。
- 赋值放在三目的真分支：`((t = recv) ? t->f : 0)`；前跳为 0 时后续字段、下标、`get` 都不求值。
- `a?.b.c` 只保护 `a`；`b` 为空仍会按普通 `.` 语义处理，需要保护时写 `a?.b?.c`。
- `p?[i]` 的 `i` 在 `p` 为 0 时不求值（三目保证）。
- `m["k"]?.c` 的 `get` 只调用一次；`m?["k"]` 的 `get` 在 `m` 为 0 时不调用。

### 4.3 结果与 NULL

| 结果类型 | 缺失值 | 说明 |
| --- | --- | --- |
| 指针 / 函数指针 | `0`（NULL） | 与 `Map::get` 对齐 |
| 整数 / 浮点 / 枚举 / bool | `0` | 标量 0 与合法 0 不可区分；调用方需知道字段可缺 |
| 数组字段 | 退化为指针，`0` | 仅当 C 语义允许退化 |
| struct / union / 含 Drop 的值 | **拒绝** | 无 NULL 表示；浅拷贝会双释放（battle §1） |

本卡不引入 `Option`/`T?`；标量 0 的歧义是接受的 C 风格限制，不在本卡修。

### 4.4 拒绝规则与诊断（冻结文案）

| ID | 触发 | 文案（逐字；`<type>` 为实际类型名） |
| --- | --- | --- |
| L53-1 | `a?.b`，`a` 为 struct 值 | `optional chain '?.' requires a pointer receiver; a struct value has no empty state` |
| L53-2 | `a?["k"]` / `a?[i]`，`a` 为 struct 值 | `optional subscript '?[' requires a pointer receiver; a struct value has no empty state` |
| L53-3 | `p?.f` 的 `f` 为 struct/union/Drop 值 | `optional chain result must be a pointer or scalar; '<type>' has no NULL representation` |
| L53-4 | `p?[i]` 的元素为 struct/union/Drop 值 | `optional subscript result must be a pointer or scalar; '<type>' has no NULL representation` |
| L53-5 | `m["k"]?.c` 的 `V` 为指针（`get` 返回 `V**`） | `optional chain on a map lookup requires a value-typed V; got pointer value type; use a map of values or guard the inner pointer` |
| L53-6 | `p?.b = 1`、`&p?.b`、`p?[i] = x` | `optional chain/subscript is not an lvalue; it cannot be assigned or address-taken` |
| L53-7 | `p?.m()` / `p?[i].m()`（可选方法调用） | `optional method calls are not supported; assign the receiver to a variable first` |

诊断一律 `rc=1`、不落 `.c`；夹具按 `file:line:col` + 文案逐字比对，`<type>` 用正则前缀。

### 4.5 切词（冻结策略）

不在词法层合成 `?.` token；`?` 仍是 `?`。parser 在后缀位置看 `?` 的下一个 token：

| `?` 后 | 判定 | 用例 |
| --- | --- | --- |
| `T_NUM` 且文本以 `.` 开头 | 三目 + 浮点字面量，**不消费** | `c?.5 : 1.0` → `(c ? .5 : 1.0)` |
| `T_PUNCT "."`，再下一个是 `T_ID` | 可选链字段 | `a?.b` |
| `T_PUNCT "["` | 可选下标 | `p?[i]`、`m?["k"]` |
| 其他 | 维持 PH-44 的后缀 `?` | `x?;`、`a ? b : c` |

- `a?.5` 不完整三目 → 语法错误，不得识别为可选链。
- 不改 `Lexer.h.ct:244-271` 的 `.5` 扫描，不改 `?` 的单字符兜底。
- 词法 token 数不变；`?.` 与 `?[` 都是 parser 层组合。

### 4.6 `?[` 的同一套语义

- 只给**已有下标形态**加可选性：C 指针 `p[i]`、`Map*` 的 `m->get(k)`；不把用户类型 `get` 协议扩到指针接收者。
- `p?[i]` 与 `p?.f` 共用：`p` 0 → `0`；接收者只求值一次；结果限制同 §4.3；赋值/取址 L53-6。
- `m?["k"]` 的 `m` 必须是 `Map*`；`Map` 值接收者走 L53-2（改用 `m["k"]?.c`）。
- `p?[i]?.c`：先按 `p?[i]` 得到指针/标量，再按 `?.` 规则；中间结果落临时量。

## 5 任务切分

| 片 | 交付物 | 验收命令 | 提交 | 可单独回滚 | effort |
| --- | --- | --- | --- | --- | --- |
| S0 | 核对 `Lexer` / `Expr` / `Emitter` 锚点；确认 `?` 后缀分支、`.` 指针接收者、`Map::get` 返回 `V*`；复跑 T1/N1/P1/P2 基线 | §3 四条命令逐条复跑并记输出 | 无提交 | 无需回滚 | 0.5d |
| S1 | 新夹具与 `test/ast/p53_optional.sh`；按 T-7 产出红证（N/P 全红，T1 保持绿） | `bash test/ast/p53_optional.sh <ct-ast>`；红证含 `baseline: 43b8c992`、原始输出、rc | `test(ct-ast): PH-53 红`（只含夹具/脚本/红证） | `git revert <sha>` | 1d |
| S2 | parser 组合识别 `?.` / `?[`；接收者分类；L53-1/L53-2/L53-7 | E53-8/E53-9/E53-10/E53-15 | `feat(ct-ast): PH-53 S2 切词与接收者判定`（≤150 行） | `git revert <sha>` | 1.5d |
| S3 | `?.` 字段链：指针、值上取到的指针、调用返回指针；临时量/单次求值；L53-3/L53-6；T1 回归 | E53-1/E53-2/E53-7/E53-11/E53-14 | `feat(ct-ast): PH-53 S3 字段可选链`（≤150 行） | `git revert <sha>` | 2d |
| S4 | map 链：`m["k"]?.c` 单次 `get`；`m?["k"]`；`V` 为指针 → L53-5；链式短路 | E53-3/E53-4/E53-6/E53-13 | `feat(ct-ast): PH-53 S4 map 可选链`（≤150 行） | `git revert <sha>` | 1.5d |
| S5 | `?[`：指针下标、map 指针下标、值上取到的指针；L53-4；与 `?.` 组合 | E53-5/E53-12/E53-14 | `feat(ct-ast): PH-53 S5 可选下标`（≤150 行） | `git revert <sha>` | 1d |
| S6 | 卡面 §10 收口记录、版本落点、README、golden 核对 | E53-16 | `docs+version: PH-53 收口`（§10） | 单独回滚会破坏版本；按 §9 回滚 | 0.5d |

T-7：S1 红提交是 S2–S5 的祖先；每片提交正文复述 `baseline`、命令、原始输出与 `red: rc=...`。
纯文档/版本片 S6 不需红证，但必须在提交正文写 `no-test: 版本与收口记录` 并经评审签字。

## 6 验收判据

| ID | 命令 / 比对 | 通过条件 | 失败条件 |
| --- | --- | --- | --- |
| E53-1 | `p53_ptr_field`：`S *p`，`p` 有效/`0` | 生成 C 含 `(p ? p->b : 0)`；运行输出 `present=7 missing=0` | 出现 `p->b` 未判空，或值错 |
| E53-2 | `p53_field_ptr`：`a.b?.c`，`a` 为值、`b` 为指针 | 生成 C 含临时量与 `t ? t->c : 0`；运行 `7`/`0` | 接收者求值两次或值错 |
| E53-3 | `p53_map_value`：`m["k"]?.c`，`Map<char *, B>` | 生成 C 中 `get` **调用**只出现一次（不含声明/定义）；存在 `7`、缺失 `0` | `get` 调用两次或缺失崩 |
| E53-4 | `p53_map_ptr_sub`：`m?["k"]`，`Map<char *, B> *` | 生成 `(m ? m->get(k) : 0)`；`m=0`、缺键均 `0`；存在取到 `B*` | 未判空或键错 |
| E53-5 | `p53_ptr_sub`：`p?[i]` | 生成 `(p ? p[i] : 0)`；`p=0` 为 `0`，有效取值 | 未判空或求值越界 |
| E53-6 | `p53_chain`：`m["a"]?.b?.c`，键缺失/中间指针空/全存在 | 缺失与中间空均为 `0`；全存在取到值；后续 `get` 未执行 | 空指针解引用或提前求值 |
| E53-7 | `p53_eval_once`：`f()?.b`，`f` 计数 | 生成 C 只调用一次 `f`；计数 `1` | 计数 `2` |
| E53-8 | `p53_ternary_dot5`：`c?.5 : 1.0`，`c=1`/`c=0` | `ct` rc=0；生成含 `(c ? .5 : 1.0)`；两分支正确 | `.5` 被切开或走可选链 |
| E53-9 | `errors/p53_value_receiver.ct` | rc=1；无 `.c`；L53-1 文案与 `file:line:col` 命中 | 落 `cc` 或通用 `?` 文案 |
| E53-10 | `errors/p53_value_subscript.ct` | rc=1；L53-2 命中 | 放行 |
| E53-11 | `errors/p53_struct_result.ct` | rc=1；L53-3 命中 | 生成 C 或静默 0 |
| E53-12 | `errors/p53_struct_elem.ct` | rc=1；L53-4 命中 | 生成 C 或静默 0 |
| E53-13 | `errors/p53_map_vptr.ct` | rc=1；L53-5 命中 | 把 `V**` 当 `V*` |
| E53-14 | `errors/p53_lvalue.ct` | rc=1；L53-6 命中 | 生成可赋值产物 |
| E53-15 | `errors/p53_method.ct` | rc=1；L53-7 命中 | 放行可选方法调用 |
| E53-16 | `check-goldens.sh` fixpoint；`check-ast.sh`；`check-all.sh` | 三项 rc=0；11 道硬门禁全绿；无新增 golden 漂移 | 任一失败 |

## 7 夹具与 golden 处理

- 正例放 `test/ast/p53_*`，由 `test/ast/p53_optional.sh` 统一编译、grep 生成形状、运行比对；
  **不建** `.expected.c`，避免临时量命名把 golden 钉死。
- 反例放 `test/ast/errors/p53_*.ct`，脚本按 `file:line:col` 与文案逐字检查，rc 必须为 1，且无 `.c`。
- T1 三目用例只做行为回归（生成含 `(c ? .5 : 1.0)`、两分支运行），不新增 golden。
- 既有 `test/cases/*.expected.c` 不得因本卡改动；`check-goldens.sh` 必须 fixpoint。
  若出现非预期 diff，停止并回滚该片，不得直接重生成。
- 本卡落库（文档）阶段不生成任何 golden；golden 只在 S6 核对，不新建。

## 8 范围外归属

| 项 | 归属 |
| --- | --- |
| `T?` / `Maybe<T>` / 值语义可缺失 | 不立项；若做，单独立相（battle §2） |
| struct 值接收者 `a?.b` | 本卡拒绝（L53-1） |
| struct 值结果 / Drop 字段结果 | 本卡拒绝（L53-3/L53-4） |
| 可选方法调用 `a?.m()` | 本卡拒绝（L53-7）；求值次数语义未定 |
| 赋值/取址 `p?.b = 1`、`&p?.b` | 本卡拒绝（L53-6） |
| 用户类型 `get` 的指针接收者 | PH-52 明确不做；本卡不扩 |
| `v[0]` 参数类型匹配 | [REQ-JSACCESS-1](../planning/requirements-pool.md)，不占相号 |
| 多级 JSON `v["a"]["b"]` | 包层 `JsonRef` |
| 前端 DF-1/DF-2/DF-3、B-2/SH-73、ABI 加固 | 需求池 / 后续相；不并入本卡（见 [立项草案 §8](../proposals/phase53-scope-draft.md)） |

## 9 风险与回滚

| 风险 | 信号 | 回滚 |
| --- | --- | --- |
| `?` 与 `?.`/`?[` 切词回归 | T1 或 `a?.5` 行为变化 | 回滚 S2；`?` 回落单字符 |
| 临时量命名冲突 | 生成 C 重复变量名 | 回滚 S3；改用统一唯一前缀 |
| 接收者求值两次 | E53-7 计数 `2` | 回滚 S3；所有非简单标识符强制落临时量 |
| map `get` 两次 | E53-3 的 `get` 调用计数 ≠ 1 | 回滚 S4 |
| 值结果被静默放行 | L53-3/L53-4 未命中 | 回滚 S3/S5 |
| golden 漂移 | `check-goldens` 红 | 回滚该片；逐字节核对后再决定是否重生成 |
| 与 PH-51 `.` 指针接收者冲突 | `p?.b` 发射成 `p.b` 或 `S**` | 回滚 S3；复用 PH-51 的 `.` 发射规则 |

## 10 收口记录（待填）

| 项 | 结果 |
| --- | --- |
| E53-1…E53-7 | `p53_optional.sh` 全绿：指针字段、值上指针、map 值/指针下标、`p?[i]`、链式短路、单次求值 |
| E53-8 | `c?.5 : 1.0` 仍为三目；`a?.5` 语法错误 |
| E53-9…E53-15 | 七条 L53 负例逐字命中，rc=1，无 `.c` |
| E53-16 | `check-goldens` 25/25 fixpoint；check-ast 1436/0；`check-all` 11/11 |
| 版本落点 | 五处 `CTC_VERSION` + README 两处 → `0.53.0` |
| tag | `v0.53.0` annotated tag 已建并推送 |

收口时按 V-7 在同一动作内移动版本、建 annotated tag、推 tag；分支推送仍须用户显式指令。

## 11 与 PH-53 立项草案的关系

- 本卡即立项草案 Q1 的 **B1 选项**落定：PH-53 施工主题为 `?.` 可选链。
- 原 `?.` 记录从「记录 / 待商定」转为设计依据，相号不再闲置；见
  [设计记录](../proposals/phase53-optional-chain-draft.md)。
- 草案其余候选**不进本相**：A1 前端 DF-1/2/3、A2 REQ-JSACCESS-1、A3 SH-73、A4 ABI 加固
  留在需求池或后续相候选；C1/C2/C4/C5 留治理项；C3 文档真相随本卡落库一并修正。
  具体处置表见 [立项草案 §8](../proposals/phase53-scope-draft.md)。
- 本卡不预排 PH-54；后续相由负责人另行立项。

## 12 冻结与版本

- `version-minor: 53`；收口版本 `0.53.0`，PATCH 由本相 fix 数决定，不写死。
- 不改 ABI、不新增运行时符号、不改 `lib/std` 公共 API。
- 切词规则、语义、诊断文案、E53-1…E53-16 一并冻结；中途改动按 T-6 走变更记录，不得静默放宽。
