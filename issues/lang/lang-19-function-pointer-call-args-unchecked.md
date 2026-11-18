# LANG-19 · 函数指针调用的实参不检查

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct check --types` 调用判定） |
| 类型 | 静默错误（类型/arity 均不报） |
| 严重度 | Medium |
| 状态 | `open`（PH-69-R2 发现，待实现） |
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
