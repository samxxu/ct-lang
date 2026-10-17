# SH-1 · `MAX_FUNCS` 余量极小，是 CT 线最紧的扩展瓶颈

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | **Medium** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 站点 | `selfhost/src/core.ct:37`（`#define MAX_FUNCS 64`）等 |
| 状态 | 已修复（commit `b6b3dc4`，前置于 roadmap Phase 5） |

## 现象

CT 线（L2）的顶层 plain-C 签名预算 `MAX_FUNCS = 64` 已接近用尽，源码注释自述。

## 证据

```
selfhost/src/core.ct:449   （MAX_FUNCS) and the budget is nearly exhausted.
selfhost/src/core.ct:470   because plain-C top-level signatures are capped (MAX_FUNCS) and the budget
selfhost/src/core.ct:4123  if (sym->nfuncs >= MAX_FUNCS) die(0, "too many functions (max %d)", MAX_FUNCS);
```

roadmap 实测：`core.ct 33 + driver ≈15 + 10 个 pub 包装器 ≈ 58 / 64`；`MAX_METHOD`（32）中 `PipeOps` 已用 **31**；roadmap L704 记「顶层函数零新增——`MAX_FUNCS` 余量仍是 1」。

## 影响

`MAX_FUNCS` **计入所有顶层 plain-C 签名（含 `static`）**，是 CT 线（Phase 5 起所有新能力）最硬的容量天花板。AST 主线的第一版编译器必须落在 `32 struct / 16 trait / 64 plain-C` 之内，否则连「自身能不能被 L1 编过」都成问题（roadmap 已述「增长一代滞后」）。

## 修复建议

- 这是**约束记录**而非缺陷修复：新逻辑**必须**写进 `impl` 块（impl 方法不计入 `MAX_FUNCS`），并注意 `MAX_METHOD`——把方法放进 `PipeOps` / `RewriteOps` 对应的一半。
- 在 AGENTS §2/§6 与 roadmap 的显著位置固化此约束（当前仅在 roadmap Phase 3 段落提到）。
- 切勿为扩容而改 `ctc.c` 的 `MAX_*`（冻结期明令禁止）。

## 验证

新增 CT 侧函数后跑 `check-goldens.sh` 第 7 步（L1 vs L2 不动点）与 `check-archive.sh`；若 `MAX_FUNCS` 溢出，`core.ct:4123` 会 `die`。
