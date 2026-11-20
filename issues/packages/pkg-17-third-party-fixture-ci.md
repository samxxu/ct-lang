# PKG-17 · 第三方真实包 fixture 与 `ct index verify` 进 CI

| 项 | 值 |
| --- | --- |
| 模块 | packages / CI |
| 定性 | 能力缺口（v1.0 包体系收尾） |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [ct-pkg-get-contract.md](../../docs/planning/ct-pkg-get-contract.md)、[D-014](../../docs/decisions/D-014.md)、[PKG-14](pkg-14-ph83-index-verify-and-binary.md) |
| 状态 | **待办（REQ 选 fixture；DEV 接 CI）** |

## 现象

`ct index verify` 已实现（PH-83），但常规 CI 尚未覆盖；第三方身份路径缺少一个可重放的
真实包 fixture，无法证明“非官方 publisher 可安装”。

## 期望

1. 选一个**固定、可离线重放**的第三方包 fixture（vendored 或固定 commit + 摘要）；
2. CI 常规跑：`ct index verify` + `ct get --index` + `ct build`，验证：
   - 六字段行可安装；
   - 五字段旧行按行硬错；
   - 摘要不符硬错；
3. 不依赖网络；若必须联网，标为外部依赖并给手动步骤；
4. fixture 的版本/摘要写进测试说明，防漂移。

## 验收

- CI 有独立断言，失败可定位到具体步骤；
- fixture 与契约 v1 的 spec 形态一致；
- 不改变发布边界（不做 release/index 生成）。

## 关联

- [D-014](../../docs/decisions/D-014.md)、[PKG-13](pkg-13-legacy-five-field-row-hard-error.md)、[v1 路线 §1.5](../../docs/planning/v1-release-plan.md#L57-L71)
