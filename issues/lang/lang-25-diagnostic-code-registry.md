# LANG-25 · 稳定诊断码 registry（v1.2）

| 项 | 值 |
| --- | --- |
| 模块 | lang（工具链 / 诊断） |
| 定性 | 能力缺口（非缺陷） |
| 严重度 | Low |
| 锚点 | v0.88.3（2026-11-22，外部架构评估 P1） |
| 依据 | [LANG-10](lang-10-machine-readable-diagnostics.md)、[架构评估](../../docs/reviews/2026-11-22-architecture-assessment-eval.md) |
| 状态 | open |
| 处置证据 | **已立项（v1.2；与 v1.1 的 parse JSON 分开）** |

## 现象

诊断目前是文本 + 部分 JSON；没有稳定 code。IDE 插件与 CI 只能匹配自由文本，
消息一改就静默失效。报告把诊断视为 API，这个判断成立。

## 期望（v1.2）

1. **码制**：`E-<域>-<编号>` / `W-<域>-<编号>`（域如 TYPE / PARSE / TRAIT / DRIVER / ABI）；
2. **registry**：每个 code 一行——含义、严重级、首次版本、样例、对应测试；
3. **双通道**：文本与 JSON 共用同一诊断对象，JSON 必带 `code`；
4. **兼容**：默认文本格式保持可读；code 只追加，不改既有消息语义；
5. **测试**：每个 code 至少一个正例/负例；code 不得重复或复用。

## 非目标

- 不在 v1.0/v1.1 引入；v1.1 只补 parse JSON 通道（LANG-10）；
- 不改严重级、不改退出码；
- 不做 LSP。

## 验收

- registry 文档入库，`check-docs` 可查重；
- 文本与 JSON 的 code 一致；
- 至少覆盖 parse / type / trait / driver 四域；
- 旧消息文本不被删除，只追加 code。
