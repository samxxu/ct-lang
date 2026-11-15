# SH-85 · `ct pkg check` 扫描工程内所有文本文件，文档示例中的绝对 `-I` 会误判

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct pkg check` 扫描范围） |
| 类型 | 能力缺口（检查范围超出 CT 已声明的判据） |
| 严重度 | Medium |
| 状态 | open |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [提案 §9 判据范围](../../docs/proposals/ct-pkg-shared-store.md)、[需求 SP-024](../../docs/planning/ct-pkg-shared-store-requirements.md) |

## CT 承诺了什么

- §9：`ct pkg check` 只实现 PK-1/2/5/8，其余判据不在 CT 的实现范围。
- SP-024 把「不得出现指向自身绝对路径的 `-I`」列为工程侧自查项，不是 CT 全文件扫描的承诺。

CT 没有承诺扫描工程内全部文本文件。

## 实测差距

`README.md` 或其它文档里出现示例命令 `-I /绝对路径`，`ct pkg check` 会让整个工程判红：

```console
$ ct pkg check .
ctc: 'README.md' contains an absolute -I
$ echo $?
1
```

判据本意是拦截清单或构建脚本中的绝对路径，但扫描范围覆盖了所有文本文件。

## 最小复现

```console
$ mkdir -p /tmp/sh85/src && cd /tmp/sh85
$ printf 'name = demo\nversion = 0.2.0\npublisher = ct\nns-root = src\n' > ct.pkg
$ printf '示例：ct build -I /opt/ct/include\n' > README.md
$ ct pkg check .
ctc: 'README.md' contains an absolute -I
$ echo $?
1
```

## 期望行为

- 扫描范围限定为构建相关文件：`ct.pkg`、`ct.lock`、`*.ct`、`*.h.ct`、构建脚本；
- 或扫描时跳过 Markdown 围栏代码块与文档目录；
- 若保留全文件扫描，诊断必须说明「文档命中」并允许显式豁免，而不是直接判整工程红。

## 影响

文档里的安装/构建示例与检查互相冲突；工程要么删掉示例，要么无法通过检查。

## 关联

- [SH-80](sh80-pkg-check-criteria-narrow.md)：同一命令的判据覆盖面与作用域。
