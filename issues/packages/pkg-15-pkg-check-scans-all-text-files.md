# PKG-15 · `ct pkg check` 扫描包内所有文本文件，文档示例中的绝对 `-I` 会误判

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct pkg check` 扫描范围） |
| 定性 | 实现缺陷：判据作用域过宽，把文档内容当构建输入 |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 实测版本 | v0.60.0 |

## 现象

包内 `README.md` 或其它文档里出现示例命令 `-I /绝对路径`，`ct pkg check` 会让整个包判红：

```console
$ ct pkg check .
ctc: 'README.md' contains an absolute -I
$ echo $?
1
```

判据本意是拦截清单或构建脚本中的绝对路径，但扫描范围覆盖了包内所有文本文件。

## 最小复现

```console
$ mkdir -p /tmp/pkg15/src && cd /tmp/pkg15
$ printf 'name = demo\nversion = 0.2.0\npublisher = ct\nns-root = src\n' > ct.pkg
$ printf '示例：ct build -I /opt/ct/include\n' > README.md
$ ct pkg check .
ctc: 'README.md' contains an absolute -I
$ echo $?
1
```

## 期望行为

- 扫描范围限定为构建相关文件：`ct.pkg`、`ct.lock`、`*.ct`、`*.h.ct`、构建脚本；
- 或在扫描时跳过 Markdown 围栏代码块与文档目录；
- 若保留全文件扫描，诊断必须说明「文档命中」并允许显式豁免，而不是直接判整包红。

## 影响

文档里的安装/构建示例与发布门禁互相冲突；包要么删掉示例，要么无法通过检查。

## 关联

- [PKG-10](pkg-10-pkg-check-criteria-too-narrow.md)：同一命令的判据覆盖面与作用域问题。
