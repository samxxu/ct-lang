# LANG-20 · 内建容器方法实参类型不检查

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct check --types` 容器方法） |
| 类型 | 静默错误 |
| 严重度 | Medium |
| 状态 | `open`（PH-69-R4 发现，待实现） |
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
