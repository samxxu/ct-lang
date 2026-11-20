---
id: TEST-24
title: "PH-79 证据/任务声明与仓库不符：p79_index/places/migrate/docs 不存在、无红证基线"
status: open
area: testing
severity: P2
opened: 2026-11-20
confirmed-by: REV-PH-79
---

# TEST-24 · PH-79 的任务/红证与仓库对不上

## 来源

[PH-79 收口复核](../../docs/reviews/2026-11-20-phase79-rev-verdict.md) B4（G1/G5/T-7/PN-10）。

## 现象

卡面 `docs/design/phase79.md:67-73` 的验收列写了五个脚本：

| 任务 | 卡面验收 |
| --- | --- |
| S3a | `p79_basic` |
| S3b | `p79_index` |
| S3c | `p79_places` |
| S3d | `p79_migrate` |
| S3e | `p79_docs` |

仓库里实际只有 `test/ast/p79_basic.sh`：

```console
$ git archive v0.79.1 | tar -x -C /tmp/rev-ph79
$ ls /tmp/rev-ph79/test/ast/p79_*.sh
test/ast/p79_basic.sh
$ for f in p79_basic p79_index p79_places p79_migrate p79_docs; do
    [ -f /tmp/rev-ph79/test/ast/$f.sh ] && echo "present $f" || echo "MISSING $f"
  done
present p79_basic
MISSING p79_index
MISSING p79_places
MISSING p79_migrate
MISSING p79_docs
```

卡面 §2.1 还写 `p79_basic` 断言 `a[1..]` 与 `Vec.as_slice`，但实际夹具用的是
`s[1..]`，也没有 `Vec.as_slice`（§1.1 已把它延期）。卡面 §5 只列了 `p79_basic` 的 15 条绿输出。

红证也不存在：

```console
$ git show 255016e0 --format='%B' --no-patch
test(ct-ast): p79 S3 红
$ git show 255016e0:test/ast/p79_basic.sh | grep -c baseline
0
$ ls test/ast/p79_red* 2>/dev/null || echo "no p79 red log"
no p79 red log
```

`255016e0` 的正文没有 `baseline:`、命令、原始输出或退出码；实现提交 `dda27c19` 又往
`p79_basic.sh` 加了 7 个用例（`container`/`option`/`result`/`arrelem`/`iface`/`closure`/`ret`），
这些用例从未在实现前跑红。卡面 §2 要求“每项任务先提 `test(...) 红`（含 `baseline: <sha>`）”，
PN-10 也要求每个 stage 有独立红/绿提交；实际只有一个红提交且无红证。

## 期望

二选一：

1. 补齐 `p79_index`/`p79_places`/`p79_migrate`/`p79_docs`，每个有独立红证（`baseline` + 原始输出）
   与绿输出；或
2. 把卡面任务表改成如实反映单脚本 `p79_basic` 的覆盖，并按 T-7 补 `baseline: <sha>` 的红证
   （含实现前红、实现后绿）。

同时修正 §2.1 的 `a[1..]`/`Vec.as_slice` 声明，补齐 `box`（行为已红但夹具未覆盖）与
`p79_index` 的 trap/get/const 分组说明。

## 影响

卡面“S3a–S3e 已落”和“实现红证 VERIFY 见 §5”与仓库证据不符；G1/G5/T-7 的机械检查抓不到
“验收脚本不存在”与“红证为空”。这是流程/证据缺口，不改变 SH-99/100/101 的代码缺口性质。
