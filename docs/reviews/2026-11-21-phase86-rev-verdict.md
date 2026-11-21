# PH-86 收口复核（REV，2026-11-21）

> **结论：通过（PASS）**。HEAD `2189c5f5`（v0.86.0）。E86-1…8 逐条复核通过；
> 3 项非阻断见 §9。未 push、未改实现。
> 对象：[phase86 卡](../design/phase86.md)、[p86_errors](../design/p86_errors.md)、
> [p86_metrics](../design/p86_metrics.md)、
> [battle/p86-errorpath](../../battle/p86-errorpath/verdict.md)。

## 0 方法与环境
从 **`git archive 2189c5f5`** 自举，不使用工作树当前产物；`/tmp` 私建目录、私有
`TMPDIR`。工作树另有其他任务的未提交文件（`battle/ct-guide-1/**`、
`docs/guide-for-c-programmers.md` 等），本复核未使用、未提交。

```console
$ git rev-parse HEAD && uname -m
2189c5f50245e21c862b24791fef78831235efa3
arm64
$ cc --version | head -1 && python3 --version
Apple clang version 21.0.0 (clang-2100.4.1.1)
Python 3.15.2
$ git archive 2189c5f5 | tar -x -C /tmp/p86rev/src && sh /tmp/p86rev/build.sh
== L0 == == L1 == == L2 == == ct-ast ==
built /tmp/p86rev/build/ct-ast
ct-ast v0.86.0
$ wc -c /tmp/p86rev/build/*.err   # 7 个文件全为 0 字节：零告警
```

## 1 四条 S86 探针（归档自举编译器）
```console
$ TMPDIR=/tmp/p86rev/tmp bash test/ast/p86_tokens.sh /tmp/p86rev/build/ct-ast /tmp/p86rev/build/astsrc
p86tokens: 29 passed, 0 failed
$ TMPDIR=/tmp/p86rev/tmp bash test/ast/p86_capi.sh /tmp/p86rev/build/ct-ast /tmp/p86rev/build/astsrc
p86capi: 20 passed, 0 failed
$ TMPDIR=/tmp/p86rev/tmp bash test/ast/p86_errors.sh /tmp/p86rev/build/ct-ast
p86errors: 23 passed, 0 failed
$ TMPDIR=/tmp/p86rev/tmp bash test/ast/p86_docs.sh /tmp/p86rev/build/ct-ast
p86docs: 23 passed, 0 failed
```

四条探针在**归档自举**上全绿，不依赖工作树或 `.temp/` 旧产物。

## 2 E86-1 — token 视图、零拷贝、生命周期

**通过。** 独立检查归档自举产出的 `Lexer.c/Lexer.h`：

```console
$ grep -n 'memcpy' /tmp/p86rev/build/astsrc/Lexer.c
396:    if (n > 0) memcpy(out, _self->tokstr.ptr, (size_t)n);
407:    if (n > 0) memcpy(_self->cbuf, _self->tokstr.ptr, (size_t)n);
$ grep -n 'tokstr.ptr = ' /tmp/p86rev/build/astsrc/Lexer.c
72:    l->tokstr.ptr = l->src + start;
$ grep -c toktext /tmp/p86rev/build/astsrc/Lexer.h /tmp/p86rev/build/astsrc/Lexer.c
Lexer.h:0   Lexer.c:0
```

- 只有 `tok_copy`（调用方缓冲）与 `tok_cstr`（词法器 scratch）两处边界复制；
  词法扫描本身 `tokstr.ptr = src + start`，`len` 由游标相减得到；
- `TokView { const char *ptr; int len; }` 与 `lib/std/Str.h.ct` 的
  `Str { char *ptr; int len; }` 同布局（const 不改变布局）；L2 不认识 std 层、
  PH-81 禁止 `Str` 字段，故本地拼写，卡 §7.4 已记账；
- `lex_view_ok` 断言 `ptr + len <= src + srclen`；`read_file` 的源缓冲在进程内不释放
  （既有行为），`load_unit` 保存/恢复 `srclen`；AST 侧名字均经 `tok_copy` 落副本；
  多单元探针（头单元先解析）在 ASan 下另测，输出 42，无报告（§6 CE-1）。

## 3 E86-2 — NUL 相关 C API 迁移

**通过（口径注记 N-2）。** 基线 `1e2c30f7` 与 HEAD 的同口径计数：

| 模式（`selfhost/ct-ast`） | 基线 v0.85.0 | HEAD v0.86.0 |
| --- | ---: | ---: |
| `toktext` | 728 | 0 |
| `strcmp(self->lex->tok` | 458 | 0 |
| `strncmp(self->lex->tok` | 6 | 0 |
| `strlen(self->lex->tok` | 10 | 0 |
| `snprintf(...toktext` | 128 | 0 |
| `strdup(`（frontend） | 0 | 0 |
| `tok_is` / `tok_copy` / `tok_cstr` | 0 / 0 / 0 | 486 / 79 / 37 |

`tok_cstr()` 的 35 个调用点全部是立即实参；探针另行拒绝“赋值给变量/return”。
CE-2 直接链接生成后的 Lexer 单元，证明 scratch 指针跨 `next()` 会改写成下一个
token、159 字节恰好填满 `cbuf[160]`、160 字节视图被钳到 159 且仍终止。

**N-2（非阻断，文字口径）**：卡 §1.1/E86-2 写 “`cstr()` … 调用方释放”；实现没有
调用方 `malloc`/`free` 的 token 文本：`tok_cstr` 返回词法器 scratch（不释放），
`tok_copy` 写调用方栈缓冲（无需释放）。所有权更简单、泄漏面更小，但与字面表述
不同；建议下次文档统一时改成现行契约。

## 4 E86-3 — 语料逐字节、自举不动点

**通过。** 66 个语料（`test/cases/*.ct` + `examples/*/*.ct`，排除 dialect）由归档
自举编译器重新发射，与 `test/probes/p85_corpus_sha.tsv` 逐字节一致：

```console
$ python3 tools/p85_inventory.py --root . corpus-manifest --ct /tmp/p86rev/build/ct-ast > /tmp/p86rev/corpus86.tsv
$ wc -l /tmp/p86rev/corpus86.tsv test/probes/p85_corpus_sha.tsv
      66 /tmp/p86rev/corpus86.tsv
      66 test/probes/p85_corpus_sha.tsv
$ diff -u test/probes/p85_corpus_sha.tsv /tmp/p86rev/corpus86.tsv
（无输出，exit 0）
```

自举不动点（第 2 层允许差异，按 D-017 A1）：

```console
$ ct-ast build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/p86rev/fixp/ast2
$ cc -std=c99 /tmp/p86rev/fixp/ast2/*.c -o /tmp/p86rev/fixp/ct-ast2
$ /tmp/p86rev/fixp/ct-ast2 build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/p86rev/fixp/ast3
$ diff -rq /tmp/p86rev/fixp/ast2 /tmp/p86rev/fixp/ast3
（无输出，exit 0）
```

## 5 E86-4 — 诊断、行为、ASan；S86c 的 `?`/errdefer 裁定

**通过。** 345 条负例的 `exit + stderr sha256` 与基线清单逐条一致；且用 **基线
v0.85.0 编译器**重跑同一清单也一致，证明清单本身忠实于基线，不是只对当前代码自证：

```console
$ python3 /tmp/p86rev/diagcheck.py /tmp/p86rev/build/ct-ast
manifest rows=345 missing_paths=0 differ=0
$ python3 /tmp/p86rev/diagcheck.py /tmp/p86rev/basebuild/ct-ast
manifest rows=345 missing_paths=0 differ=0
```

8 条词法边界 fixture（长标识符/长字符串/长 PP/非法后缀/未终止字符串/注释列号/
陈旧整数文本）的 `.expected.err` 也与基线编译器逐字一致：

```console
$ for f in test/ast/p86_errors/*.ct; do 基线 ct-ast "$f" … cmp -s … ; done
baseline vs p86_errors expected: 8 match, 0 differ
```

行为/ASan：`check-sanitizers` 全绿（§7），另有 §6 CE-1 的 1MB token、EOF 边界、
多单元导入在 ASan/UBSan 下零报告。

### 5.1 S86c battle 判决（A 是否成立）

**A 成立。** 独立复现 L2 的硬约束（不用 `Result` 类型，排除原证据里 `cc` 先因
未知类型失败的干扰）：

```console
$ /tmp/p86rev/build/l2 /tmp/p86rev/ce/l2q.ct -o /tmp/p86rev/ce/l2q.c
L2 rc=0
$ grep -n '?;\|errdefer' /tmp/p86rev/ce/l2q.c
10:    int v = get(&x)?;
11:    errdefer { return 1; }
$ cc -std=c99 /tmp/p86rev/ce/l2q.c -o /tmp/p86rev/ce/l2q.bin
l2q.c:10:21: error: expected expression
cc rc=1
```

`selfhost/l2` 中 `errdefer` 命中 0，也没有后缀 `?` 的下降分支；ct-ast 源码由 L2
引导编译，写入这两个构造必破链。选项 B（先补 L1/L2）改冻结层、跨 phase、动
golden；选项 C（只在测试夹具里用）是假绿。故 S86c 改为“错误出口清单 + 诊断逐字
对照”，**是范围缩减，不是 S86c 字面任务通过**；E86-4 的字面判据（诊断不变 +
行为/ASan）已满足。REVIEW 已在
[battle/p86-errorpath](../../battle/p86-errorpath/verdict.md) 签字，并附条件：
PH-87/88 开卡前由 REQ 二选一（补引导层，或把同名判据降为 `no-test` 文档项），
不得静默沿用。

## 6 新反例（4 条，均在本机归档自举上）

### CE-1 token 视图越界/悬垂（ASan/UBSan）

ASan 编译器由归档 `astsrc` 重编（`-fsanitize=address,undefined`）。输入覆盖：
无末尾换行的 EOF token、1,000,000 字节标识符/字符串/PP 行、159/160 字节边界、
导入单元末尾 token、导入单元报错。

```console
$ for f in in/*.ct; do ASAN_OPTIONS=detect_leaks=0 ./ct-ast-asan "$f" -o out.c; done
bigid      rc=1 san=0 err=in/bigid.ct:1:5: error: identifier is too long
bigpp      rc=1 san=0 err=… error: preprocessor line exceeds 159 bytes; split it or move it to a header
bigstr     rc=1 san=0 err=… error: string literal is too long (max 158 bytes; split it)
eof_brace  rc=0 san=0
eof_id     rc=0 san=0
max159     rc=0 san=0
max160     rc=1 san=0 err=in/max160.ct:1:5: error: identifier is too long
$ CT_C_BOUNDARY=allow ./ct-ast-asan build --emit-c -I units units/main.ct -o units/out
multi rc=0 san=0
$ ./units/main.bin
42
$ ./ct-ast-asan build --emit-c -I units units/mainbad.ct -o units/outbad
units/bad.h.ct:2:5: error: identifier is too long
badunit rc=1 san=0
```

### CE-2 `tok_cstr()` scratch 生命周期 / 截断边界

直接链接生成后的 `Lexer.c`，13 条断言全过（ASan/UBSan 构建）：

```console
$ cc -fsanitize=address,undefined -std=c99 -I. Lexer.c ce_tokcstr.c -o ce_tokcstr
$ ./ce_tokcstr
ok   tok_cstr returns the scratch buffer, no allocation
ok   the scratch pointer is stable across next()
ok   a stored pointer now spells the next token (lifetime ends at next)
ok   a 159-byte token fills cbuf[160] and terminates
ok   a 160-byte token keeps a 159-byte view and sets toktrunc
ok   tok_copy(8) truncates a 159-byte token to 7 and reports overflow
ce2: 0 failure(s)
```

### CE-3 超长 token 不改变诊断/不崩溃

已含在 CE-1 的 1MB 三类输入：均退出 1、诊断文本与 8 条 fixture 一致、san=0。

### CE-4 `build --check-level` 不受影响

```console
$ TMPDIR=/tmp/p86rev/tmp bash test/ast/p85_a_wire.sh /tmp/p86rev/build/ct-ast
p85a: 9 passed, 0 failed
$ # 另用 159 字节标识符的合法程序验证三档发射逐字节相同
legal/{off,warn,error} rc=0 files=1 stderr=0
LEGAL EMISSION IDENTICAL ACROSS off/warn/error
mismatch/{off,warn} rc=0 files=1; mismatch/error rc=1 files=0
mismatch/warn stderr=[… warning: return: expected 'int', got 'char *']
WARN PRODUCT == OFF PRODUCT
ERROR WROTE NO PRODUCT
```

## 7 回归门禁（干净 HEAD 克隆，私有 TMPDIR）

```console
$ TMPDIR=/tmp/p86rev/tmp-checkall bash selfhost/check-all.sh
check-all: OK (11 hard gates green)
  == summary: 1565 passed, 0 failed, 5 skipped ==   # check-ast
check-warnings: 500 ok, 0 failed

$ TMPDIR=/tmp/p86rev/tmp-san bash selfhost/check-sanitizers.sh
check-sanitizers: OK (586 checks, no sanitizer report)

$ bash tools/check.sh g0 && bash tools/check.sh g8
g0: OK (block 1.17.0, session-map present)
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2346 relative links in 381 files, v0.86.0, 11 hard gates,
              12 phase status, 5 适用版本 header(s), 2 superseded link(s),
              10 signoff(s))
# 本复核提交后：2351 links / 382 files / 5 headers（+本文 5 links / 1 file）
```
版本五处 `CTC_VERSION` 全为 `0.86.0`（`selfhost/l0/ctc.c`、`selfhost/l1/ctc.ct`、
`selfhost/l2/core.ct`、`selfhost/l2/driver.ct`、`selfhost/ct-ast/main.ct`），
`test/cases` + ABI 共 51 个 banner 为 `Generated by ct v0.86.0`；README/docs/README/
AGENTS 的当前版本一致。

## 8 E86-8 回滚演练

**通过（等价演练；N-1 记录命令时效）。** 卡 §7.2 的逐字命令在最终 HEAD 上会失败：

```console
$ git archive 2189c5f5 | tar -x -C /tmp/p86rev/rollhead
$ (git show 7425d28d --format=) | git apply -R
error: patch failed: selfhost/ct-ast/frontend/lex/Lexer.h.ct:43 (does not apply; exit 1)
```

原因是收口提交 `2189c5f5` 自己改了 `Lexer.h.ct` 的一行注释
（`for a prefix of the given length` → `as a prefix of the token`），S86b 补丁的
上下文因此过期。在**收口前** `32e0d5f1` 上同一命令逐字成功：

```console
$ git archive 32e0d5f1 | tar -x -C /tmp/p86rev/rollpre
$ (git show 7425d28d --format=) | git apply -R   # S86b reverse OK
$ (git show 3c41b5b7 --format=) | git apply -R   # S86a reverse OK
$ grep -c toktext selfhost/ct-ast/frontend/lex/Lexer.h.ct
58
```

在最终 HEAD 上用等价回滚（`1e2c30f7..2189c5f5` 之间 `selfhost/ct-ast` 只有
S86a/S86b 两个源码提交 + 收口的一行注释；把该子树覆盖为基线即等价）重跑：

```console
$ git archive 1e2c30f7 selfhost/ct-ast | tar -x -C /tmp/p86rev/roll
$ sh buildat.sh /tmp/p86rev/roll /tmp/p86rev/rollbuild
built /tmp/p86rev/rollbuild/ct-ast
ct-ast v0.85.0
$ /tmp/p86rev/rollbuild/ct-ast test/ast/01_hello/prog.ct -o hello.c && cc … && ./hello.bin
hello ast
$ python3 tools/p85_inventory.py --root . corpus-manifest --ct /tmp/p86rev/rollbuild/ct-ast | diff test/probes/p85_corpus_sha.tsv -
（无输出，exit 0；66 行）
```

**N-1（非阻断）**：E86-8 的记录命令在最终 HEAD 过期，建议改成
`git apply -R --3way`（解决那行注释冲突）或直接写“基线 `selfhost/ct-ast` 覆盖”，
并在下次收口重跑；回滚能力本身已验证。

## 9 非阻断项汇总

| # | 项 | 影响 | 建议 |
| --- | --- | --- | --- |
| N-1 | E86-8 记录命令在最终 HEAD 因收口注释改动不可逐字重放 | 证据时效；回滚能力已等价验证 | 更新卡 §7.2 命令或重跑；见 §8 |
| N-2 | E86-2 字面“`cstr()` 调用方释放”与实现的 `tok_cstr` scratch / `tok_copy` 调用方缓冲不同 | 无泄漏、所有权更简单；文字不一致 | 下次文档统一改口径 |
| N-3 | 卡 §7.5 的 check-docs 原始输出 `2351 / 382 / 6` 只在混入其他任务未提交文件时复现（`docs/guide-for-c-programmers.md` 提供第 6 个 header）；复核前干净 HEAD 是 `2346 / 381 / 5`，本复核提交后是 `2351 / 382 / 5` | 门禁本身仍绿；收口证据被工作树污染 | 用干净 HEAD 重录该行证据，或注明当时的未提交文件 |

## 10 未覆盖声明

- 未在 Linux/x64、QEMU 或 p83 dist 跨平台产物上重跑；本复核为 arm64 Darwin。
- 未逐条重测 E86-6 的 5 次耗时原始值；本次独立 5 次中位为
  `ct-ast build --emit-c` 741.4 → 816.4 ms（+10.1%，方向与报告的 +2.6% 一致；
  绝对值和负载相关，不作为门禁）。
- 未修改实现、未 push、未打 tag。
