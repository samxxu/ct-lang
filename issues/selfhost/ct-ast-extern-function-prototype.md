# SH-22 · `extern` 只接受变量：函数原型被拒，且诊断位置漂移到后续行

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Medium |
| 锚点 | commit `224c08f`（Batch 2 收尾，2026-10-22） |
| 文件 | [selfhost/ct-ast/frontend/parse/Parser.h.ct](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L292-L303)（`extern` 分支） |
| 状态 | 已修（2026-10-22：原型只声明；诊断位置回到 `extern` 行） |

## 现象

Batch 2 的 `extern` 只声明**变量**。手写一个库函数的原型（没有可 `#include` 的头文件时）被拒绝：

```ct
#include <stdio.h>

extern int lib_fn(int x);

int main(void)
{
    printf("%d\n", lib_fn(2));
    return 0;
}
```

```
$ ct prog.ct -o prog.c
prog.ct:6:1: error: extern declares a variable, not a function
```

两处问题：

1. **能力**：`extern int lib_fn(int x);` 是合法且必要的 C 声明形式；只支持 `extern int lib_flag;`
   意味着「不 include 头文件就调不了库函数」。
2. **位置**：`extern` 在第 4 行，诊断却报在 **6:1**（`printf` 那一行）。原因是
   `parse_func` 已经把整条声明连同后面的 token 消费完，`fail()` 用的是当前 lexer 位置。

`extern void *lib_alloc(int n);` 同样报在下一行（`4:1`，实际在第 3 行）。

## 影响

- 第三方诉求 (4)「支持 extern 声明」只兑现了变量那一半；函数原型仍要靠 `#include`。
- 位置错位让用户以为是下一行的语句有问题，排查成本增加；也违反项目约定的
  `file:line:col: error:` 必须指向真实出错位置。

## 修复建议

1. 在 `extern` 分支里区分「变量声明」与「函数原型」：名字后跟 `(` 且以 `;` 结束时，按原型处理
   —— 发射到 `.h`，`.c` 不发射任何东西（与 `extern` 变量同一条规则）；跟 `{` 时仍拒绝
   （`extern` 不能带函数体，现有负例 `test/ast/errors/extern_function.ct` 保留）。
2. 诊断位置改为在进入 `extern` 分支时快照 `tokline`/`tokstart`，不要用消费后的位置。

## 验证

- `extern int lib_fn(int);` + `extern void *lib_alloc(int);` 两个最小复现编过，生成物里只有声明。
- 现有负例 `extern_function.ct` 仍应以非零退出，且位置指向 `extern` 行。
- 新增正例 `test/modules/extern_decl` 扩展，`check-all.sh` 九关全绿。
