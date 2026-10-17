# DOC-1 · README 顶部阶段声明滞后

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **High** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | [README.md](../../README.md#L6) L6 |
| 状态 | 已修复（commit `5bde821`） |

## 现象

README 第 6 行声明：

> Phase 0 … **Phase 1（自举，2026-10-15）**与 **Phase 2（模块化，2026-10-16）**均已完成，当前进入 **Phase 3：内存**（`Drop` / `delete` 放宽）。

## 证据

[docs/roadmap.md](../../docs/roadmap.md) 总览表（L21–L24）实测：

```
| Phase 2 | 模块化 | ✅ 完成（2026-10-16；非版本 tag phase2-multifile-split） |
| Phase 3 | 内存   | ✅ 完成（2026-10-16；在 selfhost/src/** 实现，L1 冻结） |
| Phase 4 | 诊断与溯源 | ✅ 完成（2026-10-16；4 个切片全部落地，版本仍 v0.0.1） |
| Phase 5 | 新增特性 | 🔭 展望 |
```

即 **Phase 3、Phase 4 均已完成，当前处于 Phase 5**。

## 影响

README 是仓库门面，阶段声明是对外契约的第一句话。写成 Phase 3 会让读者误判项目进度、误判哪些能力已可用（`#line` / `--diagnostics` 等 Phase 4 能力已经落地）。

## 修复建议

把 L6 的阶段句改为与 roadmap 一致的表述，例如：「…Phase 1（自举）、Phase 2（模块化）、Phase 3（内存）、Phase 4（诊断与溯源）均已完成，当前进入 **Phase 5：新增特性**」。

## 验证

改后与 [roadmap.md](../../docs/roadmap.md) 总览表逐行对齐；`v0.0.1` 保持不动（刻意未 bump）。
