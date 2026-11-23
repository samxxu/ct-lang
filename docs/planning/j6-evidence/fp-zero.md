# 全量语料 B 误报为零（SH-118 / E-V1-5）

| 项 | 值 |
| --- | --- |
| 判据 | [v1-PH-0 E-V1-5](../../phases/v1-PH-0/card.md)：全量语料 FP=0 的命令、清单与原始输出入库 |
| 判定 | `ct check --types`（与 `ct build --check-level=warn` 同判定、同文案，见 [spec §1](../../language-spec.md)） |
| 语料 | `examples test lib` 下全部 `.ct`（P-1.1 口径） |
| 基线（红） | `369fac67`（7 个合法夹具被 B 误报） |
| 修复后（绿） | `7753ab33`（`p118` 全量 0 命中） |
| 探针 | [test/ast/p118_fp_all.sh](../../../test/ast/p118_fp_all.sh) |
| skip 表 | [test/ast/p118_skip.tsv](../../../test/ast/p118_skip.tsv)（47 行，每行带依据） |
| 结论 | **green**：1377 个合法件 0 命中；47 个 skip 全部是负例 / 诊断演示 / p32 前 B 基线夹具 |

## 1 复跑（干净 HEAD）

```sh
git archive 7753ab33 | tar -x -C /tmp/sh118
cd /tmp/sh118
mkdir -p /tmp/sh118-b
CC=cc
$CC -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/sh118-b/ctc
/tmp/sh118-b/ctc selfhost/l1/ctc.ct -o /tmp/sh118-b/l1.c
$CC -Wall -Wextra -std=c99 /tmp/sh118-b/l1.c -o /tmp/sh118-b/l1
/tmp/sh118-b/l1 build selfhost/l2/driver.ct -o /tmp/sh118-b/l2src
$CC -Wall -Wextra -std=c99 /tmp/sh118-b/l2src/*.c -o /tmp/sh118-b/l2
/tmp/sh118-b/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/sh118-b/astsrc
$CC -Wall -Wextra -std=c99 /tmp/sh118-b/astsrc/*.c -o /tmp/sh118-b/ct-ast
TMPDIR=/tmp/sh118-tmp sh test/ast/p118_fp_all.sh /tmp/sh118-b/ct-ast
```

期望（退出码 0）：

```console
$ TMPDIR=/tmp/sh118-tmp sh test/ast/p118_fp_all.sh /tmp/sh118-b/ct-ast
OK p118/fp (0 B diagnostics; checked 1377 legal .ct, skipped 47, corpus 1424)
```

`--selftest` 是同一探针的负例：它先在临时语料放一个合法件（必须过），再放
`int x = "s";`（必须红），证明判定不会悄悄失效：

```console
$ sh test/ast/p118_fp_all.sh /tmp/sh118-b/ct-ast --selftest
OK p118/selftest (clean corpus passes; injected B diagnostic turns red)
```

## 2 语料计数与 P-1.1 对账

| 项 | 值 |
| --- | --- |
| 全部 `.ct` | **1424**（32,194 行） |
| 合法件（实际判红/判绿） | **1377** |
| skip | **47** |
| B 命中 | **0** |

P-1.1 在 `3e3c52ad` 记的是 **1381** 个 `.ct`；当前 `369fac67` 为 **1424**：
相对基线 **+44 / -1**（`1 381 + 44 - 1 = 1 424`）。

- 新增 44：`test/ast/errors` 7、`test/modules/sh60_*` 14、`test/ast/{293…297}` 6、
  `examples/54…57` 5、`test/pkg/fixtures` 4、`docs/snippets` 3、其余 5；
- 删除 1：`test/ast/errors/temp_receiver_trait_chain.ct`。

新增件全部落在上面的合法件 / skip 分类内，没有改变 P-1.1 的扫描范围定义。

## 3 skip 表（47 行，只减不增）

[test/ast/p118_skip.tsv](../../../test/ast/p118_skip.tsv) 每行是 `<path><TAB><reason>`。
三类，共 47 行：

| 类别 | 行数 | 依据 |
| --- | --- | --- |
| negative | 36 | B 负例 / 错误巡回：`test/ast/check_errors` 12、`test/ast/errors` 16、`test/ast/p80_retain/neg_escape` 1、`test/errors` 4、`test/modules/p25_static_argtype` 4、`test/probes/fixtures/p35_iface_mismatch` 1 |
| baseline | 7 | p32 前 B 基线夹具（`test/probes/fixtures/p32_*`）：当时没有 `--types`，其中含故意未检查的 C 非法转换（`char *pc = struct A *`、`struct A = struct B`），B 判红是正确行为 |
| demo | 4 | `examples/tour/16_diagnostics` 3 个诊断演示、`test/ast/loop_count_type` 的 L22-5 告警演示；它们故意触发诊断，不是合法件 |

机械约束（由探针执行）：

- 每个 skip 行必须有非空 `reason`；
- 行内路径必须存在且在 P-1.1 语料内；
- 行内文件必须**仍然**命中一条 B 诊断；不再命中的行判 `stale row` 红，因此表只能缩小；
- 合法件一旦进表会先因 `stale row` 暴露；7 个真实 FP 从未进表。

## 4 红证（基线 `369fac67`）

在 `451e9cdc` 的测试提交上，用基线 `369fac67` 构建的 ct-ast 复跑（退出码 1）：

```console
$ sh test/ast/p118_fp_all.sh <baseline-369fac67>/ct-ast
FAIL p118/fp: test/ast/p80_retain/field_branch_init.ct
  test/ast/p80_retain/field_branch_init.ct:11:18: error: initializer: expected 'struct String', got 'int'
FAIL p118/fp: test/ast/p80_retain/field_loop0.ct
  test/ast/p80_retain/field_loop0.ct:11:18: error: initializer: expected 'struct String', got 'int'
FAIL p118/fp: test/ast/p80_retain/field_loop_long.ct
  test/ast/p80_retain/field_loop_long.ct:10:18: error: initializer: expected 'struct String', got 'int'
FAIL p118/fp: test/ast/p81_box/layout.ct
  test/ast/p81_box/layout.ct:11:37: error: initializer: expected 'struct String', got 'char *'
FAIL p118/fp: test/ast/p81_box/record.ct
  test/ast/p81_box/record.ct:29:34: error: initializer: expected 'struct String', got 'char *'
FAIL p118/fp: test/ast/p81_box/uaf.ct
  test/ast/p81_box/uaf.ct:7:27: error: initializer: expected 'struct String', got 'char *'
FAIL p118/fp: test/ast/p81_box/vecbox.ct
  test/ast/p81_box/vecbox.ct:14:33: error: initializer: expected 'struct String', got 'char *'
  test/ast/p81_box/vecbox.ct:26:36: error: initializer: expected 'struct String', got 'char *'
FAIL p118/fp: 7 finding(s); checked 1377 legal .ct, skipped 47, corpus 1424
```

`baseline: 369fac67`；测试提交 `451e9cdc`；修复提交 `7753ab33`（`451e9cdc` 的
子提交，满足先红后绿）。

## 5 绿证（`7753ab33`）

```console
$ sh test/ast/p118_fp_all.sh <7753ab33>/ct-ast
OK p118/fp (0 B diagnostics; checked 1377 legal .ct, skipped 47, corpus 1424)
$ sh test/ast/p118_fp_all.sh <7753ab33>/ct-ast --selftest
OK p118/selftest (clean corpus passes; injected B diagnostic turns red)
```

接入点在 `selfhost/check-ast.sh` 第 8 道内（**不新增 gate 编号**），子检查名
`SH-118 E-V1-5 fp-all` 与 `SH-118 E-V1-5 fp-all negative`；`check-all` 仍是 12 门。

## 6 7 个真实 FP 的定性（未 skip）

7 个文件都是合法夹具：p80_retain 的 `holder = { 0 }` 由 SH-102 / D-015 §1.2
定义为“聚合零填充，所有 owning 字段已定义”；p81_box 的 `new Record { 7, "x" }`
是 `T x = { … }` 同一花括号路径上的字符串字面量，按 spec §4.70 的 `String s = "x"`
隐式绑定合法。它们被 SH-115 新增的 `chk_brace_init` 误判：

| 形态 | 误报 | 正确语义 |
| --- | --- | --- |
| `Holder h = { 0 };` | `initializer: expected 'struct String', got 'int'` | `0` 是聚合零填充，不是 int→String 赋值 |
| `new R { 1, "x" }` / `{ .tag = "literal" }` | `initializer: expected 'struct String', got 'char *'` | 字符串字面量在 String/Str 字段上走 `lit_coerce` 的隐式绑定 |

处置：`7753ab33` 在 `chk_brace_init` 跳过且仅跳过这两种合法形态。非零整数写
String 字段、int 字段写字符串、struct 指针/结构互赋等负例仍照旧报错；`p115`
22/22、`p80_retain` / `p81_box` 探针全绿。按 SH-118 非目标，**不新增 B 规则**，
只修 SH-115 新判定的误报边界；机制归属仍是 [SH-115](../../../issues/selfhost/sh115-b-plus-strengthening.md)
（如需在台账层面确认，交 REV 决定，本卡不改 issue 状态）。

## 7 门禁（私有 TMPDIR）

命令：

```sh
mkdir -p /tmp/sh118-tmp
TMPDIR=/tmp/sh118-tmp bash selfhost/check-all.sh
TMPDIR=/tmp/sh118-san bash selfhost/check-sanitizers.sh
bash tools/check.sh g0
bash tools/check.sh g6
bash tools/check.sh g8
python3 test/docs/check-docs.py
```

原始结果（`7753ab33` + 本证据提交）：

```console
$ TMPDIR=/tmp/sh118-tmp bash selfhost/check-all.sh
  ok    SH-118 E-V1-5 fp-all (0 B diagnostics over examples test lib)
  ok    SH-118 E-V1-5 fp-all negative (injected B diagnostic turns red)
  ok    p88/metrics
check-all: OK (12 hard gates green)

$ TMPDIR=/tmp/sh118-san bash selfhost/check-sanitizers.sh
check-sanitizers: OK (599 checks, no sanitizer report)

$ bash tools/check.sh g0
g0: OK (block 1.18.0, session-map present)
$ bash tools/check.sh g6
g6: OK (307 issues; open=2 verified=285 rejected=12 deferred=7 superseded=1)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2984 relative links in 431 files, …, 12 hard gates, …)
```

`p88_metrics` 的 `emitted_after` 因本条修复在 `chk_brace_init` 增加 22 行发射 C，
同批由 `52218` 更新为 `52240`（`docs/history/p88_metrics.md`），探针复算一致。
第一次 `check-all` 用长 TMPDIR（`…/.temp/sh118/tmp`）时 batch 42 的一条诊断被
`MAX_TEXT` 截断而判红；改用短路径 `/tmp/sh118-tmp` 后通过，不是代码失败。

## 8 未覆盖与边界

- 判定用单文件 `ct check --types`；import 单元另有 `p69_fp.sh`（跨单元），两者不重复计数；
- `ct build --check-level=warn` 与 `ct check --types` 同判定（spec §1），本卡以
  `ct check` 为准，未对 1424 个文件再跑一遍 build；
- skip 表只校验“仍命中”，不重新判定负例内容；负例的质量由各自探针负责；
- 外部包语料（std）不在本仓 v1.0 口径内，按 SH-118 非目标不消费；
- 真实 FP 若再次出现，`p118` 直接红，不会自动进 skip：必须先进 issue 再修。
