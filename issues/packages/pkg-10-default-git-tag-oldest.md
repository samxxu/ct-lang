# PKG-10 · `ct get <git>` 无 range 时落到最旧 tag

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` 的 git tag 选择 / 默认版本语义） |
| 定性 | **行为缺陷**：省略 range（以及 `*`）时按 MVS 取最低 tag；裸名经索引/默认 registry 与 URL 入口不一致 |
| 严重度 | **High**（默认安装旧版本，静默） |
| 优先级 | **P1**（包线 patch） |
| 状态 | **open** |
| 锚点 | 复现于 `v0.63.2`（`0e541f32`）；修复在 `v0.63.3` |
| 文件 | [Pkg.h.ct](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct)：`git_pick_tag`、`pkg_index_lookup` |

## 现象

`ct get https://github.com/ct-pkg/json` 安装 `ct/json 0.1.1`（最旧 tag），而用户期望与
`ct get json` 一样取最新版本。`ct get <git>@*` 同样取最旧。

## 最小复现

本地 git registry，两个 tag：

```console
$ git tag
0.1.0
v0.2.0

$ CT_REGISTRY=file:///tmp/reg ct get gutil
installed 1 package(s)
$ grep gutil ct.lock
ct/gutil 0.1.0 git file:///tmp/reg/gutil ... sha256:...
```

`ct get gutil@*` 同样得到 `0.1.0`；显式 `gutil@^0.1.0` 得到 `0.1.0` 是正确 MVS 行为。

## 代码定位

`git_pick_tag` 的注释与比较固定为 `version_cmp(v, best) < 0`（最低满足版本）；
`pkg_index_lookup` 同样按 `< 0` 选行。无 range / `*` 时 `range_match` 接受所有版本，
于是“最低满足”退化为“最旧 tag”。

## 期望行为

1. **省略 range**：取最新 tag；
2. **`*`**：取最新 tag；
3. **显式范围**（`^x.y.z`、`>=` 等）：仍按 MVS 取最低满足版本；
4. 索引路径与 git URL 路径同规则；
5. 无 tag 时仍回退默认分支（现有行为不变）。

## 验收判据

| # | 输入 | 期望 |
| --- | --- | --- |
| A1 | 两 tag `0.1.0` / `0.2.0`，`ct get gutil` | lock 为 `0.2.0` |
| A2 | 同上，`ct get gutil@*` | lock 为 `0.2.0` |
| A3 | 同上，`ct get gutil@^0.1.0` | lock 为 `0.1.0` |
| A4 | 索引含两版本，`ct get --index ... gutil` | 取最新行 |
| A5 | 无 tag | 仍锁默认分支 tip |

## 处置

- 测试：`test/pkg/run.sh` 增“no range / * picks newest”段；
- 实现：`git_pick_tag` / `pkg_index_lookup` 的默认选择改为最大版本，显式范围保持最小；
- 版本：`v0.63.3`（fix，+PATCH）；`test/pkg` 144/0。
