# TEST-11 · compile 与 build 两模式没有同一特性的镜像用例

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [test/ast](../../test/ast)（56 个探针，仅 compile）、[test/modules](../../test/modules)（67 个目录，仅 build）、[selfhost/check-ast.sh](../../selfhost/check-ast.sh) |
| 状态 | 待修 |

## 现象

ct-ast 有两条独立的发射路径（`compile` 的 `emit_program` 与 `build` 的 `emit_unit` / `write_header`），
但测试语料按模式分裂：

- `test/ast/**` 只走 **compile**（`prog.ct` 单文件，D34 行为判定）；
- `test/modules/**` 只走 **build**（多单元、`import`、`pub`、`.h.ct`，`cmp expected.out`）；
- 两模式共用的用例只有 batch 30 的 `.h.ct` 规则（`check-ast.sh` 的 split 段断言产物集合）。

因此 §4.12–4.38 的 27 个特性（`switch` / `enum` / `union` / `goto` / 位域 / 匿名成员 / 复合字面量 /
变参 / C11 / `__attribute__` / 后缀等）**没有任何一节在 build 模式下被执行**，反之 build 侧的
`pub` / `extern` / `.h.ct` 也没有在 compile 模式下镜像。

## 证据

```bash
$ ls test/ast | wc -l          # 56 + errors
57
$ ls test/modules | wc -l
67
$ grep -n "build .*test/ast\|compile .*test/modules" selfhost/check-ast.sh
# 无匹配
```

## 影响

两条发射路径已经在历史上分叉过（SH-13 的 `pub` 全局被丢弃、12.1 的 map wrapper 在 build 模式
从未发射，都是只在 build 模式暴露的问题）。没有镜像用例时，同一构造在另一模式下的缺陷只能靠
用户偶遇；而 compile 与 build 的产物命名 / `#line` / 头文件拆分逻辑并不共享。

## 修复建议

对 27 个特性中的高风险子集（`switch`、`enum`、`union`、位域、匿名成员、`static` 局部、复合字面量、
`__attribute__`）各增加一个最小 build 用例（单单元 `main.h.ct` + 消费单元，或单单元 `.ct`），
断言「编译 + 运行 + 产物集合」；同理，至少一个 `pub` / `extern` 用例在 compile 模式下跑一遍。

## 验证

新增用例在两种模式下都非零失败可区分（故意破坏其中一条路径应只让对应用例红）；九关全绿。

## 处理（2026-10-31）

已修复：8 个 compile 夹具（switch / enum / union / 位域 / 匿名成员 / static 局部 / 复合字面量 / `__attribute__`）经 `build` 单单元镜像运行。
