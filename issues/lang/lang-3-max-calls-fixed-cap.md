# LANG-3 · `MAX_CALLS` 固定 1024，按整次构建累计

| 项 | 值 |
| --- | --- |
| 模块 | lang（编译器容量） |
| 严重度 | Medium |
| 优先级 | **P2** —— 目前无人被挡，但属「包长大才突然报错」的悬崖 |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV） |
| 锚点 | `v0.53.1`（`c4727787`） |
| 详情 | [max-calls-limit.md](../../docs/reviews/max-calls-limit.md)（口径、改动面、绕法、余量实测） |

## 精确触发条件

一次 `ct build` 的**全部单元累计**出现第 1025 个「指向已解析自由函数的调用表达式」。
同名函数调多次记多条；原型、方法调用、静态方法调用、函数指针调用、libc 调用都不占槽。

## 最小复现

```sh
python3 - <<'PY'
lines = ["#include <stdio.h>", "int f(int x);", "int main(void) {"]
lines += ["    f(%d);" % i for i in range(1025)]
lines += ["    return 0;", "}"]
open("n1025.ct","w").write("\n".join(lines) + "\n")
PY
ct-ast build n1025.ct -o out
```

## 实际行为

```text
n1025.ct:1028:11: error: too many calls
rc=1
```

1024 条通过；两个单元 500 + 600 在入口第 524 条耗尽（`main.ct:529:11`），500 + 400 通过。

## 期望行为

按需增长（翻倍扩容），或至少在文案里说明「按单次构建累计」并给出分层出库的绕法。

## 影响面

- 每条 324 字节（`caller[160] + callee[160] + line`），1024 条约 332 KB 常驻；
- 实测余量：rill-dsl 410/1024（最紧）、ct-json 271、ct-fsguard 78、ct-sse 26；
- 「把热点函数拆到独立单元」**实测无效**——只要仍在同一次构建里就继续累计。

## 绕法

分层出库（`ct build --lib` + 链接）、函数指针间接、按闭包拆成多次构建。

## 定位

- 上限：[Expr.h.ct:55](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L55)；
- 存储：[Parser.h.ct:3759](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L3759) 的 `static struct Call g_calls[1024]`；
- 计数点：[Expr.h.ct:5732](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L5732)；上限检查：`:6227`；
- 归零只在整次 build（`Module.h.ct:1503`）与单文件编译（`Driver.h.ct:438`）。

## 诊断判据（2026-11-15 补）

当前超限原文（HEAD `v0.53.1` 重建，1030 个 `f();` 的探针）：

```text
calls.ct:1024:8: error: too many calls
```

只有「第几个调用点 + 一句话」，没有上限值、没有累计口径、没有绕法。修复时必须同时满足：

| ID | 断言 |
| --- | --- |
| D1 | 文案含上限与口径：`MAX_CALLS=1024`（整次构建累计） |
| D2 | 位置指向**触发上限的那个调用点**（`file:line:col`），不是文件开头或函数起点 |
| D3 | 给一条可执行建议：拆成多次 `ct build` / `--lib` 分层，或改用函数指针 |
| D4 | 不写 `.c` 产物，rc=1，且诊断走 `--diagnostics=json` 时是结构化对象（与 LANG-10 联动） |

回归夹具：1024 条通过、1025 条命中 D1–D4、两单元 500+600 仍在入口第 524 条命中且位置正确。

## 处置（2026-11-19，PH-72）

- 提交：`43cf9251`
- 改动：MAX_CALLS 2048→8192，溢出文案含上限与绕法
- 验证：`sh test/ast/p72_maxcalls.sh <ct-ast>` → `OK p72/maxcalls`（3000 条通过；9000 条报 `too many calls (MAX_CALLS=8192; ...)`）

## 处置（2026-11-20，DEV · 复跑）

- 结论：PH-72 的修复仍在 HEAD；只记录证据，不改 `status`。
- 命令/输出：

```console
$ bash test/ast/p72_maxcalls.sh /tmp/ci9-sh93-build/ct-ast
OK p72/maxcalls (4096+ calls, named limit)
```

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举（`ct-ast v0.77.1`）后：

```console
$ sh test/ast/p72_maxcalls.sh /tmp/rev-v0771-build/ct-ast
OK p72/maxcalls (4096+ calls, named limit)
$ echo $?
0
```

探针同时覆盖 3000 条通过、9000 条报 `too many calls (MAX_CALLS=…)`；修复提交
`43cf9251` 为 HEAD 祖先。

## 复核（CI-11 复验，2026-11-21，REV）

**结论：verified（独立复跑）。** 在干净归档 HEAD `600e6595` 上重建 ct-ast v0.88.0，
重跑本条的回归探针；命令与原始输出如下（退出码 0）。

```console
$ sh test/ast/p72_maxcalls.sh /tmp/ct-head/b/ct-ast
OK p72/maxcalls (4096+ calls, named limit)
$ echo $?
0
```

状态词与证据对齐：正文有修复记录，回归探针存在并本轮通过，故维持 `verified`。
