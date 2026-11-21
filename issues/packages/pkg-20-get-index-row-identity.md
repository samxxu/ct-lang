# PKG-20 · A2：`ct get` 选中索引行未校验 name/publisher/version/tag（bugfix）

| 项 | 值 |
| --- | --- |
| 模块 | packages / 消费侧索引读取 |
| 定性 | **bugfix**（对齐已成文契约；冻结期允许） |
| 严重度 | Medium |
| 锚点 | v0.84.1（2026-11-21） |
| 依据 | [对齐清单 A2](../planning/ct-pkg-index-alignment.md)、[契约 §4.4](../planning/ct-pkg-get-contract.md#44-ct-index-verify只读ct-lang-负责)、[D-014](../decisions/D-014.md) |
| 状态 | open |
| 处置证据 | **待办（DEV；冻结期 bugfix 切片）** |

## 现象

`ct index verify` 会拒绝非法 name / publisher / version / tag；但 `ct get --index` 命中同一行时
不校验，直接进入 `git clone`。实测（v0.84.1）：

```console
$ ct index verify /tmp/ct-idx-probe/idx_badtag
line 1: tag-version: index tag 'v9.9.9' must be 'v0.1.0'
index verify: FAIL

$ ct get --index /tmp/ct-idx-probe/idx_badtag pub/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed       # 没有先报 tag 错

$ ct index verify /tmp/ct-idx-probe/idx_badpub
line 1: identity: index publisher 'local' must be non-empty, not 'local', without '/'
index verify: FAIL

$ ct get --index /tmp/ct-idx-probe/idx_badpub local/foo@0.1.0
ctc: git clone of 'file:///tmp/nope' failed       # 没有先报 publisher 错
```

## 根因

`pkg_index_lookup` 只做 `name` / `publisher` 匹配与 digest 拼写检查
（[Pkg.h.ct:2441-2471](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2441-L2471)）；
`pkg_index_verify` 才做 name / publisher / version / tag / digest 全套校验
（[Pkg.h.ct:2680-2715](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2680-L2715)）。

`index_name_ok` / `index_version_ok` 已是 `PkgIndex.h.ct` 的 `pub` 函数
（[PkgIndex.h.ct:32-33](../../selfhost/ct-ast/tool/pkg/PkgIndex.h.ct#L32-L33)），可直接复用。

## 期望

对**被选中**的六字段行，在返回成功前执行与 verify 相同的校验：

- `index_name_ok(tok[0])`；
- publisher 非空、非 `local`、无 `/`；
- `index_version_ok(tok[1])`；
- `tag == 'v' + version`；
- digest 保持现有 `sha256:<64 lowercase>` 检查（已存在）。

错误文案与 verify 一致；失败发生在任何 `git clone` / store / lock 写入之前。
**不做** `ct get` 全文件扫描（未选中坏行仍不阻塞）。

## 兼容断言

| 用例 | 断言 |
| --- | --- |
| 六字段合法行 | 与现状一致，`ct get` / `ct install` 正常 |
| 五字段旧行 | 仍按 legacy 硬错，文案不变 |
| 选中行 name 非法 | `ct get` 硬错，文案同 verify |
| 选中行 `publisher = local` | `ct get` 硬错，文案同 verify |
| 选中行 `version` 非 `x.y.z` | `ct get` 硬错，文案同 verify |
| 选中行 tag 非 `v<version>` | `ct get` 硬错，文案同 verify |
| 未选中坏行 | 不影响选中好行的 `ct get` |

## 验收与门禁

1. 先提 `test(pkg): PKG-20 A2 红`（baseline 见提交说明），覆盖上述负例；
2. 实现后转绿；`ct index verify` 既有探针不变；
3. 双 job：host + Linux x64，跑 `ct get → ct index verify → ct install → 运行比对`；
4. 单提交回滚；不夹带 A1（若 A1 未合入，先 rebase）或 B/C 改动。

## 非目标

- `ct get` 全文件校验 / duplicate 检测（verify 的职责；全文件预检属 v1.1）；
- 原生 `ct index refresh`（[PKG-18](pkg-18-native-ct-index-refresh.md)）；
- index 仓脚本修复。

## 关联

- [PKG-21](pkg-21-ct-pkg-index-refactor-ruling.md)（总跟踪）
- [对齐清单](../planning/ct-pkg-index-alignment.md)
- [PKG-19](pkg-19-get-index-field-count.md)（A1，独立提交）
