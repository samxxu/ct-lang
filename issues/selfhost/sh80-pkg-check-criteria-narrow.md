# SH-80 · 包发布前的清单校验：`ct pkg check` 判据窄于已声明的清单语义

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct pkg check` / 包清单读取 / 发布前门禁） |
| 类型 | 能力缺口（包发布前的清单校验未兑现已声明语义） |
| 严重度 | Medium |
| 状态 | 不受理（非问题，2026-11-16 本仓评估） |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [提案 §7 字段表](../../docs/proposals/ct-pkg-shared-store.md)、[§9 判据范围](../../docs/proposals/ct-pkg-shared-store.md)、[§7 版本与 tag 一致性](../../docs/proposals/ct-pkg-shared-store.md) |

## CT 承诺了什么

包发布链路的入口是包清单，清单字段语义由提案 §7 定义：

- §7 定义 `dep` 形如 `<publisher>/<name>@<range>`，`requires` 是编译器版本约束；
  `licence` 标为**非必填**，并写明「约定，工具不解析」。
- §7 规定 `version` 与引用 tag 不一致时，由 `ct get` / `ct verify` 报错。
- §9 明确 `ct pkg check` 的实现范围是 **PK-1/2/5/8**。

## 实测差距

`ct pkg check` 对一份清单只输出 `ok: 4 criteria`，实际只检查 `name` / `version` / `publisher` / `ns-root`
四项**是否存在**：

1. 有 `licence` 的清单删掉该字段后仍是 `ok: 4 criteria`——§7 把 `licence` 标为非必填且工具不解析，
   这是已接受的设计口径，**不算缺口**；
2. `dep = pkg-b` 短名照过——§7 已声明 `dep` 必须是完整名，这一条未兑现；
3. `requires = ct >= 999.0.0` 照过——§7 声明了该字段，但没有可满足性检查；
4. `version` 与最近 tag 不一致不查——§7 把一致性判给 `ct get` / `ct verify`，但发布前路径同样没有拦住。

## 最小复现

```console
$ mkdir -p /tmp/sh80/src
$ printf 'name = pkg-a\nversion = 0.2.0\npublisher = pub-a\nns-root = src\nlicence = MIT\n' > /tmp/sh80/ct.pkg
$ ct pkg check /tmp/sh80
ok: 4 criteria

$ sed -i '' '/^licence/d' /tmp/sh80/ct.pkg
$ ct pkg check /tmp/sh80
ok: 4 criteria

$ printf 'dep = pkg-b\n' >> /tmp/sh80/ct.pkg
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

## 本仓评估（2026-11-16）

- **受理：否（非问题）**
- **定性：非问题**——判据边界已由提案明确划出，不是实现与承诺不一致。
- **依据：** 提案 §9（[ct-pkg-shared-store.md](../../docs/proposals/ct-pkg-shared-store.md)）明确：
  「本仓只承诺 `ct pkg check R` 的实现范围：PK-1/2/5/8；其余判据（命名空间一致性、tag 一致、
  依赖全名、离线解析等）由发布侧用自身门禁举证」。§7 字段表把 `licence` 标为**非必填**，
  并写明「约定，工具不解析」。
- **结论：** `dep` 全名、`requires` 可满足性、`version`/tag 一致性都不在 CT 已声明的判据内，
  外部「检查过窄」的定性不成立。若项目要扩大判据，属**需求变更**：先改 §9 与 SP 判据，
  再实现，不能当缺陷直接修。
