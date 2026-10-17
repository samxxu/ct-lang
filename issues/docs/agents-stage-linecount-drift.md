# DOC-2 · AGENTS §1 阶段与 `ctc.c` 行数滞后，且与 §2 自相矛盾

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **High** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | [AGENTS.md](../../AGENTS.md#L23)、[AGENTS.md](../../AGENTS.md#L34) §2 |
| 状态 | 已修复（commit `5bde821`） |

## 现象

§1 项目画像（L23）写：

> 当前进入 **Phase 1：自举**……`ctc.c` 现为**纯 OO**（3836 → **2897** 行）

## 证据

- `wc -l ctc.c` → **2930** 行（非 2897）。
- 阶段：roadmap 总览表记 Phase 2/3/4 ✅，实际为 **Phase 5**（见 [DOC-1](readme-phase-drift.md)）。
- **自相矛盾**：AGENTS §2 的 L34 / L52 / L53 已按 Phase 3+ 现实书写——`selfhost/src/**`（`core.ct` + `driver.ct`）、「L1 自 Phase 3 起冻结」、「`check-archive.sh` 的 ratchet 跑的是 L2」。§1 停留在 Phase 1，与 §2 同一文件内打架。

## 影响

AGENTS 是本仓库**唯一行为规约**，AI 代理/新人都先读它。阶段与行数错误会直接误导后续工作的范围判断。

## 修复建议

1. L23 阶段句与行数更新为当前事实（Phase 5 / `ctc.c` 2930 行）。
2. 顺带消除 §1↔§2 矛盾（二者应以 §2 为准）。

## 验证

改后 `grep -n 'Phase' AGENTS.md` 检查 §1 与 §2 表述一致；`wc -l ctc.c` 与文中数字一致。
