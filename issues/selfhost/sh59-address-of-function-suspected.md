# SH-59 · `&f`（取函数地址）疑似静默错译 —— 待补最小复现

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 表达式发射） |
| 严重度 | Info |
| 锚点 | `v0.19.1`（2026-11-06） |
| 文件 | —（尚未定位） |
| 状态 | 待复现：2026-11-06 两个探针均生成正确的 `(&f)` |

## 现象

早前会话报告过「`&f` 被静默错译」，与
[SH-56](sh56-map-method-arity-unchecked.md)（实参被丢）、
[SH-57](sh57-import-after-decl-silently-dropped.md)（import 被丢）归为同一类：编译器退出码正常，
生成物与源码语义不符。

本轮在 `v0.19.1` 上试了两个形状，**都没有复现**，生成的 C 是正确的 `(&f)`：

```ct
/* addrfn.ct */
int f(int x) { return x + 1; }

int main(void)
{
    int (*p)(int) = &f;
    return p(1) - 2;
}
```

```text
$ ct build --emit-c addrfn.ct -o out
$ grep -n 'int (\*p)' out/addrfn.c
11:    int (*p)(int) = (&f);
```

```ct
/* fnfield.ct：结构体字段持有函数指针 */
struct S { int (*fn)(int); }
int inc(int x) { return x + 1; }
int main(void) { S s; s.fn = &inc; return s.fn(1) - 2; }
```

```text
$ grep -n 's.fn =' out/fnfield.c
17:    s.fn = (&inc);
```

（`fnfield.ct` 的 `struct` 以 `}` 收尾——CT 的 struct 声明不带分号，这是有意形状。）

## 影响

未知。若当时的形状确实存在，按定义它属于「退出码 0、语义不符」，优先级不低于 SH-56。

## 期望行为

拿到最小复现后按形状定性：生成物应与源码逐表达式对应；若属于 CT 明确不支持的位置（例如
`&` 作用于右值 / 临时量），应硬错而不是发射别的东西。

## 待办

需要早前会话里的那段源码（结构体形状、`&f` 出现在哪个位置：初始化器 / 实参 / map recipe 的
CALL / 全局初始化器）。补齐后回填「最小复现」并升级严重度。
