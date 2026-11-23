---
id: TEST-23
title: "v0.77 覆盖缺口：无行覆盖、ct-ast 无单测、容量上限/近相 example 缺失"
status: deferred
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
5. v0-PH-64 后能力无 example：freestanding/alloc、c-boundary/shim、emit-model、check --types；
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

## 处置（2026-11-20，DEV）

**结论：deferred（可分批；本批不做）。**

已核实现状（2026-11-20，HEAD 含 DOC-75 `aa1b0d3b`）：

```console
$ ls -d examples/*/ | wc -l
51
$ find test/ast -mindepth 1 -maxdepth 1 -type d | wc -l
299
$ ls test/ast/errors/*.ct | wc -l
295
$ find test/ast/errors -name '*.ct' | wc -l
337        # 含 errors/ 子目录内的 42 个；README 的 295 指顶层裸 .ct
$ command -v llvm-cov lcov
（无输出；仅 /usr/bin/gcov 存在，Apple LLVM 21 的 gcov 兼容层）
$ ls -d test/unit
test/unit  # 这是 L0 C 辅助函数的白盒测试，不是 ct-ast 单测
```

缺口 6/10（计数与 README 不一致）已由 DOC-75 的 D-3/D-4 对齐：README 的
299 目录 / 295 顶层 error 夹具 / 51 example 与实测一致。剩余 1–5、7–9 未做。

为什么本批不做：覆盖率（nightly 报告）、ct-ast 白盒单测、3–5 个容量夹具、
4 个 near-phase example 是四个独立交付物，每个都要自己的命令与输出
（T-1/T-2），不是一次 fix。

下一最小动作（成本从低到高）：

1. nightly 加 `gcov` 报告（只报告不设阈值）：`CC="cc --coverage"` 重建
   ct-ast，跑 `check-ast.sh` 后 `gcov`；文件 `.github/workflows/nightly.yml`；
2. `test/ast/p72_limits.sh`：`MAX_GENERIC_INSTS`/`MAX_CLOSURES`/`MAX_PARAMS`/
   `MAX_STRUCT_TPARAMS` 各一条越界硬错负例，接入 `check-ast.sh`；
3. 4 个 near-phase example：`examples/77_*`（freestanding/alloc、
   c-boundary/shim、emit-model、check --types），每个 20–40 行 +
   `expected.out`；
4. 计数脚本：`ls test/ast/errors/*.ct | wc -l` 与 `find test/ast -mindepth 1
   -maxdepth 1 -type d | wc -l` 回填 `test/README.md:6/19`。

## 复核（2026-11-20，REV）

**结论：REV 认可 defer 理由；`deferred` 属 REQ/USER，status 不动。**

```console
$ ls -d examples/*/ | wc -l
51
$ find test/ast -mindepth 1 -maxdepth 1 -type d | wc -l
299
$ ls test/ast/errors/*.ct | wc -l
295
$ find test/ast/errors -name '*.ct' | wc -l
337
$ command -v llvm-cov lcov gcov
/usr/bin/gcov
```

计数与处置段一致；覆盖率、ct-ast 白盒单测、容量夹具、near-phase example 是四项
独立交付物，各需自己的命令与输出（T-1/T-2），defer 理由成立。

## 处理（REQ，2026-11-21）

- 状态：`deferred`（P2，1.0 后质量批）
- 触发：v1.0 发布后，或 nightly 覆盖率任务启动时
- 不能关闭：覆盖率/单测/示例尚未交付；不在 1.0 硬门禁内

## 处置（2026-11-23，DEV，部分交付；status 不动）

TEST-23 的第 1–4 项与第 9 项在本批落地；第 5–8 项与第 10 项未做。
front-matter 仍是 `deferred`（是否转 `open`/`verified` 由 REQ 决定）。

| 缺口 | 本批交付 | 验收命令 / 输出 |
| --- | --- | --- |
| 1 行覆盖 | [`test/coverage/run.sh`](../../test/coverage/run.sh)（gcov，只报告）+ nightly `coverage` job + artifact | `bash test/coverage/run.sh` → `line coverage: 68.98%`（19935/28901，25 个源） |
| 2 ct-ast 白盒单测 | [`test/ast/test25_unit.sh`](../../test/ast/test25_unit.sh) + 三个 C 夹具：`tc_expr_num`/`tc_expr_fnum`/`type_key`、`ctype_adtctor`/`ctype_opt`/`ctype_slice_get`/`ctype_slice_range`、`em_expr_num`/`map_clean_type`/`map_recipe_callee` | `test25unit: 3 passed, 0 failed`；由 `check-ast.sh` 调用 |
| 3 容量 | `io_names` 1024 临界 + 1025 越界；越界文案写上单元名与上限 | `check-ast.sh` 的 capacity 段 |
| 9 近相 example | `examples/54_freestanding_alloc`、`55_c_boundary_shim`、`56_emit_model`、`57_check_types` | `sh test/run.sh` 的 near-phase 层 4 项 `ok` |

红证（基线 `43b1b086`，实现前）：

```console
$ <基线 ct-ast> /tmp/cap_io_names.ct -o /tmp/cap_io_names.c
/tmp/cap_io_names.ct:2052:12: error: too many distinct calls
rc=1
$ python3 test/coverage/selftest.py
FAIL coverage-wiring: nightly.yml: no 'coverage:' job
rc=1
```

绿（本批 HEAD）：

```console
$ python3 test/coverage/selftest.py
coverage-wiring: 1 real check + 5 negative mutations, all as expected
$ sh test/run.sh
== summary: 165 passed, 0 failed ==
```

未做：第 5 项（sanitizer/fuzz 进本地）、第 6/10 项（计数脚本回填 test/README 的旧数字）、
第 7 项（`49_socket` 依赖的 std API）、第 8 项（ICCARM 等工具链矩阵）。

## 处置（REQ，2026-11-23）：剩余项 deferred

已交付：4 个近相 example（54–57）、io_names 边界、覆盖率报告、runner 计数回填。
剩余第 5–8 项（sanitizer/fuzz 进硬门禁、`49_socket` 的 std API、ICCARM 工具链矩阵）需外部工具链/
std 包，触发：v1.1 工具链矩阵立项；当前不阻塞 v1.0。
