# SH-115 · B+ 类型检查强化（v0.x 立即启动）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`frontend/type` + build 接线） |
| 定性 | 能力强化（所有者 2026-11-22：强化提前，不等 v1-pre） |
| 严重度 | **High**（CLI 默认值变更的前置） |
| 锚点 | v0.88.3（2026-11-22） |
| 依据 | [Kimi 评审核对](../../docs/reviews/2026-11-22-kimi-v088-review-eval.md) §5；所有者 2026-11-22 裁定 |
| 状态 | open |
| 处置证据 | **accepted（下一 v0.x；与 CLI 默认 `warn` 同批落地）** |

## 背景

PH-85 只把 B 已有的判定（赋值/初值/`return`/`$` 目标/实参）接进 `ct build`，默认仍是 `off`。
所有者 2026-11-22 裁定：**强化类型检测现在做，不等 v1-pre**；强化落地同批把 CLI
`--check-level` 默认从 `off` 升为 `warn`（`--check-level=off` 保留为逃生口）。

## 范围（第一批）

1. **默认值**：下一 v0.x 起 CLI 默认 `warn`；生成物 `.c` / `.h` 逐字节不变，只多 `warning:` 行。
2. **补已知静态缺口**（按“可静态判定 + 不引入误报”准入）：
   - [SH-60](sh60-mct-signature-types-decorative.md) 的 1a/1b/2b：静态映射实参、
     未知参数类型、`const`/`volatile` 归一化；
   - 函数指针**字段**调用的残留路径（LANG-19 只覆盖变量；见其“残余”段）；
   - 泛型实例、ADT 负载/`match` 绑定、字段初值中可由现有 `chk_assignable` 判定的错配。
3. **一致性**：`ct check --types` 与 `ct build --check-level=warn` 同判定、同文案；
   不允许一边报、一边不报。
4. **证据**：全量语料 FP=0 仍是 v1.0 硬门禁；`warn` → `error` 只在 FP=0 之后（v1.1 S2）。

## 非目标

- Rust 级借用检查、全 C UB / 格式串检查；
- 改生成 C 的形状或 golden 逐字节内容；
- 在 v1.0 冻结期新增语言语法。

## 验收

- 每条新判定有正例 + 负例夹具，负例断言文案与位置；
- 全量语料 FP=0 的命令与清单入库（J-6 / D2 证据口径）；
- 默认 `warn` 后 `test/cases` / `test/ast` 的产物逐字节不变，只允许 warning 行差异；
- README、spec §1、[stable-subset](../../docs/stable-subset.md) 的默认值措辞同批更新；
- `check-all` 与 `check-docs` 绿。

## 关联

- PH-85 机制（`--check-level=off|warn|error`）；
- [SH-60](sh60-mct-signature-types-decorative.md)、[LANG-19](../lang/lang-19-function-pointer-call-args-unchecked.md)；
- [v1-release-plan](../../docs/planning/v1-release-plan.md) §2.4、D2 证据；
- [J-6 台账](../../docs/planning/j6-evidence/ledger.md)。
