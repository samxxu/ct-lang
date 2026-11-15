# PKG-5 · 缓存键是裸包名，不同发布方的同名包互相串用

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` git 缓存） |
| 定性 | **Bug**（静默取到别的发布方的代码） |
| 严重度 | High |
| 锚点 | 工作树 `89b1124b`（`ct v0.53.0` 二进制实测） |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)（`fetch_git`：`%s/.cache/ct-pkg/<name>`，`git fetch` 沿用已有 origin） |
| 状态 | **open**；随 S1 一起修（[Phase 54 卡 §3](../../docs/design/phase54.md)） |

## 现象

`ct get <publisher>/<name>` 的发布方段只用来拼首次 clone 的 URL；缓存目录与已有 origin 都按**裸包名**定位。只要同名包已缓存，后续任何发布方的同名 spec 都会复用该缓存，`git clone` 不会发生，也不会校验 origin。

## 最小复现

前置：`~/.cache/ct-pkg/util` 已存在（origin 为发布方 `a` 的仓库）。

```sh
mkdir -p /tmp/p5/proj && cd /tmp/p5/proj
printf 'name = demo\nversion = 0.1.0\n' >ct.pkg
ct get b/util; echo "rc=$?"; cat ct.lock
```

实际输出：

```text
vendored 1 package(s)
rc=0
util 0.1.0 git b4b7b43… sha256:12613dbf…
```

`b` 不是原发布方，却拿到了 `a` 的代码。冷机器上同一 spec 会变成：

```text
$ ct get someorg/somepkg
ctc: git clone of 'https://someorg/somepkg' failed
```

## 期望行为

- 缓存键为 `<publisher>/<name>`，并校验缓存 origin 与 spec 一致；不一致报错，不复用。
- 落盘按 `<publisher>/<name>/<version>/`（[SP-001](../../docs/planning/ct-pkg-shared-store-requirements.md)）。

## 交叉引用

- 提案 [§1](../../docs/proposals/ct-pkg-shared-store.md)、[§12 D1](../../docs/proposals/ct-pkg-shared-store.md)
- 需求 SP-001 / SP-014
- [PKG-4](pkg-4-duplicate-package-name-silent-first.md)（依赖图内的同名静默）

## 修复排期

S1（工具最小可用）：缓存路径与 origin 校验一起改；迁移期旧裸名缓存视为不可用并重新 clone。
