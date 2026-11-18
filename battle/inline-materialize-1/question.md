# battle/inline-materialize-1 — 链中 inline 物化 `$name`

| 字段 | 值 |
| --- | --- |
| 争点 | 是否给方法链增加 `.m(args)$name`，把该跳返回值物化到已声明变量，并继续以该变量为接收者 |
| 当前 HEAD | `0c449d2e`（v0.67.0；Phase 68 已收口；SH-73 为有意限制） |
| 触发理由 | 用户认为 CT 鼓励链式，缺少 inline 物化会显得僵化；要求 battle |
| proposer | REQ（主张 A：新增 `$name`） |
| opposition | REVIEW（主张 B：用现有拆链/into，不新增语法） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/language-spec.md`、`docs/design/**`；只写 `battle/inline-materialize-1/` 与 `/tmp` |

## 范围（必须先统一）

```ct
HttpRequest req;
"...".method("GET")$req.header(...).send();
```

语义：

1. `method("GET")` **只求值一次**；
2. 结果赋给**已声明**的 `req`；
3. 链继续以 `req` 为接收者；
4. 不改变所有权/生命周期规则；
5. **不**处理同一对象的兄弟方法；兄弟方法用 `a into { .m(); .n(); }`；
6. **不**要求 SH-73 先修；SH-73 仍是动态派发临时值接收者的有意限制。

## 位置 A（新增 `$name`）

1. 语法：`.m(args)$name`，只允许链中方法调用后；链尾不允许。
2. `name` 必须已声明、类型匹配；不引入新声明/类型推断。
3. 一次求值、一次赋值；后续链接收者就是 `name`。
4. 多跳可多次物化；同一变量重复出现按顺序覆盖。
5. `?.m()$x` 短路时不赋值；未初始化使用按既有检查报错。
6. 纯 desugar：`T x = <call>; x.next()`；不自动释放/不接管所有权。

## 位置 B（拒绝新增语法）

1. 现有拆链已等价：
   ```ct
   HttpRequest req = "...".method("GET");
   req.header(...).send();
   ```
2. 兄弟方法用 `into`，不是链。
3. `$` 当前不是标识符，新增 `$name` 要改 lexer/parser/上下文，成本与歧义不值。
4. 链式鼓励不等于必须内联物化；两行写法清楚且零语言改动。
5. 若一定要内联，先证明两行写法在真实代码中造成显著负担。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 真实价值：inline 物化是否解决链式可读性/复用，而非仅少写一行 | 真实样例/字符数/维护性 |
| J-2 | 语法歧义：`$` 不是标识符，`$name` 在 range/into/errdefer/普通表达式中是否可区分 | lexer/parser 夹具 |
| J-3 | 类型/所有权：已声明变量、接口复制、`?.` 短路、多次物化、未初始化 | 语义矩阵 |
| J-4 | SH-73 关系：是否真的独立；是否会误导为“修了链式” | 探针/文档 |
| J-5 | 实现成本：lexer/parser/type/emit/诊断/测试 | 文件/行数/阶段 |
| J-6 | 兼容/回退：现有代码、golden、`into`、两行写法 | 全量门禁 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点核：
- `language-spec` §4.52（into 语法与限制）、§4.47/§4.58（`$` 的既有义项）、SH-73；
- `examples/29_into_block`、`test/ast/152_into_trait_method`、`test/ast/155_into_value_host`；
- 当前 `$` 词法/parser 是否已有 `$ident` 路径。
