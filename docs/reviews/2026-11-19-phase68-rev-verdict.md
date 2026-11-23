# v0-PH-68 收口复核（REV）

> **结论**：`REV: 通过`（附 3 项不阻断观察，见 §6）
> **复核者**：REV / rev-ph68；日期 2026-11-19；HEAD `bf8190b182d7062ec6c10364a08db92a8d6ccdf3`。
> **方法**：只依据 HEAD 源码与 CI。按 `selfhost/check-ast.sh` 的同一条链，从 L0 重新自举
> L1→L2→ct-ast 到 `/tmp/rev68`，**不使用工作树里的旧二进制**；红证用 `git archive <baseline>`
> 导出后重建同一条链复现，不采信转述。

## 0 环境与自举

```console
$ uname -a
Darwin ... 27.2.0 Darwin Kernel Version 27.2.0 ... arm64
$ cc --version | head -1
Apple clang version 21.0.0 (clang-2100.4.1.1)
$ git rev-parse HEAD
bf8190b182d7062ec6c10364a08db92a8d6ccdf3
$ /tmp/rev68/ct-ast -v
ct-ast v0.67.0
```

自举命令（与 `check-ast.sh:404-431` 一致）：

```sh
cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev68/ctc
/tmp/rev68/ctc selfhost/l1/ctc.ct -o /tmp/rev68/l1.c
cc -Wall -Wextra -std=c99 /tmp/rev68/l1.c -o /tmp/rev68/l1
/tmp/rev68/l1 build selfhost/l2/driver.ct -o /tmp/rev68/l2src
cc -Wall -Wextra -std=c99 /tmp/rev68/l2src/*.c -o /tmp/rev68/l2
/tmp/rev68/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev68/astsrc
cc -Wall -Wextra -std=c99 /tmp/rev68/astsrc/*.c -o /tmp/rev68/ct-ast
# 结果：BUILD OK；l0/l1/l1b/l2b/astb 五个日志均为 0 字节（零警告）
```

## 1 E68-1…E68-4 逐条

### E68-1（234 / 数组维度）

```console
$ bash test/ast/p68_typebuf.sh /tmp/rev68/ct-ast
OK p68/typebuf (234 green)
exit=0
$ /tmp/rev68/ct-ast check --types test/ast/234_err_return_contract/prog.ct; echo rc=$?
rc=0
```

234 的 `initializer:` 误报已消失（无输出、rc=0）。

### E68-2（表达式类型表）

```console
$ bash test/ast/p68_exprtypes.sh /tmp/rev68/ct-ast
OK p68/exprtypes
exit=0
```

探针正例零诊断；负例 `bin/unary/tern/cast` 产生 `>=3` 条 `initializer:` 诊断。

### E68-3（四个位置）

```console
$ bash test/ast/p68_positions.sh /tmp/rev68/ct-ast
OK p68/positions (init/assign/return/container arg)
exit=0
```

### E68-4（误报账 / 合法语料）

```console
$ bash test/ast/p68_fp.sh /tmp/rev68/ct-ast
OK p68/fp (FP=0/301 legal fixtures; 1 documented skip: loop_count_type)
exit=0
```

卡 §6 写的 `FP=0/301` 与实测**逐字一致**。301 的构成可复算：脚本 shell glob 命中
`289 (test/ast/*/prog.ct) + 6 (examples/*/prog.ct) + 8 (examples/*/src/main.ct) = 303`，
去掉名字过滤 `*err_*` 的 234 一件、`SKIP` 的 `loop_count_type` 一件，得 301。

**E68-4 冻结阈值 438 的独立复现**（battle/typecheck-1 同口径：289 + 216 + 25 = 530 件，
先跑 plain `ct check` 取 rc=0，再跑 `--types`）：

```console
battle-enum total=530 plain-green=438 FP=0 plain-red=92
```

即冻结的 `FP=0/438` **另行实测成立**；§6 的 301 只是脚本较窄的枚举，不是把 438 缩水成 301。

## 2 红证与实现配对

```console
$ git log --oneline | grep v0-PH-68
bf8190b1 feat(ast): v0-PH-68 类型核心收口（v0.67.0）
f1ee02c6 test(ast): v0-PH-68-R3/R4 四位置探针与误报账
0a8438a4 feat(ast): v0-PH-68-R2 表达式类型表（二元/一元/三元/cast）
8b60e9ae test(ast): v0-PH-68-R2 红（表达式类型表）
42a1932d feat(ast): v0-PH-68-R1 数组维度参与初值判定（234 转绿）
067413f8 test(ast): v0-PH-68-R1 红（数组维度初值）
```

- R1：实现 `42a1932d` 的父提交 = `067413f8`（`test(ast): v0-PH-68-R1 红…`），
  红证 baseline `ba5572b3` = `067413f8^`；`ba5572b3` 是 HEAD 祖先。
- R2：实现 `0a8438a4` 的父提交 = `8b60e9ae`（`test(ast): v0-PH-68-R2 红…`），
  红证 baseline `1589515b` = `8b60e9ae^`；`1589515b` 是 HEAD 祖先。

**独立重建红证**（`git archive <baseline>` → 同一条自举链 → 用 HEAD 的探针跑基线二进制）：

```console
# R1 基线 ba5572b3 + HEAD test/ast/p68_typebuf.sh
FAIL p68/typebuf: 234 (rc=1)
  test/ast/234_err_return_contract/prog.ct:9:23: error: initializer: expected 'char', got 'char *'
exit=1

# R2 基线 1589515b + HEAD test/ast/p68_exprtypes.sh
FAIL p68/exprtypes: negative cases skipped (diagnostics=0, want >=3)
exit=1
```

与两个红提交正文的红证逐字一致，红→绿配对成立。

**R3/R4 无实现**：`f1ee02c6` 只改 `selfhost/check-ast.sh`（接线）与两份探针，
`git diff 0a8438a4 f1ee02c6 -- selfhost test` 仅此三文件，**不含编译器引擎**；
收口提交 `bf8190b` 的 `selfhost/` 变更只有五处 `CTC_VERSION` 各一行。故“R3/R4 是验收任务、
无实现提交”与事实相符。

## 3 版本与 tag

五处声明一致：

```console
selfhost/l0/ctc.c:61:#define CTC_VERSION "0.67.0"
selfhost/l1/ctc.ct:108:#define CTC_VERSION "0.67.0"
selfhost/l2/core.ct:55:#define CTC_VERSION "0.67.0"
selfhost/l2/driver.ct:36:#define CTC_VERSION "0.67.0"
selfhost/ct-ast/main.ct:36:#define CTC_VERSION "0.67.0"
```

```console
$ git tag -l v0.67.0
v0.67.0
$ git cat-file -t v0.67.0
tag
$ git rev-parse v0.67.0^{commit}
bf8190b182d7062ec6c10364a08db92a8d6ccdf3
$ git rev-parse v0.67.0
2c5036ec1fff1b82078f853fff69eba1ff7cb1f2
$ git ls-remote origin 'refs/tags/v0.67.0*'
2c5036ec1fff1b82078f853fff69eba1ff7cb1f2	refs/tags/v0.67.0
bf8190b182d7062ec6c10364a08db92a8d6ccdf3	refs/tags/v0.67.0^{}
$ git tag -n99 v0.67.0
v0.67.0         v0-PH-68 closeout (bf8190b)
```

本地 tag 对象与远端一致（`2c5036ec…`），peeled commit 与 HEAD 一致（`bf8190b…`）。

## 4 CI

```console
$ XDG_CACHE_HOME=/tmp/ghcache gh run list --workflow ci.yml --limit 5
in_progress  feat(ast): v0-PH-68 类型核心收口（v0.67.0）  ci  main  push  44410450867 ...
completed success  test(ast): v0-PH-68-R3/R4 四位置探针与误报账  ci  main  push  44408642249 ...
completed success  feat(ast): v0-PH-68-R2 表达式类型表（二元/一元/三元/cast）  ci  main  push  44404536596 ...
completed success  docs(roadmap): 开卡 v0-PH-69…75，非硬件相全部就位  ci  main  push  44403287564 ...
completed cancelled  feat(ast): v0-PH-68-R1 数组维度参与初值判定（234 转绿）  ci  main  push  44402619514 ...
```

`bf8190b` 的 run `44410450867`（headSha 逐字等于 HEAD）最终：

```console
status=completed conclusion=success
ubuntu-gcc success / macos-clang success / ubuntu-clang-smoke success
```

`ubuntu-gcc` 日志（`gh run view --job 135176863866 --log`）：

```text
ok    v0-PH-68-R1 typebuf (array dimension survives the initializer check)
ok    v0-PH-68-R2 exprtypes (bin/unary/tern/cast typed)
ok    v0-PH-68-R3 positions (init/assign/return/container arg)
ok    v0-PH-68-R4 fp (0 false positives, skip table)
check-all: OK (11 hard gates green)
== summary: 1487 passed, 0 failed, 0 skipped ==   # 该 summary 为 check-ast 段
```

run URL：https://github.com/samxxu/ct-lang/actions/runs/44410450867

## 5 诚实性核对

### check-ast 仍全绿

本地 `/tmp/rev68` 独立自举后跑 `bash selfhost/check-ast.sh`：

```console
ok    v0-PH-68-R1 typebuf (array dimension survives the initializer check)
ok    v0-PH-68-R2 exprtypes (bin/unary/tern/cast typed)
ok    v0-PH-68-R3 positions (init/assign/return/container arg)
ok    v0-PH-68-R4 fp (0 false positives, skip table)
== summary: 1483 passed, 0 failed, 4 skipped ==
EXIT=0
```

4 条 skip 全是 Renode/平台项（`baremetal_renode`、`v0-PH-67-R2/R3/R5`），**没有一条 v0-PH-68**；
CI 的 Linux 上 4 条全部执行，故 CI summary 为 `1487 passed, 0 failed, 0 skipped`。
卡 §6 写的 `check-ast 1483 passed` 是本地账，与上述一致。

### skip 没有被写成 pass

`loop_count_type` 的“故意报告”是真实的：

```console
$ /tmp/rev68/ct-ast check --types test/ast/loop_count_type/prog.ct; echo rc=$?
test/ast/loop_count_type/prog.ct:12:5: error: type mismatch: 'loop' count must be an integer (got 'double'); the value is converted to int
rc=1
```

`p68_fp.sh` 把它计入 `SKIP` 并从分母剔除，但在最后一行的 OK 文本里**显式写出**
`1 documented skip: loop_count_type`；`check-ast.sh` 的 R4 行是脚本退出码的 pass，
不是把 skip 当 pass。没有发现“skip 静默转绿”。

### golden

收口提交改了 63 个 `test/cases/*.expected.*` 与 `test/modules/p39_lib/lib.expected.abi.h`，
逐行核对**只有版本 banner 一行变化**：

```console
$ git show bf8190b -- test/cases | grep -E '^[+-]' | grep -v '^[+-][+-]' | grep -v '0\.67\.0\|0\.66\.0'
（无输出）
```

即 golden 的语义无变化，与卡 §6 “golden 无变化”的口径一致。

### 301 与 438

见 §1：脚本实测 301（与卡 §6 一致），冻结口径 438 另行独立复现为 `FP=0/438`。
两者都不是 0 误报的反例。

## 6 观察（不阻断）

1. **卡 §6 对 438 的解释不准确。** §6 写“规划里的 438 含 import 多单元”，但
   `battle/typecheck-1/verify.json` 的口径是 438 = plain `ct check` rc=0 的**单单元**件；
   41 个 import 件在其中是 plain-red，不在 438 内。438 与脚本 301 的差主要来自枚举范围
   （脚本不扫 `test/cases` 与 `examples/**` 的非 `prog.ct` 件），不是 import。建议后续
   单独提交修正这句说明；不影响 E68-4（REV 已另测 0/438）。
2. **`p68_fp.sh` 的 301 分母排除了 234。** 名字过滤 `*err_*` 命中
   `test/ast/234_err_return_contract`，故 234 不在 FP 分母里；它由 E68-1 单独验绿。
   建议在脚本注释或卡里把这条排除与 `loop_count_type` 并列写明，避免读者误以为
   234 也在 301 中。
3. **R1 红提交混入了卡与 roadmap。** `067413f8` 除 `p68_typebuf.sh` 外还新增
   `docs/phases/v0-PH-68/card.md` 与改 `docs/roadmap.md`。按 6.6 T-7 的“只含测试、夹具与红证”
   字面，这是范围混合；红证本身与实现配对不受影响。建议后续红提交只带测试与证据。

另：tag message 用 legacy `v0-PH-68`，而卡 §0 的编号是 `v0-PH-68`；因 phase-ID 迁移仍被
blocker 挡住（卡首已注明 legacy 路径），此处按现状记录，不单独判红。

## 7 结论

四条退出判据在独立自举的 `ct-ast` 上逐条通过；红证/实现配对与 R3/R4 的“验收任务”定性
均与 git 事实相符；五处版本、annotated tag、远端 tag 与 `bf8190b` 一致；CI 三 job 全绿，
`ubuntu-gcc` 有 `ok v0-PH-68-R1…R4` 与 `check-all: OK (11 hard gates green)`；`check-ast`
本地 1483 passed / 0 failed，4 条 skip 均非 v0-PH-68；skip 未被写成 pass。

**`REV: 通过`**
