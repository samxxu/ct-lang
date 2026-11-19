# PH-75 收口复核（REV）

> **结论：`REV: 通过`**（附 4 项不阻断观察，见 §8）
> **复核对象**：`c827a5ae64179bc912933e6411a15c3943d3138a`
> （`feat(ast): PH-75 闭包作方法实参收口（v0.74.0）`），tag `v0.74.0`。
> **复核者**：REV / rev-ph75；日期 2026-11-19。
> **方法**：只依据提交与 clean 副本。用 clean clone/`git archive c827a5ae` 在
> `/tmp/rev-ph75` 重新自举 L0→L1→L2→ct-ast；红证在红提交的 clean 副本上重建编译器复现，
> 不采信转述，也不使用工作树当前产物。
> **并行说明**：复核期间工作树有另一会话的在途改动（`docs/design/phase65.md` 删除、
> `docs/design/phase77.md` 新增、`docs/roadmap.md`、`docs/session-map.md` 修改）。本报告全部
> 验收都在 `c827a5ae` 的 clean 副本上做；verdict 提交只含本文件，不触碰这些在途改动。

## 1 环境与自举

```console
$ uname -m; uname -sr; cc --version | head -1; git --version; gh --version | head -1
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)
git version 2.54.0 (Apple Git-157)
gh version 2.104.0 (2026-11-12)
$ W=/tmp/rev-ph75; mkdir -p $W
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o $W/ctc
$ $W/ctc selfhost/l1/ctc.ct -o $W/l1.c
$ cc -Wall -Wextra -std=c99 $W/l1.c -o $W/l1
$ $W/l1 build selfhost/l2/driver.ct -o $W/l2src
$ cc -Wall -Wextra -std=c99 $W/l2src/*.c -o $W/l2
$ $W/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o $W/astsrc
$ cc -Wall -Wextra -std=c99 $W/astsrc/*.c -o $W/ct-ast
$ $W/ct-ast --version
ct-ast v0.74.0
```

## 2 卡 §3/§7：两个探针

```console
$ bash test/ast/p75_closure.sh /tmp/rev-ph75/ct-ast
OK p75/closure (pair-form method argument)
rc=0
$ bash test/ast/p75_closure_neg.sh /tmp/rev-ph75/ct-ast
OK p75/closure-neg (literal + bound variable)
rc=0
```

与卡 §3 的 R1/R2 `verify`、§7 的 E75-1 一致。

## 3 行为复核

### 3.1 pair 形方法收闭包并运行

```console
$ /tmp/rev-ph75/ct-ast check --types pos.ct
rc=0
$ /tmp/rev-ph75/ct-ast build -o prog pos.ct
'cc' -std=c99 -I '.ctbuild' '.ctbuild/pos.c' '-o' 'prog'
rc=0
$ ./prog; echo $?
0
```

生成物确认按 `(tramp, &env)` 两参发射，不是把闭包当单槽：

```c
int r = b.__each_vptr->each(&b, __ct_cl_tramp_0,
                           &(struct __ct_cl_env_0){ b });
```

`pos.ct` 为卡 §7 的 pair 形（`int (*f)(void *env, int x), void *env`）与
`(int x) => b.total + x`；`r == 10` 时返回 0。

### 3.2 单 fp 形态硬错（字面量与绑定变量）

```console
$ /tmp/rev-ph75/ct-ast check --types lit.ct
lit.ct:4:39: error: a closure cannot be passed to a method argument yet (SH-65); pass '(fn, env)' explicitly
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph75/ct-ast check --types var.ct
var.ct:4:73: error: a closure cannot be passed to a method argument yet (SH-65); pass '(fn, env)' explicitly
ctc: 1 error(s) generated
rc=1
```

两种形态的 `build` 也都 `rc=1`、不产生产物，不再静默写未声明的标识符。

### 3.3 容器 `each` 未被误伤

```console
$ /tmp/rev-ph75/ct-ast build --emit-c -o /tmp/rev-ph75/out-generic_string_table \
    examples/18_generic_string_table/generic_string_table.ct
cc -std=c99 -I /tmp/rev-ph75/out-generic_string_table \
   /tmp/rev-ph75/out-generic_string_table/generic_string_table.c -o a.out
rc=0
$ /tmp/rev-ph75/ct-ast build --emit-c -o /tmp/rev-ph75/out-container_each_generic \
    examples/19_container_each_generic/container_each_generic.ct
cc -std=c99 -I /tmp/rev-ph75/out-container_each_generic \
   /tmp/rev-ph75/out-container_each_generic/container_each_generic.c -o a.out
rc=0
```

## 4 红证/实现配对

```console
$ git log --oneline --grep PH-75
c827a5ae feat(ast): PH-75 闭包作方法实参收口（v0.74.0）
74e58fe7 feat(ast): PH-75-R1 pair 形闭包作方法实参（SH-65）
eaa78050 test(ast): PH-75-R1 红（pair 形闭包作方法实参）
ffe3621d fix(ast): PH-75-R2 闭包拒绝只作用于 struct/trait 方法
eb9280d6 feat(ast): PH-75-R2 闭包作方法实参硬错（SH-65/SH-67）
542c19ba test(ast): PH-75-R2 红（闭包作方法实参静默）
$ git rev-parse eaa78050^ 74e58fe7^ 542c19ba^ eb9280d6^
2f0ec52d50fd7d21840f523d33e0d35e7d0b6a56
eaa78050ee9754959001ad0d79ac176cef10dbb7
5d271142f74606fff73d9bf5d87add12351535ab
542c19bae29a796f2bf758affbe1d9126798bfb8
$ git merge-base --is-ancestor eaa78050 74e58fe7 && echo yes
yes
$ git merge-base --is-ancestor 542c19ba eb9280d6 && echo yes
yes
```

R1、R2 的 `test(...) 红` 都是对应实现提交的**直接父提交**；两个 `baseline`
（`2f0ec52d`、`5d271142`）分别是红提交的父提交，且都是 `HEAD` 的祖先。配对成立。

在 clean 副本上重建红提交的编译器复跑，红证确实红：

```console
$ git archive eaa78050 | tar -x -C /tmp/rev-ph75/red1   # 源码同 baseline 2f0ec52d
$ /tmp/rev-ph75/l2 build -I red1/selfhost/ct-ast red1/selfhost/ct-ast/main.ct -o red1/astsrc
$ cc -std=c99 red1/astsrc/*.c -o red1/ct-ast            # ct-ast v0.73.0
$ bash test/ast/p75_closure.sh /tmp/rev-ph75/red1/ct-ast
FAIL p75/closure: pair-form check rejected
  pos.ct:8:15: error: a closure cannot be passed to a method argument yet (SH-65); pass '(fn, env)' explicitly
FAIL p75/closure: pair-form build failed
rc=1
$ git archive 542c19ba | tar -x -C /tmp/rev-ph75/red2
$ ... 同链重建 ... && bash test/ast/p75_closure_neg.sh /tmp/rev-ph75/red2/ct-ast
FAIL p75/closure-neg: lit not refused
FAIL p75/closure-neg: var not refused
rc=1
```

红提交的 `baseline` 与相邻关系成立；红→绿全由实现提交转绿。

## 5 版本与 tag

五处 `CTC_VERSION` 全为 `0.74.0`：

```console
$ grep -rho 'CTC_VERSION "[^"]*"' \
    selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
    selfhost/l2/driver.ct selfhost/ct-ast/main.ct | sort | uniq -c
   5 CTC_VERSION "0.74.0"
```

tag 为 annotated，对象 / peeled / 远端一致：

```console
$ git cat-file -t v0.74.0
tag
$ git rev-parse v0.74.0 v0.74.0^{}
8021f511018812d6975d4fa3fed848a84326b45a
c827a5ae64179bc912933e6411a15c3943d3138a
$ git cat-file -p v0.74.0 | tail -2

PH-75 closeout (c827a5a)
$ git ls-remote --tags origin 'v0.74.0*'
8021f511018812d6975d4fa3fed848a84326b45a	refs/tags/v0.74.0
c827a5ae64179bc912933e6411a15c3943d3138a	refs/tags/v0.74.0^{}
$ git ls-remote origin refs/heads/main
c827a5ae64179bc912933e6411a15c3943d3138a	refs/heads/main
```

`v0.74.0` = PH-75、`d=1`（`AGENTS.md` 的 `version-minor-offset` 偏离登记），
与卡 §0 的 `version-minor: 74`、`docs/history/phase-log.md` 的 `v0.74.0` 行一致。

## 6 CI

`c827a5ae` 的 push run 三 job 全绿：

```console
$ gh run view 44467721235 --json headSha,status,conclusion,jobs --jq ...
{"headSha":"c827a5ae64179bc912933e6411a15c3943d3138a",
 "status":"completed","conclusion":"success",
 "jobs":[{"name":"ubuntu-gcc","conclusion":"success"},
          {"name":"macos-clang","conclusion":"success"},
          {"name":"ubuntu-clang-smoke","conclusion":"success"}]}
```

run：<https://github.com/samxxu/ct-lang/actions/runs/44467721235>

ubuntu-gcc 的 hard gates 原始输出：

```console
== summary: 1515 passed, 0 failed, 0 skipped ==
check-all: OK (11 hard gates green)
```

clean 副本上单独跑 check-ast（macOS 跳过 4 个需要 Linux Renode / GDB 的硬件探针）：

```console
$ cd /tmp/rev-ph75/clone && bash selfhost/check-ast.sh
== summary: 1511 passed, 0 failed, 4 skipped ==
```

与卡 §7 的 `check-ast 1511 passed` 一致（CI 的 1515 = 1511 + 本机跳过的 4 项）。
clean archive 上 docs 门禁同样通过：

```console
$ python3 test/docs/check-docs.py
check-docs: OK (1875 relative links in 316 files, v0.74.0, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
```

## 7 诚实性：§7 口径与实现一致，收口未夹带行为改动

- 收口提交 `c827a5ae` 对 `selfhost/ct-ast/{frontend,backend,tool}` 无 diff；golden 变化
  逐行只有 `Generated by ...` 版本 banner，无其他差异——是纯收口提交，行为实现留在
  R1/R2 两个实现提交里。
- 实现口径与 §7 一致：只有 2 参且第二参为 `void *` 的 pair 形方法收闭包并发射
  `(tramp, &env)`；单函数指针形（字面量与绑定变量）都硬错；容器类型在拒绝逻辑里豁免。
- 未把未做写成完成：R1 的 pair 形正例与 R2 的单 fp 负例都由独立探针复现为绿。

## 8 观察（不阻断）

1. **R1 红证引用的原始输出与声明的 baseline 不符。** `eaa78050` 正文写
   `baseline: 2f0ec52d`，引用 `arity mismatch` 与 `unknown expression node`；但在
   `2f0ec52d` 上复跑，实际的失败是 R2 已落地的
   `a closure cannot be passed to a method argument yet (SH-65)`（见 §4）。红仍然红、
   配对也成立，故不阻断；但红证文字是更早基线的旧输出，建议在下次触碰该记录时更正。
2. **两个 Issue 的处置段写了不存在的 sha。** `issues/selfhost/sh65-...md:124` 与
   `issues/selfhost/sh67-...md:134` 均写「提交：`5f0e1e9?`」；`git cat-file -e 5f0e1e9`
   与 `git log --all` 都找不到该对象。实际实现是 `74e58fe7`（R1）、`eb9280d6`（R2）+
   `ffe3621d`（R2 收窄）。属证据记录笔误，建议更正。
3. **SH-65/SH-67 的 `status` 仍为 `open`。** DEV 只写了处置段（符合 5.4「DEV 不动状态
   字段」），REV 的 `verified` 尚未落账。本报告按任务边界只提交 verdict、不改台账；建议
   另由 REV 按 5.4 置为 `verified` 并引用本报告。
4. **§7 的「pair 形收闭包」实际收的是闭包字面量。** 把闭包先绑到变量再传给 pair 形方法仍
   被拒（`int (*f)(int)` 报 SH-65 硬错；`int (*f)(void *, int)` 报
   `this closure takes 1 parameters, but the expected type takes 2`）。§7 没有把该形态写成
   已完成，故不构成「未做写成完成」；但措辞可收窄为「pair 形方法收闭包**字面量**」，免得
   读者把绑定变量也算进已支持面。

## 9 结论

卡 §3/§7 的两个探针、pair 形行为、单 fp 硬错、容器豁免、红/绿配对、五处版本、tag 与
CI 三 job 均与收口主张一致；未发现把未做写成完成。

`REV: 通过`
