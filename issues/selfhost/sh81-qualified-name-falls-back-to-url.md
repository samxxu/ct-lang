# SH-81 · 包发布的限定名解析：无索引解析器时被当成 URL 去 clone

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`ct get` 包发布引用 / 限定名解析） |
| 类型 | 诊断缺陷（承诺的发布引用形态没有解析路径） |
| 严重度 | Medium |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-22，REV：修复 `7b332432`（v0.61.1）；HEAD `38cd4ae4` 重建 ct-ast v0.88.2 复跑 `ct get pub-a/pkg-a@^0.2.0` → `no index resolver for 'pub-a/pkg-a'`，不再拼 URL，rc=1） |
| 锚点 | v0.60.0（`14a99b27`） |
| 承诺出处 | [提案 §7 引用方式](../../docs/proposals/ct-pkg-shared-store.md) |

## CT 承诺了什么

§7 写明：本仓定义 `ct get <publisher>/<name>@<range>` 的包发布引用方式，裸名仅在索引中唯一时可用。
限定名是**发布引用的首选形态**，解析失败时应说明解析链缺什么。

## 实测差距

没有配置索引解析器时，`ct get` 不报「无法解析」，而是把 `publisher/name` 拼成
`https://<publisher>/<name>` 去 clone。以下 `pub-a/pkg-a` 为占位名：

```console
$ ct get pub-a/pkg-a@^0.2.0
ctc: git clone of 'https://pub-a/pkg-a' failed
```

同一目标改用裸名则成功：

```console
$ ct get pkg-a@^0.2.0
vendored 1 package(s)
```

## 最小复现

```console
$ mkdir -p /tmp/sh81 && cd /tmp/sh81
$ ct get pub-a/pkg-a@^0.2.0
ctc: git clone of 'https://pub-a/pkg-a' failed
$ echo $?
1
```

## 期望行为

- 未配置索引解析器时，限定名直接失败，文案写明「无索引解析器，无法解析 `pub-a/pkg-a`」；
- 不发起 clone，不把 `pub-a/pkg-a` 当主机名；
- 给出下一步（配置索引，或改用裸名并说明歧义风险）。

## 影响

报错指向一个不存在的主机名，排查方向被误导为网络或权限问题；实际原因是包发布引用的解析链缺失。

## 关联

- [SH-80](sh80-pkg-check-criteria-narrow.md)：同属清单语义在工具侧没有完整兑现。

## 本仓评估（2026-11-16）

- **受理：是**
- **定性：实现缺陷**——诊断路径错误，不是需求缺口。
- **依据：** 提案 §7（[ct-pkg-shared-store.md](../../docs/proposals/ct-pkg-shared-store.md)）
  定义 `ct get <publisher>/<name>@<range>` 为发布引用方式；§8 的固定错误文案里没有
  「把限定名当 URL」这一项。无对应承诺（「无索引解析器」的错误文案尚未定义）。
- **优先级 / 落点：** P2；`v0.61.x` patch，不占 phase。无索引时应报解析链缺失，
  并补一条固定文案与夹具。

## 处置（v0.61.1）

- 未配置索引时，`ct get ct/http@^0.2.0` 直接报 `no index resolver for 'ct/http'`，不再拼 URL；
- 提交 `7b332432`。

## 处置（REV/REQ，2026-11-22）

**结论：`verified`。** 修复提交 `7b332432`（v0.61.1）为 HEAD `38cd4ae4` 的祖先。在干净归档 HEAD
重建 ct-ast v0.88.2，在空目录、隔离 `CT_HOME` 下复跑：

```console
$ CT_HOME=$PWD/cthome ct-ast get pub-a/pkg-a@^0.2.0
ctc: no index resolver for 'pub-a/pkg-a'
  'pub-a/pkg-a' is a publisher-qualified package name; the built-in
  pins cover the official packages only (ct/std).
  publisher-qualified package:
       ct get --index <file> pub-a/pkg-a
       CT_INDEX=<file> ct get pub-a/pkg-a
     the index is a local plain-text file; line format:
       name version publisher git-url tag sha256:<64 hex>
  known git URL:
       ct get https://<host>/<publisher>/<repo>
  local checkout:
       ct get ./path-to-pkg-a
$ echo $?
1
```

- 不再把 `pub-a/pkg-a` 拼成 `https://pub-a/pkg-a` 去 clone；
- 文案点名「无索引解析器」，并给出三条下一步（`--index` / `CT_INDEX` / 本地目录）；
- 退出码 1，不创建 lock/vendor。
