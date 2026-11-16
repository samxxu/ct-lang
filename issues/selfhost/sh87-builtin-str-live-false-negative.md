# SH-87 · 按需单元漏判：只调层内小写函数时产物缺 `Str` 单元，`cc` 失败

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`frontend/module`：`Module::builtin_live_for` 的 `Str` 判据） |
| 类型 | 生成缺陷（漏判导致链接失败；不是静默错值） |
| 严重度 | **P1**（`ct` 退 0，`cc` 退 1；影响所有只调用层函数而不写类型名的程序） |
| 状态 | `open` |
| 锚点 | `v0.63.0`（`369a2606`） |
| 承诺出处 | [REQ-HW-011](../../docs/planning/hardware-readiness-requirements.md)；[battle/hw-2 判决](../../battle/hw-2/verdict.md)、[D-007](../../docs/decisions/D-007.md) |

## 现象

`Str` 单元不是模板，T2 用三条近似判据判活（`selfhost/ct-ast/frontend/module/Module.h.ct:2031`），
其中"非内置源码包含 `Str` 子串"（`Module.h.ct:2053` → `file_mentions` → `strstr`，`:211`）
认不出层内的小写导出函数名。程序只调这些函数时，产物不含 `Str.c/.h`：

```console
$ cat d.ct
#include <stdio.h>

int main(void)
{
    return str_len(str_from("hi"));
}

$ ct build --emit-c d.ct -o out ; echo $?
0
$ ls out
d.c
$ cc -Wall -Wextra -std=c99 out/d.c -o d
out/d.c:7:12: error: call to undeclared function 'str_len'; ISO C99 and later do not support implicit function declarations
1 error generated.
```

第二条漏判路径：`file_mentions` 用 `static char buf[262144]` 单次 `fread`，超过 262143 B 的源会被
截断，`Str` 出现在截断之后即漏判（`Module.h.ct:199-211`）。

同一判据还有反方向的误差：`struct Struct`、`String`、`Strlen`、注释与字符串字面量都会**误命中**，
把 `Str.c`（3089 B / 10 符号）拉进最小程序的产物。

## 期望行为

- 层函数的调用（无论是否含 `Str` 字面量）都使该单元进产物；
- 不含 `Str` 使用的程序不因 `Struct`/`String`/注释而多拉单元。

## 影响

`ct` 退出码为 0 而 `cc` 失败，违反"要么编过、要么硬错"的生成契约；在 `--freestanding` 下同一输入
会得到 `nm -u` 面不完整或直接链接失败。

## 处置计划（C 方案，见 battle/hw-2/C-proposal.md）

1. 符号解析：非内置单元的 `N_CALL` 名字经 `find_func` 落到内置单元的函数区间即置活；
2. 词边界扫描替换 `strstr`，跳过注释与字面量，分块读文件消除 262144 B 截断；
3. 保留 `Vec` 活 → `Str` 活；
4. 探针 `test/ast/p64_on_demand.sh` 增加两条夹具（P1 小写助手直调、P2 `struct Struct` 不拉 `Str`）。

## 关联

- [battle/hw-2](../../battle/hw-2/verdict.md)：J-1/J-2 均不成立，判决 `rejected`；
- [D-007](../../docs/decisions/D-007.md)：决策记录（含失效条件）；
- [PH-64 卡 §5](../../docs/design/phase64-draft.md)：T2 的证据行需在 fix 收口时追加注记。
