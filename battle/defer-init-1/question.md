# battle/defer-init-1 — `Some *s = defer Some::new()` 是否成立

| 字段 | 值 |
| --- | --- |
| 争点 | 是否允许 `defer` 作为声明初始化式：`Some *s = defer Some::new();`，立即求值/赋值，并在作用域退出时自动清理 |
| 当前 HEAD | `ce6aa436`（v0.65.1；主规范 1.16.0 已同步） |
| 触发理由 | 用户希望把“创建 + defer 清理”合并成一条语法；要求 battle 评估 |
| proposer | REQ（主张 A：新增 defer 初始化式） |
| opposition | REVIEW（主张 B：拒绝重载 defer，使用 own/尾随块） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/language-spec.md`、`docs/design/**`；只写 `battle/defer-init-1/` 与 `/tmp` |

## 语义前提（本 battle 必须统一）

A 按用户字面解释：

```ct
Some *s = defer Some::new();
```

等价于“**立即**求值 `Some::new()`，赋给 `s`，并在当前作用域退出时清理 `s`”。  
**不是**把 `Some::new()` 延迟到作用域退出才执行；若延迟，`s` 在作用域内不可用，语义无意义。

## 位置 A（新增 defer 初始化式）

1. `defer <expr>` 只允许出现在声明初始化式右值；`expr` 立即求值一次，结果赋给变量。
2. 作用域退出时按 LIFO 清理；`return`/`break`/`continue` 走既有 defer 链。
3. 清理动作由 `Drop`/`delete` 或显式尾随块决定；空指针/失败构造不登记。
4. `defer` 与 `own` 的分工：`own` 自动 Drop，`defer` 负责无 Drop 的显式释放；二者不能同时登记同一对象。
5. 与现有尾随块 `Type s = expr defer { … };` 保持兼容；`defer expr` 是它的简写。

## 位置 B（拒绝重载 defer）

1. `defer` 保持块级语句：`defer { … }`；`defer expr` 仍是普通标识符/语法错误。
2. 创建 + 清理用现有机制：
   - 有 `Drop`：`own Some *s = Some::new();`
   - 无 `Drop`：`Some *s = Some::new() defer { delete s; };`（现有尾随块）
3. 若确实需要简写，新增明确关键字/限定符（如 `owned`/`with`），不要复用 `defer`。
4. 理由：`defer` 的语义是“延迟执行”，不是“立即构造 + 自动清理”；复用会让 `defer expr` 在语句/初始化式两种位置含义不同。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 语义清晰：`defer` 在两种位置是否可区分，是否违反“defer=延迟”直觉 | 语法/文档/用户测试 |
| J-2 | 与 `own`/Drop/尾随块重叠：是否产生两套资源机制 | 语义矩阵 |
| J-3 | 语法歧义：`defer` 作标识符、声明/表达式/块边界 | parser 夹具 |
| J-4 | 控制流/错误路径：return/break/continue/errdefer/构造失败 | 探针 |
| J-5 | 兼容性：现有 defer/own/尾随块夹具、golden、C 超集 | 全量门禁 |
| J-6 | 实现代价：parser/emitter/CFG/诊断/迁移 | 文件/行数/phase |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点核 `language-spec` §4.9.1（defer 只收块形态）、§4.9 own、§4.58 尾随块 `Type name = expr defer { … };`，以及现有 `test/ast/220_defer_order`、`p40_*`、`p49_own`。
