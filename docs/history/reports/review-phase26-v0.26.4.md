# v0.26.4 补丁 · 独立评审报告

> 评审对象：`v0.26.4` 候选树（Phase 26 之后的修复补丁，四项工作：TEST-18 / DOC-68 / CI-8 / DOC-66）。
> 评审方式：独立子会话（只读，无实现方上下文），自行构建自举链、实跑门禁、自建复现夹具。
> 结论：**release: GO**（P1–P7 PASS；P8 的 tag / 推送在放行后执行）。

---

## 1. 判据结论

| 判据 | 结论 | 评审实跑证据 |
| --- | --- | --- |
| P1 | PASS | `bash selfhost/check-ast.sh` → `== summary: 834 passed, 0 failed ==`；`130_generic_build_mode` 实跑 `6 42`、`131_generic_cross_unit` 实跑 `40`；131 的 `lib.c` 含 `static int twice__ct1(int x) {`，`prog.c` 中 `T` 计数为 0；`lib.h` 经 `hdr_instances` 为空 |
| P2 | PASS | 自检两条均 ok；评审按 `tparam_residue` / `fixture_sources` 原样复刻：脏 `lib.c` 在「全部单元」口径下得 `[T(1)]`，在「只读入口」口径下得 `[]`；干净产物两种口径皆空 |
| P3 | PASS | `check-index: 26 assertions, 0 failed`；`check-grammar.py` → `109 checks, 0 failed`；把 `TPARAMS` 置空 → `26 assertions, 12 failed`、退出 1 |
| P4 | PASS | `spec pin: ok (1.0.0, 93a8e968)`，与 `sha256sum` 主规范一致；篡改副本 → `mismatch` + 1 错；版本落后 → `stale` + 1 错；规范缺席 → `skipped (spec not found)`、0 错；删登记行 → `missing` + 1 错 |
| P5 | PASS | `design window: ok (10/12)`；13 个 design 文件 → 红；恰好 12 个 → 绿；再加 phase15 → 只报 phase15；双存 → duplicate 红；README 缺声明 → 红 |
| P6 | PASS | `check-all: OK (11 hard gates green)`；`834 passed, 0 failed`；`check-warnings: 253 ok, 0 failed`；`check-goldens: OK`；single 3 / multi 4 均 `0 regression`；`check-docs: OK (875 links / 174 files)`。不低于基线 830 |
| P7 | PASS | 五处 `CTC_VERSION`（`l0` / `l1` / `l2/core` / `l2/driver` / `ct-ast/main`）一致（`0.26.4`）；剔除版本串后 `8c88211..HEAD` 在 `selfhost/{l0,l1,l2,ct-ast}` 无语义改动；发布提交的 74 个 golden 仅版本 token 变化 |
| P8 | 发布前不可判 | 复核时 `origin/main` 停在 `8c88211`；树干净、门禁全绿 → **release-ready**。tag 与推送状态见 [phase26.md §9.1](../../design/phase26.md) |

## 2. 评审发现与处置

| # | 严重度 | 发现 | 处置 |
| --- | --- | --- | --- |
| 1 | minor | 扫描器 fail-open：实例体提取要求 `__ctN(` 与 `{` 同行、类型参数声明在列 1；自检只覆盖 K&R | 记入 [phase26.md §2.7](../../design/phase26.md) 的「扫描器的书写形态假设」行，附触发信号与届时改法（按花括号深度匹配 + Allman 自检样本）。当前发射器恒为 K&R + 列 1，不构成现存风险 |
| 2 | minor | 文档称实例体在 `extra/lib.c`，实际 `-o` 扁平化为 `lib.c` | 已更正 `phase26.md` §9 与 TEST-18 处置段 |
| 3 | minor | design-window 红证记「两条错误」，实测 15 条（max=99 时全部既有阶段与 80 越界，另加 duplicate 与两条缺状态行） | 已按实测改写 `phase26.md` §9 |
| 4 | minor | `spec pin:` 状态行只在成功路径打印，失败时只剩笼统 `FAIL` | `fix(check-docs): print the spec pin state before the failure summary` 把两条状态行移到失败分支之前 |

## 3. 复核范围与边界

- 评审未修改仓库文件；临时产物（`hdr_clean.h`、`test/docs/__pycache__/`）已删，`git status` 为空。
- 评审自建自举链（L0 → L1 → L2 → `ct-ast`，版本串 `0.26.4`），未复用实现方的构建产物。
- 四个 backlog 条目的处置段（TEST-18 / DOC-68 / CI-8 / DOC-66）与代码、门禁输出逐条比对一致。
- `phase26.md` §2.7 的覆盖表与实测相符，没有「不支持跨单元、不适用」这类失实论证。

## 4. 放行

`release: GO`。P8 的完成由发布后的远端 hash 核对回写（见 [phase26.md §9](../../design/phase26.md)）。
