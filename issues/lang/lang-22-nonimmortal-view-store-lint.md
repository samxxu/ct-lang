# LANG-22 · 非 immortal `Str` 视图存入容器/ADT/全局时 warning（v1.1）

| 项 | 值 |
| --- | --- |
| 模块 | lang（A 检查器 / 借用视图） |
| 定性 | 特性（warn 级 lint；**不做硬错**） |
| 严重度 | Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [DOC-85](../../issues/docs/doc-85-idiom-priority-card.md)；[language-spec §4.70](../../docs/language-spec.md#L2885-L2927)；[SH-106](../selfhost/sh106-str-view-escape-no-lint.md) |
| 状态 | verified |
| 处置证据 | **待评估（v1.1；不进 v1.0/本次文档修正）** |

## 背景

实测边界：

- **硬错**：`Str` 作 struct 字段、`Map<Str,V>` 的键；
- **可编译**：`Vec<Str>`、`Option<Str>`、ADT 负载、全局 `Str`，但存的是借用视图；
- **安全惯用法**：`Vec<Str> names = { "uart0", "uart1", "i2c0" };` 全是 immortal 字面量，
  永远安全，是嵌入式/驱动的常见设备名表；
- **有风险**：`v.push(local_string.as_str())` 这类非 immortal 来源；owner 死后视图悬垂。

不把容器/ADT/全局升级成硬错：会误杀常量表，且硬错拦不住“先存 String 再 as_str”的绕法。

## 目标

在 `ct check` / `ct build` 的警告层增加：

> `storing a non-immortal 'Str' view; the owner must outlive the container`

- 初始化源是字面量 / immortal（`refs = -1`）→ **零告警**；
- 非 immortal 来源存入 `Vec` / `Option` / ADT 负载 / 全局 → **warning**；
- 不做硬错；不改变现有可编译性；
- 局部判断即可，不承诺跨过程生命周期分析。

## 范围

| 位置 | 行为 |
| --- | --- |
| `Vec<Str>` / `Option<Str>` 元素 | 字面量来源不告警；非 immortal 来源 warning |
| ADT 负载 `Str` | 同上 |
| 全局 `Str` 初始化 | 字面量不告警；非 immortal 来源 warning |
| 函数参数/局部/返回 | 不在本条（返回局部视图见 SH-106） |
| struct 字段 / `Map` 键 | 保持硬错，不改 |

## 验收

1. `Vec<Str> names = { "uart0", "uart1" };` 零告警；
2. `String s = ...; Vec<Str> v; v.push(s.as_str());` 给 warning；
3. `Option<Str>` / ADT 负载 / 全局的非 immortal 来源同样 warning；
4. 不改变现有程序的编译成功与否；warn 可被 `--check-level`/配置控制；
5. 文档（guide/idioms）与告警文案一致；
6. 不进入 v1.0；v1.1 评估后决定是否默认开启。

## 非目标

- 不做完整借用检查器；
- 不把 `Vec<Str>` / ADT / 全局改成硬错；
- 不覆盖跨函数/跨单元的 owner 生命周期；
- 不替代 SH-106（返回局部 `Str` 视图）的 lint。

## 关联

- [DOC-85](../../issues/docs/doc-85-idiom-priority-card.md)
- [SH-106](../selfhost/sh106-str-view-escape-no-lint.md)
- [language-spec §4.70](../../docs/language-spec.md#L2885-L2927)

## 处置（DEV，2026-11-23）：v1.1 warn 级 lint 已实现

复用 SH-106 的 `str_escape` 记账（`str_escape_class`），在四个存储点判定：

| 存储点 | 代码位置 |
| --- | --- |
| `Vec` 元素（`push` / `set` / `put` 的形参） | `Expr.h.ct` inherent method 形参循环 |
| `Vec<Str>` brace 初始化 | `Stmt.h.ct` `parse_vec_brace_init` |
| ADT 变体负载 | `Expr.h.ct` `parse_adt_ctor` |
| 全局 / `static` 声明与赋值 | `Parser.h.ct` 文件作用域初始化式、`Stmt.h.ct` 赋值 |

文案：`storing a non-immortal 'Str' view; the owner must outlive the container`。
severity 与既有 `str_escape` 一致：compile / `ct build` warning，`ct check` error；
不改变可编译性，不做硬错。安全形态（immortal 字面量、参数 / 字段 / 全局 / static /
`self` 的视图、owning `String`）不报。

验证：`test/ast/lang22_str_store.sh`（15 条断言，含正例与六类负例 + `ct build` warning）。
`status` 字段不动；是否把 v1.1 lint 默认开启由 REQ/REV 另定。

## 复核（REV，2026-11-23）

非 immortal `Str` 视图存入 `Vec`/ADT/全局/static 时 warning；容器 push/set/put、brace 初始化
均覆盖；安全形态不误报；`ct build` warning、`ct check` error；探针 15/15。
