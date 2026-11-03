# DOC-58 · `issues/README.md` 的门禁口径在 Phase 19 后再次过期（11 道 / 映射错误）

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low |
| 锚点 | commit `db4cae4`（2026-11-03，`v0.19.0`） |
| 文件 | [issues/README.md:57](../../issues/README.md#L57) |
| 状态 | 已修复（本轮，2026-11-03） |
| 关联 | [DOC-56](doc56-issues-readme-gate-count.md)（2026-11-02 已修，本轮再次漂移） |

## 现象

第 57 行自报「现状一律以此为口径」，但三处数字都已过期：

```text
- 硬关卡计数随阶段演进：6 → 7 → 8 → 9 → 10 → **11**（当前共 **11** 道：第 10 道是文档门禁
  `test/docs/check-docs.py`，第 11 道是 `test/std/run.sh`；…）。
  …现状一律以 `check-all.sh` 的「11 hard gates green」与 roadmap 为准。
```

## 证据

`selfhost/check-all.sh` 当前 12 个 `run_gate`（顺序即编号）：

```text
 10) std layer (Phase 17.2)
 11) semantic entry (Phase 19.4)      ← Phase 19 新增
 12) docs (links, version, gate count, phase status)
```

- `python3 test/docs/check-docs.py` → `OK (678 relative links in 155 files, v0.19.0, 12 hard gates, …)`。
- 第 10 道是 **std**、第 11 道是 **semantics**、第 12 道才是 **docs**；原文把 docs 写成第 10、
  std 写成第 11，与现状正好错位。

## 原因

`test/docs/check-docs.py` 的扫描面是 `docs/**`、根 `README.md` 与 `docs/glossary.md`，
**不包含 `issues/README.md`**。Phase 19 加门禁时，文档门禁为绿，台账这一行没有任何机制会把它挡住，
于是同一处措辞第二次漂移。

## 影响

台账开头把这一行当作「现状口径」，读者（包括下一轮审查）会据此按 11 道验收；`docs/README.md`、
根 `README.md`、`glossary.md` 又都写 12 道，形成对外不一致。

## 修复建议

1. 改为：`6 → 7 → 8 → 9 → 10 → 11 → **12**（当前共 12 道：10 = std、11 = semantic entry、12 = docs）`；
   结尾的 `「12 hard gates green」` 同步。
2. 去掉 `check-all.sh` 的行号区间，改为不带行号的引用（该区间已漂移两次）。
3. 可选（治本）：让 `test/docs/check-docs.py` 也扫描 `issues/README.md` 的硬关卡数字，
   或在 `check-all.sh` 里加一条 `grep` 断言，使台账数字跟随 `run_gate` 计数。

## 处置

**认可，已修。** 采纳建议 1、2、3 的「机器可读」变体。

- 台账现状段改为 12 道并修正映射（10 = std、11 = semantic entry、12 = docs），删掉 `check-all.sh`
  的行号区间，见 [issues/README.md:65-71](../../issues/README.md#L65-L71)。
- 治本选了**标记法**而非全文扫描：本文件的带日期验证记录里保留了当时的旧口径（`8 hard gates green`、
  `9 关` 等），把整份文件交给 `GATE_CLAIM` 会一次性报 17 条历史失真。于是在现状段放
  `<!-- gates:12 -->`，由 [check-docs.py](../../test/docs/check-docs.py#L129-L137) 只校验这个标记。
- 双向验证：标记为 `12` 时 `python3 test/docs/check-docs.py` → `OK (… 12 hard gates …)`；
  改成 `11` 后 → `FAIL: issues/README.md: marker says 11 hard gates, check-all.sh runs 12`。
- 未采用「让 `check-all.sh` 加 grep 断言」：计数真值已在 docs 门禁里，再加一处会形成第二个真值来源。
