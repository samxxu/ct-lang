# SH-113 · 内建单元判活边界测试（v1.1）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 构建 / 内建单元加载） |
| 定性 | 测试加固（已知近似边界） |
| 严重度 | Low |
| 锚点 | v0.88.3（2026-11-22，外部架构评估 P1） |
| 依据 | [hw-2 判决](file:///Users/samxx/dsh-ws/ct-lang/battle/hw-2/verdict.md)、[SH-112](sh112-typed-ir-architecture.md)、[架构评估](../../docs/reviews/2026-11-22-architecture-assessment-eval.md) |
| 状态 | open |
| 处置证据 | **已立项（v1.1；v1.0 不动判活逻辑）** |

## 现象

`builtin_live_for` 按源码文本判活（`src_has_word` / `src_has_prefix` / `src_has_box_type`），
不是语义引用图。hw-2 已判“文本近似不足”；词边界匹配修掉了 `Struct`/`String`/注释误命中，
但**小写导出函数名仍可能漏判**。当前没有一组测试把“命中/不命中”的边界钉住。

## 期望（v1.1）

新增 6 组正负例，锁住当前契约：

1. 注释里出现 `Vec` / `String` → 不加载；
2. 标识符 `MyVec` / `Vecx` / `Stringy` → 不加载；
3. `struct` 字段 `String` → 加载 `Str` 单元；
4. 字符串字面量里出现 `Option` / `Result` → 不加载；
5. `str_` 前缀调用 → 加载对应单元；
6. 只有小写导出函数名（如 `str_len`）→ 记录为**已知漏判**，
   测试断言当前行为并在注释指向本卡；若 DEV 能低成本修正，则改为正例。

## 非目标

- 不在 v1.0 改判活算法；
- 不做语义引用图（v1.2，[SH-112](sh112-typed-ir-architecture.md)）；
- 不改生成 C 行为。

## 验收

- 6 组用例进 `test/ast` 或构建级测试，`check-ast` / `check-all` 绿；
- 每组注明“期望加载/不加载”与依据；
- spec 的内建层条目保留“判活是近似”的说明；
- 已知漏判在测试里显式标注，不静默跳过。
