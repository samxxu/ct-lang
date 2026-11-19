# LANG-20 · 内建容器方法实参类型不检查

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct check --types` 容器方法） |
| 类型 | 静默错误 |
| 严重度 | Medium |
| 状态 | `open`（复测为误报，待 REV 改判） |
| 承诺出处 | [PH-69 卡](../../docs/design/phase69.md) R4 |

## 现象

```c
int main(void)
{
    Vec<Vec<int>> g = {};
    Vec<int> row = {1, 2};
    g.push(row);          /* expected: argument 1 wants Vec<int>, got Vec<Vec<int>> */
    return 0;
}
```

`ct check --types` 退出 0，无诊断。

## 原因

内建容器没有 `struct` impl 块，`chk_mcall_args` 只处理 `struct ` 基类型；
容器方法的形参 `T` 未按接收者实例（`Vec<Vec<int>>`）替换后比较。

## 修复方向

在容器方法分支用 `inst_subst_type(ibase, formal)` 解析 `T`，再走
`chk_assignable(diag=6)`；先覆盖 `push/set/put`。

## 复测（2026-11-19，PH-69-R4）

原报告的例子是**合法**调用：`g: Vec<Vec<int>>`、`row: Vec<int>`，`g.push(row)`
的元素类型正是 `Vec<int>`。真正的错配如下，当前编译器已正确报错：

```console
$ cat bad.ct
int main(void) { Vec<int> v = {1, 2}; v.push("x"); return 0; }
$ ct check --types bad.ct
bad.ct:4:12: error: argument 1: expected 'int', got 'char *'
```

内建容器经 `struct Vec_int` 实例走的是 `chk_mcall_args` 的 `impl` 绑定路径，
`T` 被替换后比较。因此本条**不成立**，建议 REV 改 `rejected`（或 `wontfix`），
不需要新实现；PH-69-R4 以探针 `p69_containers.sh` 验收既有行为。

## 处置（2026-11-20，DEV · 复跑）

- 结论：本条原判为误报（PH-69-R4 已覆盖既有行为）；本轮复跑确认探针绿，
  仍需 REV 改判 `rejected`/`wontfix`。只记录证据，不改 `status`。
- 命令/输出：

```console
$ bash test/ast/p69_containers.sh /tmp/ci9-sh93-build/ct-ast
OK p69/containers (builtin container args)
```

## 复核（2026-11-20，REV）

**结论：误报成立；`rejected` 属 REQ/USER，REV 不代写，保持 `open`。**

```console
$ sh test/ast/p69_containers.sh /tmp/rev-v0771-build/ct-ast
OK p69/containers (builtin container args)
$ echo $?
0
```

原报例子 `g: Vec<Vec<int>>`、`row: Vec<int>`、`g.push(row)` 是合法调用；真正的错配
`Vec<int> v; v.push("x")` 当前报 `argument 1: expected 'int', got 'char *'`。5.4 把
`rejected` 分给 REQ/USER，故本轮只记录复核结论，请 REQ 改判。
