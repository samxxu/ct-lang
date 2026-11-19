# v0.77.2 LANG-5 / LANG-7 / PKG-9 + DOC 批复核（REV）

> **结论：`REV: 通过`**——7 条全部 `verified`：LANG-5、LANG-7、PKG-9、DOC-69、DOC-71、DOC-72、DOC-73。
> 另记 3 项**不阻断**瑕疵：DOC-71 两处新增锚点不可解析、DOC-72 的 B3-2/B4 deferred 无明确触发条件、
> LANG-7 红证二进制与标注 baseline 不一致。三项均不改变文档内容或修复结论，详见 §7。
>
> **复核对象**：`bbe82d42`（tag `v0.77.2`，本地 annotated tag、未 push）；DEV 提交
> `7b8e8c9b`（LANG-5）、`eed1cbcd`（LANG-7）、`35757b08`（PKG-9）、`38248747`（DOC 批）。
> **复核者**：REV / rev-lang-pkg；日期 2026-11-20。
> **方法**：只依据 `git archive v0.77.2`，在 `/tmp/rev-src-v0772` 重新自举 L0→L1→L2→ct-ast
> （`ct-ast v0.77.2`）；红/绿对照另取 `git archive fa89d727` 重建基线二进制
> （`ct-ast v0.77.1`），用同一探针复跑。不使用工作树当前产物，不转述 DEV 提交正文。
> **权限边界**：本轮只写 issue 的 `status`/复核段与本文件；未改代码、版本号、`battle/**`、
> `docs/reviews/**` 既有正文；未 push、未打 tag、未 bump。

## 1 环境与自举

```console
$ uname -m; uname -sr; cc --version | head -1
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)

$ git archive v0.77.2 | tar -x -C /tmp/rev-src-v0772
$ bash /tmp/rev-build.sh /tmp/rev-src-v0772 /tmp/rev-v0772
[build] L0
[build] L1
[build] L2
[build] ct-ast
[build] done: /tmp/rev-v0772/ct-ast
ct-ast v0.77.2
```

基线同样四步（`/tmp/rev-src-base` ← `fa89d727`），产出 `/tmp/rev-base/ct-ast`，`-v` 为
`ct-ast v0.77.1`。四段 `cc` 均 `-Wall -Wextra -std=c99`，无警告输出。

## 2 LANG-5：指针/接口字段访问红→绿

探针 `test/ast/p77_lang5_field.sh` 在 v0.77.2 归档内直接跑；基线归档尚无该脚本，故用
HEAD 的同一支探针配基线二进制（夹具全在脚本内，不依赖归档树）。

```console
$ sh test/ast/p77_lang5_field.sh /tmp/rev-v0772/ct-ast
ok   b["k"].v with a pointer result is refused
ok   b["k"].v with an interface result is refused
ok   b["k"]->v compiles and runs
ok   b["k"].v with a value result compiles and runs
ok   b["k"].m() still materialises and runs
ok   f().m() still materialises and runs
ok   f().v on a value compiles and runs
ok   p.v on a pointer variable is refused
ok   b["k"].m() pointer receiver keeps its diagnostic
OK p77/lang5 (field receiver: pointer/interface refused, value forms kept)
$ echo $?
0

$ sh test/ast/p77_lang5_field.sh /tmp/rev-base/ct-ast
FAIL p77/lang5: b["k"].v with a pointer result is refused
  exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
FAIL p77/lang5: b["k"].v with an interface result is refused
  exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
ok   b["k"]->v compiles and runs
ok   b["k"].v with a value result compiles and runs
ok   b["k"].m() still materialises and runs
ok   f().m() still materialises and runs
ok   f().v on a value compiles and runs
FAIL p77/lang5: p.v on a pointer variable is refused
  exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
ok   b["k"].m() pointer receiver keeps its diagnostic
$ echo $?
1
```

基线 3 例静默（指针结果、接口结果、指针变量），v0.77.2 均硬错且首行带 `file:line:col`；
值返回、方法物化、`->` 三组保持绿。

**issue 原文与 DEV 范围的差异（不打回）**：原文对形态 2/3 的期望是「至少一致：要么都支持，
要么都硬错」，并未要求值返回也硬错。值返回 `f().v` 是合法 C（`struct Inner` 返回值取字段，
cc 通过），方法形态由发射器物化；两者都支持，符合「都支持」分支。真正静默坏 C 的是指针/接口
返回，`7b8e8c9b` 已拒绝，故不按「值返回未硬错」判 `reopened`。

T-7：红 `7627a43d`（父 `fa89d727`）→ 修 `7b8e8c9b`；红提交只含探针与 `check-ast.sh` 接入，
实现提交只改 `Expr.h.ct`。

## 3 LANG-7：类型名静态调用诊断红→绿

```console
$ sh test/ast/p77_lang7_static_type.sh /tmp/rev-v0772/ct-ast
ok   typedef receiver names the type
ok   enum receiver names the type
ok   struct static call still works
ok   declared struct with no such method keeps its message
ok   an undeclared name still reports an undeclared variable
OK p77/lang7 (type-name static call diagnostic)
$ echo $?
0

$ sh test/ast/p77_lang7_static_type.sh /tmp/rev-base/ct-ast
FAIL p77/lang7: typedef receiver names the type
  missing diagnostic /static method 'make' cannot be resolved: 'MyInt' is a type name, not a variable/: .../typealias.ct:2:30: error: use of an undeclared variable
FAIL p77/lang7: enum receiver names the type
  missing diagnostic /static method 'make' cannot be resolved: 'Color' is a type name, not a variable/: .../enum.ct:2:30: error: use of an undeclared variable
ok   struct static call still works
ok   declared struct with no such method keeps its message
ok   an undeclared name still reports an undeclared variable
$ echo $?
1
```

typedef / enum 接收者在 v0.77.2 报准确诊断，位置在接收者；struct 静态调用、struct 无此方法、
未知名三例文案不变。T-7：红 `d0cb10c4`（父 `38248747`）→ 修 `eed1cbcd`，链成立。
DEV 处置把 baseline 写作 `38248747`，红证实际用 `fa89d727` 重建的二进制；两者只差 LANG-5 的
`Expr.h.ct` 49 行，LANG-7 路径不受影响，红证仍成立（见 §7）。

## 4 PKG-9：被拒 get 不写 store

全量 `test/pkg/run.sh` 在 v0.77.2 归档内自建链后运行（未用工作树产物）：

```console
$ cd /tmp/rev-src-v0772 && bash test/pkg/run.sh
== PKG-9: a manifest must declare publisher + ns-root before ct get ==
  ok    ct get refuses a manifest without publisher
  ok    ct get refuses a manifest without ns-root
  ok    a refused get commits no dependency to the store
  ok    a refused get leaves the previous ct.lock byte-identical
  ok    a complete manifest writes a v2 lock and lands in the store
  ok    ct pkg check still reports both missing fields
== summary: 153 passed, 0 failed ==
$ echo $?
0
```

定向红/绿（`bad` 缺 `publisher`、`dep = ../good@^0.2.0`；`good` 身份完整）：

```console
# 基线 eed1cbcd（527dcb66 的父；Pkg.h.ct 与 fa89d727 相同）
$ HOME=B/home CT_HOME=B/home /tmp/rev-base/ct-ast get ../bad
ctc: './../bad/ct.pkg' is missing 'publisher'
$ echo $?
1
$ find B/home -maxdepth 5 -type d
B/home
B/home/pkg
B/home/pkg/ct
B/home/pkg/ct/demo
B/home/pkg/ct/demo/0.2.0
B/home/pkg/ct/demo/0.2.0/ns      # 依赖已写进 store
$ test -f B/proj/ct.lock; echo $?
1

# v0.77.2
$ HOME=H/home CT_HOME=H/home /tmp/rev-v0772/ct-ast get ../bad
ctc: './../bad/ct.pkg' is missing 'publisher'
$ echo $?
1
$ find H/home -maxdepth 5
H/home                          # store 为空
$ test -f H/proj/ct.lock; echo $?
1
```

逐条：A1/A2、A1b、A3、A6、A7 全绿。原单「rc=0 + 静默退 v1 lock」是 v0.58.0 历史锚点，
HEAD 已不可复现；本次红证针对 HEAD 残余缺陷（拒绝前仍提交依赖），与历史锚点分开记录。
A4/A5 的显式 v1 开关未实现：PH-63 已移除 vendor 读写，v1 行无法被 `ct build` 消费，
「没有标记就拒绝」的理由成立，不计漏项。T-7：红 `527dcb66`（父 `eed1cbcd`）→ 修 `35757b08`。

## 5 DOC-69 / 71 / 72 / 73

### 5.1 DOC-69

```console
$ awk '/^### 1.4/,/^### 1.5/' docs/history/design/phase26.md | grep -c '^| D[0-9]'
22
$ awk '/^### 1.4/,/^### 1.5/' docs/history/design/phase26.md | grep -c '^| D2[3-9]'
0
$ awk '/^### 1.5/,/^### 1.6/' docs/history/design/phase26.md | grep -c '^| E[0-9]'
8
$ git merge-base --is-ancestor d73e3fb2 HEAD; echo $?
0
```

§9.9 存在且把 E6→P8 的补丁口径与「下一相卡面要求」写在唯一位置，冻结原文未动；D 仍 22 行、
无 D23+，E 仍 8 行，未回溯扩写。建议项 2 的 deferred 触发条件「下一相冻结 §1.5/§5 时」写明。

### 5.2 DOC-71

```console
$ grep -n '当前成员的占位' docs/language-spec.md
2154:- **`$` 是当前成员的占位，不是下标**：...
$ grep -n '当前成员值' docs/history/design/phase24.md
160:4. **可多次出现**：... 同一个当前成员值 ...
$ grep -n '`\$`（当前成员 / 自身）' docs/glossary.md
69:| `$`（当前成员 / 自身） | ... |
```

独立实测（v0.77.2 归档二进制）：

```console
$ /tmp/rev-v0772/ct-ast compile /tmp/rev-doc71/p.ct --c-boundary=allow -o /tmp/rev-doc71/p.c
$ sed -n '6,7p' /tmp/rev-doc71/p.c
    int a[] = { ((int)2), ((int)3), ((int)4) };
    int b[] = { ((int)0), ((int)1), ((int)2) };
$ /tmp/rev-doc71/p
a 2 3 4
b 0 1 2
```

`$` 绑定序列成员值，不是 0 起下标，与改后叙述一致；诊断文案保留并注明历史措辞；glossary 条目
覆盖 range / `into` 两个语境。发射器注释未改，处置登记 deferred、触发条件「随下次实现提交」明确。

### 5.3 DOC-72

```console
$ sed -n '5,7p' docs/language-spec.md
> **适用版本**：安装入口 **ct-ast**（`selfhost/ct-ast/main.ct`），不在此固定版本号——实际版本以
> `ct -v` 为准。最近一次全文复核是 v0.53.1（2026-11-15），此后正文按 phase 增量修订，
$ grep -n 'v0.16.0' docs/tutorial.md; echo $?
1
$ grep -n '::=' docs/language-spec.md; echo $?
1
$ grep -c 'L0' docs/language-spec.md; grep -c 'L2' docs/language-spec.md
31
41
$ sed -n '1p' docs/architecture.md
# ctc 内部架构（L0 种子；主线 ct-ast 见 §0）
```

`.m.ct` 可被 import 修正也独立复跑：`map_unit_cross` 用 v0.77.2 构建 rc=0，产物与
`expected.out` 一致。B1-2/B1-3/B1-4、B2-2/B2-3 已落地；B2-1 的代际表与 31/41 计数一致。
B1-1 的字面验收「页首版本 == `ct -v`」改为「不固定版本号、以 `ct -v` 为准」，相等断言留给
B3-1，属已声明的 deferred。B1-1/B2-1/B3-1 有下一动作；**B3-2/B4 的 deferred 只有「分阶段 /
后置」，没有日期、phase 或前置门禁**，按 5.4 建议 REQ 补可判定触发点（见 §7）。

### 5.4 DOC-73

四份新文档存在：`docs/llm-guide.md`（83 行）、`docs/std-catalog.md`（85 行）、
`docs/ct-pkg.md`（55 行）、`docs/ct-pkg-index.md`（74 行）；`docs/README.md` 新增生态入口，
tutorial §10 指向 std-catalog，package-guide §0 补三角色，glossary 统一六字段现行 / 五字段旧行。

A4 的前提独立复核（2026-11-20 拉取官方索引）：

```console
$ awk 'NF{print NF}' /tmp/rev-index.txt | sort | uniq -c
  10 5
  10 6
$ grep '^std ' /tmp/rev-index.txt
std 0.19.0 ct https://github.com/ct-pkg/std v0.19.0 sha256:432086f0ec6c…
```

内置 pin 表 `std / 0.19.0 / v0.19.0` 与 `/tmp/std019` 的 16 个公开模块口径一致。DOC-73 无 deferred。

## 6 版本、tag 与门禁

```console
$ grep -n '#define CTC_VERSION' selfhost/l0/ctc.c selfhost/l1/ctc.ct \
    selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
selfhost/l0/ctc.c:61:#define CTC_VERSION "0.77.2"
selfhost/l1/ctc.ct:108:#define CTC_VERSION "0.77.2"
selfhost/l2/core.ct:55:#define CTC_VERSION "0.77.2"
selfhost/l2/driver.ct:36:#define CTC_VERSION "0.77.2"
selfhost/ct-ast/main.ct:36:#define CTC_VERSION "0.77.2"
$ grep -rl 'Generated by ct v0\.77\.2' test examples | wc -l
51
$ grep -rl 'Generated by ct v0\.77\.1' test examples | wc -l
0
$ git cat-file -t v0.77.2; git rev-parse 'v0.77.2^{commit}'
tag
bbe82d421effba3ac4290f53478fb1296b828a5b
$ git tag -l --format='%(contents)' v0.77.2
LANG-5/LANG-7/PKG-9 fixes (bbe82d4)
$ git branch -r --contains bbe82d42 | wc -l
0
```

五处 `CTC_VERSION` 与 51 个 golden/ABI banner（25 个 `.expected.c` + 25 个 `.expected.h` +
`test/modules/p39_lib/lib.expected.abi.h`）均在 `bbe82d42`；无 `v0.77.1` 残留 banner。
tag 为 annotated、指向 HEAD，本地未 push（远端不包含 `bbe82d42`），与「未 push」一致；
`g8` 对本轮 fix tag 绿（`fix-tags` deviation）。

```console
$ bash tools/check.sh g0
ok  ./docs/spec/ai-coding-workflow.md（全文副本 sha256=c22c85ee…）
ok  AGENTS.md（version=1.17.0）
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (1990 relative links in 329 files, v0.77.2, 11 hard gates, 12 phase status, 5 适用版本 header(s))
design window: ok (12/12)
```

## 7 不阻断观察

1. **DOC-71 两处新增锚点不可解析**：链接写作
   `#447-数组-range-初值-ab-phase-24仅-ct-ast`，按 GitHub `github-slugger` 对标题
   「4.47 数组 range 初值 `a..b($)`（Phase 24，仅 ct-ast）」的计算，实际应为
   `#447-数组-range-初值-abphase-24仅-ct-ast`（`ab` 与 `phase` 之间无连字符）。位置：
   [phase24.md:160-161](../history/design/phase24.md#L160-L161) 与
   [DOC-71 处置项 1](../../issues/docs/doc71-range-dollar-is-member-not-index.md)。全仓 fragment
   链接 89 条，不合规 10 条（本批新增 2 条、既有 8 条）；`check-docs` 只校验相对路径存在，
   不校验 `#fragment`。内容正确，记为引用瑕疵，建议下次文档提交统一修正。
2. **DOC-72 B3-2/B4 的 deferred 无明确触发条件**：只写「分阶段」「后置」，没有日期、phase 或
   前置门禁；按 5.4 应由 REQ/USER 补触发点。REV 不改 `deferred`，不据此打回。
3. **LANG-7 红证 baseline 标注与二进制不一致**：标注 `38248747`，实际用 `fa89d727` 重建的
   二进制；两者只差 LANG-5 的 `Expr.h.ct` 49 行，LANG-7 路径不受影响，红证仍成立。
4. **DOC-73 的「核对基线 ct 0.77.1」**：新文档按写作时 HEAD（v0.77.1）记录，属历史事实，
   不随 v0.77.2 bump 回改；不作为版本漂移。

## 8 结论

| issue | 处置 | REV 结论 | 关键证据 |
| --- | --- | --- | --- |
| LANG-5 | 指针/接口返回值的 `.v` 硬错 | `verified` | 基线 3 例静默；v0.77.2 9/9 绿 |
| LANG-7 | 类型名静态调用准确诊断 | `verified` | 基线 2 例文案错；v0.77.2 5/5 绿 |
| PKG-9 | 身份校验前移、被拒 get 不写 store | `verified` | 基线 store 有 `ct/demo`；v0.77.2 空；pkg 153/0 |
| DOC-69 | §9.9 映射 + 不扩写冻结判据 | `verified` | D 22 / E 8 / d73e3fb2 祖先 |
| DOC-71 | `$` 改「当前成员」 | `verified` | `2..5($)` → 2 3 4；两处锚点瑕疵记 §7 |
| DOC-72 | spec 版本/结构收敛（部分 deferred） | `verified` | 31/41、零 `::=`、零 `v0.16.0`、map_unit_cross 绿 |
| DOC-73 | LLM 生态入口与口径统一 | `verified` | 四份新文档；索引 10×5 + 10×6；16 模块 |

`REV: 通过`（7/7 verified，0 reopened）。本轮未改代码、版本号、`battle/**`、既有
`docs/reviews/**`，未 push、未打 tag。
