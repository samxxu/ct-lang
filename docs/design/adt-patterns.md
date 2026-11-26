# ADT 模式 A/B：字面量 / 嵌套 / 结构体 / or / 守卫（v1-PH-2 S4–S5）

> 状态：**实现设计（2026-11-27）**。对应 [REQ-ADT-PATTERN-1](../planning/requirements-pool.md#req-adt-pattern-1--adt-模式扩展字面量--嵌套--结构体--or--守卫--泛型-adt) 的前两段、
> [v1-PH-2](../phases/v1-PH-2/card.md) 的 S4–S5。S6（泛型 ADT）不在本设计内。
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
| or 模式 `A | B` | S5 | 任何模式位置；DNF 条件组，见 §9 |
| 指针负载上的模式 | 不做 | 负载字段类型为指针时，只能 `_` 或绑定整个值 |
| 守卫 `pattern if expr` | S5 | 见 §9；守卫可读模式绑定 |

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

- S4 只扩展模式文法与穷尽框架，不引入 or / 守卫；`A | B` 与 `if` 守卫在 S5 补齐（§9）。
- 字符串字面量模式不在本轮：现有 `Str` / `String` 没有 `==`，需要运行期比较入口，属
  REQ-ADT-PATTERN-1 的后续切面。
- 嵌套模式的穷尽是**保守**判定：可反驳的嵌套 arm 不计入覆盖；写 `_` 永远安全。
- 非 ADT 主语只在语句 `match` 开放；表达式 `match` 仍要求 ADT 主语，避免把 `match` 变成
  通用 `switch` 表达式（S5 再评估）。
- 模式不穿透指针负载；`T { p: T2 { … } }` 里的 `T2` 必须是值字段。

## 9 S5：or 模式与守卫（`v1-PH-2` S5）

### 9.1 文法

```
pattern      := or-pattern
or-pattern   := pattern-atom ('|' pattern-atom)*
pattern-atom := '_' | binder | literal | variant-pattern | struct-pattern
arm          := pattern ('if' expr)? '=>' block        // statement match
              | pattern ('if' expr)? '=>' expr         // expression match
```

- `|` 可以出现在任何模式位置，包括变体负载与结构体字段里
  （`Some(A.X(n) | A.Y(n))`、`Point { x: 0 | 1, .. }`）。
- 守卫是 arm 级的：`pattern if guard => …`。守卫表达式与 `if` 语句的条件同语法，
  在模式匹配成功后才求值（C 的 `&&` 短路保证）。

### 9.2 条件与绑定

- 解析期把整个 arm 的模式展开成 **DNF 条件组**：每个 `|` 复制当前组集合，
  组内测试按 AND 累加。运行期条件是各组的 OR。
- **绑定一致性**：同一 arm 的所有 DNF 组必须绑定**同名集合**且每个名字的**类型相同**；
  否则是硬错。`A(r) | B(w, h)` 因此不合法（`r` 在另一组里缺失）。
- 同名绑定在不同组里可以走不同的访问路径（`Circle(r) | Square(r)`）：只要类型是
  整数族，发射器按组条件选择访问器（`(tag==0) ? ….Circle.r : (tag==1) ? ….Square.s : …`）。
  非整数族（owning / 结构体 / 指针）在路径不同时是硬错，避免浅拷贝。
- 绑定是 arm 块内的普通局部量；守卫与 arm 体都能读它。

### 9.3 穷尽算法（S5 扩展）

在 S4 的“不可反驳根模式才计数”之上：

1. **or 分支逐支计数**：一个 `A | B` arm 对每个“不可反驳的变体根”分支分别标记
   `covered[v]`；两支同名变体是 `duplicate match arm for variant`。
2. **守卫 arm 不计入穷尽**：带守卫的 arm 不标记 `covered`，也不构成 catch-all；
   `_ if cond` 不是兜底。缺分支时若只有守卫 arm 提过该变体，诊断改为
   `match does not cover variant '…' (a guarded arm does not count as coverage; …)`。
3. **非 ADT 主语**：仍需一个**无守卫**的 `_` / 根绑定兜底；只有守卫 catch-all 时报
   `match on '…' needs a final unguarded '_ => { … }' arm (a guarded arm does not count as coverage)`。
4. **嵌套仍是保守判定**：嵌套的变体/结构体/字面量子模式（含 `Some(X(n) | Y(n))`）
   即使覆盖了内部全部变体，也不使根变成不可反驳；仍要 `_` 或根兜底。这是 S4 口径
   的延续，S6 的泛型 ADT 也不改它。
5. **重复模式**：带守卫的 arm 之间允许逐字相同的模式（不同守卫）；`_` 末位规则与
   `_` 唯一规则不变。守卫 arm 不参与“完整模式重复”的比较。

### 9.4 诊断（S5 新增）

| 场景 | 文本 |
| --- | --- |
| or 两组名字集合不同 | `or-pattern alternatives bind different names ('<n>' is missing)` |
| 同名不同类型 | `or-pattern alternatives bind '<n>' as different types ('<T1>' and '<T2>')` |
| 非整数族跨路径绑定 | `an or-pattern cannot bind '<n>' of type '<T>' at different offsets (S5: integer payloads only)` |
| 守卫 arm 的变体缺口 | `match does not cover variant '<A>.<V>' (a guarded arm does not count as coverage; add an unguarded arm or write '_ => { … }')` |
| 非 ADT 守卫兜底 | `match on '<T>' needs a final unguarded '_ => { … }' arm (a guarded arm does not count as coverage)` |

位置都在 arm 的模式起始 token；漏分支在 `match` 关键字处（沿用 §4.73）。

### 9.5 发射形态

**无守卫**（含纯 or-pattern）沿用 if/else 链，最后一支仍是 `else`：

```
if (__ct_match0.tag == 0 && ((__ct_match0.u.Circle.r == 0) || (__ct_match0.u.Square.s == 0))) { … }
else if (__ct_match0.tag == 1) { … }
else { … }
```

or-pattern 的组条件是 `(组0) || (组1)`；跨变体时每组自带 `.tag=<v>` 行，
`arm.num = -1`。同名整数绑定的访问器是条件表达式（见 §9.2）。

**有守卫**时整个 match 换成 flag 形状，因为守卫失败要落到下一支：

```
int __ct_matched0 = 0;
if (!__ct_matched0 && (__ct_match0.tag == 0)) {
    int r = __ct_match0.u.Circle.r;        // 绑定先于守卫
    if (r > limit) { __ct_matched0 = 1; { … } }
}
if (!__ct_matched0 && (__ct_match0.tag == 1)) { … }
…
```

- `__ct_matchedN` 保证只执行一支；守卫在绑定声明之后求值。
- 绑定在 arm 的包裹块结束时释放（守卫为假也释放），与普通局部量一致。
- 已知 C 形态边界：语句 `match` 的**最后一支**不能写 `else`（守卫失败要能落到
  下一支），因此穷尽但所有 arm 都 `return` 的函数若 match 是函数最后一条语句，
  C 编译器会报 `-Wreturn-type`；在 match 之后补一条 `return` 即可。表达式
  `match` 不受影响（`return match (…)` 本身无条件返回）。

### 9.6 AST / TIR / LIR 映射

- **AST**：`N_ARM.text4` 是 `|` 分组的条件串（单组时与 S4 逐字节相同）；
  `N_ARM.d` 改为守卫表达式 id（-1 = 无守卫，模式描述树仍是解析期临时物）；
  绑定行的 `text4` 为 `?g:path,g:path,…` 时表示按组选择访问器。
- **TIR**：`TS_ARM.text2` 继续携带条件串；新增 `TS_ARM.guard`（守卫表达式 id，
  0 = 无）。`TS_ARM.text` 的绑定路径可以带 `?g:path,…`（`;` 仍是绑定分隔符）。
- **LIR**：or-pattern 的条件组与“按组选访问器”需要 flag 形状/条件访问器，
  S5 的 LIR 切片不复制这两者：lowering 见到 `arm->guard >= 0` 或条件串含 `|`
  即把该函数标为未覆盖（`L7822` / `L7832`），整函数回退到 AST body seam。
  `--ir=on` 因此仍与 AST 路径逐字节一致；这是 S5 的诚实边界，S8 的 emitter
  契约再决定是否把该形状下沉到 LIR。

### 9.7 S5 边界（诚实登记）

- 守卫可读绑定；但守卫里**不能**用 `?`（在条件里提前返回）——与 `if` 条件同规则。
- 嵌套 or/变体的穷尽仍是保守判定（§9.3 第 4 条）。
- 字符串字面量模式、指针负载模式仍不做（同 S4）。
- 跨变体的非整数绑定（owning / 结构体）不做（§9.2）。
- LIR 的 or/守卫打印回退到 AST body seam（§9.6）。
