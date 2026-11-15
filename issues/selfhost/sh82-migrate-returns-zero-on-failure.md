# SH-82 · `ct migrate` 报错后仍返回 0

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct migrate` 退出码） |
| 类型 | 能力缺口（迁移结果不可被调用方判断） |
| 严重度 | **High**（静默失败） |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [需求 SP-029](../../docs/planning/ct-pkg-shared-store-requirements.md)、[提案 §10 S3 验收](../../docs/proposals/ct-pkg-shared-store.md) |

## CT 承诺了什么

SP-029 承诺：`ct migrate` 后删除 `vendor/` 仍可构建（`ct migrate && mv vendor /tmp/v && ct build` RC=0）。
提案 §10 的 S3 验收同样以「迁移后无需 vendor」为出口。要兑现这条，调用方必须能先知道迁移是否成功；
退出码没有单独的承诺条目，但它是最基本的可判断信号。

## 实测差距

迁移 `vendor/` 时打印清单缺字段错误，进程退出码仍为 0：

```console
$ ct migrate
'./vendor/fsguard/ct.pkg' is missing 'publisher'
$ echo $?
0
```

`vendor/fsguard` 实际未迁移，脚本会带着旧目录继续执行。

## 最小复现

```console
$ mkdir -p /tmp/sh82/vendor/fsguard && cd /tmp/sh82
$ printf 'name = fsguard\nversion = 0.1.0\n' > vendor/fsguard/ct.pkg
$ ct migrate
'./vendor/fsguard/ct.pkg' is missing 'publisher'
$ echo $?
0
```

## 期望行为

- 任一条目迁移失败 → `ct migrate` 返回非零；
- 逐条打印失败项，最后给出汇总（成功 N 条、失败 M 条）；
- 不得在失败时把整体结果标成成功。

## 影响

脚本与自动化无法感知迁移失败，后续构建继续读取未迁移的旧目录，问题被推迟到更远的位置才暴露。

## 关联

- [SH-80](sh80-pkg-check-criteria-narrow.md)：同类「发现问题但门禁不阻断」。
- [SH-84](sh84-verify-strict-no-dev-override-path.md)：严格校验的入口缺失。
