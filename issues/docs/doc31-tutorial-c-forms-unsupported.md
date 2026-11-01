# DOC-31 · 教程称 `switch` / `do-while` / `goto` 不受 ct-ast 支持，实际早已支持

| 项 | 值 |
| --- | --- |
| 模块 | docs（教程） |
| 严重度 | **High** |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [docs/tutorial.md:468-470](../../docs/tutorial.md#L468-L470)（中文）、[docs/tutorial.md:944-947](../../docs/tutorial.md#L944-L947)（英文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

教程 §11「会踩的坑」第 5 条写：

> **ct-ast 只接受已实现的子集**：`switch` / `do-while` / `goto` 等普通 C 会在 `{` 处报
> `unexpected token`。要写这类代码只能手工构建 L0 种子……`install.sh` 装出的 `ctc` 是 `ct` 的别名，
> 一样不支持。

这三类构造自 batch 4 / 7 起就由 ct-ast 解析并重新发射，language-spec §4.13（`switch` / `do-while`）
与 §4.16（`goto` / 标签）明确列为已支持；README 的变换表也写「`switch` / `do-while` / `goto` …
都已支持」（[README.md:141](../../README.md#L141)）。教程因此让用户放弃一个可用的编译器，属于面向用户的高危漂移。

## 证据

实测（`/tmp/ctaudit` 的四层链现场构建的 `ct-ast`）：

```ct
#include <stdio.h>
int main(void) {
    int i = 2;
    switch (i) {
    case 1: printf("one\n"); break;
    case 2: printf("two\n"); break;
    default: break;
    }
    do { i--; } while (i > 0);
    goto done;
done:
    printf("%d\n", i);
    return 0;
}
```

```text
$ ./ct-ast sw.ct -o sw.c ; echo $?
0
$ cc -Wall -Wextra -std=c99 sw.c -o sw && ./sw
two
0
```

另见 [language-spec.md:592-630](../../docs/language-spec.md#L592)（§4.13）、
[language-spec.md:698-736](../../docs/language-spec.md#L698)（§4.16）、语料 `test/ast/13_switch`、
`test/ast/17_goto` 与 `check-ast.sh` 的 batch 4 / batch 7 负例块（每类诊断都被钉死）。

## 建议

重写 §11.5（中英对称）：把「只接受已实现的子集」改为「语言子集见 language-spec §4，没有已知的未实现形式」，
并删掉「只能手工构建 L0 种子」的误导性结论。该条与 §11.7 的「struct 数组字段」条目同源，
可一并复核。
