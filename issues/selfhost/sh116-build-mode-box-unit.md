# SH-116 · `ct build` 不发射 Box 内置单元（`struct ct_Box_hdr` 不完整）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（build 模式内置单元集合） |
| 定性 | bug（文档承诺的 `ct build` 路径不可用） |
| 严重度 | **High**（任何多单元/`ct build` 工程用到 `Box<T>` 都构建失败） |
| 锚点 | `72c22173`（v0.88.3 + SH-60；2026-11-23） |
| 依据 | [doc-freshness 报告](../../docs/reviews/doc-freshness-2026-11-23.md) P0；`lib/core/Box.h.ct` |
| 状态 | open |
| 处置证据 | **accepted（2026-11-23 所有者同意立项；P0 复核确认，并扩大为“最小程序也失败”）** |

## 现象

`ct build` 把 `Box<T>` 程序的产物拆成单元发射时，**Box 内置单元没有进入产物集合**：
用户单元里只剩 `struct ct_Box_hdr;` 前置声明，`cc` 报定义不完整。

### 最小复现（不依赖 examples/52）

```console
$ cat /tmp/boxt.ct
struct P { int x; }
int main(void) { Box<P> b = new P { 7 }; int y = b.at()->x; b.release(); return y; }

$ ct build /tmp/boxt.ct -o /tmp/boxt
fatal error: too many errors emitted, stopping now [-ferror-limit=]
# 含 'struct ct_Box_hdr' incomplete definition / size_t 未定义

$ ls .ctbuild
boxt.c  prog.c  Str.c  Str.h  Vec.c  Vec.h      # 没有 Box.c / Box.h
```

同一源码的 compile 模式是好的：

```console
$ ct compile /tmp/boxt.ct -o /tmp/boxt.c
$ grep -c 'ct_Box_hdr' /tmp/boxt.c     # 9（含 struct 定义）
```

### examples/52 的两种症状

| 基线 | `ct build examples/52_box_new/prog.ct` 的报错 |
| --- | --- |
| 报告基线 `43b1b086` | `prog.ct:127:30: error: call to undeclared library function 'malloc'` |
| 当前 `72c22173` | `prog.ct:36:28: error: incomplete definition of type 'struct ct_Box_hdr'` |

两者同属“Box 的单元/预置头没有并入 build 产物”，但当前 HEAD 是**整个单元缺失**，
不是报告推测的“只缺 `<stdlib.h>`”。修复时以当前 HEAD 为准。

## 为什么门禁没拦住

- `test/run.sh` 对带 `//@ct-requires: ct-ast` 的样例用 **compile 模式**（`ct-ast <file> -o <c>`），
  所以 `examples/52_box_new` 报 `ok`，当前 `test/run.sh` 为 `160 passed, 0 failed`；
- `selfhost/check-warnings.sh` 的 build-mode 段只覆盖 `08_map_binding` / `13_builder_chain` /
  `14_scalar_host`，不含 `50…53`；
- `examples/README.md:114` 把 52 的门禁写成 `test/run.sh + check-ast.sh`，两者都是 compile 模式。

## 期望

1. `ct build` 与 `ct compile` 对同一 `Box<T>` 程序等价：产物可编译、可运行、输出一致；
2. `ct build examples/50…53` 全部可跑；
3. build 模式的单元集合与 `builtin_units` 的“需要即发射”策略一致（Vec / Str / Option / Result 同一口径）。

## 排查线索（不代替实现）

- `selfhost/ct-ast/frontend/module/Module.h.ct`：`builtin_units[5]`、`module_src_wants_Box`
  （`Box<` / `box<` / `new T {` 判定）、`builtin_live_for` 的发射判定（Vec / Option / Result / Str
  各有分支，**未见 Box 分支**）、`builtin_units` 槽位写入（`Str.h.ct` / `Box.h.ct` 相邻初始化）；
- `lib/core/Box.h.ct` 顶部有 `#include <stdlib.h>`，`pub struct ct_Box_hdr` 定义在该单元；
- compile 模式能内联，build 模式漏单元 → 优先查“单元是否需要发射”的判定，而不是 prologue 文本。

## 验收

- 红：先提交 `test/ast/p116_box_build.sh`（或等价夹具），在 `ct build` 下复现失败并贴原始输出；
- 绿：`test/ast/p116_box_build.sh` 通过；`ct build examples/52_box_new/prog.ct` 输出 `4 4`；
- `check-warnings.sh` 增加 50–53 的 build-mode 段（零告警 + 可运行）；
- `test/run.sh` 与 `check-ast` 全绿；生成物逐字节不变（compile 模式不得回退）；
- `examples/README` 的 52 门禁口径与 `docs/reviews/doc-freshness-2026-11-23.md` 的 P0 一并修正（文档部分见 [DOC-96](../docs/doc-96-doc-freshness-followups.md)）。

## 非目标

- 不改 `Box<T>` 布局、Drop、`at()` 借用语义（D-016 / §4.71 不动）；
- 不借机改 Vec / Str / Option / Result 的发射策略；
- 不改 README 首屏结构（P1-1 已降级，见 DOC-96 非目标）。

## 关联

- [doc-freshness-2026-11-23](../../docs/reviews/doc-freshness-2026-11-23.md)（P0 原始证据）
- [DOC-96](../docs/doc-96-doc-freshness-followups.md)（文档侧收口）
- [DOC-86](../docs/doc-86-readme-v088-rewrite.md)（README 重写）
- [SH-105](sh105-goldens-static-freeze.md)（静态 goldens）
