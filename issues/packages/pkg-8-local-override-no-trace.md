# PKG-8 · `ct get` 遇到工程内同名目录仍静默下载，本地覆盖不留痕

| 项 | 值 |
| --- | --- |
| 模块 | packages（本地覆盖与可复现性） |
| 定性 | **诊断缺陷**（覆盖行为存在但不可观测） |
| 严重度 | Medium |
| 锚点 | 工作树 `89b1124b`（`ct v0.53.0` 二进制实测） |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)（`get_spec` / `get_one` 无本地覆盖分支）、`Module.h.ct` `resolve_import`（导入方目录静默优先） |
| 状态 | **已修**（PH-54 S2/S3：SP-015；构建 stderr 发 `note:`，`Pkg.h.ct:2896`） |

## 现象

两件事都没有提示：

1. 工程里已有 `./<name>/` 目录时，`ct get <name>` 照常下载并写 `vendor/<name>`；
2. 构建期同名单元既在导入方目录又在 `-I` 根时，导入方目录**静默胜出**。

同一份 lock 在两台机器上可能用到不同的包内容，且构建输出看不出来。

## 最小复现

```sh
mkdir -p /tmp/p8/proj/std && cd /tmp/p8/proj
printf 'name = demo\nversion = 0.1.0\n' >ct.pkg
printf 'namespace std;\n' >std/placeholder.h.ct
ct get std; echo "rc=$?"; cat ct.lock
```

实际输出：

```text
vendored 1 package(s)
rc=0
std 0.1.0 git 7091816… sha256:72918e7…
```

本地 `./std/` 对 `ct get` 完全没有影响，lock 里也没有任何“本地有同名目录”的记录。

构建期覆盖（静默）：

```sh
# main.ct 同目录 alpha/Alpha.h.ct 返回 111，-I other 里同名单元返回 222
ct build -I other main.ct -o /tmp/p8b && /tmp/p8b
# 111   （导入方目录胜出，无提示）
```

## 期望行为

- 命中本地目录时优先使用，并在 lock 记 `dir` 行、构建 stderr 输出
  `ctc: note: '<name>' resolves to the local directory (dev override): <path>`。
- `ct verify --strict` 在存在 `dir` 行时失败，供 CI 拒绝本地覆盖（[SP-015 / SP-016](../../docs/planning/ct-pkg-shared-store-requirements.md)）。

## 交叉引用

- 提案 [§6](../../docs/proposals/ct-pkg-shared-store.md)
- 需求 SP-015 / SP-016 / SP-028

## 修复排期

S3（校验与迁移）：解析顺序与留痕一起改；`--strict` 与 `ct migrate` 同批落地。
