# DOC-11 · language-spec 仍称 ct-ast 与 L2「行为等价」，实际已有两处分叉

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **High** |
| 锚点 | commit `4ef8b68`（2026-10-21） |
| 文件 | [docs/language-spec.md:5-7](../../docs/language-spec.md#L5-L7)、[:495-496](../../docs/language-spec.md#L495-L496) |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象

规范状态段声明：

> 本文描述 ct 语言的核心语法——L0 与 CT 线（L2；v0.10.0 起安装入口由**行为等价的** ct-ast 提供）共同接受与产出的部分。

## 证据

差分实测（`/tmp/rev21/{l2,ct-ast}`，同一输入）：

| 输入 | L2 | ct-ast |
| --- | --- | --- |
| 块式 `namespace A { … }` | `exit=0` | `exit=1`，`a namespace is file-scoped …` |
| 跨命名空间裸调用（`test/modules/ns_bare_call` 同形） | `exit=0` | `exit=1`，`lives in another namespace and needs a qualified call` |
| `switch` + `do-while` | `exit=0` | `exit=1`，`unexpected token` |

前两条由提交 `45b68e7`、`4ef8b68` 有意引入；第三条是 ct-ast 从未支持 C passthrough。

此外规范自身已在 §接口限制处（中文 443 行 / 英文 1004 行）写明「ct-ast 已放宽上述限制，L0 / L2 不变」，即文档内部也已承认分叉。

## 影响

「行为等价」是 Phase 9/10 的验收口径（D34），把它写进规范状态段会让读者以为两者可互换；实际安装入口是 ct-ast，L2 只是回归 oracle。

## 修复建议

状态段改为：

- ct-ast 是安装入口；L2 是冻结的回归 oracle；
- 列一张「已知分叉」小表（块式 namespace、跨命名空间裸调用、`switch`/`do-while` 等 C 透传），并注明方向（哪边更严）。

## 验证

状态段中英文均不再出现「行为等价 / behaviourally equivalent」；分叉表与差分实验一致。
