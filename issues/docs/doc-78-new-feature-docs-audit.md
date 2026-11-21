# DOC-78 · 新特性文档核对（String/Str/切片/ref-out/box/new）

| 项 | 值 |
| --- | --- |
| 模块 | docs（spec / tutorial / patterns） |
| 定性 | 文档核对（非从零编写） |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [language-spec.md](../../docs/language-spec.md)、[tutorial.md](../../docs/tutorial.md)、[patterns.md](../../docs/patterns.md) |
| 状态 | **已完成核对（2026-11-21）；tutorial 两章由 DOC-90 承接** |

## 核对矩阵（2026-11-21）

| 特性 | spec | tutorial | patterns | 可运行证据 |
| --- | --- | --- | --- | --- |
| `ref` / `out` | §4.68 | §15 | §7（新增） | p78_basic / p70_definite |
| 切片 `T[]` | §4.69 | 缺章 → [DOC-90](doc-90-tutorial-string-slice-chapters.md) | §7（新增） | p79_basic / p79_places |
| `String` / `Str` | §4.70 | 缺章 → [DOC-90](doc-90-tutorial-string-slice-chapters.md) | §7（新增） | p80_* / README §0.5 |
| `box` / `new` | §4.71 | §17 | §7（新增） | p81_box |
| ADT / `match` | §4.73 | §18 | §6 | p84_match |

## 落库（2026-11-21）

- **patterns §7「句柄与借用视图选型」**：五行表（拥有/借用、切片传参、`out`/`ref`、
  `box`、指针），判据列全部指向 `idioms.md`（入库前见 [DOC-85](doc-85-idiom-priority-card.md)），
  不另立第二套判据；机制细节只链 spec §4.68–§4.71。
- **patterns §4 事实修正**：原文「参数错配、返回类型不符要到 C 编译器才报」已过时——
  按值 struct 的实参/返回不一致（v0.53.2 起）与 impl 签名漂移（v0.45 起）已是硬错，
  `ct build --check-level=warn|error` 可提前阻断；已按现状改写。
- **patterns §6 同性质修正**：`_` 不是“必须显式书写”，而是未穷尽时的兜底；全部变体覆盖后
  不必写，写了会被提示“多余”。
- **能力表对齐**：[capabilities.tsv](../../docs/capabilities.tsv) 已覆盖 `strings`、`params-slices`
  （含 `ref/out` 与切片）、`box`、`adt`；DOC-77 断言保证节号可解析。
- **示例/负例**：五项均有既有 `test/ast` 探针；`tutorial-cases` 夹具（DOC-86 D3-5）收录
  String/Str、切片、`box`、ADT 四条。
- 未新增任何未实现能力描述；`idioms.md` 入库仍是 DOC-85 的交付项。

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
