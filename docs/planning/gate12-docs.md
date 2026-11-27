# Gate 12（ct-ast 静态 goldens）文档同步补丁

> 用途：交付 DEV，**随 gate 12 激活的同一次提交**落地；不得独立 commit。
>
> 基线：HEAD `48533f23`（2026-11-21）。补丁文件：[gate12-docs.patch](gate12-docs.patch)。

## 为什么必须原子落地

`check-docs` 的「门禁条数」断言要求文档里的条数等于 `selfhost/check-all.sh` 的 `run_gate`
数量。只改文档不加门禁 → `check-docs` 红；只加门禁不改文档 → 同样红。**不存在先改文档的
安全窗口**，所以本补丁必须与以下两项同提交：

1. `selfhost/check-goldens-ast.sh`（新脚本，SH-105）；
2. `selfhost/check-all.sh` 的第 12 条：
   `run_gate "12) CT: ct-ast static goldens" CT_C_BOUNDARY=allow bash selfhost/check-goldens-ast.sh <ct-ast>`。

## 应用

```sh
git apply docs/planning/gate12-docs.patch
# 若目标文件已有本地编辑（当前工作区可能正在改 README/docs），改用：
git apply --3way docs/planning/gate12-docs.patch
```

补丁只改文案，不含代码；在干净 HEAD 上已用 `git apply` 验证可应用（5 文件、9 行）。

## 五处替换

| 文件 | 位置 | 旧 → 新 |
| --- | --- | --- |
| `README.md` | §5 文档与测试 | 跑 `11` 道硬门禁 → `12` |
| `docs/README.md` | 文档约定第 4 条 | 当前共 `11` 道 → `12` 道 |
| `docs/glossary.md` | 硬关卡 / 聚合入口两行 | `11` 个条目 / `11` 关 / `OK (11 hard gates green)` → `12`；门禁列表追加 `check-goldens-ast` |
| `AGENTS.md` | §5 门禁入口行 | `11` 道硬门禁 → `12` 道 |
| `issues/README.md` | `<!-- gates:N -->` 与当前计数段 | `gates:11` → `12`；当前 `11` 道 → `12`；列表追加 `check-goldens-ast`；`「11 hard gates green」` → `12` |

不改：`issues/README.md` 第 1196 行的历史快照（`v0.18.1` 11 道 / `v0.19.0` 起 12 道）、
`docs/history/**`、`battle/**` 的历史记录。

## 验证

```sh
python3 test/docs/check-docs.py
# 期望：…, 12 hard gates, …

bash selfhost/check-all.sh
# 期望：check-all: OK (12 hard gates green)
```

**负例（证明原子性）**：临时注释掉 `check-all.sh` 的第 12 条 `run_gate`，重跑
`python3 test/docs/check-docs.py`，必须因 gate 计数不一致而红；恢复后绿。

## 回滚

补丁与门禁接线在同一提交：回滚该提交即同时恢复 11 道文案与 11 道门禁，不留半态。
