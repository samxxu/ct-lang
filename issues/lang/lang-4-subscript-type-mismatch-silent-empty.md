# LANG-4 · 数字下标落到不匹配的 `get`，静默返回空值

| 项 | 值 |
| --- | --- |
| 模块 | lang（自定义下标协议 / 类型匹配） |
| 严重度 | **High（静默错误）** |
| 优先级 | **P0** —— 唯一一条「编译通过、运行给错值且无诊断」的条，下游最痛 |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV） |
| 锚点 | `v0.53.1`（`c4727787`） |

## 精确触发条件

类型在固有 `impl` 里只声明了**参数类型与下标实参类型不一致**的 `get`（典型是 `char *get(char *)`），
同时源码里写下标。PH-52 的协议匹配只看「方法名 + 参数个数 + 非 `static`」
（[Expr.h.ct:6269-6320](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L6269-L6320)），于是 `x[0]` 被展开成
`X_get(&x, 0)`——把一个整数当指针传入。

## 最小复现

```ct
#include <stdio.h>
struct J { int n; }
impl J {
    char *get(char *k) { (void)k; return "empty"; }
}
int main(void) {
    J j = { 1 };
    printf("[%s]\n", j[0]);
    return 0;
}
```

```sh
ct-ast a4.ct -o a4.c          # rc=0
cc -std=c99 a4.c -o a4 && ./a4
```

## 实际行为

```text
[empty]
```

编译期 rc=0，**没有任何诊断**；运行期 `j[0]` 走的是 `get((char *)0)` 路径，拿到的是「缺键」的返回值。

## 期望行为

编译期硬错，并列出候选签名：

```text
error: type 'J' has no subscript matching 'get(int)': candidates are 'char *get(char *)'
```

（即 `REQ-JSACCESS-1` 的参数类型匹配；见 [requirements-pool.md](../../docs/planning/requirements-pool.md) 与
[user-index-operator.md](../../docs/proposals/user-index-operator.md) 的 D-IX-6。）

## 影响面

- ct-json：`doc[0]` 拿到的永远是「缺键」分支，错误在业务层才显形；
- rill-dsl：容器下标同源；
- 所有「同类型既要字符串键又要数字键」的容器，只能放弃 `[]` 改 `get_idx(i)`。

## 绕法

包层提供 `get_idx(int)` / `get_str(const char *)`，消费方按实参类型选函数名；`[]` 只用于字符串键。

## 修复方向

把「实参静态类型 → 候选签名」的匹配接进 `custom_index_method`，0 命中 / 歧义均硬错。属 `REQ-INDEX-1` 的 S1 切片。

## 处置（2026-11-19，PH-72）

- 提交：`d5906bd8`
- 改动：`custom_index_method` 增加下标类型判定（chk_type + chk_assignable）
- 验证：`sh test/ast/p72_subscript.sh <ct-ast>` → `OK p72/subscript`（`j[0]` 对 `char *get(char *)` 报 `argument 1: expected ...`）

## 处置（2026-11-20，DEV · 复跑）

- 结论：PH-72 的修复仍在 HEAD；只记录证据，不改 `status`。
- 命令/输出：

```console
$ bash test/ast/p72_subscript.sh /tmp/ci9-sh93-build/ct-ast
OK p72/subscript (key type)
```

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举（`ct-ast v0.77.1`）后：

```console
$ sh test/ast/p72_subscript.sh /tmp/rev-v0771-build/ct-ast
OK p72/subscript (key type)
$ echo $?
0
```

探针断言 `j[0]` 对 `char *get(char *)` 报 `argument 1: expected 'char *', got 'int'`，
`j["k"]` 与 `int get(int)` 正例通过；修复提交 `d5906bd8` 为 HEAD 祖先。

## 复核（CI-11 复验，2026-11-21，REV）

**结论：verified（独立复跑）。** 在干净归档 HEAD `600e6595` 上重建 ct-ast v0.88.0，
重跑本条的回归探针；命令与原始输出如下（退出码 0）。

```console
$ sh test/ast/p72_subscript.sh /tmp/ct-head/b/ct-ast
OK p72/subscript (key type)
$ echo $?
0
```

状态词与证据对齐：正文有修复记录，回归探针存在并本轮通过，故维持 `verified`。
