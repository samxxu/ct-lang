# PKG-15 · 包管理 conformance 数据与 runner

| 项 | 值 |
| --- | --- |
| 模块 | packages（跨仓验收） |
| 定性 | 能力缺口（无双实现对照基准） |
| 严重度 | Medium |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [契约 v1](../../docs/planning/ct-pkg-get-contract.md) §3.3/§9、[D-014](../../docs/decisions/D-014.md) |
| 状态 | open |
| 处置证据 | **待办（REQ 定数据，DEV 接 runner）** |

## 现象

`package-check.sh` 与 `ct pkg check` 各自实现同一批规则，缺一套机器可执行的共同基准；
digest 算法只有文字描述，没有可回归的输入输出对。

## 交付

1. **数据**（版本化，纯文本）：
   - 合法/非法 `ct.pkg`（缺 publisher、`local`、坏 `ns-root`、未知键等）；
   - 合法/非法索引行（五字段旧行、字段数、digest 拼写、tag/版本不一致）；
   - digest 输入输出对：至少包含契约 §3.3 的三个向量；
2. **runner**：同一份数据分别喂 `ct` 与 shell，逐条比对退出码与诊断类别；
3. **基准**：契约 v1 发布时给出“两边一致/已知差异”清单。

## 验收

- 数据可被第三方 registry 直接复用；
- digest 三向量与契约 §3.3 完全一致；
- runner 在 CI 中可对固定 `ct` 版本重放；差异必须显式登记，不得静默跳过。

## 关联

- [PKG-12](pkg-12-contract-v1-doc-gaps.md)（判据编号）、[PKG-13](pkg-13-legacy-five-field-row-hard-error.md)（旧行行为）
