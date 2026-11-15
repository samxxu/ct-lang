# PKG-14 · `ct verify --strict` 拒绝 dev override

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct verify --strict` 与本地开发态） |
| 定性 | 能力缺口：严格校验只接受 store 化后的 lock |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 实测版本 | v0.60.0 |

## 现象

本地开发时用 dev override 指向工作目录，`ct verify --strict` 直接拒绝：

```console
$ ct verify --strict
ctc: --strict requires a store-backed lock
$ echo $?
1
```

## 最小复现

```console
$ mkdir -p /tmp/ver14 && cd /tmp/ver14
$ ct install            # lock 中含 dir 源的 override 条目
$ ct verify --strict
ctc: --strict requires a store-backed lock
$ echo $?
1
```

## 期望行为

二选一，并写进 `ct verify` 的帮助与文档：

- `--strict` 同时校验 dev override 条目（校验目录存在、清单身份字段、digest 与当前内容一致）；
- 或把「仅 store 条目可严格校验」拆成独立开关，允许 `ct verify --strict --allow-override`
  验证可验证的部分，并对 override 条目给出 warning 而非整条拒绝。

## 影响

本地开发态无法使用严格校验，只能先把包 publish 到 store 才能验；校验被推迟到发布之后，
失去「提交前拦住」的价值。

## 关联

- [PKG-13](pkg-13-install-printed-include-collides-with-override.md)：同属 dev override 与 store 规则的边界。
