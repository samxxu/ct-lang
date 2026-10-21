# DOC-13 · phase10 的 D44 身份口径与实际三态不符，PkgOps 方法数少算 1

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `4ef8b68`（2026-10-21） |
| 文件 | [docs/design/phase10.md:74](../../docs/design/phase10.md#L74)（D44）、[:59](../../docs/design/phase10.md#L59)（10.6） |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象与证据

### 1. D44 写两态，实际三态

文档：

> D44 | 身份识别 | ct-ast 也按 `argv[0]` basename 识别：`ct` → `ct`，其余 → `ctc`（与 L2 相同）

实测：

```text
$ /tmp/rev21/ct-ast -v
ct-ast v0.12.0
```

`selfhost/ct-ast/main.ct` 的身份分支是三分支（`ct` / `ctc` / 其余保持 `ct-ast`），并以 `ct-ast` 作为 `prog` 的初值。同一文档的能力对差表（第 35 行）反而写对了三态。

### 2. `PkgOps` 方法数

文档 10.6 写「新 trait `PkgOps`，28 个方法」；对 `impl PkgOps for Pkg` 块内的签名计数为 **29**。

## 影响

D44 是"已定案"的设计决策记录，两态描述会误导后续维护者以为可以直接复用 `ct`/`ctc` 二分；方法数偏差会影响容量预算（`MAX_METHOD`）。

## 修复建议

- D44 改为三态，并说明第三态仅用于开发/自编译（`ct-ast` 名字）；
- 10.6 的 28 改为 29；
- 建议在 `check-ast.sh` 的 `-v` 断言里显式钉住三种名字，避免再次漂移。

## 验证

`ct-ast -v` 输出与文档一致；`PkgOps` 计数脚本与文档数字一致。
