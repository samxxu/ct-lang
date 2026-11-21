# LANG-19 · 函数指针调用的实参不检查

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct check --types` 调用判定） |
| 类型 | 静默错误（类型/arity 均不报） |
| 严重度 | Medium |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV；PH-69-R2） |
| 承诺出处 | [PH-69 卡](../../docs/design/phase69.md) R2 |

## 现象

```c
int main(void)
{
    int (*fp)(int) = 0;
    return fp("x");
}
```

`ct check --types` 退出 0，无任何诊断（期望 `argument 1: expected 'int', got 'char *'`）。

## 原因

调用判定只覆盖具名函数/方法（`chk_call_args` / `chk_mcall_args`）；callee 是
`N_VAR` 且类型为函数指针时，没有从 `int (*)(int)` 里取原型。

## 触发条件

拿到 `int (*fp)(int)` 形态即可复现；详见 PH-69-R2。

## 修复方向

在调用判定里解析函数指针类型串（`ret (*)(params)`），复用 `chk_assignable(diag=6)`；
arity 与变参（`...`）分开处理。

## 处置（2026-11-19，PH-69-R2）

- 实现：调用分支在 `find_func` 落空且变量类型含 `(*)` 时解析原型，复用
  `chk_type`/`chk_assignable(diag=6)` 与 `arity_warn`；`...` 尾接受多余实参，
  零实参/多余实参均报 arity；
- 探针：`test/ast/p69_calls.sh`（负：错类型、多余实参、零实参；正：合法调用、
  `...` 尾）；
- 残余：函数指针**字段**（`o.add(2,3)`）走的是另一条 N_CALL 转换，未覆盖，
  如需再开一条。

## 处置（2026-11-20，DEV · 复跑）

- 结论：PH-69-R2 的修复仍在 HEAD；只记录证据，不改 `status`。
- 命令/输出：

```console
$ bash test/ast/p69_calls.sh /tmp/ci9-sh93-build/ct-ast
OK p69/calls (fnptr prototype)
```

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举（`ct-ast v0.77.1`）后：

```console
$ sh test/ast/p69_calls.sh /tmp/rev-v0771-build/ct-ast
OK p69/calls (fnptr prototype)
$ echo $?
0
```

探针覆盖负例（错类型 / 多余实参 / 零实参均报 `argument 1` 或 `arity mismatch`）与
正例（合法调用、`...` 尾）；实现属 PH-69-R2，修复在 HEAD。
