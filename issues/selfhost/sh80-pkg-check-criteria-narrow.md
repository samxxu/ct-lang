# SH-80 · `ct pkg check` 的判据窄于 CT 已声明的清单语义

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct pkg check` / 清单读取） |
| 类型 | 能力缺口（已声明的语义未在检查中兑现） |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [提案 §7 字段表](../../docs/proposals/ct-pkg-shared-store.md)、[§9 判据范围](../../docs/proposals/ct-pkg-shared-store.md)、[§7 版本与 tag 一致性](../../docs/proposals/ct-pkg-shared-store.md) |

## CT 承诺了什么

- §7 定义 `dep` 形如 `<publisher>/<name>@<range>`，`requires` 是编译器版本约束；
  `licence` 是 SPDX 约定，**工具不解析**。
- §7 规定 `version` 与引用 tag 不一致时，由 `ct get` / `ct verify` 报错。
- §9 明确 `ct pkg check` 的实现范围是 **PK-1/2/5/8**。

## 实测差距

`ct pkg check` 对一份清单只输出 `ok: 4 criteria`，实际只检查 `name` / `version` / `publisher` / `ns-root`
四项**是否存在**：

1. 有 `licence` 的清单删掉该字段后仍是 `ok: 4 criteria`——按 §7 这不算 CT 的判据，属承诺边界内；
2. `dep = http` 短名照过——§7 已声明 `dep` 必须是完整名，这一条未兑现；
3. `requires = ct >= 999.0.0` 照过——§7 声明了该字段，但没有可满足性检查；
4. `version` 与最近 tag 不一致不查——§7 把一致性判给 `ct get` / `ct verify`，但发布前路径同样没有拦住。

## 最小复现

```console
$ mkdir -p /tmp/sh80/src
$ printf 'name = demo\nversion = 0.2.0\npublisher = ct\nns-root = src\nlicence = MIT\n' > /tmp/sh80/ct.pkg
$ ct pkg check /tmp/sh80
ok: 4 criteria

$ sed -i '' '/^licence/d' /tmp/sh80/ct.pkg
$ ct pkg check /tmp/sh80
ok: 4 criteria

$ printf 'dep = http\n' >> /tmp/sh80/ct.pkg
$ ct pkg check /tmp/sh80
ok: 4 criteria
```

## 期望行为

- `dep` 不是完整名 → 非零，并给出 `<publisher>/<name>` 的正确形态；
- `requires` 不可能满足 → 非零，打印当前 CT 版本与要求；
- `version` 与最近 tag 不一致 → 至少 warning，并打印两边值；
- 输出列出实际执行的判据，而不是固定 `4 criteria`。

## 影响

清单里已声明的依赖形态与版本一致性无法在发布前被机器拦住；`ok: 4 criteria` 给出的覆盖面
小于 CT 自己写下的清单语义。

## 关联

- [SH-85](sh85-pkg-check-scans-docs.md)：同一命令的扫描范围。
- [SH-82](sh82-migrate-returns-zero-on-failure.md)：同类「检查发现问题但调用方拿不到失败」。
