# DOC-78 · 新特性文档核对（String/Str/切片/ref-out/box/new）

| 项 | 值 |
| --- | --- |
| 模块 | docs（spec / tutorial / patterns） |
| 定性 | 文档核对（非从零编写） |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [language-spec.md](../../docs/language-spec.md)、[tutorial.md](../../docs/tutorial.md)、[patterns.md](../../docs/patterns.md) |
| 状态 | **待办（REQ 核对）** |

## 现状

- spec 已有 §4.68 `ref`/`out`、§4.69 切片 `T[]`、§4.70 `String`/`Str`；
- 需要核对 `box<T>` / `new`、`patterns.md` 与 tutorial 的对应关系，以及“能力描述与实现一致”。

## 期望

1. 逐特性核对：spec 节号、tutorial 示例、patterns 写法三者一致；
2. 补 `box`/`new` 的 spec 节与 tutorial 示例（若缺）；
3. 每个特性至少一个可运行示例或负例，挂到既有门禁；
4. 与 [DOC-77](doc-77-capability-spec-section-assertions.md) 的能力表对齐。

## 验收

- 能力表覆盖全部新特性；
- 示例可编译/运行（或明确标注为非法负例）；
- 不新增未实现能力的描述。

## 关联

- [v1 路线 §1.5](../../docs/planning/v1-release-plan.md#L57-L71)
