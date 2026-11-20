# 会话映射

> 中文

| 任务 | 对话 | 角色 | phase |
| --- | --- | --- | --- |
| 文档治理（1.9.0 落库 / 语言 / roadmap） | 当前 DSH 会话（lead） | REQ / DEV | — |
| PH-38 立项与实现 | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-38 |
| PH-39 实现与收口（R1–R9 / E39-1–E39-9） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-39 |
| PH-40 实现与收口（R1–R7 / E40-1–E40-9） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-40 |
| PH-41 实现与收口（R1–R9 / E41-1–E41-10） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-41 ✅ v0.41.0 |
| PH-42 实现与收口（R1–R8 / E42-1–E42-8） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-42 ✅ v0.42.0 |
| PH-42 独立评审与定稿（battle p42-1 C） | 当前 DSH 会话（lead） | REVIEW / EDITOR | PH-42 |
| PH-43 文稿定稿（G1 修订；实施待主编安排） | 当前 DSH 会话（lead） | REQ / EDITOR | PH-43 |
| PH-63 包管理去 vendor 收口 | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-63 ✅ v0.62.0 |
| SH-86 数组/const vptr 静态初始化（P0） | 当前 DSH 会话（lead） | DEV / VERIFY | — ✅ v0.62.1 |
| SH-87 内置层 `Str` 判活（battle hw-2 承接） | 当前 DSH 会话（lead） | DEV / VERIFY | — ✅ v0.63.2 |
| PH-64 裸机生成契约（T1–T5） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-64 ✅ v0.63.0 |
| PH-65 严格 C 边界（R1–R7 / E65-1–E65-8） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.64.0 |
| PH-66 libc I/O 内置例外（R1–R5 / E66-1–E66-6） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.65.0 |
| PH-67 无真机硬件能力扩展（R1–R6 / E67-1–E67-6） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.66.0 |
| PH-68 类型核心（R1–R4 / E68-1–4） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.67.0 |
| PH-69 跨单元/泛型/trait 类型检查（R1–R4 / E69-1–3） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.68.0 |
| PH-70 CFG/定值/控制流（R1–R3 / E70-1–3） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.69.0 |
| PH-71 own/borrow/Drop + 包级 strict（R1–R3 / E71-1–3） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.70.0 |
| PH-72 静默错误与诊断批（R1–R6 / E72-1–3） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.71.0 |
| PH-73 字段可见性与 ABI（R1–R3 / E73-1–3） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.72.0 |
| PH-74 模型导出（R1–R3 / E74-1–3） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.73.0 |
| PH-75 闭包作方法实参（R1–R2 / E75-1–3） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.74.0 |
| PH-76 链中 inline 物化 `$name`（S1–S4 / E76-1–5） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | — ✅ v0.76.0 |
| PH-77 官方包身份与解析契约（S0–S5 / E77-1–E77-8） | 当前 DSH 会话（lead） | EDITOR / DEV / VERIFY | PH-77 ✅ v0.77.0 |
| PH-78 `ref` / `out` 参数（S2a–S2c / E78-1–E78-6） | 当前 DSH 会话（DEV `dev-ph78`） | DEV | PH-78 ✅ v0.78.0（fix v0.78.1） |
| PH-79 切片 `T[]`（S3a–S3e / E79-1–E79-6） | 当前 DSH 会话（DEV `dev-ph79`） | DEV | PH-79 ✅ v0.79.0 |
| PH-80 `String`/`Str`（S5a + S5b；D-013 入口闭合） | 当前 DSH 会话（DEV `dev-ph80`） | DEV | PH-80 ✅ v0.80.4（E80-1…8 全通过；SH-102 自动 retain R1–R7，D-015 字段 release + 分支合并） |
| PH-81 `box`/`new`（S1；P-7.5 + S1a/S1b/S1c） | 当前 DSH 会话（DEV `dev-ph81`） | DEV | PH-81 ✅ v0.81.0（E81-1…6；P-7.5 证据；D-016） |
| PH-82 泄漏防护（S82a–S82d；E82-1…8） | 当前 DSH 会话（DEV `dev-ph82`） | DEV | PH-82 ✅ v0.82.0（E82-1…8 全通过；D-012） |
| PH-83 包管理契约 v1 与索引校验（S83a–S83d；E83-1…8） | 当前 DSH 会话（DEV `dev-ph83`） | DEV | PH-83 ✅ v0.83.0（契约 v1 / `ct index verify` / conformance / Linux 产物；D-014）；PKG-14 fix v0.83.1；Linux CT_HOME 路径 fix v0.83.2 |
| PH-84 最小 ADT/match（S84a–S84d；D3） | 当前 DSH 会话（REQ） | REQ / EDITOR | PH-84 🟨 准备（v0.84.0；入口 PH-83 收口） |
| v1-pre 编译器重写（PH-85 inventory+spike/M0 粗切/A 机制 → PH-86 词法 → PH-87 解析+检查 → PH-88 发射器） | 当前 DSH 会话（REQ） | REQ / EDITOR | D1/D-017 已定；逐卡开卡，同一时刻一张 |
| v1.0 发布前清单（已定项：J-6 台账 / goldens 静态化 / 文档与包体系收尾） | 当前 DSH 会话（REQ） | REQ / EDITOR | v1-PH-0 前置；争议项见 v1 路线 §6 |
| v1.1 M1 精细切分（S1）+ A 默认强制（S2） | 当前 DSH 会话（REQ） | REQ / EDITOR | v1-PH-1；D-017 |
| `HW-1`/`HW-2` 硬件批次 | 外部依赖（无硬件） | REQ | 只登记，不阻塞 |

> 本仓库当前为单会话工作，三类常驻对话未建；见 `AGENTS.md` 的 `deviation: single-session-workflow`。
