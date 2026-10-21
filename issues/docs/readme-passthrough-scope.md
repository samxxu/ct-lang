# DOC-12 · README 的「其它任意 C 代码原样透传」对出厂编译器不成立

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `4ef8b68`（2026-10-21） |
| 文件 | [README.md:115](../../README.md#L115)（英文 [:513](../../README.md#L513)） |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象

转换表最后一行：

> | 其它任意 C 代码 | 原样透传 |

该表没有标注适用编译器；而安装入口 `ct` 自 Phase 10.7 起由 ct-ast 提供。

## 证据

实测（`/tmp/rev21`，同一输入）：

```text
$ ct-ast pass.ct -o /tmp/pass.c ; echo $?
ctc: line 4: unexpected token (at '{')
1
$ l2 pass.ct -o /tmp/pass.c ; echo $?
0
```

输入内容为 `switch` + `do-while`；ct-ast 在 `switch` 的 `{` 处报错。README 同段第 352 行也承认「未识别的 trait/struct/impl 之外的普通 C 行按原样透传」只描述 L0 的行重写行为。

## 影响

读者会认为 ct 可以当作纯 C 的超集使用；实际上 ct-ast 只接受已实现的语法子集（`switch` / `do-while` / `goto` / 位运算等会直接报错），L0/L2 才是"透传"的那一侧。

## 修复建议

二选一：

1. 给该行加限定语：「**L0 / L2**：其它任意 C 代码｜原样透传；**ct-ast**：只接受已实现子集」；
2. 在表下加一行注：明确列出 ct-ast 会拒绝的构造类型，并指向 DOC-11 的分叉表。

## 验证

README 中英文两处对该行的适用编译器表述一致；用 `switch` 例子复核不再与文档矛盾。
