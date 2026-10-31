# TEST-12 · `check-warnings.sh` 未扫描 `test/patterns`（及 archive / acceptance）

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Low |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [selfhost/check-warnings.sh:10-19](../../selfhost/check-warnings.sh#L10-L19)、[:96-199](../../selfhost/check-warnings.sh#L96-L199)、[selfhost/check-ast.sh:257-283](../../selfhost/check-ast.sh#L257-L283) |
| 状态 | 待修 |

## 现象

`check-warnings.sh` 头注释列出的扫描面是：

```text
bootstrap 产物 → test/ast/*/prog.ct → test/cases + examples → test/modules → bindings/mock-hal
```

循环实现与注释一致（[:96](../../selfhost/check-warnings.sh#L96)、
[:101](../../selfhost/check-warnings.sh#L101)、[:116](../../selfhost/check-warnings.sh#L116)、
[:154](../../selfhost/check-warnings.sh#L154)、[:192](../../selfhost/check-warnings.sh#L192)），
**不含** `test/patterns/**`、`test/archive/**`、`test/acceptance/**`。

## 证据

```bash
$ grep -n "patterns\|archive\|acceptance" selfhost/check-warnings.sh
# 无匹配
```

`test/patterns` 的 6 个模式（batch 35）仍被 [check-ast.sh:257-283](../../selfhost/check-ast.sh#L257-L283)
以 `-Wall -Wextra -std=c99` 构建，并对**非空的 stderr** 做失败判定，因此有间接兜底；

`archive` 与 `acceptance` 则既不进 warnings 扫描，也不保证被 `-Wall -Wextra` 构建（archive 只对
L2 做棘轮）。

## 影响

`test/patterns` 的间接兜底意味着告警仍会让 `check-ast.sh` 变红，风险较低；但扫描面与头注释的
「all generated code」口径不符，读者会误以为 patterns 也在 146 项之内。`archive` / `acceptance`
的生成物没有任何零告警保证。

## 修复建议

二选一：(a) 把 `test/patterns` 纳入 `check-warnings.sh` 的循环（与 `bindings` 同级的独立段），
并在头注释同步；(b) 若不打算覆盖 archive / acceptance，在头注释明确写出「不在扫描面」及原因
（archive 由 L2 棘轮、acceptance 为跨层探针）。

## 验证

改后 `bash selfhost/check-warnings.sh` 的计数与头注释一致；九关全绿。

## 处理（2026-10-31）

已修复：`check-warnings.sh` 扫描 `test/patterns/**`（146→152）。`archive` / `acceptance` 仍不在扫描面内：前者由 L2 ratchet，后者是跨层探针，头注释已写明。
