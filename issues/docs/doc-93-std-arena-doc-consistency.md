# DOC-93 · `std::arena` 文档口径统一

| 项 | 值 |
| --- | --- |
| 模块 | docs（std 目录 / C 程序员指引 / battle 记录） |
| 定性 | 文档矛盾（外部 std 包能力是否存在） |
| 严重度 | Low（不影响编译，只影响读者与外部文档引用） |
| 锚点 | v0.88.3（2026-11-22） |
| 依据 | [std::arena 改名提议评估](../../docs/reviews/2026-11-22-arena-rename-proposal-eval.md) §4 |
| 文件 | [std-catalog](../../docs/std-catalog.md#L46)、[guide-for-c-programmers](../../docs/guide-for-c-programmers.md#L284-L290)、[battle/ct-guide-1](../../battle/ct-guide-1/verdict.md#L13) |
| 状态 | open |
| 处置证据 | **accepted（先请 STD 组确认；只统一文档；不改 `std::arena` 名、不把 Arena 上收 `lib/core`；内置层目录/命名空间迁移另见 DOC-87）** |

## 现象

> 术语先行：`lib/std` 是**编译器内置层**（自动加载，不是包）；`std` 才是外部 ct-pkg 包
> （规范名 `ct/std`，`ct get` 安装、`import std::…` 使用）。不要把 std 包写成 `lib/std`。
> 内置层自身的目录/命名空间将改为 `lib/core` / `core::*`，见
> [DOC-87](doc-87-lib-core-rename.md)；本卡只处理 `std::arena` 的口径，不预设改名已执行。

同一个 `std::arena` 在三处说法互相矛盾：

1. [std-catalog](../../docs/std-catalog.md#L46)：`std::arena` 模块存在，入口 `std::arena::Arena`
   （核对基线 std 0.19.0）；
2. [guide-for-c-programmers](../../docs/guide-for-c-programmers.md#L284-L290)：
   “`lib/std` … 也没有公开的 `std::arena`”（这里的 `lib/std` 指内置层，不是 std 包）；
3. [battle/ct-guide-1](../../battle/ct-guide-1/verdict.md#L13)：`std::arena` 不存在，
   已从指引删除。

仓内代码没有任何 `std::arena` 引用：`selfhost` 的 `import std::` 为 0 条，
`std::arena` 在 `.ct/.h.ct/.m.ct` 中为 0 处；selfhost 用的是仓内
`runtime::arena::Arena`（[Arena.h.ct](../../selfhost/ct-ast/runtime/arena/Arena.h.ct)）。
因此矛盾只在文档层，不在实现层。

## 期望

1. **外部确认（STD 组）**：`std 0.19.0` 是否真的发布 `arena` 模块；入口、类型名、
   是否需要 `ct get` / `import`。这是唯一无法由 CT 仓单独判定的事实。
2. **按确认结果统一 CT 文档**：
   - 若存在：guide 改成“`lib/std`（内置层）没有 arena；`std` 包（规范名 `ct/std`，
     不是 `lib/std`）提供 `std::arena::Arena`，需 `ct get ct/std` 并
     `import std::arena::Arena`”；std-catalog 保留；battle 加一条补充说明
     （历史记录不改写，追加当前口径）。
   - 若不存在：std-catalog 删除该行或标 `planned`；guide 保留“无公开 arena”；
     外部文档与本仓评估同步标注“未发布”。
3. **不改名**：`arena` 是模块名，小写与 `std::str` / `std::io` 等 15 个模块一致；
   类型 `Arena` 已是 PascalCase。若要做“模块名 PascalCase”的全生态变更，另开 ADR，
   不在本卡范围。
4. **不迁 `lib/core`**：selfhost 零外部 std 依赖，Arena 也不是编译器魔法；无上收触发条件。
5. **审计脚本（若入库）**：用 `^\s*import\s+std::` 而不是裸 `std::`；区分内部
   `runtime::arena` 与外部 `std::arena`；代码判据与文档判据分开。

## 验收

- STD 组的书面确认（有/无、版本、入口）附在本卡；
- 三处文档对 `std::arena` 的说法一致，且与确认结果一致；
- `python3 test/docs/check-docs.py` 绿；
- 不改任何编译器代码、不改 std 包。

## 关联

- [std::arena 改名提议评估](../../docs/reviews/2026-11-22-arena-rename-proposal-eval.md)；
- [std-catalog](../../docs/std-catalog.md)、[guide-for-c-programmers](../../docs/guide-for-c-programmers.md)；
- [battle/ct-guide-1](../../battle/ct-guide-1/verdict.md)；
- 外部提案《std::arena 改名 std::Arena + 编译器对外部 std 依赖的审计与处置》。

> 归属说明：本卡开在 **CT 仓 `issues/docs/`**，因为矛盾发生在 CT 仓的文档与门禁；
> STD 包仓只需回答“模块是否存在”，不需要在 std 仓另开一张同号卡。
