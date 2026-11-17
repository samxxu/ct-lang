# SH-89 · libc I/O 自动补头：空程序不应带 stdio，调用时才补

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射器 / 调用检测） |
| 定性 | 需求实现：把 `printf` 等 I/O 作为内置例外，按调用补头 |
| 严重度 | Medium（输出契约/依赖面） |
| 优先级 | P1 |
| 状态 | `open`（DEV 已处置，待复核） |
| 依据 | [D-008](../../docs/decisions/D-008.md) |
| 文件 | `selfhost/ct-ast/frontend/parse/**`、`backend/emit/Emitter.h.ct`、`frontend/module/Module.h.ct`、`test/ast/**` |

## 现象

空程序生成物也带：

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
```

`printf` 不写 include 也能编译；目前是内置层头文件无条件进入产物，不是“调用才补”。

## 期望

- 空程序不带 stdio；
- 调用 `printf/fprintf/sprintf/snprintf/scanf/fscanf/sscanf/puts/putchar/fputs/fputc/fflush/perror`
  时补一次 `<stdio.h>`；
- 宽字符六函数补 `<wchar.h>`（宽字符启用时）；
- `syslog/err/fcntl/ioctl/open/execl/...` 不补 stdio；
- 用户同名函数/宏不被抢；
- `--freestanding` 不自动补，未提供 shim 时硬错。

## 验收

| # | 输入 | 期望 |
| --- | --- | --- |
| A1 | `int main(void){return 0;}` | 产物无 `#include <stdio.h>` |
| A2 | `printf("x")` | 产物含一次 `<stdio.h>` |
| A3 | `puts("x")` | 产物含一次 `<stdio.h>` |
| A4 | `scanf("%d",&x)` | 产物含一次 `<stdio.h>` |
| A5 | `syslog(...)` | 产物不含自动 `<stdio.h>`；需 shim/显式声明 |
| A6 | 用户定义 `int printf(...)` | 不自动补头，不抢用户声明 |
| A7 | `--freestanding` + `printf` | 硬错或要求 shim，不自动补头 |
| A8 | 重复调用 `printf` | 头只出现一次 |

## 范围

先做 ISO C stdio 一组；宽字符、`dprintf/asprintf`、`putc` 宏形态另列。  
不改 `.m.ct`/`.shim` 的 include 权利；不改 `--freestanding` 的无 libc 承诺。

## 处置

待实现；不占 PH-65 的 R1–R7 冻结任务。实现时先出 A1/A2 红夹具，再改发射器。

## 处置（v0.65.0，PH-66）

- 提交：R1 `663546cb`（闭集 + 直接调用记录）、R2 `d9c00a1c`（补头，每头一次）、
  R3 `f022ffc3`（compile 模式按需拼接内置层，空程序 0 系统头）、R4 `c5c357f1`
  （同名不抢 / `syslog` 不补 / `--freestanding` 硬错）、R5 `d5e0fa80`（规范 §4.67）；
- 探针：`p66/io-detect`、`p66/io-emit`、`p66/io-empty`、`p66/io-boundary`、
  `p66/docs` 五支全绿（`check-ast` 1477/0）；
- 已知边界：`vprintf` 族不补；`syslog`/`open`/`fcntl` 等集合外不补（D-008 §3）；
  `--freestanding` 不补且调用未声明时报错。
