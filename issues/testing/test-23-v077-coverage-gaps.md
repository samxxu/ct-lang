---
id: TEST-23
title: "v0.77 覆盖缺口：无行覆盖、ct-ast 无单测、容量上限/近相 example 缺失"
status: open
area: testing
severity: P2
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# TEST-23 · 覆盖缺口

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §3 / §7；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 缺口

1. 无行/分支覆盖率数据（37k 行 ct-ast 哪些没跑到不可回答）；
2. ct-ast 无单元测试（Lexer/Parser/TypeCheck/Emitter 只端到端）；
3. 容量上限只测 `MAX_CALLS`；`MAX_GENERIC_INSTS=64`、`MAX_CLOSURES=64`、`MAX_PARAMS=16`、`MAX_STRUCT_TPARAMS=2` 无边界夹具；
4. sanitizer/fuzz 只在 nightly；
5. PH-64 后能力无 example：freestanding/alloc、c-boundary/shim、emit-model、check --types；
6. examples 实际 51 个（报告写 52），教程仍写 16；
7. `49_socket` 是文档型样例（只有 README，不进门禁），依赖的 `FileDesc`/`Socket` 仓内不存在；
8. 工具链矩阵缺失：GCC/clang 之外（ICCARM 等）未验证，生成 C 依赖 `__attribute__`；
9. 4 个 near-phase example 缺失：freestanding/alloc、c-boundary/shim、emit-model、check --types；
10. `test/README` 的 119/141 与实测 299/295 不一致（与 DOC-75 D-3 联动）。

## 期望

- nightly 加 `llvm-cov`/`gcov`（只报告，不设阈值）；
- ct-ast 纯函数层少量白盒单测（编码/转义/类型名/map 记录）；
- 3–5 个容量上限夹具；
- 4 个 near-phase 最小 example（20–40 行）；
- 计数脚本回填 examples/test。

## 验收

- 覆盖率报告可看；
- 每个新夹具/example 有命令与输出；
- 上限越界硬错有负例；
- `examples` 计数与 README 一致。

## 范围

P2；不阻塞 1.0；可分批。
