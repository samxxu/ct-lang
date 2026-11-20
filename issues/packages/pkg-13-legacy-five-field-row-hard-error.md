# PKG-13 · 五字段旧索引行改为按行硬错

| 项 | 值 |
| --- | --- |
| 模块 | packages（`ct get` 索引解析） |
| 定性 | 破坏性契约变更（推翻契约 I12 的“只读兼容”） |
| 严重度 | High（存量包会立即不可安装） |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [ct-pkg-get-contract.md](../../docs/planning/ct-pkg-get-contract.md) §3.2/§8、[ct-pkg-index.md](../../docs/ct-pkg-index.md) |
| 状态 | **待办（DEV 实现；发布顺序由 REQ 协调）** |

## 裁定

[D-014](../../docs/decisions/D-014.md) 第 5 条：五字段旧行**按行立即硬错**——请求的 spec 命中五字段行即失败；
索引中其余六字段行照常可用。契约 I12 已同步改写。

## 影响

- `ct/hal` 等仍是五字段旧行的包会立即不可安装；
- 官方 pin 表（`std`）不受影响，因为走编译期常量；
- index 仓必须先清零五字段行，再发布带硬错的 `ct` 版本。

## 期望行为

```text
$ ct get --index old.index acme/util@1.0.0
ctc: index row for 'acme/util 1.0.0' is legacy (five fields); a six-field row is required
```

- 请求命中旧行：退出码 1，不写 store、不写 lock；
- 请求命中六字段行：行为不变；
- 错误信息给出六字段形态示例。

## 发布前置（必须与 index 仓协同）

1. index 仓刷新全部行为六字段，并给出清零证明；
2. 本仓再发布硬错版本；或在硬错版本前先发“逻辑存在但默认关闭”的过渡版本；
3. 旧行清零后，方可删除兼容分支。

## 验收

- 新增夹具：旧行命中硬错、六字段行正常、混合索引按行判定；
- 契约 §9 验收第 4 条与实现一致；
- 发布说明写明破坏性变更与迁移步骤。

## 关联

- [D-014](../../docs/decisions/D-014.md)、[PKG-12](pkg-12-contract-v1-doc-gaps.md)
- [ct-pkg-index.md](../../docs/ct-pkg-index.md) §2/§3 需同步旧行为描述
