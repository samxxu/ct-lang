# PKG-12 · `ct migrate` 报错后仍返回 0

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct migrate` 退出码） |
| 定性 | 实现缺陷：失败路径未把退出码传递出去 |
| 严重度 | **High**（静默失败） |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 实测版本 | v0.60.0 |

## 现象

`ct migrate` 在迁移 `vendor/` 时打印清单缺字段的错误，但进程退出码仍为 0：

```console
$ ct migrate
'./vendor/fsguard/ct.pkg' is missing 'publisher'
$ echo $?
0
```

`vendor/fsguard` 实际未迁移，脚本会带着旧的 vendor 继续执行。

## 最小复现

```console
$ mkdir -p /tmp/mig12/vendor/fsguard && cd /tmp/mig12
$ printf 'name = fsguard\nversion = 0.1.0\n' > vendor/fsguard/ct.pkg
$ ct migrate
'./vendor/fsguard/ct.pkg' is missing 'publisher'
$ echo $?
0
```

## 期望行为

- 任一条目迁移失败 → `ct migrate` 返回非零；
- 文案继续逐条打印失败项，最后给出汇总（成功 N 条、失败 M 条）；
- 不得在失败时把整体结果标成成功。

## 影响

脚本与 CI 无法感知迁移失败，后续构建会继续读取未迁移的 vendor，问题被推迟到更远的位置才暴露。

## 关联

- [PKG-9](pkg-9-missing-identity-fields-silent-v1-lock.md)：同一类「清单缺字段却继续走」的静默路径。
- [PKG-6](pkg-6-install-does-not-validate-imports.md)：同为退出码不反映实际失败。
