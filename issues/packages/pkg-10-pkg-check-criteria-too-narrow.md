# PKG-10 · `ct pkg check` 判据过窄，只校验四个字段是否存在

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct pkg check` 发布前门禁） |
| 定性 | 判据缺口：只做存在性检查，不校验取值语义 |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 实测版本 | v0.60.0 |

## 现象

`ct pkg check` 对一份清单只输出 `ok: 4 criteria`，实际只检查 `name` / `version` / `publisher` / `ns-root`
四项**是否存在**。以下四类问题都能通过：

1. 清单有 `licence` 字段，删掉后仍是 `ok: 4 criteria`——许可声明缺失不报。
2. `dep = http` 这类短名照过——未要求 `publisher/name` 或可解析的完整名。
3. `requires = ct >= 999.0.0` 照过——不检查版本下限是否可能满足。
4. `version` 与最近 tag 是否一致不查。

## 最小复现

```console
$ mkdir -p /tmp/pkg10/src
$ printf 'name = demo\nversion = 0.2.0\npublisher = ct\nns-root = src\nlicence = MIT\n' > /tmp/pkg10/ct.pkg
$ ct pkg check /tmp/pkg10
ok: 4 criteria

$ sed -i '' '/^licence/d' /tmp/pkg10/ct.pkg
$ ct pkg check /tmp/pkg10
ok: 4 criteria

$ printf 'dep = http\n' >> /tmp/pkg10/ct.pkg
$ ct pkg check /tmp/pkg10
ok: 4 criteria

$ printf 'requires = ct >= 999.0.0\n' >> /tmp/pkg10/ct.pkg
$ ct pkg check /tmp/pkg10
ok: 4 criteria
```

## 期望行为

`ct pkg check` 至少在以下方面给出可执行判据：

- `licence` 缺失或为空 → 非零，文案指名字段；
- `dep` 的值必须是 `publisher/name` 或能被当前解析器解析的完整名，短名 → 非零并给候选；
- `requires` 的下限必须与当前 CT 版本可满足，否则非零并打印当前版本与要求；
- 清单 `version` 与最近 tag 不一致 → 至少 warning，并打印两边值；
- 输出中列出实际执行的判据条数，而不是固定 `4 criteria`。

## 影响

许可变更、依赖声明错误、不可能满足的版本下限都无法在发布前被机器拦住；门禁给出「4 项全过」的
确定感，但覆盖面远小于发布所需。

## 关联

- [PKG-3](pkg-3-unknown-keys-silently-ignored.md)：清单字段的读取与容忍策略。
- [PKG-9](pkg-9-missing-identity-fields-silent-v1-lock.md)：同属「清单问题没有在入口被拦住」。
