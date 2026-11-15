# SH-81 · 无索引解析器时，限定名被当成 URL 去 clone

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct get` 限定名解析） |
| 类型 | 诊断缺陷（承诺的引用形态没有解析路径） |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [提案 §7 引用方式](../../docs/proposals/ct-pkg-shared-store.md) |

## CT 承诺了什么

§7 写明：本仓定义 `ct get <publisher>/<name>@<range>` 的引用方式，裸名仅在索引中唯一时可用。
限定名是**首选引用形态**，解析失败时应说明解析链缺什么。

## 实测差距

没有配置索引解析器时，`ct get` 不报「无法解析」，而是把 `publisher/name` 拼成
`https://<publisher>/<name>` 去 clone：

```console
$ ct get ct/http@^0.2.0
ctc: git clone of 'https://ct/http' failed
```

同一目标改用裸名则成功：

```console
$ ct get http@^0.2.0
vendored 1 package(s)
```

## 最小复现

```console
$ mkdir -p /tmp/sh81 && cd /tmp/sh81
$ ct get ct/http@^0.2.0
ctc: git clone of 'https://ct/http' failed
$ echo $?
1
```

## 期望行为

- 未配置索引解析器时，限定名直接失败，文案写明「无索引解析器，无法解析 `ct/http`」；
- 不发起 clone，不把 `ct/http` 当主机名；
- 给出下一步（配置索引，或改用裸名并说明歧义风险）。

## 影响

报错指向一个不存在的主机名，排查方向被误导为网络或权限问题；实际原因是限定名的解析链缺失。

## 关联

- [SH-80](sh80-pkg-check-criteria-narrow.md)：同属清单语义在工具侧没有完整兑现。
