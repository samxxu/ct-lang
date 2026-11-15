# SH-84 · 包发布的严格校验：`ct verify --strict` 没有本地开发态路径

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct verify --strict` / 包 lock / dev override） |
| 类型 | 能力缺口（不是回归；现有行为符合已写下的判据） |
| 严重度 | Medium |
| 状态 | 不受理（非问题；改动需先改 SP-016） |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [需求 SP-016](../../docs/planning/ct-pkg-shared-store-requirements.md)、[提案 §10 S3](../../docs/proposals/ct-pkg-shared-store.md) |

## CT 承诺了什么

SP-016 明确：`ct verify --strict` 在 lock 含 `dir` 行或 vendor 回退时**失败**。
提案 §10 的 S3 判据同样写 `--strict` 在 dev override 下 RC=1。

因此当前拒绝 dev override **不是缺陷，也不是回归**，而是已承诺的行为。

## 实测差距

差距在于：包发布前没有本地开发态的严格校验入口。本地开发时用 dev override 指向工作目录，
`ct verify --strict` 直接拒绝，只能在 store 化之后才验：

```console
$ ct verify --strict
ctc: --strict requires a store-backed lock
$ echo $?
1
```

## 最小复现

```console
$ mkdir -p /tmp/sh84 && cd /tmp/sh84
$ ct install            # lock 含 dir 源条目
$ ct verify --strict
ctc: --strict requires a store-backed lock
$ echo $?
1
```

## 期望行为

若要让本地开发态也能严格校验，需要先补需求条目，再实现二选一：

- `--strict` 同时校验 dev override：目录存在、清单身份字段完整、digest 与当前内容一致；
- 或新增独立开关（如 `--strict --allow-override`），对可验证部分严格、对 override 条目给 warning。

在需求未改之前，不应把当前拒绝当成 bug 修掉。

## 影响

提交前的严格校验只能推迟到 store 化之后，失去「在本地先拦住」的价值；但这是能力边界，不是错误行为。

## 关联

- [SH-83](sh83-install-printed-include-collides-with-override.md)：同属 dev override 的规则边界。

## 本仓评估（2026-11-16）

- **受理：否（非问题）**
- **定性：非问题**——当前行为与已写下的判据一致；「本地态也要严格校验」是能力不足，
  属**需求需要变更**，不是缺陷。
- **依据：** SP-016（[需求](../../docs/planning/ct-pkg-shared-store-requirements.md)）明确
  「`ct verify --strict` 在 lock 含 `dir` 行或 vendor 回退时失败」；提案 §10 S3
  （[ct-pkg-shared-store.md](../../docs/proposals/ct-pkg-shared-store.md)）同一判据。
- **若要支持：** 先改需求（新增开关或 `--strict --allow-override` 语义），再实现；
  不能按缺陷直接修。文档里可补一句「`--strict` 只验 store-backed lock」，属于文档补齐。
