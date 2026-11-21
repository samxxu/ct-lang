# DOC-81 · PH-85 收口提交的干净归档 check-docs 因 docs/README 死链失败

| 项 | 值 |
| --- | --- |
| 模块 | docs（收口文档 / 门禁证据） |
| 定性 | 提交树死链（工作树绿、归档红） |
| 严重度 | High（E85-7 与 v0.85.0 收口证据不成立） |
| 锚点 | `e0b0c561`（v0.85.0，2026-11-21） |
| 文件 | `docs/README.md:21`；`docs/guide-for-c-programmers.md`（未入库）；`issues/selfhost/sh106-str-view-escape-no-lint.md`（未入库） |
| 状态 | **open** |

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

PH-85 卡 §7.4 记的是 `check-docs: OK (2295 relative links in 377 files, v0.85.0, …)`，
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

- [PH-85 卡](../../docs/design/phase85.md) §7.4、E85-7
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
