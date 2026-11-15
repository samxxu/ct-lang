# LANG-14 · struct 形参收到非 struct 实参只报 warning，由 cc 兜底

| 项 | 值 |
| --- | --- |
| 模块 | lang（诊断分级） |
| 严重度 | Medium |
| 优先级 | **P2** —— 不产生错误二进制，但 CT 把错误留给 C 编译器，诊断位置与级别都不一致 |
| 状态 | **已修**（v0.53.2 工作树，回归 `struct_arg_from_charptr` / `struct_arg_wrong_struct`） |
| 锚点 | `v0.53.2`（工作树） |
| 上游 | ct-json JSON-3（仓库外记录，本仓不复制） |

## 精确触发条件

实参类型与形参**不可能在 C 里兼容**（任一侧的基类型是 struct，另一侧不是同一个 struct），
例如 `char *` 实参传给 `Str`（`struct Str`）形参。

## 最小复现

```ct
struct Str { char *p; }
static int take(struct Str s) { (void)s; return 0; }
int main(void) { return take("k"); }
```

```console
$ ct build m.ct -o /tmp/m
m.ct:3:25: warning: type mismatch: 'take' argument 1: expected 'struct Str', got 'char *'
'cc' -std=c99 -I '.ctbuild' ...
m.ct:13:17: error: passing 'char[2]' to parameter of incompatible type 'struct Str'
1 error generated.
rc=1
```

## 根因与修法

`Expr::argtype_mismatch`（19.2）把「确定的类型不一致」一律返回 1，`argtype_check` 按
[规范 §6.1](../../docs/language-spec.md) 的统一口径报 warning。修法：**至少一侧是按值 struct**
（`fdp == 0 || adp == 0`，任一侧基类型是 struct）时返回 2，`argtype_check` 升为
`error: type mismatch: '<callee>' argument <n>: expected '<T>', got '<U>'`（与静态配方
`argtype_check_static` 同一句文案）。

边界刻意收窄：`struct P *` ↔ `struct Q *` 这类**指针**不一致在 C 里带诊断可转换，仍保持
warning（既有 `atype_fn` / `atype_m` 用例即此形态）；算术类宽松规则不动。

## 影响面评估（warning → error）

- 该 warning 只在 **C 必然拒绝** 的按值 struct 形态上升级；`struct P *` ↔ `struct Q *`、
  `int *` ↔ `char *` 这类「C 允许带诊断继续」的指针不一致仍保持 warning，因此不会收紧
  现有可编译代码（首轮把指针形态也升级，被 `atype_fn` / `atype_m` 两个既有用例抓红，已收窄）。
- 下游实测：ct-json / rill-dsl / ct-sse / ct-fsguard / ct-http 的构建设置均要求
  warning-free；这类调用当前都以 cc error 收场，没有任何包依赖该 warning 得到可运行产物
  （JSON-3 原文同结论）。
- 规范同步：[§6.1](../../docs/language-spec.md) 的「默认路径只报警告」补一句 struct 例外。

## 残留（不在本条）

`char *` ↔ `Str` 的**隐式转换**（让该调用直接合法）不属本条；本条只要求「CT 自己报 error」。

## 定位

- 判定：[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct) `argtype_mismatch`；
- 分级：[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct) `argtype_check`；
- 回归：`test/ast/errors/struct_arg_from_charptr.ct`（必须 error）；反向覆盖由既有
  `test/ast/errors/` 的指针/算术不一致用例承担（仍为 warning 的路径不新增 fixture，
  避免零 warning 门禁被一条预期警告打红）。
