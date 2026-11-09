# SH-64 · 泛型体内类型参数出现在值位置仍退出 0，发射裸 `T`

| 模块 | selfhost |
| --- | --- |
| 严重度 | **P1（High）** |
| 锚点 | `v0.26.2` / `5b43fac` |
| 文件 | [Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3258-L3275) |
| 状态 | **open**（2026-11-09 `v0.26.2` 收尾复核发现） |

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
