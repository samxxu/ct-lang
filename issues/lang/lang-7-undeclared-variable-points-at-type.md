# LANG-7 · 静态方法解析失败时报 `use of an undeclared variable`

| 项 | 值 |
| --- | --- |
| 模块 | lang（诊断文案） |
| 严重度 | Low |
| 优先级 | **P3** —— 只误导方向，不挡功能；与 LANG-2 同一路径，建议同修 |
| 状态 | open |
| 锚点 | `v0.53.1`（`c4727787`） |

## 精确触发条件

静态调用无法解析、且接收者是一个**类型名**时（LANG-2 的主路径）。编译器把接收者当变量查，
查不到后落到通用的未声明变量兜底。

## 最小复现

同 [LANG-2](lang-2-namespaced-static-method-unresolved.md) 的 `main.ct`：

```sh
ct-ast build -I . main.ct -o prog
```

## 实际行为

```text
main.ct:4:16: error: use of an undeclared variable
```

列号 16 指向 `Box.make` 的点号——报错对象是一个**类型名**，用户会去查 import / 可见性，
而真实原因是静态方法没解析出来（namespace 前缀导致查找键不匹配）。

## 期望行为

```text
error: static method 'make' of type 'Box' cannot be resolved; namespace-qualified type names are not supported
```

（或以「类型上没有该方法」为主句，并列出该类型的静态方法候选。）

## 影响面

所有踩 LANG-2 的下游（ct-sse、nexcore）在排查时会先怀疑 import/可见性；
外部反馈口径也因此把问题描述成「静态方法不可用」而非「namespace 下的名字解析」。

## 定位

通用兜底在 [Expr.h.ct:5854](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L5854)；
静态调用识别在 [Expr.h.ct:5239](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L5239)。

## 说明

这只是 LANG-2 的次生问题，单独登记是为了「修完 LANG-2 后还要检查文案」不被漏掉；
若 LANG-2 修好后该路径不再可达，本单随之关闭。
