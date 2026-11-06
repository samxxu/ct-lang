# SH-57 · 写在声明之后的 `import` 被静默丢弃

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 单元扫描） |
| 严重度 | Medium |
| 锚点 | `v0.19.1`（2026-11-06） |
| 文件 | [frontend/module/Module.h.ct:239-266](../../selfhost/ct-ast/frontend/module/Module.h.ct#L239-L266)（`scan_imports`） |
| 状态 | 待修 |

## 现象

`scan_imports` 只收集**前导区**的 `import`：循环遇到第一个既不是 `#` 预处理行、也不是 `import`
的 token 就 `break`（`Module.h.ct:265`）。之后正文解析既不为后置 `import` 补登记依赖，也不报错，
于是这条 import 整条消失。

后果分两种，都不会指向 import 本身：

- 被丢掉的单元**没被用到**：连模块是否存在都不检查。模块名写错也照样构建成功；
- 被丢掉的单元**被用到**：错误出现在使用点，报文是「没有这个方法 / 没有这个类型」，
  指向的是用法而不是位置。

## 最小复现

一、完全静默（模块 `late::Thing` 根本不存在）：

```ct
/* importlate3.ct */
int helper(void) { return 0; }

import late::Thing;

int main(void)
{
    return helper();
}
```

```text
$ ct build --emit-c importlate3.ct -o out
cc -std=c99 -I out out/importlate3.c -o a.out
$ echo $?
0
```

二、错误指向使用点（`std` 现为 ct-pkg 包 `std` 0.1.0；此例的 import 写在声明之后、本就会被丢弃，
因此不需要安装即复现）：

```ct
/* importlate2.ct */
int helper(void) { return 0; }

import std::str::String;

int main(void)
{
    return "abc".len() - 3 + helper();
}
```

```text
$ ct build --emit-c importlate2.ct -o out
importlate2.ct:7:1: error: no method 'len' for type 'char *'
```

没有任何一处提示 `import` 位置不对。

## 影响

同 [SH-56](sh56-map-method-arity-unchecked.md)：输入被丢、退出码正确，读者只能靠「明明 import 了
却找不到方法」自己推断。手写代码容易踩，文档示例照抄时更难定位（示例里的 import 通常就写在第一行，
一旦被挪动就会静默失效）。

## 期望行为

二选一，倾向第一种：

- 位置错误的 `import` 直接硬错，例如 `import must appear before any declaration`；
- 或正文解析阶段也接受 `import`，与前置等价（代价是「前导区」这条规则消失，需要同步 spec §4.10）。

补回归：`ast` fixture 一条「后置 import + 不存在的模块」，断言构建失败并给出与位置相关的报文。
