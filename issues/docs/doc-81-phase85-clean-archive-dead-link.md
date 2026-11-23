# DOC-81 · v0-PH-85 收口提交的干净归档 check-docs 因 docs/README 死链失败

| 项 | 值 |
| --- | --- |
| 模块 | docs（收口文档 / 门禁证据） |
| 定性 | 提交树死链（工作树绿、归档红） |
| 严重度 | High（E85-7 与 v0.85.0 收口证据不成立） |
| 锚点 | `e0b0c561`（v0.85.0，2026-11-21） |
| 文件 | `docs/README.md:21`；`docs/guide-for-c-programmers.md`（未入库）；`issues/selfhost/sh106-str-view-escape-no-lint.md`（未入库） |
| 状态 | verified |
| 层级 | **Tier 2（`v1.0` 发布）**；须给“修/不修+理由”，见 [battle/v1-readiness-1](../../battle/v1-readiness-1/verdict.md) |
| 处置证据 | **复核通过（2026-11-22，REV）**：`v0.85.0` tag 干净归档 `check-docs` 退出 0；当前 HEAD 归档亦 0；guide/SH-106 已入库，工作树链接不再悬空 |

## 现象

`e0b0c561` 在 `docs/README.md` 新增一行
`[guide-for-c-programmers.md](guide-for-c-programmers.md)`，但 `docs/guide-for-c-programmers.md`
不在该提交的树里（工作树里是其他会话的未跟踪文件）。因此**从提交归档**跑门禁 11 必红：

```console
$ R=$(mktemp -d /tmp/ph85docs.XXXXXX); git archive e0b0c561 | tar -x -C "$R"
$ (cd "$R" && python3 test/docs/check-docs.py); echo rc=$?
FAIL: docs/README.md: dead link -> guide-for-c-programmers.md
spec pin: skipped (master spec draft 1.17.0)
check-docs: FAIL (1 problem(s))
rc=1
```

把工作树的未跟踪 guide 临时补进归档后，它自己又链到未入库的
`issues/selfhost/sh106-str-view-escape-no-lint.md`，仍然红：

```console
$ cp docs/guide-for-c-programmers.md "$R/docs/"
$ (cd "$R" && python3 test/docs/check-docs.py); echo rc=$?
FAIL: docs/guide-for-c-programmers.md: dead link -> ../issues/selfhost/sh106-str-view-escape-no-lint.md
spec pin: skipped (master spec draft 1.17.0)
check-docs: FAIL (1 problem(s))
rc=1
```

同一命令在工作树里是绿的，因为未跟踪文件恰好存在：

```console
$ python3 test/docs/check-docs.py; echo rc=$?
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (2318 relative links in 378 files, v0.85.0, 11 hard gates, 12 phase status, 6 适用版本 header(s), 2 superseded link(s), 10 signoff(s))
design window: ok (12/12)
rc=0
```

v0-PH-85 卡 §7.4 记的是 `check-docs: OK (2295 relative links in 377 files, v0.85.0, …)`，
与工作树的 2318/378 也对不上：收口证据是在**加 guide 行之前**跑的，加行后没有重跑
归档树。

## 期望

- `git archive <收口 sha> | tar -x` 后 `python3 test/docs/check-docs.py` 退出 0；
- `docs/README.md` 不链接未入库文件；若 guide 要作为正式文档，guide 与它引用的
  SH-106 必须在同一提交或更早提交入库；否则先删该行；
- 收口证据必须用归档树，不得用含未跟踪文件的工作树。

## 验收

- `R=$(mktemp -d); git archive e0b0c561 | tar -x -C "$R"; (cd "$R" && python3 test/docs/check-docs.py)` 退出 0；
- `bash selfhost/check-all.sh`（同一归档）11/11 绿；
- 若走 fix 提交，按 6.7 V-3 只 bump 一次 PATCH（v0.85.1），并引用本条目。

## 关联

- [v0-PH-85 卡](../../docs/phases/v0-PH-85/card.md) §7.4、E85-7
- [REV 复核](../../docs/reviews/2026-11-21-phase85-rev-verdict.md) §4.1

## DEV 处置（2026-11-21）

已修，且按 REV 允许的方式**重写本地未推历史**（不新增 PATCH：v0.85.0 从未 push/tag，
收口提交本身被重写，6.7 V-3 的 fix/PATCH 路径不适用；版本仍 0.85.0，五处一致）。

修法：从 `docs/README.md` 移除指向未入库 `guide-for-c-programmers.md` 的一行；**未触碰**
另一席位的未跟踪 guide 与其 SH-106 链接。

验证（干净归档，判据树 = `git archive HEAD`）：

```console
$ R=$(mktemp -d /tmp/ph85docs.XXXXXX); git archive HEAD | tar -x -C "$R"
$ (cd "$R" && python3 test/docs/check-docs.py); echo rc=$?
check-docs: OK (2317 relative links in 378 files, v0.85.0, 11 hard gates,
             12 phase status, 5 适用版本 header(s), 2 superseded link(s),
             10 signoff(s))
design window: ok (12/12)
rc=0
```

`bash selfhost/check-all.sh` 的 11 门见卡 §7.4/§7.7；`bash tools/check.sh g8` 绿。

## 复核（2026-11-22，REV）

**结论：`verified`。** 原验收把锚点钉在 `e0b0c561`，该提交是 2026-11-21 重写本地未推历史
**之前**的收口对象；重写后已不是 `HEAD` 的祖先（`git merge-base --is-ancestor e0b0c561 HEAD`
返回 1），对它的归档仍红是旧态，不是当前缺陷。等价收口是 annotated tag `v0.85.0`
（`1e2c30f7`，含 F1 修复与 REV 复核）。

### 复核命令与原始输出

```console
$ git rev-parse v0.85.0^{commit}
1e2c30f76889bc52c3f2fde52106c07c474b1dd0

$ R=$(mktemp -d /tmp/ph85tag.XXXXXX); git archive v0.85.0 | tar -x -C "$R"
$ (cd "$R" && python3 test/docs/check-docs.py); echo rc=$?
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (2332 relative links in 379 files, v0.85.0, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 11 signoff(s))
design window: ok (12/12)
rc=0

$ git merge-base --is-ancestor e0b0c561 HEAD; echo rc=$?
rc=1

$ git ls-files docs/guide-for-c-programmers.md issues/selfhost/sh106-str-view-escape-no-lint.md
docs/guide-for-c-programmers.md
issues/selfhost/sh106-str-view-escape-no-lint.md

$ R2=$(mktemp -d /tmp/ph85head.XXXXXX); git archive HEAD | tar -x -C "$R2"
$ (cd "$R2" && python3 test/docs/check-docs.py); echo rc=$?
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (2601 relative links in 401 files, v0.88.2, 11 hard gates, 12 phase status, 7 适用版本 header(s), 2 superseded link(s), 9 signoff(s), 10 briefing item(s), 34 J-6 row(s), 28 stability row(s), 3 compat marker(s), 20 capability row(s))
design window: ok (12/12)
rc=0
```

`docs/README.md` 现链接 `guide-for-c-programmers.md`；该文件与它引用的 SH-106 均已入库，
所以当前工作树与 HEAD 归档都不再是“工作树绿、归档红”。v0.85.0 收口树则已移除该行
（`git cat-file -e v0.85.0:docs/guide-for-c-programmers.md` 失败，但归档 `check-docs` 绿），
与 DEV 处置一致。
