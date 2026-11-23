# 诊断码 registry（LANG-25）

> **状态：最小实现（v1.2 子集）**。对应 [LANG-25](../../issues/lang/lang-25-diagnostic-code-registry.md)；
> 码表是唯一真相，`test/docs/check-docs.py` 会校验本文与源码里的码字面量集合一致、无重复、格式合法。
> 本文只登记**已经实现并接入**的码；未接入的诊断暂不编造码。

## 1 码制

格式：`E-<域>-<三位编号>` / `W-<域>-<三位编号>`。

| 段 | 规则 |
| --- | --- |
| 前缀 | `E` = 默认 error，`W` = 默认 warning；它是**编译/构建模式的默认严重级**，`ct check` 仍可按既有策略把同一码升为 `error`，码本身不变 |
| 域 | 大写下划线，当前为 `PARSE` / `DRIVER` / `LOWER` / `TYPE` / `TRAIT` / `NAME` / `MEM` / `LANG` |
| 编号 | `001`–`899` 为具体码；`999` 是**该域的未分类兜底**，一个域只允许一个 |
| 稳定性 | 码只追加，不重编号、不复用；删掉一条诊断时把码标 `retired` 并保留行，编号永久空缺 |

## 2 双通道契约

| 通道 | 行为 |
| --- | --- |
| 默认文本 | **逐字节不变**：不输出码（LANG-10 的快照门禁仍按原字节比较） |
| `--diag-codes` 文本 | 行尾追加 ` [<code>]`，位置、级别、消息文字都不动 |
| `--diagnostics=json` | 每条记录**必带** `"code":"<code>"`；解析错误文档与 warning 文档同名同值 |
| 共享对象 | 文本与 JSON 从同一个 `ct_diag_code_for_error()` / `ct_diag_warn_code()` 取值，禁止各自拼字符串 |

示例（同一条 warning）：

```console
$ ct-ast --diag-codes prog.ct -o /tmp/x.c
prog.ct:4: warning: potential leak: 'p' (S*) allocated but never deleted [W-MEM-001]
$ ct-ast --diagnostics=json prog.ct -o /tmp/x.c
{"warnings":[{"code":"W-MEM-001","type":"potential_leak",...}]}
```

## 3 码表

| code | 默认级别 | 含义 | 首次版本 | 样例 | 对应测试 |
| --- | --- | --- | --- | --- | --- |
| E-PARSE-001 | error | 语法结构不成立（通用 token 失配） | v0.88.3+（未发版） | `error: unexpected token` | test/ast/p_lang25.sh |
| E-PARSE-002 | error | 需要表达式的位置没有表达式 | v0.88.3+（未发版） | `error: expected an expression` | test/ast/p_lang25.sh |
| E-PARSE-004 | error | 引用了未声明的变量 | v0.88.3+（未发版） | `error: use of an undeclared variable` | test/ast/p_lang25.sh |
| E-PARSE-006 | error | `defer` body 内做控制转移 | v0.88.3+（未发版） | `error: a defer block cannot transfer control` | test/ast/p38_defer_control.ct |
| E-PARSE-007 | error | `errdefer` body 内做控制转移 | v0.88.3+（未发版） | `error: an errdefer block cannot transfer control` | test/ast/errors/p40_errdefer_control |
| E-PARSE-008 | error | `break` 不在循环或 switch 内 | v0.88.3+（未发版） | `error: break is only allowed in a loop or switch` | test/ast/p_lang25.sh |
| E-PARSE-009 | error | `continue` 不在循环内 | v0.88.3+（未发版） | `error: continue is only allowed in a loop` | test/ast/p_lang25.sh |
| E-PARSE-010 | error | 跳转之后的语句不可达 | v0.88.3+（未发版） | `error: unreachable code after a jump` | test/ast/p_lang25.sh |
| E-PARSE-011 | error | auto-drop 需要行首的 `}` | v0.88.3+（未发版） | `error: auto-drop requires the closing '}' at the start of a line` | test/modules/autodrop_layout |
| E-PARSE-012 | error | `goto` 跨过带 `defer` 的块 | v0.88.3+（未发版） | `error: a goto cannot cross a block with defer` | test/ast/errors/p38_goto_cross.ct |
| E-PARSE-013 | error | `errdefer` 回滚 `own` 对象 | v0.88.3+（未发版） | `error: an own object cannot be rolled back by errdefer` | test/ast/errors/p40_errdefer_own |
| E-PARSE-014 | error | 闭包通过 `return` 逃逸 | v0.88.3+（未发版） | `error: a closure cannot escape through 'return'` | test/ast/p_lang25.sh |
| E-PARSE-999 | error | 解析/语义错误的未分类兜底 | v0.88.3+（未发版） | `error: unclosed #ct-raw (expected #ct-endraw)` | test/ast/p_lang25.sh |
| E-DRIVER-001 | error | import 无法解析 | v0.88.3+（未发版） | `error: cannot resolve import 'x/Y'` | test/ast/p_lang25.sh |
| E-DRIVER-002 | error | 输入文件打不开 | v0.88.3+（未发版） | `ctc: cannot open the input file` | test/ast/p_lang25.sh |
| E-DRIVER-003 | error | `.m.ct` 单元不产生输出 | v0.88.3+（未发版） | `ctc: a .m.ct unit produces no output` | test/ast/p_lang25.sh |
| E-DRIVER-004 | error | 输出文件或输出目录不可写、不可创建 | v0.88.3+（未发版） | `ctc: cannot write ...` | test/ast/p_lang25.sh |
| E-LOWER-001 | error | 临时接收者不在语句/赋值起点，无法安全物化 | v0.88.3+（未发版） | `error: a method call on a temporary is only allowed at the start of a statement or of an assignment` | test/ast/p_lang25.sh |
| E-LOWER-002 | error | 单条语句的可 hoist 接收者超过上限 | v0.88.3+（未发版） | `error: too many hoisted receivers in one statement` | test/ast/p_lang25.sh |
| E-LOWER-004 | error | SH-111 I1：清理边形状/控制转移/环 | v0.88.3+（未发版） | `error: lowering invariant I1: ...` | test/ast/p111_invariants.sh |
| E-LOWER-005 | error | SH-111 I2：同一条边上 defer 晚于释放 | v0.88.3+（未发版） | `error: lowering invariant I2: ...` | test/ast/p111_invariants.sh |
| E-LOWER-006 | error | SH-111 I3：errdefer 出现在正常出口 | v0.88.3+（未发版） | `error: lowering invariant I3: ...` | test/ast/p111_invariants.sh |
| E-LOWER-007 | error | SH-111 I4：接收者临时缺失或重名 | v0.88.3+（未发版） | `error: lowering invariant I4: ...` | test/ast/p111_invariants.sh |
| W-TYPE-001 | warning | 实参个数与签名不符；`ct check` 升为 error | v0.88.3+（未发版） | `warning: arity mismatch: 'f' takes 2 argument(s), 1 given` | test/ast/p_lang25.sh |
| W-TYPE-002 | warning | 实参类型与签名不符；`ct check` 升为 error | v0.88.3+（未发版） | `warning: type mismatch: 'f' argument 1: ...` | test/ast/p_lang25.sh |
| W-TRAIT-001 | warning | 两个 trait 同名方法，取 `use` 顺序首个 | v0.88.3+（未发版） | `warning: ambiguous method: 'f' declared by 'A' and 'B'` | test/ast/p_lang25.sh |
| W-TRAIT-002 | warning | impl 方法签名与 trait 不一致 | v0.88.3+（未发版） | `warning: signature mismatch: ...` | test/ast/p_lang25.sh |
| W-NAME-001 | warning | 内层 `loop` 遮蔽外层隐式计数器 | v0.88.3+（未发版） | `warning: inner loop shadows ...` | test/ast/p_lang25.sh |
| W-DRIVER-001 | warning | 项目 `vendor/std` 遮蔽内置容器层 | v0.88.3+（未发版） | `warning: the built-in Vec/Map supersede ...` | test/ast/p_lang25.sh |
| W-MEM-001 | warning | 分配后从未释放 | v0.88.3+（未发版） | `warning: potential leak: 'p' (S*) allocated but never deleted` | test/ast/p_lang25.sh |
| W-MEM-002 | warning | 条件返回路径上可能泄漏 | v0.88.3+（未发版） | `warning: potential leak: ... may leak on a return path` | test/ast/p_lang25.sh |
| W-MEM-003 | warning | 借用指针通过 `return` 逃逸 | v0.88.3+（未发版） | `warning: a borrowed pointer escapes through 'return'` | test/ast/p_lang25.sh |
| W-MEM-004 | warning | 切片视图随局部数组逃逸 | v0.88.3+（未发版） | `warning: slice escape: ...` | test/ast/p_lang25.sh |
| W-MEM-005 | warning | `Box<X>` 字段直接成环 | v0.88.3+（未发版） | `warning: ... direct cycle ...` | test/ast/p82_cycle.sh |
| W-MEM-006 | warning | 借用 `Str` / `U16Str` 视图逃逸 | v0.88.3+（未发版） | `warning: borrowed 'Str' view escapes ...` | test/ast/p_lang25.sh |
| W-LANG-001 | warning | `box<T>` 弃用别名（LANG-24） | v0.88.3+（未发版） | `warning: 'box<T>' is deprecated; write 'Box<T>'` | test/ast/p81_box/alias.ct |

## 4 扩展与查重规则

1. **先登记后实现**：新码先加本表一行，再在 `tool/diag/Diag.h.ct` 的两个映射函数里落字符串；两边集合必须相等。
2. **查重是门禁**：`test/docs/check-docs.py` 断言本表无重复 code、格式合法、级别前缀一致、每格非空、行数 ≥ 20，并扫描 `selfhost/ct-ast/**/*.ct` 的码字面量集合与本文逐项相等。少一行、多一行、拼错大小写都红。
3. **不得复用**：一个 code 的语义变了就新增 code；旧码保留并在本表标注 `retired`（`retired` 不删除行，但源码不得再引用）。
4. **一批只做一批**：本实现覆盖 parse / driver / type / trait / name / mem / lang / lower 的 38 个码；未映射的既有诊断走各域 `999` 兜底，不得自行发明新域。
5. **测试**：每个 code 至少一个可复跑命令（上表最后一列）；新增码必须同时加正例或负例，不能只改文档。

## 5 边界与非目标

- 不改严重级、不改退出码；`--diag-codes` 只影响文本行尾。
- 不把 `--diag-codes` 设为默认：默认文本必须与 LANG-10 的逐字节快照一致。
- 解析/驱动错误目前没有 `sem_error` 的 JSON 通道（LANG-10 7b 只覆盖记录在 `ParseSupport` 的失败）；JSON 的 `code` 覆盖已进入 JSON 的两类记录（parse failure 与 warning store）。
- 不做 LSP、不做诊断国际化；LSP 字段映射归后续能力。
