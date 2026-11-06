# DOC-63 · 教程与内存指南的「适用版本」仍写 `v0.16.0`

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low |
| 锚点 | commit `c27da3d`（`v0.19.1` + 1 commit，2026-11-03） |
| 文件 | [docs/tutorial.md:5](../../docs/tutorial.md#L5)、[docs/memory-guide.md:5](../../docs/memory-guide.md#L5) |
| 状态 | 待处理 |

## 现象

两篇面向使用者的文档头部都写「适用版本：v0.16.0」，但仓库当前版本是 `v0.19.1`，且两份文档在
`v0.16.3`–`v0.19.1` 间都被更新过（教程已补 `ct check` 行与诊断说明）。

## 证据

```text
$ grep -n "适用版本" docs/tutorial.md docs/memory-guide.md
docs/tutorial.md:5:> **适用版本**：v0.16.0，安装入口为 **ct-ast** ...
docs/memory-guide.md:5:> **适用版本**：v0.16.0，主线编译器 **ct-ast** ...
```

```text
$ ct -v
ct v0.19.1
```

外部评估 §4.7 也把这一处列为「仍有过期点」；README / AGENTS 已按当前版本维护。

## 影响

Low：不影响语义，但读者按版本号判断文档时效，会误以为教程停留在 `v0.16.0`，从而怀疑
`ct check` / `borrow` 等新内容是否可信。

## 修复建议

1. 两处改为当前版本（`v0.19.1`），或改成不绑定数字的「当前主线 `ct-ast`」；
2. 若版本号准备长期自动维护，把它接入 `test/docs/check-docs.py`（与 `<!-- gates:N -->` 同类做法），
   避免每次 bump 都要人工同步；
3. 顺带检查 `docs/*.md` 是否还有其它 `v0.16.x` 的「适用版本」抬头。

## 验证

- `grep -rn "适用版本" docs/*.md` 与 `CTC_VERSION` 一致（或不再写具体版本）；
- `python3 test/docs/check-docs.py` 通过。
