# v0-PH-81 收口复核（REV · 2026-11-21）

> 命名注记（LANG-24 Stage A）：本文件是历史快照，正文保留当时的 `box<T>` 拼写；v1.0 起规范拼写为 `Box<T>`（见 docs/language-spec.md §1.2）。


| 项 | 值 |
| --- | --- |
| 复核对象 | `c2ec9cd6`（`v0.81.0`，tag `v0.81.0`） |
| 范围 | `box<T>` + `new`（S1a–S1c）、E81-1…6、D-016、D-011 J-2a、版本 / tag / G8 / check-all / sanitizer |
| 方法 | `git archive v0.81.0` → 独立自举 L0→L1→L2→ct-ast（不读工作树产物）；跑 p81 与 p78/79/80 关键探针；独立正例 / 负例；P-7.5 `run.sh` 复跑；`check-all` / `check-sanitizers` / `check-warnings` / `g0` / `g8` / `check-docs` / `p39 r8`；读码对照卡与 D-016 |
| 结论 | **REV: 通过**（v0-PH-81 范围内未发现阻断缺口；§5 为不阻断观察） |
| 交付 | 本文件；不改代码、不 push；无 v0-PH-81 issue 状态变更 |

## 1 独立自举（archive，不依赖工作树产物）

```console
$ rm -rf /tmp/rev81/src && mkdir -p /tmp/rev81/src /tmp/rev81/build
$ git archive v0.81.0 | tar -x -C /tmp/rev81/src
$ cd /tmp/rev81/src
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev81/build/ctc
$ /tmp/rev81/build/ctc selfhost/l1/ctc.ct -o /tmp/rev81/build/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev81/build/l1.c -o /tmp/rev81/build/l1
$ /tmp/rev81/build/l1 build selfhost/l2/driver.ct -o /tmp/rev81/build/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev81/build/l2src/*.c -o /tmp/rev81/build/l2
$ /tmp/rev81/build/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev81/build/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev81/build/astsrc/*.c -o /tmp/rev81/build/ct-ast
$ /tmp/rev81/build/ct-ast --version
ct-ast v0.81.0
```

每一步退出码 0，五处 C 编译 `-Wall -Wextra` 均无告警（原始日志 `/tmp/rev81/build/*.log`）。

```console
$ CT_STD_DIR=$PWD/lib/std sh test/ast/p81_box.sh /tmp/rev81/build/ct-ast
ok   layout -fsanitize=address
ok   layout -fsanitize=undefined
ok   layout (behaviour + sanitizers)
ok   record -fsanitize=address
ok   record -fsanitize=undefined
ok   record (behaviour + sanitizers)
ok   vecbox -fsanitize=address
ok   vecbox -fsanitize=undefined
ok   vecbox (behaviour + sanitizers)
ok   boxstr -fsanitize=address
ok   boxstr -fsanitize=undefined
ok   boxstr (behaviour + sanitizers)
ok   cycle -fsanitize=address
ok   cycle -fsanitize=undefined
ok   cycle (behaviour + sanitizers)
ok   ctx -fsanitize=address
ok   ctx -fsanitize=undefined
ok   ctx (behaviour + sanitizers)
ok   asan sensitivity (at() view after release -> heap-use-after-free)
ok   neg_new_string (rejected: new of a built-in handle)
ok   neg_new_int (rejected: new of a scalar)
ok   neg_new_vec (rejected: new of a container)
ok   neg_new_no_brace (rejected: new without a brace list)
ok   neg_box_slice (rejected: slice payload)
ok   neg_box_str (rejected: Str payload)
ok   neg_field_str (rejected: borrowed Str field)
ok   neg_raw_field (rejected: raw .ptr on a box)
ok   neg_new_global (rejected: new at file scope)
ok   neg_new_static (rejected: new in a static local)
ok   selfhost/l0/ctc.c CTC_VERSION 0.81.0
ok   selfhost/l1/ctc.ct CTC_VERSION 0.81.0
ok   selfhost/l2/core.ct CTC_VERSION 0.81.0
ok   selfhost/l2/driver.ct CTC_VERSION 0.81.0
ok   selfhost/ct-ast/main.ct CTC_VERSION 0.81.0
ok   README / docs/README carry v0.81.0
ok   spec has the box<T>/new section (4.71)
ok   tutorial has the box<T>/new section (17)
ok   package-guide records the box C ABI boundary
ok   roadmap lists Phase 81 with v0.81.0
ok   D-016 records the v0-PH-81 design decision
p81_box: OK
$ echo $?
0
```

（`uaf` 子进程按设计 Abort，脚本据此断言 ASan 报 `heap-use-after-free`；这不是失败。）

P-7.5 证据可复跑（隔离副本、主仓只读）：

```console
$ WORK=/tmp/rev81/p75 bash docs/planning/j6-evidence/p75/run.sh
...
---- p81 (exit 0) ----      p81_box: OK
---- p80_layout (exit 0) ----  p80_layout: OK
---- p80_retain (exit 0) ----  p80_retain: OK
summary: P-7.5 evidence OK (p81 probe + p80 layout/retain, 0 failed)
$ echo $?
0
```

## 2 不回归探针（同一 archive 构建）

| 探针 | 退出码 | 结果 |
| --- | --- | --- |
| `p80_layout.sh` | 0 | `p80_layout: OK`（含 ASan/UBSan 灵敏度） |
| `p80_literal.sh` | 0 | `p80_literal: OK` |
| `p80_methods.sh` | 0 | `p80_methods: OK` |
| `p80_cstr.sh` | 0 | `p80_cstr: OK` |
| `p80_retain.sh` | 0 | `p80_retain: OK` |
| `p80_migrate.sh` | 0 | `p80_migrate: OK` |
| `p79_basic/places/index/migrate.sh` | 0/0/0/0 | 全 `ok` 断言 |
| `p78_basic/types/method.sh` | 0/0/0 | 全 `ok` 断言 |

`p78_method.sh` 在 `check-all` 的调用环境下需要 `CT_C_BOUNDARY=allow`（脚本自身未 export，`check-all.sh` 全局 export）；
补上后 6 条曾被误报的断言全绿，属调用环境差异，不是回归。

## 3 E81-1…6 逐条

| ID | 结论 | 证据 |
| --- | --- | --- |
| E81-1 | **通过** | `layout` 输出 `sizeof(box)=16 sizeof(header)=8`、`payload_offset=8 expected=8`；生成的 C 里 `struct box_Rec { struct ct_box_hdr *h; struct Rec *ptr; }`、`box_Rec__payload_release` 调 `String_Drop_drop(&p->tag)`；`_Static_assert` 钉住 16/8 |
| E81-2 | **通过** | `record` 位置式 / 指定式、独立探针嵌套 `{ { 1 }, 2 }` → `1 2`；上下文关键字独立探针 `6 4 8`；`neg_new_string/int/vec/no_brace/global/static` 全 exit 1 |
| E81-3 | **通过** | 10 个负例全 exit 1 且诊断指名；额外独立探针 `new U16String`、`new Map<int,int>`、`new box<int>`、`new Str`、`new int[3]` 也全 exit 1 |
| E81-4 | **通过** | `vecbox` 的 `at()` / Drop glue；`uaf` 报 `heap-use-after-free`；6 个正例 ASan/UBSan stderr 0；嵌套 box 释放探针 ASan/UBSan 干净 |
| E81-5 | **通过（契约）** | `cycle`：`before: a_refs=2 b_refs=2` → `after handles: a_refs=1 b_refs=1`，无环告警；`--debug-leaks` 实测 `unknown option`（未实现），卡 §7.2/§7.4 与 D-016 §6 已如实记录 |
| E81-6 | **通过** | 旧 golden 只改版本 token（`v0.80.4→v0.81.0`，无其他差异行）；`check-all` 11 门全绿；`check-sanitizers` 583 项；spec §4.71 / tutorial §17 / package-guide §5 断言全 ok |

独立探针原始输出（archive 构建）：

```console
$ ./ctx2          # int new; 字段 new; 形参 new; new = new + 1
6 4 8
$ ./boxbase       # new Record + b.f + release
id=7 len=3 b.refs=1 tag.refs=2 live=1
after s.release tag_live=1 tag.refs=1
after b.release live=0 refs=0
$ ./nested        # new Outer { { 1 }, 2 }
1 2
$ ./ptrderef2     # box<T> *p 的 p->x 自动解引用
3
4
$ ./nestbox2      # 嵌套 box 字段的 retain / 静态 release
leaf.refs=2 child.refs=2 child.x=5
after leaf release child.x=5 refs=1
after n release tmp.refs=1 tmp.x=5
done
```

负例诊断（节选，全部 exit 1；独立探针源在 `/tmp/rev81/probes`，均以上述 archive 构建的 ct-ast 编译）：

```console
neg_new_string.ct:4:18: error: 'new String' / 'new Str' is not supported; use the literal, 'to_string()' or 'as_str()'
neg_new_int.ct:4:18: error: 'new' only accepts a named struct type; scalars, pointers, arrays, unions, enums and built-in handles are not boxed
neg_new_vec.ct:4:18: error: 'new' only accepts a named non-generic struct type; instantiate the generic first and box the value
neg_new_no_brace.ct:5:16: error: 'new R' needs a brace initializer; only 'new T { ... }' is supported
neg_box_slice.ct:4:12: error: a slice 'T[]' cannot be stored in box<T>; it is a non-owning view
neg_box_str.ct:4:14: error: a borrowed view cannot be boxed; box<T> owns its payload (use String for an owning string)
neg_field_str.ct:3:18: error: a borrowed 'Str' view cannot be a struct field; store an owning 'String' and call as_str() at the use site
neg_raw_field.ct:7:14: error: '.h' / '.ptr' are raw implementation fields; use the box's methods or at()
neg_new_global.ct:3:1: error: 'new' is only supported in a local initializer; a file-scope or static object cannot allocate at run time
neg_new_static.ct:5:23: error: 'new' cannot initialize a static object; it allocates at run time, so assign it in the function body
```

## 4 D-016 / D-011 J-2a / 跨单元

- **布局**：D-016 §1 的 16 字节句柄、8 字节 `{refs,aux}` 头、`header_size(T)=round_up(8, _Alignof(T))` 与上述
  `layout` / 生成 C 一致；`refs` 从 1 起、无 immortal 分支（`retain` 只对 `refs >= 0` 加一），与 §1.3 一致。
- **上下文关键字**：D-016 §2「有意偏离 D-011 J-2a」与实测一致；`int new;`、`r.new`、形参、`new = ...`、
  `new + 1` 均仍是标识符。**D-016 §2 + §8 已完整记录取代关系、理由、代价与证据**（`ctx.ct`）。
  D-011 本身没有回指 D-016 的字段，属可读性观察（§5 第 2 条），不影响语义。
- **类型边界 / 全局与 static**：D-016 §3 与 10 个负例一致；`new` 只在局部初始化器可用。
- **复制协议**：D-016 §4 的「`of` 复制构造，owning 叶各自 retain」经生成 C 验证：
  `box_H__copy` 对 `Vec` 字段发 `Vec_int_retain`、对 `String` 字段发 retain；`new` 对 String 位置项发
  `String_retain`，Vec/box 走显式协议（字段拷贝不自动 retain），与 spec §4.71 的显式协议一致。
- **静态 release**：D-016 §5 的 `String` / `Vec_*` / 嵌套 `box_*` 三分支均在生成 C 中验证
  （`box_Rec__payload_release` → `String_Drop_drop`；`box_H__payload_release` → `Vec_int_release`；
  `box_Node__payload_release` → `box_Leaf_release`）；`at()` 不 retain、`release()` 后 ASan 兜底。
- **借用 / 环**：`box<Str>`、`box<T[]>`、`struct { Str }` 硬错；环作者责任与 `--debug-leaks` 未实现见 §5。
- **跨单元限制已文档化**：D-016 §7、spec §4.71「边界」、tutorial §17、package-guide §5 四处明示
  「`ct build` 跨单元 `box<T>` 在 v0.81.0 不支持；单文件 compile / 单单元 build 可用」；C ABI 面
  「`box<T>` 不是 ABI 类型」也已写入 spec / package-guide。
- **`p39 r8`**：`sh test/modules/p39_lib/r8_probe.sh` → `p39_r8: OK`，未使用 box 的程序 `--emit-c` 与基线逐字节一致
  （`Box.h.ct` 按需加载生效）。

## 5 版本、tag、门禁

```console
$ git cat-file -t v0.81.0
tag
$ git rev-parse v0.81.0^{commit}
c2ec9cd6c10bb96e0846c698d28895ca7611a67c
$ git tag -n1 v0.81.0
v0.81.0         v0-PH-81 closeout (c2ec9cd)
$ git ls-remote origin 'refs/tags/v0.81.0*'
239677a272404e3ae4f4012418aeaf2613ef3da0        refs/tags/v0.81.0
c2ec9cd6c10bb96e0846c698d28895ca7611a67c        refs/tags/v0.81.0^{}
$ bash tools/check.sh g8        # 含 9 条历史 offset warn
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ python3 test/docs/check-docs.py
check-docs: OK (2181 relative links in 360 files, v0.81.0, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 8 signoff(s))
```

- **版本**：五处 `CTC_VERSION`、`README.md`、`docs/README.md`、`AGENTS.md`、`docs/history/phase-log.md` 全部
  `v0.81.0`；MINOR=81=v0-PH-81（`d=0`），PATCH=0。
- **tag**：annotated（`cat-file -t` = `tag`）、指向收口提交、message 含 `v0-PH-81` 与前 7 位 `c2ec9cd`、已推
  （远端 tag object 与本地一致，`^{}` 解引用到 `c2ec9cd6`）。
- **独立门禁**（archive 构建，`/tmp/rev81`）：

```console
$ bash selfhost/check-all.sh
  ok    v0-PH-81-S1 box<T>/new (E81-1…6: layout, new, release, at(), cycle, docs)
  == summary: 1540 passed, 0 failed, 4 skipped ==
check-all: OK (11 hard gates green)          # exit 0

$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
check-warnings: 490 ok, 0 failed             # exit 0

$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (583 checks, no sanitizer report)   # exit 0
```

`check-all` 中 p81 探针由 `selfhost/check-ast.sh` 接入（第八门），不是只在独立脚本里绿。

## 6 不阻断观察

1. **`--debug-leaks` 的措辞与实现**：卡 §1、E81-5 写「`--debug-leaks` 只报未配对 alloc/release 计数」，
   但该旗标在 ct-ast 未实现（实测 `ctc: unknown option '--debug-leaks'`）。卡 §7.2/§7.4 与 D-016 §6
   已如实写明「未实现、将来也只报计数」，所以读完卡与 D-016 后**不构成事实冲突**；建议后续文档把
   §1/E81-5 改成「若实现则只报计数」，避免只读前文的读者误解。不阻断 E81-5 的「不宣称环检测」判据。
2. **D-011 J-2a 无回指**：D-016 §2/§8 已完整记录「J-2a 的完全关键字在 v0-PH-81 范围内被 D-016 取代」；
   D-011 §2 表述仍是「完全关键字；`int new;` 硬错」，且没有 `superseded-by: D-016` 回指。
   建议后续文档提交补一行回指（D-011 其余裁定不变）。
3. **卡 §6/§7 编号**：`## 6 收口对照（E81-1…6）` 下没有正文，`### 7.1`…`### 7.4` 直接接在其后；
   E81 对照表实际在 §7.2。属排版问题，check-docs 绿，不影响判据。
4. **T-7 基线取祖父提交**：S1a 红证 `87fe0723` 的 `baseline: a18e7323` 是祖父提交，
   其父 `d4fd01f9` 是纯文档的 P-7.5 证据提交；代码基线等价（`d4fd01f9` 只改 `docs/planning/j6-evidence/p75/`），
   证据有效，但严格按 T-7「baseline 是 test 提交的父提交」应写 `d4fd01f9` 或把文档提交排到红证之后。
5. **`lib/std/README.md` 量词**：本轮改成「内置层由五个单元组成」，但下一句仍是「四者都是……自动预解析的单元」
   （原文未同步改）。纯文档笔误。
6. **既有缺陷（非 v0-PH-81 引入）**：struct 初始化器里调用方法会被原样发射，ct-ast 接受后 C 编译报
   `no member named 'retain' / 'to_string'`。最小复现（v0.81.0 与 v0.80.4 均可复现）：
   `struct R { String s; } ... struct R r = { y.to_string() };` →
   `error: no member named 'to_string' in 'struct String'`；
   `struct H { Vec<int> v; } ... struct H h = { v.retain() };` 同型。
   `new` 因共享花括号路径同样受影响（如 `new Record { 1, lit.to_string() }`、`new Node { leaf.retain() }`）。
   该缺陷在 v0-PH-81 之前就存在（v0.80.4 复现，只用 String/Vec），E81-2 的「与 `T x = {...}` 同路径」反而被满足；
   建议另立 SH 条目，不据此回退 v0-PH-81。
7. **E81-4 的「无泄漏」措辞**：p81 与 check-sanitizers 都设 `ASAN_OPTIONS=detect_leaks=0`（编译器 arena +
   环用例按设计泄漏），所以「ASan 无泄漏」实际由 `refs`/`ct_str_live_count()` 归零 + ASan/UBSan 无报告
   共同证明；LeakSanitizer 本身未开启。判据实质满足，措辞可比实现更准确地写成「refs/live 归零 + 无 sanitizer 报告」。

## 7 未覆盖 / 范围外

- `ct build` 跨单元 `box<T>` 按 D-016 §7 不支持，本轮按文档核对，未要求其可用。
- 自动 retain 未插入（D-016 §4 的显式协议），按设计不测。
- `--debug-leaks` 未实现，无法验证其计数输出。
- `tools/check.sh` 仍只有 `g0` / `g8` / `battle-selftest` 子命令（G1/G4/G6 缺位），
  是 `full-review-v0.77.0` 已登记的治理缺口，不属于 v0-PH-81；本轮用 `g0` + `g8` + `check-docs` 覆盖可执行部分。
- 未单独验证 32 位平台上的句柄字节数；卡与 spec 的 16/8 是 LP64 断言。

## 8 结论与交付

**REV: 通过。** E81-1…6 均有独立复现的原始输出；D-016 的布局 / 上下文关键字 / 复制协议 / 静态 release /
跨单元边界记录与实现一致；P-7.5 证据可复跑；版本、annotated tag、G8、`check-all`（11 门）、sanitizer、
warnings、check-docs 全绿。§6 的 7 条均为不阻断观察，其中第 6 条是 v0-PH-81 之前既有的初始化器方法调用缺陷，
建议另立 issue，不在本次回退。

本次只提交本文件，不 push，无 v0-PH-81 issue 状态变更。
