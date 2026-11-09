# SH-63 · `ct_generic_subst` 会把 `struct T` 改写成 `struct int`，静默产出非法 C

| 模块 | selfhost |
| --- | --- |
| 严重度 | **P2（Medium）**（触发条件罕见，但结果同样是退出 0 的坏产物） |
| 锚点 | `v0.26.0` / `ac1c7cd`（HEAD = `main`） |
| 文件 | [Symbols.h.ct](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L343-L344)、[Symbols.h.ct](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1253-L1290) |
| 状态 | **verified**（2026-11-09 评审复核，`v0.26.1` / `d29de8f`；证据见「评审复核」） |

## 现象

[Symbols.h.ct:343-344](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L343-L344) 的注释声称：

> so `T2` and `struct T` are left alone.

实现按“前后字符不是标识符字符”做整词替换，`struct T` 中的 `T` 前面是空格、后面是字符串结尾，
因此**会被替换**。若程序里真有一个名为 `T` 的 struct，且模板同时把类型参数命名为 `T`
并在签名/函数体里用到 `struct T`，就会得到 `struct int`。

## 证据（可复现）

```c
#include <stdio.h>

struct T { int v; };

T getv<T>(struct T *p)
{
    return p->v;
}

int main(void)
{
    struct T t;
    t.v = 7;
    printf("%d\n", getv<int>(&t));
    return 0;
}
```

```console
$ ct compile /tmp/p26-structT.ct -o /tmp/p26-structT.c ; echo "ct=$?"
ct=0
$ grep -n 'struct int' /tmp/p26-structT.c
9:static struct int getv__ct1(struct int *);
17:static struct int getv__ct1(struct int * p) {
$ cc -std=c99 /tmp/p26-structT.c -o /tmp/p26-structT ; echo "cc=$?"
error: expected ‘{’ before ‘int’
cc=1
```

## 影响

- 退出 0 + 非法 C，违反 [AGENTS.md](../../AGENTS.md#L120-L121) 的发射约束；错误被推迟到 `cc`。
- 与设计 D26-6“只替换类型位精确拼写”和代码注释自相矛盾。

## 修复建议

替换前先识别复合拼写的类别（`struct ` / `union ` / `enum ` 前缀），或在 `parse_type`
阶段就记录“哪些片段是类型参数、哪些是具名 struct”，替换时只动前者；同时删掉/修正错误注释。
补一条 `struct T` + `<T>` 同名夹具，断言生成物保留 `struct T`。

## 修复（`v0.26.1`，`87b03ec`）

- `ct_generic_subst()` 新增 `generic_tag_prefix()` 前瞻：匹配 token 前若只有空白且再往前是 `struct` / `union` / `enum`，跳过替换，`struct T` 保持原样（D26-13）。
- `parse_type()` 记录 `last_bare_tag`；`Parser` 在读到 `<T>` 得知类型参数名后，把被标签解析吞掉的裸返回类型 `T` 改写回类型参数，避免残留 `static struct T pick__ct1(...)`。

证据：

```console
$ ct-ast test/ast/126_generic_struct_tag/prog.ct -o /tmp/126.c
$ grep 'getv__ct1' /tmp/126.c
static int getv__ct1(struct T *);
$ cc -std=c99 /tmp/126.c -o /tmp/126 && /tmp/126
7
```

修复前同一命令得到 `static struct int getv__ct1(struct int *);`，`cc` 报 `expected '{' before 'int'`。

## 评审复核（`v0.26.1` / `d29de8f`，2026-11-09）

结论：**verified**。

```console
$ /tmp/p261/b/ct-ast /tmp/p261/probe/structT.ct -o /tmp/p261/out/p-structT.c; echo ct=$?
ct=0
$ grep -n 'getv__ct1' /tmp/p261/out/p-structT.c
9:static int getv__ct1(struct T *);
17:static int getv__ct1(struct T * p) {
$ cc -std=c99 /tmp/p261/out/p-structT.c -o /tmp/p261/out/run-structT && /tmp/p261/out/run-structT
7
```

反证（修复前基线：用冻结 L2 重编 v0.26.0 源码）：126 夹具发射
`static struct int getv__ct1(struct int *);`（退出 0，`cc` 拒绝），与 issue 现象一致。
另外，显式写 `struct T` 的返回类型探针保持 `static struct T make__ct1(int);`，没有被
`last_bare_tag` 回填误改成 `T`。未发现残余。
