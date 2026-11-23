# SH-61 · form 5 的 arity 校验不认变参 trait 方法

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 调用点解析） |
| 严重度 | Medium（2026-11-22 复核已可复现） |
| 锚点 | `v0.20.1`（2026-11-07） |
| 文件 | [frontend/parse/Expr.h.ct:1912-1956](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1912-L1956) |
| 状态 | verified |
| 处置证据 | **deferred**（2026-11-22，REV/REQ：前置「变参 trait」已落地（`Symbols.h.ct:248`、`MapBuild.h.ct:768`），form 5 仍用内联 `arity_check` 不读 `variadic`；HEAD `38cd4ae4` 复现 `f takes 2 argument(s), 4 given`。触发下一次 Expr/Parser 调用点批次；负责人 DEV；P2） |
| blocked-by | 无（2026-11-22 复核：变参 trait 已落地，缺陷现已可复现；见处置段） |

## 现象

静态 trait 的限定调用 `Trait::method(recv, ...)`（`parse_qual_path` 的 form 5）把 trait 方法声明的
形参个数 `nparams` 与实参个数 `got` 直接比较，没有变参豁免：`got > nparams` 时照旧报 arity。

同一轮里 form 3（`Trait::ns.method(...)`）与 form 4（`ns::method(...)`）走 `map_arity`，后者会读
trait 方法的变参标记并放行多余实参。于是**同一个 trait 方法，换个调用形式写，诊断就不一致**。

## 触发前提

> 本段是 2026-11-07 立项时的前置评估；2026-11-22 复核时这些 WIP 已落地（见文末处置段），
> 下列「HEAD 上不存在」的描述已过时，保留为历史记录。

`MethodSig` 的 `variadic` 字段、trait 方法签名里的 `...` 解析，都属于「变参 trait」这份尚未落地的
WIP：

- `selfhost/ct-ast/frontend/sym/Symbols.h.ct`：`MethodSig` 新增 `int variadic;`
- `selfhost/ct-ast/frontend/parse/Parser.h.ct`：`.m.ct` 单元的 trait 方法接受 `...`（`unit_is_map` 门）
- `selfhost/ct-ast/frontend/module/Map.h.ct`：`MapBind` 新增 `int variadic;`

HEAD 上这些都不存在：`parse_impl` 直接拒绝「a trait method cannot be variadic」，任何 trait 方法都
只能是非变参。因此 **form 5 的这条缺陷在 HEAD 不可复现**，它只在上述 WIP 落地后成为真缺陷。
（2026-11-22 复核：上述 WIP 已落地，本前提失效；缺陷现已可复现，见文末处置段。）

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

## 处置（REV/REQ，2026-11-22）

**结论：`deferred`（前置已消失，缺陷现已可复现）。** 本条原写「HEAD 不可复现，因为变参 trait WIP
未落地」；2026-11-22 复核发现该前提已不成立：`MethodSig` 有 `variadic` 字段
（`Symbols.h.ct:248`），`.m.ct` 绑定允许并要求 `...`（`MapBuild.h.ct:768`），`map_arity` 已按
`variadic` 放行（`Expr.h.ct:1798`）。form 5 仍保留内联比较（`Expr.h.ct:6597-6600`），因此缺陷复活。

**最小复现（HEAD `38cd4ae4` 重建 ct-ast v0.88.2）：**

```ct
/* var/var.m.ct */
namespace var;
pub trait Log { int f(char *s, int n, ...); }
map trait Log for type char * { f(recv, s, n, ...) -> strlen(s); }
```

```ct
/* main.ct */
import var::var;
int main(void) {
    char *s = "abc";
    return var::Log::f(s, s, 1, 2, 3);   /* form 5：receiver + 2 个命名参数 + 2 个变参尾巴 */
}
```

```console
$ ct-ast build -I . main.ct -o out
main.ct:5:12: warning: arity mismatch: 'f' takes 2 argument(s), 4 given
'cc' -std=c99 … -o out
$ echo $?
0
$ ct-ast check --types main.ct
main.ct:5:12: error: arity mismatch: 'f' takes 2 argument(s), 4 given
$ echo $?
1
```

同一 trait/绑定若走 namespace host 的 form 3/4，代码路径是 `map_arity`（`Expr.h.ct:1798` 读
`variadic` 后 `got >= want` 放行），不会报 arity；form 5 是唯一不一致的入口。原探针的
`ct build` 期望「无 arity 警告」与 `ct check` 期望「退出 0」在 HEAD 都失败。

**修法（下一次 Expr/Parser 调用点批次）**：把 `qf == 5` 的内联
`arity_check(..., traits[ti3].m[mi3].nparams)` 换成 `map_arity(id_line, id_col, trait, method, got)`，
或在 `got > nparams && variadic` 时放行；补正例（变参 form 5 不报）+ 负例（非变参 form 5 仍报）。
**触发/负责人/优先级**：下一次 Expr/Parser 调用点统一批次；负责人 DEV；P2（Medium）。
本批只复核，不改 `Expr.h.ct`（产品代码）。


## 复核（REV，2026-11-23）

form 5 在 `arity_check` 前读 `traits[ti].m[mi].variadic` 与 `nparams`；`got >= nparams` 放行，
非变参仍走 arity。探针 `test/ast/sh61_form5.sh`：变参 `var::Log::f(s,s,1,2,3)` 无 arity、
非变参 `var::Fixed::g(...)` 仍报 `arity mismatch: 'g'`；已接 `check-ast`。
