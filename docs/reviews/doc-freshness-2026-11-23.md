# 文档评审报告：README 样例新鲜度与文档漂移（2026-11-23）

| 项 | 值 |
| --- | --- |
| 基线 | `43b1b086`（`v0.88.3-123`；README 自标 v0.88.3） |
| 范围 | `README.md`、`docs/tutorial.md`、`docs/language-spec.md`、`docs/{idioms,patterns,guide-for-c-programmers,memory-guide,architecture}.md`、`examples/README.md`、`test/README.md`、`docs/README.md`、`tools/check.sh` |
| 方法 | 逐块读 README；干净 HEAD（`git archive`）自举 `ct` 后实跑示例与 README 代码块；`check-docs`/`g4`；计数与链接核对 |
| 结论 | **README 首屏仍是“旧特性导览 + 新特性速查表”，没有把 String/Str、Box、ADT/match、ref/out、切片、defer/? 作为主线；更严重的是 README 链接的 `examples/52_box_new` 在 `ct build` 下不能构建，而现有门禁只覆盖 compile 模式。** |
| 自动化 | 已创建每周一 09:00（Asia/Shanghai）的文档审计任务 `schedule-bb8f1fe0-cdf1-4ad7-af60-202354686117`，见 §7 |

> 本报告为 REVIEW 产出；`签收: REVIEW 2026-11-23（待 EDITOR）`。

---

## 0. 结论先行

**P0（1 条）**：`examples/52_box_new` 的 `ct build` 失败；README §0.5 把它列为“最小可跑样例”，
并写“运行任一 example：`ct build examples/50_ref_out/...`”。干净 HEAD 实测失败，现有
`test/run.sh` / `check-ast` 用 compile 模式所以没拦住。

**P1（4 条）**

1. README §0.1–§0.4 的主线样例仍是 0.2–0.6 时代的能力：HTTP 目标链、静态映射切分、
   `Vec<Shape>` 接口表、`Map` 词频；String/Str、Box、match/ADT、ref/out、切片只在 §0.5
   一个表格里出现，且只有一段 String 内联代码。新用户第一屏看不到 Ct 的“关键优势”。
2. README 代码块没有可执行来源：`docs/snippets/` 不存在，G4 只跑 `check-docs`，
   README 的 C/ct 代码块没有被编译/运行；README 却写“代码块后的命令与输出是实测结果”。
3. `examples/README` 把 52 的门禁写成 `test/run.sh + check-ast.sh`，但这两条是 compile 模式；
   `check-warnings` 的 build-mode 段只覆盖 08/13/14，不覆盖 52。文档把“compile 通过”
   写成了“可 `ct build`”。
4. README §0.3/§0.4 的代码块不是完整可复制程序（0.4 缺 `words` 定义；0.3 无文件、无命令），
   0.3 从 `/tmp` 直接 `ct build` 会撞 strict C 边界（`#include <stdio.h>`），README 没给
   `--c-boundary=allow` 或“放在 examples 下”的说明。

**P2（5 条）**：tutorial 缺 §14（13 直接跳 15）；`examples/README` 仍写 `box<T>`（LANG-24 规范是
`Box<T>`，`box` 为弃用别名）；`test/README` 计数 299/1519/4 与当前 312 目录、`test/run` 160
不符；`guide-for-c-programmers` 核对基线仍是 v0.84.1；README 的能力清单没有 `defer`/`?`/
`borrow`/`own` 的可运行片段（只有列表项）。

---

## 1. README 逐块核对

| 块 | 行 | 内容 | 最新特性？ | 可执行/门禁 |
| --- | --- | --- | --- | --- |
| §0.1 | 32–39 | `"https://..."` → method/header/timeout/send/status 目标链 | 链式派发（SH-110），但不是新句柄层 | 目标形态，非完整程序；无命令；未进门禁 |
| §0.2 | 62–64 | `"alpha,beta".split_once(...).len()` | 静态映射/类型宿主 | 一行，依赖 examples/48/std；无独立命令 |
| §0.3 | 75–103 | `Vec<Shape>` + `push` + `foreach` 异构表 | trait/接口值（旧主线） | 完整程序但**不是文件**；无命令；从 /tmp 编译触发 strict C 边界 |
| §0.4 | 114–129 | `Map<char*,int>` 词频片段 | `Map`/foreach（旧主线） | 片段，缺 `words`；无命令 |
| §0.5 | 148–162 | `String greet(Str)` | String/Str | 干净 HEAD `ct build` 输出 `hello, ct`；无文件/命令 |
| §0.5 表 | 140–144 | 50–53 四个新样例 | ref/out、切片、Box、match | 链接存在；52 的 `ct build` 失败（P0） |
| §1 | 172–176 | examples/47 静态宿主 | 旧静态宿主 | 可跑；输出 200 |

**首屏问题**：§0.1 是“目标形态”而不是可运行示例；§0.2–§0.4 连续三个旧主线示例；新能力
被压到 §0.5 的表格。用户读完前 140 行，仍不知道 Ct 已经有 `String` 自动引用计数、`Box`、
穷尽 `match`、`ref/out`、切片、`?`/`defer`。

**“每个代码块都有命令与输出”不成立**：§0.1、§0.2、§0.4 没有命令/输出；§0.3 只有一句
“`ct build` 实测输出 `12 75 87`”，没有文件路径与命令。README 第 25 行的总承诺应改写或补齐。

---

## 2. P0：`examples/52_box_new` 的 `ct build` 失败

干净 HEAD（`git archive 43b1b086`）自举 `ct` 后：

```console
$ ./ct build examples/52_box_new/prog.ct -o /tmp/e52
examples/52_box_new/prog.ct:127:30: error: call to undeclared library function 'malloc' ...
   h = (struct ct_Box_hdr *)malloc(off + sizeof(*v));
      |                              ^
rc=1
```

同一棵树上：

```console
$ bash test/run.sh
  ok    examples/52_box_new/prog.ct (ct-ast)
== summary: 160 passed, 0 failed ==
```

原因：`test/run.sh` 的 `ast_example_status` 用 **`ct-ast <file> -o <c>`（compile 模式）**，
`ct build` 走多单元 build 模式；`Box` 内置单元的 prologue（`lib/core/Box.h.ct:19` 的
`#include <stdlib.h>`）没有进入 build 产物的 `prog.c`/`Box.c` 顶部。README 却把 52 当作
`ct build` 可跑样例。**这是“文档承诺 × 门禁模式”双重缺口**：

- README §0.5 第 166 行写“运行任一 example：`ct build examples/50_ref_out/...`”，用户替换成 52 即失败；
- `examples/README` 的 52 行把 compile 门禁写成通用门禁；
- `check-warnings.sh` 的 build-mode 段只覆盖 `08_map_binding/src`、`13_builder_chain`、
  `14_scalar_host`，没有 50–53。

**修复方向**（需用户确认）：先修 Box 内置单元的 include 发射或 `ct build` 的 built-in prologue；
再给 50–53 增加 build-mode 门禁；README 的“运行任一 example”改成逐条对应命令。

---

## 3. P1：README 主线没有体现最新 Ct 的关键优势

Ct 相对 C 的关键优势在 v0.78–v0.88 已经变成：

- `String` 拥有 / `Str` 借用（自动 retain/release、零拷贝视图、`cstr()` 边界）；
- `Box<T>`/`new`（16 字节句柄、`at()` 借用、显式 `release`）；
- 穷尽 `match` + ADT payload（无 `int kind` + `switch`、无 fallthrough）；
- `ref`/`out`（调用点不写 `&`/`*`，`out` 定值分析）；
- 切片 `T[]`（`{ptr,len}`、`s[1..3]`、`xs.len`、越界 trap）；
- `defer`/`errdefer`/`?`、`borrow`/`Handback`/`own`。

README 的前四个例子只覆盖 trait/接口值/Vec/Map/静态映射；这些仍是 Ct 的能力，但不是
**当前版本的差异化优势**。建议:

1. **重写 §0.1** 为“一个完整可跑程序”，建议用 ADT + `match` + `String` + `Box` 组合
   （例如 `enum Msg { Text(String), Ping }` + `match` + `Box<Msg>`），展示“无 vtable、无
   隐藏分配、payload 生命周期显式”。
2. 把旧 HTTP 静态宿主链降为“附录/路线图”或 §0.6，不再占据第一屏。
3. 在 §0.2/§0.3 各放一个真正完整的 `examples/50…53` 代码块（或至少 `<!-- snippet -->` 引用），
   而不是只给表格。
4. 补一段 `defer`/`errdefer`/`?` 的驱动初始化/回滚示例——这是硬件/系统工程师最买账的
   “关键优势”之一，当前 README 只有能力列表。
5. 在 §0 开头加一句“本页示例全部来自 `examples/` 或 `docs/snippets/`，由门禁编译”，
   把承诺变成可验证事实。

---

## 4. P1：README 代码块没有可执行来源（G4 缺口）

- `docs/snippets/` **不存在**；`tools/check.sh g4` 只是 `python3 test/docs/check-docs.py`，
  不编译 README 代码块，也不检查 300 行。
- README 的 5 个 C/ct 块中，只有 §0.3 与 §0.5 String 是完整程序；§0.1 是目标、§0.2 是一行、
  §0.4 是片段。它们没有对应的 `.ct` 文件，也没有 `ct build` 命令。
- 因此“README 代码块是否仍能编译/输出正确”只能靠人工；本次 P0 就是这样漏掉的。

**建议**：把 README 的每个可执行块抽到 `docs/snippets/README/`（如 `0.3_shapes.ct`、
`0.5_greet.ct`），README 用引用渲染；G4 增加“snippet 存在 + `ct build` + 期望输出 + 300 行”
四项。若不想引入 snippet 目录，至少给 README 的 C/ct 块加 `// source: examples/...` 并在
`check-warnings.sh` 中 build-mode 跑一遍。

---

## 5. P2：其他文档问题

| # | 位置 | 问题 | 建议 |
| --- | --- | --- | --- |
| D-1 | `docs/tutorial.md:1896` | 章节号从 §13 直接跳 §15，**没有 §14** | 补 §14 或改编号；检查目录/链接 |
| D-2 | `docs/tutorial.md:1961` | §16“下一步”出现在 §17–§23 新特性之前，结构倒置 | 把“下一步”移到最后，或改为 §24 |
| D-3 | `examples/README.md:114` | 写 `box<T>`；LANG-24 规范拼写是 `Box<T>`，`box` 是 v1.0 弃用别名 | 改 `Box<T>`，并注明 `box` 别名告警 |
| D-4 | `test/README.md:19,28` | 写 299 目录 / 1519 passed / 4 skipped / v0.77.0；当前 312 目录、`test/run` 160、v0.88.3 | 改为“由命令输出为准”，或加计数断言 |
| D-5 | `docs/guide-for-c-programmers.md:7` | 核对基线 v0.84.1，正文已引用 v0.88.2/v0.88 | 更新基线到 v0.88.3，或写“内容按 v0.88 核对” |
| D-6 | `README.md:114-129` | §0.4 片段缺 `words` 定义，不能独立编译 | 改为引用 `examples/25_wordcount` 的完整文件，或补全 `words` |
| D-7 | `README.md:75-103` | §0.3 不是文件；从 `/tmp` 复制会因 `#include` 触发 strict C 边界 | 标注“放在 `examples/` 下运行”或给 `--c-boundary=allow` |
| D-8 | `docs/README.md:17` | tutorial 简介仍写“核心范式…map”，未提 §15–§23 新句柄层 | 更新简介 |
| D-9 | `README.md:232` 以下 | 能力列表有 `defer`/`?`/`borrow`/`own`，但 README 无对应代码块 | 加 1 个“驱动初始化 + defer/errdefer/? 回滚”的完整片段 |

**没有发现**：`docs/language-spec.md` 的 §4.68–§4.75 与 `docs/idioms.md`/`patterns.md` 的新特性
内容基本同步；`docs/architecture.md` 已明确“只覆盖 L0，主线 ct-ast 见 §0”；`docs/README` 的
`guide-for-c-programmers`/`dist` 链接有效；`check-docs` 2918 links / 422 files 全绿。

---

## 6. 根因与防复发

1. **README 代码块没有“单一来源”**：既不是 `examples/` 文件，也不是 `docs/snippets/`，所以
   编译器/门禁升级不会让它们变红。
2. **示例门禁只覆盖 compile 模式**：`test/run.sh` 对新示例用 `ct-ast <file> -o c`；`ct build`
   是 README 推荐的命令，却没有逐示例 build-mode 门禁。
3. **版本/计数靠手抄**：`test/README`、`examples/README`、`guide` 基线都出现漂移。
4. **G4 名不副实**：规范要求 snippet/300 行，项目实现只做链接与版本；`AGENTS` 0.1 也写
   “文档 snippet 缺失”，但没有 `deviation:`。

**建议的自动化**（与已创建的周任务互补）：

- G4 增 `docs/snippets/` + README 代码块编译/运行；CI 每次跑。
- `examples/` 全量 build-mode 门禁：`for d in examples/*/; do ct build ...; done`，期望输出
  与 `.expected.out` 比对；至少覆盖 50–53。
- `test/README`/`examples/README` 的计数改为生成或 `check-docs` 断言“目录数/通过数”。
- README 首屏加 `<!-- doc-freshness: latest-features -->` 标记，周任务检查其是否引用
  `String`/`Box`/`match`/`ref`/`out`/slice 中至少 4 项。

---

## 7. 已创建的自动化任务

- 任务 id：`schedule-bb8f1fe0-cdf1-4ad7-af60-202354686117`
- 名称：每周审计 README 与文档样例是否体现最新 CT 语法
- 时间：每周一 09:00 Asia/Shanghai（首次 2026-11-30 09:00）
- 目标：新会话（独立执行），只写 `docs/reviews/doc-freshness-<date>.md` 与 `docs/README` 索引；
  不改 README/源码，修复项交用户确认。
- 覆盖：README 全块、examples 50–53、tutorial/language-spec/guides、`check-docs`/g4、
  版本与计数漂移。

---

## 8. 复现命令

```console
$ git rev-parse --short HEAD          # 43b1b086
$ git archive HEAD | tar -x -C /tmp/ctdoc-head
# 自举 L0→L1→L2→ct-ast 后：
$ /tmp/ctdoc-head/ct build examples/52_box_new/prog.ct -o /tmp/e52
# error: call to undeclared library function 'malloc' ... rc=1
$ cd /tmp/ctdoc-head && bash test/run.sh
# ok examples/52_box_new/prog.ct (ct-ast); summary: 160 passed, 0 failed
$ python3 test/docs/check-docs.py
# OK (2918 links / 422 files; g4=0)
$ ls docs/snippets
# No such file or directory
$ grep -n '^## 14' docs/tutorial.md
# (no output)
```

> 说明：`test/run.sh` 的 52 通过是 **compile 模式**；`ct build` 失败是 build 模式。两者不矛盾，
> 正是本报告 P0 的证据。

---

## 9. 处置（REQ，2026-11-23）

复核基线从 `43b1b086` 前移到 `72c22173`（SH-60 四个提交之后）。结论与修正：

| 项 | 处置 |
| --- | --- |
| P0 | **确认，并扩大**：不只是 52；最小 `Box<P>` 程序在 `ct build` 下同样失败。当前 HEAD 的 `.ctbuild` 里没有 Box 单元（只有 `prog.c` / `Str.c` / `Vec.c`），compile 模式产物含 `struct ct_Box_hdr {`。症状已从“`malloc` 未声明”变为“`ct_Box_hdr` 定义不完整”，修复以当前 HEAD 为准 → [SH-116](../../issues/selfhost/sh116-build-mode-box-unit.md) |
| P1-2 / P1-3 / P1-4 / P2 | 采纳（D-6 半误判、D-4 引文错误两处除外）→ [DOC-96](../../issues/docs/doc-96-doc-freshness-followups.md) |
| P1-1 首屏重排 | 降级，不进 v1.0；理由见 DOC-96 §4 |
| D-4 引文 | 更正：报告基线时 `test/README` 已写 312 目录 / 156 passed / v0.88.3；299/1519 已由 DOC-75 修复。真实漂移只剩 156→160 |
| D-6 | 半误判：§0.4 原文已指向 `examples/25_wordcount` |
| 本报告的 `check-docs 2918/422` | 含本文件与 `docs/README` 索引的未提交改动；核对比对值为 `2917/421` |

签收：REQ 2026-11-23；USER 2026-11-23 同意立项（SH-116 / DOC-96），P1-1 暂缓。

