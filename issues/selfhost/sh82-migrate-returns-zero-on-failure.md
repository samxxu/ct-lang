# SH-82 · 包发布前的迁移：`ct migrate` 报错后仍返回 0

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct migrate` / vendor 迁移 / 发布前准备） |
| 类型 | 能力缺口（迁移结果不可被调用方判断） |
| 严重度 | **High**（静默失败） |
| 状态 | 受理（P0，v0.61.x patch） |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [需求 SP-029](../../docs/planning/ct-pkg-shared-store-requirements.md)、[提案 §10 S3 验收](../../docs/proposals/ct-pkg-shared-store.md) |

## CT 承诺了什么

SP-029 承诺：`ct migrate` 把 `vendor/` 迁入 store 后，删除 `vendor/` 仍可构建
（`ct migrate && mv vendor /tmp/v && ct build` RC=0）。提案 §10 的 S3 验收同样以「迁移后无需 vendor」
为出口。要兑现这条，调用方必须能先知道迁移是否成功；退出码没有单独的承诺条目，
但它是最基本的可判断信号。

## 实测差距

迁移 `vendor/` 时打印清单校验错误，进程退出码仍为 0：

```console
$ ct migrate
ctc: './vendor/pkg-a/ct.pkg' is invalid
$ echo $?
0
```

`vendor/pkg-a` 实际未迁移，脚本会带着旧目录继续执行；lock 也没有完成对应的 store 化。

## 最小复现

```console
$ mkdir -p /tmp/sh82/vendor/pkg-a && cd /tmp/sh82
$ printf 'name = pkg-a\nversion = 0.1.0\n' > vendor/pkg-a/ct.pkg
$ ct migrate
ctc: './vendor/pkg-a/ct.pkg' is invalid
$ echo $?
0
```

## 期望行为

- 任一条目迁移失败 → `ct migrate` 返回非零；
- 逐条打印失败项，最后给出汇总（成功 N 条、失败 M 条）；
- 不得在失败时把整体结果标成成功。

## 影响

脚本与自动化无法感知迁移失败，后续构建继续读取未迁移的旧目录，lock 也没有完成 store 化，
问题被推迟到更远的位置才暴露。

## 关联

- [SH-80](sh80-pkg-check-criteria-narrow.md)：同类「发现问题但门禁不阻断」。
- [SH-84](sh84-verify-strict-no-dev-override-path.md)：严格校验的入口缺失。

## 本仓评估（2026-11-16）

- **受理：是**
- **定性：实现缺陷**——失败路径没有把退出码传播出去。
- **依据：** SP-029（[需求](../../docs/planning/ct-pkg-shared-store-requirements.md)）承诺
  「`ct migrate` 后删除 `vendor/` 仍可构建」；退出码没有单独条目（无对应承诺），
  但 rc=0 使调用方无法验证承诺是否达成。按 AGENTS §6.8 的「静默」口径按 bug 处理。
- **优先级 / 落点：** P0；`v0.61.x` patch。失败即非零，并输出成功/失败汇总。
