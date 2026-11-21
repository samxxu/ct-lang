# LANG-20 · 内建容器方法实参类型不检查

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct check --types` 容器方法） |
| 类型 | 静默错误 |
| 严重度 | Medium |
| 状态 | rejected |
| 处置证据 | **rejected**（2026-11-22，REQ/REV 改判：原报告例子是合法调用；真实错配 `Vec<int>.push("x")` 已报 `argument 1: expected 'int', got 'char *'`；`test/ast/p69_containers.sh` OK） |
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
（2026-11-22 已由 REQ/REV 联合席位改判 `rejected`，见文末处置段；本段保留为当时的复核记录。）

```console
$ sh test/ast/p69_containers.sh /tmp/rev-v0771-build/ct-ast
OK p69/containers (builtin container args)
$ echo $?
0
```

原报例子 `g: Vec<Vec<int>>`、`row: Vec<int>`、`g.push(row)` 是合法调用；真正的错配
`Vec<int> v; v.push("x")` 当前报 `argument 1: expected 'int', got 'char *'`。5.4 把
`rejected` 分给 REQ/USER，故本轮只记录复核结论，请 REQ 改判。

## 处置（REV/REQ，2026-11-22）

**结论：`rejected`（误报）。** 作为 REV/REQ 联合席位，接受 2026-11-20 REV 复核意见，按 5.4
由 REQ 侧改判。在干净归档 HEAD（`38cd4ae4`）重建 ct-ast v0.88.2 复跑：

```console
$ sh test/ast/p69_containers.sh /tmp/ct-head-rev/.temp/b/ct-ast
OK p69/containers (builtin container args)
$ echo $?
0
$ printf 'int main(void) { Vec<int> v = {1, 2}; v.push("x"); return 0; }' > bad.ct
$ ct-ast check --types bad.ct
bad.ct:1:46: error: argument 1: expected 'int', got 'char *'
$ echo $?
1
```

**判定依据**：

- 原报告 `g: Vec<Vec<int>>; Vec<int> row; g.push(row);` 的元素类型正是 `Vec<int>`，属合法调用，
  不是「实参类型不检查」的证据；
- 内建容器经 `struct Vec_int` 实例走 `chk_mcall_args` 的 `impl` 绑定路径，`T` 已按接收者实例替换；
  真实错配（`push("x")`）在 `ct check --types` 下硬错、退出 1；
- PH-69-R4 的探针 `p69_containers.sh` 就是这条既有行为的回归断言，HEAD 绿。

无需新实现；本条关闭。若将来发现其他容器方法（`set`/`put`/`insert`）有真实的 T 未替换路径，
按新证据另立条目，不复活本条。
