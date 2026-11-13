# SH-64 · 泛型体内类型参数出现在值位置仍退出 0，发射裸 `T`

| 模块 | selfhost |
| --- | --- |
| 严重度 | **P1（High）** |
| 锚点 | `v0.26.2` / `5b43fac` |
| 文件 | [Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3258-L3275) |
| 状态 | **verified**（2026-11-09 评审复核，`v0.26.3` / `02999c4`：四类值位置全部硬错且有红/绿对照，守卫落在 `T_ID` 共同入口且未误伤同名全局/宏/标签；见「评审复核」） |

## 现象

泛型体内 `T` 已声明为类型参数，但 `parse_primary` 的兜底仍把全大写未知标识符当成 C 宏常量
原样发射（`N_RAW`），于是把类型参数当值使用时不会被拒绝：

```ct
int g<T>(T x) { (void)x; return T; }
int h(int v)  { return v; }
int g2<T>(T x) { return h(T); }
int g3<T>(T x) { return (int)(sizeof T * T); }
int g4<T>(T x) { return (int)(sizeof T + T); }
```

这五种写法 `ct compile` 全部**退出 0**，生成物含裸 `T`，随后 `cc` 报 `‘T’ undeclared`。
违反 [AGENTS.md](../../AGENTS.md#L120-L121)“不允许生成明知编译不过的 C 代码”的硬约束，
也违反本轮复核的验收句“不存在退出 0 发射未声明类型名的路径”。

## 证据（可复现）

评审方在 `/tmp/p262` 用自建 `ct-ast v0.26.2`（源码 `5b43fac`）实测：

```console
$ /tmp/p262/b/ct-ast probe/leak1.ct -o out/leak1.c; echo ct=$?
ct=0
$ grep -n 'return' out/leak1.c | tail -1
10:    return T;
$ cc -std=c99 out/leak1.c -o out/leak1.bin; echo cc=$?
out/leak1.c:10:12: error: ‘T’ undeclared (first use in this function)
cc=1
```

其余形态的发射结果：

| 写法 | 生成物 | ct | cc |
| --- | --- | --- | --- |
| `return T;` | `return T;` | 0 | 1 |
| `return h(T);` | `return h(T);` | 0 | 1 |
| `sizeof T * T` | `return (int)((sizeof(int) * T));` | 0 | 1 |
| `sizeof T + T` | `return (int)((sizeof(int) + T));` | 0 | 1 |

对照，说明它不是“所有未知名都放行”：小写类型参数 `g<elem>(elem x){ return elem; }` 硬错
`use of an undeclared variable`（退出 1）；非泛型 `return Zzz;` 同样是硬错（退出 1）。
非泛型 `return T;` 退出 0 属既有设计（ALL_CAPS 视为外部宏常量），但泛型体内 `T` 已有类型参数声明，
不应再走这条兜底。

## 根因

[Expr.h.ct L3258-L3275](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3258-L3275)：

```c
/* CT has no preprocessor: an ALL_CAPS name is a macro constant ... */
if (all_caps || strcmp(nm, "stderr") == 0 ...) {
    self->arena->nodes[n].kind = N_RAW;
    snprintf(self->arena->nodes[n].text, MAX_TEXT, "%s", nm);
    return n;
}
```

该分支没有先检查 `self->in_generic && strcmp(nm, self->in_generic_tparam) == 0`。

## 建议

在与 `_Generic` 同形的硬错之前先拦截：泛型体内标识符等于当前类型参数时
`fail("type parameter cannot be used as a value")`。并补负例（`return T;`）；
`sizeof T * 2` 的正例已由 128 覆盖。

## 关闭条件

上述值位置写法在解析期硬错（退出 1 且给出 `file:line:col: error:`），不得退出 0 发射 `T`；
门禁负例真实变红。当前 `tparam_residue` 能检出残留（实测 `leak1` → `T(1)`），
但只有夹具覆盖到该形态时才会触发，不能替代编译期硬错。

## 修复（`v0.26.3`，2026-11-09）

**根因**：`parse_primary` 读到 `T_ID` 后先走泛型实例 / 限定名 / 调用 / 裸函数值 / ALL_CAPS 宏兜底 /
`fnval_ok` 六条出口；`in_generic_tparam` 的判定原先只出现在 `_Generic` 分支，值位置从未问过它。

**修法**（不在任何单出口打补丁）：在 `T_ID` 分支的**共同入口**、`lex_next()` 之后立刻守卫——
当前标识符等于 `in_generic_tparam` 时 `fail("type parameter 'T' cannot be used as a value")`。
这样后续六条出口（包括 `T(0)`、`T::x`、`p = T`、`p = &T`）全部被同一守卫覆盖。
诊断走与未声明变量相同的 `file:line:col: error:` 通道。

**全路径枚举**：`docs/history/design/phase26.md` §2.7 逐条列出 11 组标识符 / 类型名解析路径及类型参数行为，
作为这条根因的收口证据。

**负例与红证**（`v0.26.2` 基线 vs `v0.26.3`）：

| 夹具 | v0.26.2 | v0.26.3 |
| --- | --- | --- |
| `generic_tparam_value_return.ct`（`return T;`） | 退出 0，发射 `return T;` | 退出 1，`6:13: error: type parameter 'T' cannot be used as a value` |
| `generic_tparam_value_arg.ct`（`return h(T);`） | 退出 0 | 退出 1，`11:15: ...` |
| `generic_tparam_value_mul.ct`（`sizeof T * T`） | 退出 0，发射 `(sizeof(int) * T)` | 退出 1，`6:30: ...` |
| `generic_tparam_value_add.ct`（`sizeof T + T`） | 退出 0，发射 `(sizeof(int) + T)` | 退出 1，`6:30: ...` |

四条负例各有一条 `p26_diag`（退出码 + 位置 + 文案）与一条 `p26_chk`（`ct check` 同文案）；
在 `v0.26.2` 基线上 `p26_diag` 会因退出 0 而红。门禁数字见 `docs/history/design/phase26.md` §6.3.4。

`verified` 留给独立评审。

## 评审复核（`v0.26.3` / `02999c4`，2026-11-09）

结论：**verified**。评审方在 `/tmp/p263/repo`（HEAD 副本）自建 `ct-ast v0.26.3`，全部结论用自跑命令核对。

**1. 四类值位置：全部退出 1，无产物**

```console
$ /tmp/p263/b/ct-ast probe/leak1.ct -o out/leak1.c; echo exit=$?
leak1.ct:1:34: error: type parameter 'T' cannot be used as a value
exit=1
$ /tmp/p263/b/ct-ast probe/leak4.ct -o out/leak4.c; echo exit=$?
leak4.ct:2:27: error: type parameter 'T' cannot be used as a value
exit=1
# leak2（`sizeof T * T`）1:51、leak3（`sizeof T + T`）1:51 同文案；四次运行后 out/*.c 均未生成
```

旧基线对照（`/tmp/p262/b/ct-ast`，`ct-ast v0.26.2`）同一批探针：

```console
leak1 exit=0  ->  10:    return T;
leak2 exit=0  ->  10:    return (int)((sizeof(int) * T));
leak3 exit=0  ->  10:    return (int)((sizeof(int) + T));
leak4 exit=0  ->  13:    return h(T);
```

`ct check` 侧四条负例同样退出 1、位置与文案一致（`6:13` / `11:15` / `6:30` / `6:30`），
与门禁 `p26_diag` / `p26_chk` 逐字一致。

**2. 守卫落点：`T_ID` 共同入口，位于六条出口之前**

[Expr.h.ct:2927](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2927) 进入 `T_ID` 分支 → `lex_next()` →
[L2934-L2953](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2934-L2953) 守卫 → 之后才是泛型实例、
限定名、调用、`ALL_CAPS` 兜底、裸函数值、`fnval_ok`。不是单出口补丁。

**3. 反例：合法的同名标识符未被误伤**

| 反例 | 结果 |
| --- | --- |
| 全局 `int T = 5;` + `f<U>` 体内 `return T;` | 退出 0，`cc` 通过，运行 `5` |
| `#define T 42` + `f<U>` 体内 `return T;` | 退出 0，产物保留宏调用，运行 `42` |
| `#define T 42` + `f<T>` 的 `sizeof T` | 退出 0，产物为 `sizeof(int)`，运行 `4` |
| `struct T` 标签 + `getv<T>(struct T *)` | 退出 0，产物保留 `struct T`，运行 `7`（SH-63 不回退） |
| 全局 `int T` / 宏 `T` + `f<U>` 的 `sizeof U` | 退出 0，运行 `5 4` / `42 4` |
| 非模板函数体内局部 `int T = 5; return T;`（夹具 129） | 退出 0，运行 `4 5` |

边界（硬错而非误发射）：模板体内 `int T = 3;` 被拒（`4:11: error: expected a variable name`）；
`f<T>` 体内把 `T` 当值（即使外层有同名宏 `#define T 42`）被守卫硬错——类型参数按设计遮蔽外层宏。
两者都退出 1，不会产出坏 C。

**4. `tparam_residue()` 假阳已消，红证仍在**

```console
$ bash rescheck.sh          # 同一函数体，取自 check-ast.sh
v0.26.2 leak1 product -> [T(1) ]      # 旧基线的真残留：红
v0.26.3 129 product   -> []           # 非模板函数的 `int T = 5;`：不再假阳
v0.26.3 126 product   -> []           # 7 处 `T` 全为 struct T 标签，被豁免
```

盲区未缩水、如实登记在 [TEST-18](../testing/test18-residue-scan-coverage.md)（`open`）：
`.h` 产物、`test/ast/errors/`、module `build` 产物、`test/cases` 与 `examples` 语料、`build` 模式夹具。
本轮文档措辞已限定为「编译模式夹具的实例体」，未声称全产物覆盖。

**5. 门禁**：`check-all.sh` 内 `830 passed`；评审方另跑 `check-ast.sh` 同为 `830`（详见
[review-phase26](../docs/history/reports/review-phase26.md) §13 的构成拆分：129 夹具 1 + 负例总扫 4 +
`p26_diag` 4 + `p26_chk` 4 = +13，自 817 起算）。
