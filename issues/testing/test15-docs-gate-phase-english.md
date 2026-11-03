# TEST-15 · docs 门禁只覆盖中文 phase 表，且不扫 `ci.yml`

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Low |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [test/docs/check-docs.py:141-173](../../test/docs/check-docs.py#L141-L173)；gate 计数校验 [L120-138](../../test/docs/check-docs.py#L120-L138) |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

`check-docs.py` 的 `check_phase_status` 只做两件事：

1. 遍历 `docs/design/phase*.md`（当前为 phase17 / phase18 / phase19 三份）；
2. 用 `re.search(r"^\|\s*Phase\s+<n>\s*\|")` 取阶段总览的**中文首行**，再看该行是否含 `完成` / `in progress`。

英文表的状态行形如 `| 18 | … |`，正则不匹配，因此英文状态从未被校验。DIAG-61 这类漂移正是由此漏网。

另有一处：gate 计数与 `issues` marker 的校验（`:120-138`）只读 README / docs / glossary，
不读 `.github/workflows/ci.yml`，所以 CI-6 的 `nine hard gates` 也不会让门禁失败。

## 证据

```text
$ sed -n '141,173p' test/docs/check-docs.py
# check_phase_status: for path in ... phase*.md
#   m = re.search(r"^\|\s*Phase\s+" + number + r"\s*\|", line, re.M)
```

- 实测把英文 `docs/roadmap.md:975` 保持 `🟨 in progress` 时，门禁仍绿。
- `.github/workflows/ci.yml:22`、`:33` 写 `nine hard gates`，门禁仍绿。
- 仓库内被扫描的 phase 文件只有 3 份，历史设计文档（`docs/history/design/phase*.md`）不在范围内。

## 影响

Low：现状不会导致错误构建，但门禁对「英文表状态」「CI job 名」两类高频漂移完全失明；同类问题已发生
三次（DOC-56 → DOC-58 → CI-6），继续靠人工复核的成本高于加断言。

## 修复建议

1. 英文行也匹配（例如 `^\|\s*{n}\s*\|`），中英任一为 `in progress` 即失败；
2. 把 `ci.yml` 的 gate 文案纳入校验：要么校验不含旧数字，要么让 job 名直接引用
   `issues/README.md` 的 `<!-- gates:N -->`；
3. 是否把 `docs/history/design/phase*.md` 纳入扫描需先确认（历史文档若要冻结，应显式排除并写注释）。

## 验证

- 临时把英文 Phase 18 改回 `in progress`：门禁应失败；恢复后通过；
- 临时把 `ci.yml` 的 `12` 改回 `nine`：门禁应失败；恢复后通过；
- `python3 test/docs/check-docs.py` 在正常树上仍为绿。

## 处置

**认可，已修。建议 1、2 落地；建议 3 不做。**

- 建议 1：`check_phase_status` 在找到英文行 `| n |` 时，要求同一 emoji 出现；中英任一不一致即失败。
- 建议 2：`check_gate_count` 解析 `.github/workflows/ci.yml`，把 `N hard gates` 与
  `nine|ten|eleven|twelve hard gates` 同实际 `run_gate` 数比对。CI-6 已把数字从文案里去掉，这条断言
  防的是重新写回。
- 建议 3：`docs/history/design/phase*.md` 是历史冻结文档，不纳入。它们不承载现状，扫描反而会要求
  为旧状态补门禁；现文件头已注明「带日期的记录是当时口径」。
- 双向验证：英文 Phase 18 临时改回 `🟨 in progress` → `the English roadmap row disagrees`；
  `ci.yml` step 名临时改回 `nine hard gates` → `states 9 hard gates, check-all.sh runs 12`；
  恢复后 `check-docs: OK (… 12 hard gates, 3 phase status)`。
