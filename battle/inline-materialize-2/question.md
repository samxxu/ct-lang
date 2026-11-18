# battle/inline-materialize-2 — `$name` 最小可实现方案

| 字段 | 值 |
| --- | --- |
| 争点 | 在“inline 物化需求已由用户确认”的前提下，选择安全可实现的方案 |
| 当前 HEAD | `0c449d2e`（v0.67.0；Phase 68/69 已收口；SH-73 有意限制） |
| 触发理由 | 用户已确认 inline 物化需求；本场只评“最小可实现方案”，不重新争论是否值得 |
| 前置结论 | `battle/inline-materialize-1` 否定的是“无边界 `$name`”，不是需求本身 |
| proposer | REQ（主张 A：最小 `$name`） |
| opposition | REVIEW（主张 B：不做语法，拆链/into；或要求更强证据） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/language-spec.md`、`docs/design/**`；只写 `battle/inline-materialize-2/` 与 `/tmp` |

## 方案 A（最小 `$name`）

```ct
HttpRequest req = init();          /* 已声明、已初始化 */
"...".method("GET")$req.header(...).send();
```

规则：

1. `$name` 只允许出现在**方法调用之后**，链中；链尾不允许。
2. `name` 必须**已声明且已初始化**；不新建变量、不做类型推断。
3. `name` 类型必须等于该方法返回类型；`ct check --types` 报错，不在 `--types` 模式下退化为 C 编译错误。
4. 方法调用只求值一次；结果赋给 `name`；链继续以 `name` 为接收者。
5. 不支持 `?.m()$x`（L53-7 未实现）；不支持 `own` 目标；不支持声明形态 `T x = ...$x`。
6. 不改变所有权/生命周期；`name` 是普通变量，赋值规则与普通赋值一致。
7. 不要求 SH-73 先修；`name` 是变量接收者，可能绕过 SH-73，但本方案不宣称修复它。
8. 同一链可多次物化；重复变量按顺序覆盖；不允许链尾物化。

## 方案 B（不做新语法）

1. 用两行拆链：
   ```ct
   HttpRequest req = "...".method("GET");
   req.header(...).send();
   ```
2. 兄弟方法用 `a into { .m(); .n(); }`；
3. `$` 不再增加第 4 义项；零 lexer/parser 风险；
4. 若认为两行不可接受，先补真实外部语料，再另立提案。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 语义闭合：单次求值、赋值、链续、多次、链尾、无 `?.`、无 `own` | 探针 + 反例 |
| J-2 | 类型闭合：已声明/已初始化、返回类型匹配、`--types` 负例、无推断 | 类型夹具 |
| J-3 | 语法闭合：`$` 第 4 义项与 range/into/errdefer/标识符的边界；lexer/parser 分支 | parser 夹具 |
| J-4 | 所有权/生命周期：接口值/结构体/指针赋值，是否复制/悬挂；不自动释放 | ASan/语义矩阵 |
| J-5 | SH-73 关系：是否误称修复；variable receiver 是否可绕过；文档必须写清 | 探针 + 文档 |
| J-6 | 成本/回归：4 个源文件、测试、golden、与 `into` 的职责边界 | 行数估算 |

## 证据要求

按 §7.7 E1–E5。重点：
- `$` 现有义项（spec §4.47/§4.52/§4.58）与 lexer/parser 现状；
- `into` 能/不能做什么；
- SH-73 当前行为；
- A 的最小原型是否可在当前 emitter/hoist 上实现；
- 是否能写出不依赖 definite-assignment 的“已初始化”负例。
