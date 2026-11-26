# ADT 模式 A：字面量 / 嵌套 / 结构体（v1-PH-2 S4）

> 状态：**实现设计（2026-11-27）**。对应 [REQ-ADT-PATTERN-1](../planning/requirements-pool.md#req-adt-pattern-1--adt-模式扩展字面量--嵌套--结构体--or--守卫--泛型-adt) 的第一段、
> [v1-PH-2](../phases/v1-PH-2/card.md) 的 S4。S5（or / 守卫）与 S6（泛型 ADT）不在本设计内。
> 语言口径落在 [spec §4.73](../language-spec.md#473-最小-adt-与-matchphase-84仅-ct-ast)。

## 1 范围

| 模式 | S4 是否做 | 说明 |
| --- | --- | --- |
| `_` 通配 | 已有 | 位置不变：全局最后一个 arm，只能一个 |
| 变体模式 `T.V(p, …)` | 已有，本轮允许**嵌套** | 每个负载位置必须是模式；参数个数必须等于负载字段数 |
| 绑定模式 `name` / 结构体字段简写 | 新增 | 绑定整个位置；名字在同一 arm 内不得重复 |
| 整数字面量 `0` / `-1`… | 新增 | 只用于整数族位置（`int` / `char` / `bool` / `short` / `long` / 定宽整数） |
| 字符字面量 `'a'` | 新增 | 按整数值比较；转义按 C 单字符 |
| 字符串字面量 `"k"` | **不做** | 现有类型面无字符串相等；S4 遇到即硬错，不静默降级 |
| 结构体模式 `T { f: p, g, .. }` | 新增 | 字段可显式给模式，也可简写为同名字段绑定；`..` 表示余下字段 |
| 顶层标量/结构体主语 | 新增（仅语句 `match`） | `match (n) { 0 => …  _ => … }`、`match (p) { Point { x: 0, .. } => … }` |
| 表达式 `match` | 仍限 ADT 主语 | 嵌套/字面量/结构体子模式在 ADT 负载里可用；表达式形式本身不扩主语 |
| or 模式、守卫 | S5 | 本轮不解析 |
| 指针负载上的模式 | 不做 | 负载字段类型为指针时，只能 `_` 或绑定整个值 |

## 2 文法

```
arm          := '_' '=>' block
              | pattern '=>' block
pattern      := '_' | binder | literal | variant-pattern | struct-pattern
binder       := IDENT
literal      := INT | CHAR
variant-pattern := type-name '.' variant-name '(' pattern (',' pattern)* ')'
struct-pattern  := type-name '{' field-pattern (',' field-pattern)* ','? '}'
                 | type-name '{' '..' '}'
field-pattern   := IDENT ':' pattern | IDENT | '..'
```

- 顶层 `pattern` 的类型由主语决定：ADT 主语只接受 `T.V(…)`、`_`、整值绑定；结构体主语接受
  `T { … }`、`_`、绑定；整数族主语接受字面量、`_`、绑定。
- 嵌套位置的类型由负载字段 / 结构体字段决定；类型不符在解析期报硬错。
- `..` 只能在结构体模式里出现一次，且必须是最后一个字段。
- 字段简写 `T { x }` 等价于 `T { x: x }`，绑定名就是字段名。

## 3 语义

- **匹配顺序**：arm 自上而下，第一个匹配的 arm 执行；不存在 fallthrough。
- **绑定**：绑定是 arm 块内的普通局部量，类型是所在位置的类型，按值复制。嵌套变体/结构体
  内部的绑定取其字段路径的副本；owning 负载仍按 retain 副本（与 §4.73 既有规则一致）。
- **字面量比较**：整数族位置按值比较；`bool` 用 `0` / `1`；`char` 用其整数值。
- **结构体模式**：先按主语/字段的静态类型判定（解析期），运行期只比较显式字面量字段；
  未写 `..` 且未列全字段是硬错，未知字段、重复字段也是硬错。
- **类型检查**：解析期完成；运行期不再有 tag 之外的额外分派。

## 4 穷尽性算法（S4）

对每个 arm 计算一个**可反驳性**标记：

```
irrefutable(pattern, T):
  _ / binder                       -> true
  literal                          -> false
  T.V(p1..pn)                      -> 全部 pi 对负载字段类型不可反驳
  T { f1: p1, .. } / T { f1: p1, … 列全 } -> 全部 pi 不可反驳（列全或带 `..`）
```

- **ADT 主语**：变体 `v` 被覆盖，当且仅当存在一个 arm，其根是 `v` 且该根模式对 `v` 不可反驳；
  或存在最后一个 `_` / 根绑定（捕获全部）。仅 `T.V(0)` 这类可反驳 arm **不**计入覆盖，
  但运行期仍可命中。
- **结构体主语**：带 `..` 或列全字段且所有子模式不可反驳的根结构体模式覆盖全部值；否则必须
  有 `_` / 根绑定兜底。
- **整数族主语**：有限字面量不构成穷尽，必须写 `_` / 根绑定。
- **`_` 与根绑定**：都是“捕获全部”，必须写在最后一个 arm；`_` 只能一个。根绑定是普通绑定
  （会生成变量），不可省略。
- **重复**：同一 arm 列表里，同一变体的两个“不可反驳根”是重复（沿用
  `duplicate match arm for variant 'T.V'`）；逐字相同的完整模式（规范签名相等）是
  `duplicate match arm pattern '<sig>'`；同一 arm 内同名绑定是
  `duplicate binding '<name>' in a match arm`。

## 5 诊断文本（S4 新增，均为 `file:line:col: error:`）

| 场景 | 文本 |
| --- | --- |
| 主语类型不支持 | `match needs an ADT, struct, or integer-like value, but '<T>' is not supported` |
| 空模式 / 意外 token | `expected a pattern` |
| 变体模式的类型不是 ADT | `match arm names '<X>', which is not an ADT` |
| 变体模式跨 ADT | `match arm names ADT '<A>', but the subject is '<B>'` |
| 未知变体 | `unknown variant '<V>' of ADT '<A>'` |
| 负载个数不符 | `match arm for '<A>.<V>' binds <m> name(s), but the variant has <n> field(s)` |
| 字面量落在非整数族 | `literal pattern '<lit>' does not match type '<T>'` |
| 字符串字面量 | `string literal patterns are not supported (S4: int/char/bool only)` |
| 结构体名未知 | `struct pattern names '<X>', which is not a declared struct` |
| 结构体模式跨类型 | `struct pattern names '<S>', but the subject is '<T>'` |
| 未知字段 | `unknown field '<f>' in a struct pattern for '<S>'` |
| 重复字段 | `duplicate field '<f>' in a struct pattern` |
| 漏字段（无 `..`） | `struct pattern for '<S>' is missing field '<f>' (name it or write '..')` |
| 指针负载 | `a pointer payload cannot be matched by a pattern (use '_' or bind the whole value)` |
| 整数族/结构体缺兜底 | `match on '<T>' needs a final '_ => { … }' arm` |
| 指针主语不是 ADT/结构体 | 复用第 1 行（`'<T>' is not supported`） |

`match does not cover variant '<A>.<V>' (add the arm or write '_ => { … }')` 与
`a wildcard match arm must be the last arm` 沿用 §4.73 的既有文本。

## 6 AST 与 LIR 映射

**AST**（`frontend/parse/StmtMatch.h.ct`）：

- `N_MATCH`：`a` 主语；`b` arm 链；`text` ADT C tag（非 ADT 主语为空）；`text2` 非 ADT 主语的
  C 类型拼写；`aux` bit0 = 指针主语，bit4 = 非 ADT 主语。
- `N_ARM`：`num` 根变体下标（–1 = 非变体）；`text/text2/text3` 变体名 / union 成员 / ADT tag；
  `a` 绑定链；`b` 块；`c` 表达式 `match` 的 yield 赋值；`d` 模式描述树根；`text4` 运行期
  条件串（`path=value;` 重复，路径以 `.` / `->` 开头、根位置为空串）；`aux` bit1 `_`、
  bit2 表达式形式、bit4 非 ADT 主语。
- 模式描述树复用 `N_BIND` 行（只挂在 `arm->d`，不参与语句/表达式遍历）：`aux` 1 变体、
  2 结构体、3 字面量、4 `_`、5 绑定、6 结构体字段；`text` 名称，`text2` 变体 union 成员 /
  结构体类型，`num` 变体下标或字面量值，`a` 子模式链，`b` 该模式是否不可反驳。
- 绑定行的 `text4` 是相对主语临时量的访问路径（`.` / `->` 开头；根绑定用空串，指针主语
  的根绑定用 `*`）。

**TIR/LIR**：

- `TS_ARM.text` 的绑定编码从 `field|name|type;` 改为 `path|name|type;`；`TS_ARM.text2`
  携带条件串。`TS_MATCH.text2` 携带非 ADT 主语的 C 类型拼写（`aux` bit4 标记）。
- `TK_MATCH_ARM` 的 arm 条件同 `TS_ARM.text2`；LIR 的 `LS_MATCH` / `LE_MATCHEXPR` 的
  arm 三元组是 `[variant, cond-expr, block]`（0 表示无额外条件）。条件表达式由
  `LE_TEMP`（匹配临时量）+ `LE_FIELD` / `LE_ARROW` + `LE_NUM` + `LE_BINARY(LB_EQ)` 组成，
  因此临时量编号在打印期才拍定。

## 7 C 发射形态

```
struct Shape __ct_match0 = (subject);
if (__ct_match0.tag == 0 && (__ct_match0.u.Circle.r == 0)) { … }
else if (__ct_match0.tag == 1) { … }
else { … }
```

- 顶层变体 tag 仍由 if/else 链判定；嵌套变体追加 `<path>.tag == k`，字面量追加
  `<path> == value`，结构体字段同理。
- 非 ADT 主语声明为 `%s __ct_matchN`（`%s` 是主语 C 类型，指针时 `%s *`），没有 tag 测试，
  条件全部来自 `arm->text4`；最后一个 arm 是 `else`。
- 绑定初始化写 `__ct_matchN` + 路径；根绑定是指针主语时写 `(*__ct_matchN)`。
- 表达式 `match` 仍是 GNU statement expression，逐字沿用 §4.73 的 `__ct_mresN` 形态。

## 8 边界与诚实登记

- S4 只扩展模式文法与穷尽框架，不引入 or / 守卫；`A | B` 与 `if` 守卫留给 S5。
- 字符串字面量模式不在本轮：现有 `Str` / `String` 没有 `==`，需要运行期比较入口，属
  REQ-ADT-PATTERN-1 的后续切面。
- 嵌套模式的穷尽是**保守**判定：可反驳的嵌套 arm 不计入覆盖；写 `_` 永远安全。
- 非 ADT 主语只在语句 `match` 开放；表达式 `match` 仍要求 ADT 主语，避免把 `match` 变成
  通用 `switch` 表达式（S5 再评估）。
- 模式不穿透指针负载；`T { p: T2 { … } }` 里的 `T2` 必须是值字段。
