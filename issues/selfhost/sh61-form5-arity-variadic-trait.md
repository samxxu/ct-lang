# SH-61 · form 5 的 arity 校验不认变参 trait 方法

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 调用点解析） |
| 严重度 | Medium（当前 HEAD 不可复现） |
| 锚点 | `v0.20.1`（2026-11-07） |
| 文件 | [frontend/parse/Expr.h.ct:1912-1956](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1912-L1956) |
| 状态 | blocked（前置「变参 trait」WIP 未落地；2026-11-10 复核仍不可复现） |

## 现象

静态 trait 的限定调用 `Trait::method(recv, ...)`（`parse_qual_path` 的 form 5）把 trait 方法声明的
形参个数 `nparams` 与实参个数 `got` 直接比较，没有变参豁免：`got > nparams` 时照旧报 arity。

同一轮里 form 3（`Trait::ns.method(...)`）与 form 4（`ns::method(...)`）走 `map_arity`，后者会读
trait 方法的变参标记并放行多余实参。于是**同一个 trait 方法，换个调用形式写，诊断就不一致**。

## 触发前提

`MethodSig` 的 `variadic` 字段、trait 方法签名里的 `...` 解析，都属于「变参 trait」这份尚未落地的
WIP：

- `selfhost/ct-ast/frontend/sym/Symbols.h.ct`：`MethodSig` 新增 `int variadic;`
- `selfhost/ct-ast/frontend/parse/Parser.h.ct`：`.m.ct` 单元的 trait 方法接受 `...`（`unit_is_map` 门）
- `selfhost/ct-ast/frontend/module/Map.h.ct`：`MapBind` 新增 `int variadic;`

HEAD 上这些都不存在：`parse_impl` 直接拒绝「a trait method cannot be variadic」，任何 trait 方法都
只能是非变参。因此 **form 5 的这条缺陷在 HEAD 不可复现**，它只在上述 WIP 落地后成为真缺陷。

## 根因

form 5 在 `Expr.h.ct` 里内联比较，绕开了 form 3 / form 4 共用的 `map_arity`：

```c
if (mi3 < self->sym->traits[ti3].nm
    && self->arity_check(id_line, id_col, qc, got,
                         self->sym->traits[ti3].m[mi3].nparams) != 0)
    return -1;
```

而 `map_arity` 的判定是：

```c
if (self->sym->traits[ti].m[mi].variadic && got >= want) return 0;
```

同一套「形参个数 + 变参标记」判定写了两份，form 5 这份漏掉了变参分支。

## 修法

变参 trait 的 WIP 落地后：

1. form 5 复用同一套变参判定：读 `traits[ti3].m[mi3].variadic` 与 `nparams`，`got > nparams` 且方法
   变参时放行，否则照旧走 `arity_check`；
2. `map_arity` 整体落地后，把三处收敛到 `map_arity`，删掉 form 5 的内联比较。

## 探针（变参 trait WIP 落地后补）

```ct
/* 静态 trait 的变参方法，receiver 之外的实参走变参尾巴 */
a::T::log(s, "x", 1)
```

- `ct build`：不得出现 arity 警告；
- `ct check`：退出 0、无诊断。
