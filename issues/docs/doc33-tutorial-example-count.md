# DOC-33 · 教程称 `examples/` 有 7 个可运行示例，实际 8 个

| 项 | 值 |
| --- | --- |
| 模块 | docs（教程） |
| 严重度 | Low |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [docs/tutorial.md:483](../../docs/tutorial.md#L483)（中文）、[docs/tutorial.md:961](../../docs/tutorial.md#L961)（英文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

§12「下一步」写「`examples/**` —— 7 个可运行示例」，英文版写 "seven runnable demos"。
`examples/` 实有 8 个目录（`01_greeter` … `08_map_binding`），README §4 与 `test/run.sh` 也按 8 个描述
（其中 `08_map_binding` 由 `check-ast.sh` 构建、`07_dialect` 由 dialect 层驱动）。

## 证据

```text
$ ls -d examples/*/ | wc -l
8
$ ls -d examples/*/ 
examples/01_greeter/ … examples/08_map_binding/
```

## 建议

改为 8，中英同步；或直接去掉数字，改为「`examples/**` —— 每个语法点一个可运行示例」，
避免下次增删示例再漂。
