# PKG-11 · 无索引解析器时，限定名被当成 URL 去 clone

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` 限定名解析） |
| 定性 | 诊断缺陷：解析失败被降级成网络错误，指向不存在的地址 |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 实测版本 | v0.60.0 |

## 现象

在没有配置索引解析器时，`ct get` 对限定名不报「无法解析」，而是把 `publisher/name` 拼成
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
$ mkdir -p /tmp/get11 && cd /tmp/get11
$ ct get ct/http@^0.2.0
ctc: git clone of 'https://ct/http' failed
$ echo $?
1
```

## 期望行为

- 未配置索引解析器时，限定名直接失败，文案明确写「无索引解析器，无法解析 `ct/http`」；
- 不发起 clone，不把 `ct/http` 当主机名；
- 文案给出可操作的下一步（配置索引，或改用裸名并说明歧义风险）。

## 影响

报错指向一个不存在的主机名，排查方向被误导为网络或权限问题；实际原因是解析链缺失。

## 关联

- [PKG-5](pkg-5-cache-key-bare-name.md)：`ct get` 的发布方与缓存键处理。
