# v0-PH-74 收口复核（REV）

> **结论：`REV: 通过`**（附 3 项不阻断观察，见 §8）
> **复核对象**：`5d271142f74606fff73d9bf5d87add12351535ab`
> （`feat(ast): v0-PH-74 模型导出收口（v0.73.0）`），tag `v0.73.0`。
> **复核者**：REV / rev-ph74；日期 2026-11-19。
> **方法**：只依据提交与 clean archive。用 `git archive 5d271142` 在 `/tmp/rev74-t/src`
> 重新自举 L0→L1→L2→ct-ast；红证用 `git archive ee1e06d7` 在 `/tmp/rev74-base` 重建同一条链
> 复现，不采信转述。验收命令全部在 clean 树上跑，不使用工作树当前产物。
> **并行说明**：复核期间工作树有未跟踪目录 `battle/static-dispatch-1/`，本报告与 verdict 提交
> 不触碰它。

## 1 环境与自举

```console
$ uname -m; uname -sr; cc --version | head -1; git --version; gh --version | head -1
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)
git version 2.54.0 (Apple Git-157)
gh version 2.104.0 (2026-11-12)
$ rm -rf /tmp/rev74-t && mkdir -p /tmp/rev74-t/src
$ git archive 5d271142 | tar -x -C /tmp/rev74-t/src
$ cd /tmp/rev74-t/src && mkdir -p /tmp/rev74-t/l2src /tmp/rev74-t/astsrc
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev74-t/ctc
$ /tmp/rev74-t/ctc selfhost/l1/ctc.ct -o /tmp/rev74-t/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev74-t/l1.c -o /tmp/rev74-t/l1
$ /tmp/rev74-t/l1 build selfhost/l2/driver.ct -o /tmp/rev74-t/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev74-t/l2src/*.c -o /tmp/rev74-t/l2
$ /tmp/rev74-t/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev74-t/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev74-t/astsrc/*.c -o /tmp/rev74-t/ct-ast
$ /tmp/rev74-t/ct-ast -v
ct-ast v0.73.0
```

红证基线同链自举（`git archive ee1e06d7` → `/tmp/rev74-base`），`-v` 为 `ct-ast v0.72.0`。

## 2 卡 §3/§6：两个探针与 check-all

clean `5d271142` 树上全部 `rc=0`：

```console
$ sh test/ast/p74_model.sh /tmp/rev74-t/ct-ast
OK p74/model (J11 loc + entry unit)
exit=0
$ sh test/ast/p74_map.sh /tmp/rev74-t/ct-ast
OK p74/map (lib facet + entry file)
exit=0
```

E74-3 用 clean 树跑全量门禁：

```console
$ bash selfhost/check-all.sh
  ok    v0-PH-74-R1/R2 model (J11 loc + entry unit)
  ok    v0-PH-74-R3 map (lib facet + entry file)
...
== summary: 1509 passed, 0 failed, 4 skipped ==
...
check-all: OK (11 hard gates green)
```

与卡 §6 的 `11/11`、`check-ast 1509 passed` 一致。

## 3 行为复核

### 3.1 model JSON 的 `loc.line/col`

独立夹具（非 v0-PH-74 探针）：

```console
$ printf 'struct S { int a; };\nint f(void) { return 0; }\n' > m.ct
$ /tmp/rev74-t/ct-ast build --emit-c --emit-model model.json m.ct -o out
$ python3 -c 'import json;m=json.load(open("model.json"));print(m["file"]);print(m["structs"][0]["fields"][0])'
m.ct
{'name': 'a', 'type': 'int', 'visibility': 'unknown', 'loc': {'file': 'm.ct', 'line': 1, 'col': 16}}
```

`int a` 的列号 16 与卡 §6 一致；model 以 entry 单元 `m.ct` 为对象。

### 3.2 `--lib --emit-map` 落盘与 build map 的 `file`

```console
$ /tmp/rev74-t/ct-ast build --lib --emit-map libmap.json -I . lib/lib.h.ct -o out/lib.a
$ wc -c libmap.json
302 libmap.json
$ python3 -m json.tool libmap.json | head
{
    "compiler": "ct v0.73.0",
    "file": "lib/lib.h.ct",
...
$ /tmp/rev74-t/ct-ast build --emit-map nb.json -I . main.ct -o out/prog
$ grep -o '"file":"[^"]*"' nb.json | head -1
"file":"main.ct"
```

lib 模式产物确实落盘；build map 的顶层 `file` 是 entry 单元 `main.ct`，不是内置层
`lib/std/...`。SH-79 两个 facet 都成立。

## 4 红证/实现配对

```console
$ git rev-parse 0ac39705^ ffc08538^
ee1e06d7a2c0abac033af977f52d83a5c2b5b8dc
0ac397053ce6695bdc03d1ba1d8f719b60c2f87d
$ git merge-base --is-ancestor 0ac39705 ffc08538 && echo yes
yes
```

`0ac39705`（`test(ast): v0-PH-74 红`）的父提交是 `ee1e06d7`，且它是 `ffc08538`
（`feat(ast): v0-PH-74 模型行列与 SH-79 两 facet`）的父提交；红→绿相邻，配对成立。

用 clean 树探针跑基线 `ee1e06d7` 产物，红证可复现：

```console
$ sh test/ast/p74_model.sh /tmp/rev74-base/ct-ast
Traceback (most recent call last):
  File "<stdin>", line 7, in <module>
KeyError: 'col'
exit=1
$ sh test/ast/p74_map.sh /tmp/rev74-base/ct-ast
FAIL p74/map: --lib --emit-map wrote no file
  'cc' '-std=c99' '-fvisibility=hidden' '-I' '.ctbuild' '-c' '.ctbuild/lib.c' '-o' '.ctbuild/lib.o'
  'ar' 'rcs' 'out/lib.a' '.ctbuild/lib.o'
exit=1
```

红提交正文写的 `baseline: ee1e06d7，ct-0720` 与实跑一致。

## 5 版本与 tag

五处 `CTC_VERSION` 全为 `0.73.0`：

```console
$ grep -rho 'CTC_VERSION "[^"]*"' \
    selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
    selfhost/l2/driver.ct selfhost/ct-ast/main.ct | sort | uniq -c
   5 CTC_VERSION "0.73.0"
```

tag 为 annotated，对象/peeled/远端一致：

```console
$ git cat-file -t v0.73.0
tag
$ git rev-parse v0.73.0 v0.73.0^{}
81c7a709f1850b7eee3cf74a13f93f3054005a18
5d271142f74606fff73d9bf5d87add12351535ab
$ git cat-file -p v0.73.0 | tail -2
v0-PH-74 closeout (5d27114)
$ git ls-remote --tags origin 'v0.73.0*'
81c7a709f1850b7eee3cf74a13f93f3054005a18	refs/tags/v0.73.0
5d271142f74606fff73d9bf5d87add12351535ab	refs/tags/v0.73.0^{}
$ git ls-remote origin refs/heads/main
5d271142f74606fff73d9bf5d87add12351535ab	refs/heads/main
```

tag message 含 phase 与收口 sha 前 7 位；`v0.73.0` = 83（v0-PH-74，`d=1`）符合 `AGENTS.md`
的 `version-minor-offset` 偏离登记。

## 6 CI

`5d271142` 的 push run 三 job 全绿，未被并发取消：

```console
$ gh run view 44463399586 --json headSha,conclusion,jobs --jq ...
{"headSha":"5d271142f74606fff73d9bf5d87add12351535ab",
 "conclusion":"success",
 "jobs":[{"name":"macos-clang","conclusion":"success"},
          {"name":"ubuntu-gcc","conclusion":"success"},
          {"name":"ubuntu-clang-smoke","conclusion":"success"}]}
```

run：https://github.com/samxxu/ct-lang/actions/runs/44463399586

## 7 诚实性：字段面未被改动破坏

v0-PH-74 的实现 diff 只在 Emitter 的 `loc` 加 `col`、Module 加 `model_unit` 与 entry 选择，
未改 `pub` 字段可见性/ABI 导出面。旧回归全绿：

```console
$ bash test/modules/p39_lib/r8_probe.sh /tmp/rev74-t/ct-ast
p39_r8: OK
$ /tmp/rev74-t/ct-ast build --emit-c test/modules/split/main.ct -o /tmp/rev74-t/split
$ cc -Wall -Wextra -std=c99 /tmp/rev74-t/split/*.c -o /tmp/rev74-t/split.bin
$ /tmp/rev74-t/split.bin
woof 7
$ bash test/ast/p73_export.sh /tmp/rev74-t/ct-ast
OK p73/export (pub field surface)
$ bash test/ast/p73_abi.sh /tmp/rev74-t/ct-ast
OK p73/abi (duplicate struct refused)
```

收口提交的 golden 变化仅 banner：50 个 `test/cases/*.expected.*` 的 diff 行全部是
`Generated by ...` 版本行，无其他差异。

## 8 观察（不阻断）

1. 卡 §3 的 R1 行 `verify` 写的是 `bash test/ast/p74_j11.sh`，但仓库从未有该文件
   （`find`/`git log --all` 均无）；R1 实际由 `p74_model.sh` 的 `loc.line/col` 断言与
   check-all 覆盖，§6 引用的也是 `p74/model`。属卡片文字与实现不一致，建议在卡片解冻时
   把 §3 的 R1 `verify` 改为 `p74_model.sh`，或补上 `p74_j11.sh`。
2. SH-79 处置段写「提交：`a0f2e2c`」，该 sha 在仓库中不存在（`git cat-file -t a0f2e2c`
   → `fatal: Not a valid object name`）；实际实现是 `ffc08538`。属证据记录笔误，建议更正。
3. SH-79 台账 `status` 仍为 `open`；DEV 只写了处置段（符合 5.4「DEV 不动状态字段」），
   REV 的 `verified` 尚未落账。本报告只做 phase 收口复核、未改台账，建议另由 REV 按 5.4
   把 SH-79 置为 `verified` 并写独立复现证据。

## 9 结论

卡 §3/§6 的探针、行为、红绿配对、版本/tag、CI 与旧回归均与收口主张一致。

`REV: 通过`
