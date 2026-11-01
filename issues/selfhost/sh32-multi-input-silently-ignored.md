# SH-32 · compile 模式接受多个位置参数，静默只编译最后一个

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast CLI） |
| 严重度 | Low |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [tool/driver/Driver.h.ct:179-188](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L179-L188) |
| 状态 | 已修（2026-10-31）：compile 模式拒绝第二个位置参数，并显式消费 `compile` 关键字；门禁断言 `compile mode refuses a second input` |

## 现象

compile 模式的参数循环对每个非选项参数都执行 `in = argv[i]`，没有任何「已经指定过输入」的检查；
循环后只判断 `if (!in)`。于是

```text
ct a.ct b.ct -o out.c
```

只编译 `b.ct`，`a.ct` 被静默丢弃，退出码 0。同类不一致：`ct a.ct build` 会把 `build` 当作输入
（分派只看 `argv[1]`），随后报 `cannot open the input file: build`，而不是提示用法。

`build` 模式对多输入是有意的（多单元），但 compile 模式没有对应语义——「静默丢掉一个文件」
与仓库「不静默」的约定不符，也容易让用户以为两个文件都编了。

## 证据

```text
$ ./ct-ast a.ct b.ct -o out.c ; echo $?
0
$ grep -c '<a.ct 独有符号>' out.c
0
```

（本轮用两份内容不同的最小单元验证：产物只含第二份的符号。）

## 建议

在覆盖 `in` 前检查：`if (in) { fprintf(stderr, "ctc: only one input is allowed in compile mode\n"); return 1; }`；
或在 usage 里明确 compile 只接受一个输入并拒绝多余项。该问题与在册的 SH-24（compile / build 两套 CLI 解析器）
同源，建议随 SH-24 的处置一并处理。
