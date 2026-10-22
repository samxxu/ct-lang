# SH-21 · 函数指针不能指向 C 库函数，只能指向 CT 自己声明的函数或 ALL_CAPS 宏

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Medium |
| 锚点 | commit `224c08f`（Batch 2 收尾，2026-10-22） |
| 文件 | [selfhost/ct-ast/frontend/parse/Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L904-L912)（`parse_primary` 的裸名兜底） |
| 状态 | 已修（2026-10-22：未声明的裸名原样发射，交给 C 编译器校验） |

## 现象

函数指针（2b.4）现在可以声明、赋值、调用、作字段与参数。但**赋值右侧只能解析到 CT 函数表**：
把 `#include` 引入的 C 库函数放进指针时报「未声明的变量」：

```ct
#include <stdlib.h>

int main(void) {
    void (*p)(int);
    p = exit;          /* C 库函数，ct 从未声明过 */
    return 0;
}
```

```
$ ct prog.ct -o prog.c
prog.ct:4:9: error: use of an undeclared variable
```

## 证据

| 赋值右侧 | 结果 |
| --- | --- |
| `p = my_handler;`（CT 里 `static` 定义的函数） | 通过 |
| `p = exit;`（`#include <stdlib.h>` 提供原型） | `use of an undeclared variable` |
| `#define EXIT exit` + `p = EXIT;` | 通过（全大写 → 原样发射） |

同一条路径对普通调用是通的：`write(2, buf, len)`、`printf(...)` 这类**调用**只要名字出现在
调用位置就能发射（`m8` 实测）。限制只出现在「把裸函数名当作值」的上下文。

## 影响

- 第三方诉求 (4) 的原话是「让对象能持有库回调而**不靠宏绕过**」。当前唯一的绕法恰好就是宏，
  所以这一半诉求仍未满足。
- 典型场景：`atexit(cleanup)` 里的 cleanup 可以；但把 `free`、`puts`、libc 的 comparator
  （`qsort` 需要一个 `int (*)(const void *, const void *)`）直接放进 struct 字段，就必须再包一层
  CT 函数或写 `#define`。

## 修复建议

1. 在「裸函数名作为值」的分支里，若 `resolve_func` 失败且该名字**不是**变量/类型，则发射原样
   标识符而不是报错（C 侧会在链接期给出真正的诊断）。这与 map wrapper 的 `rewrite_globals`
   已经采用的策略一致：「查不到的名字留给 `#include`」。
2. 为避免把拼写错误也放行，可以只在明显是「取地址/赋给函数指针」的上下文放宽；这需要表达式
   侧的期望类型，可放在后续批次。
3. 至少在 `language-spec.md` §6 写清现在的边界：函数指针的右值必须是 CT 声明过的函数，
   库函数要经 `#define` 或一层包装。

## 验证

- 上面的最小复现必须编过，`p = exit; p(0);` 生成物零告警。
- 新增正例 `test/ast/24_fnptr_libfn`，以及一条负例确保真正的拼写错误仍报错（若采纳方案 2）。
- `bash selfhost/check-all.sh` 九关全绿。
