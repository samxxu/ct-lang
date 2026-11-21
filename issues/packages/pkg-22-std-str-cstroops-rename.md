# PKG-22 · std 包：`std::str::String` 单元改名 `std::str::CStrOps`

| 项 | 值 |
| --- | --- |
| 模块 | packages / ct-pkg `std` |
| 定性 | 命名修正（避免与内置 `String` 混淆） |
| 严重度 | Medium |
| 锚点 | `std 0.19.0`（2026-11-21） |
| 依据 | [language-spec §4.51](../../docs/language-spec.md#L1978-L1989)；[DOC-85](../../issues/docs/doc-85-idiom-priority-card.md) |
| 状态 | **待办（ct-pkg/std 包；本仓只同步消费文档）** |

## 现象

`std` 包的 `char *` 方法层：trait 早已叫 `CStrOps`，但单元文件叫 `String.m.ct`，
所以导入写成 `import std::str::String;`。这与内置的 `String` 句柄同名，用户和模型容易
把它当成“内置 String 的包版本”，产生混淆。

`language-spec §4.51` 已预留口径：“std 侧若改名为 `CStrOps`，CT 待其发版后再同步，
不预先改”。

## 决策

| 项 | 决定 |
| --- | --- |
| 单元文件 | `std/str/String.m.ct` → **`std/str/CStrOps.m.ct`** |
| 导入写法 | `import std::str::CStrOps;` |
| trait | 保持 `CStrOps` 不变；方法表/`map trait CStrOps for type char *` 不变 |
| 兼容 | 旧 `String.m.ct` 保留一个 MINOR：作为 `CStrOps` 的薄兼容单元（若 import 可传递则直接转出；否则保留重复映射并在文件头标 deprecated） |
| 版本 | `std` 包 MINOR bump（0.x 语义允许），索引行随发布更新 |
| 本仓 | 只改文档/示例的导入口径；不改内置 `String`、不改 `std::*` 其他单元 |

## 验收

1. `import std::str::CStrOps;` 后 `"42".to_int()`、`s.length()` 等可用；
2. 旧 `import std::str::String;` 在兼容窗内仍可用，文件头有 deprecation 说明；
3. `std` 包 `ct.pkg` 版本/索引行更新；`ct index verify` 通过；
4. `std` 包测试、`examples/wave1-demo` 等消费者迁移；
5. 内置 `String`/`Str`/`Vec` 等不受影响；
6. 一个 MINOR 后移除 `String.m.ct`，另立清理 issue。

## 非目标

- 不改方法语义（`to_int` 仍是 `atoi` 语义）；
- 不改内置 `String`（内置类型改名归 DOC-87 Stage 2）；
- 不改 `std::io` / `std::num` 等其他单元；
- 不在本仓复制 std 包源码。

## 风险

| 风险 | 缓解 |
| --- | --- |
| 旧导入路径失效 | 保留 `String.m.ct` 一个 MINOR；错误文案提示新路径 |
| 文档/示例漂移 | 本仓文档写“0.19.0 旧名 / 下一 MINOR 新名”，不提前改可运行示例 |
| 包版本与索引不同步 | 发布时一次更新 `ct.pkg`、索引行、README |

## 关联

- [DOC-85](../../issues/docs/doc-85-idiom-priority-card.md)
- [language-spec §4.51](../../docs/language-spec.md#L1978-L1989)
- [DOC-87](../../issues/docs/doc-87-lib-core-rename.md)（内置层 `namespace core`，另一条线）
