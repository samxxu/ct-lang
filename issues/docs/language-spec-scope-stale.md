# DOC-9 · language-spec 的范围与时态已过期（仍称 L2 语法「正在重做」）

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `ec97f99`（2026-10-17） |
| 文件 | [docs/language-spec.md](../../docs/language-spec.md#L4-L14)、[§10](../../docs/language-spec.md#L428-L436) |
| 状态 | ✅ 已修复（2026-10-18，方案 2：改契约） |

## 现象

语言规范开头声明：

> 本文描述 `ctc`（即 L0）当前接受与产出的语法……它们**正在 CT 侧重做**（不在本文范围内）

§10 同样写：「`namespace` / 多文件 / `import` / `pub` 已由 Phase 2……恢复（**本文不描述其语法**）」。

## 证据

- Phase 2–7 已全部收口（[roadmap](../../docs/roadmap.md) 总览表全 ✅，当前 `v0.7.0`），「正在重做」的时态已不成立；
- `namespace` / `import` / `pub` / `Drop` / `#line` / `own` 均已在 L2 实现并有 designed/golden 用例；
- [AGENTS.md](../../AGENTS.md) §5 明确要求「改动语法或产物命名时，必须同步更新 `docs/language-spec.md`」。

即：**唯一被称为「语言规范」的文档，不描述当前编译器实际支持的一半语法**，且其免责理由已过期。

## 影响

新用户与编辑器/工具作者会把 spec 当作权威来源，从而漏掉模块系统、Drop、`#line`、AutoDrop（后者 §4.9 已有）等能力；AGENTS §5 的强制同步条款也因此名存实亡。

## 修复建议

二选一，并在文档中明确：

1. **扩范围**：在 spec 中补 L2 语法章节（namespace / import / `pub` / `.h.ct` / Drop / `#line` / CLI 开关），标注适用编译器；
2. **改契约**：若坚持 spec 只覆盖 L0，则修订 AGENTS §5 的措辞为「L0 语法变更必须同步 spec；L2 语法变更必须同步 roadmap/design」，并在 spec 顶部给出 L2 语法参考的明确链接。

## 验证

spec 中不再出现「正在重做」；且 AGENTS §5 与实际维护口径一致。

## 处理（2026-10-18）

采用方案 2：spec 顶部改为「描述 L0 与 L2 共有的核心语法」，明确 L2 独有构造（namespace / import / pub / 多文件 / Drop / #line / 诊断）不在语法章节内并给出 roadmap / design 链接；§10 改为「L2 独有」并去掉「正在重做 / 恢复进度」的时态。AGENTS §5 第 4 条同步改为分层维护口径（核心语法 → spec + README；L2 独有 → roadmap + design）。
