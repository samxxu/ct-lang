# DOC-56 · `issues/README.md` 仍写「9 hard gates green」作为现状口径

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low |
| 锚点 | commit `553d300`（2026-11-02，工作树 `v0.18.0`） |
| 文件 | [issues/README.md](../../issues/README.md#L49) L49 |
| 状态 | 已修（2026-11-02，`v0.18.0`）：改为「当前共 **11** 道（第 10 道文档门禁、第 11 道 std 层）」，并去掉漂移的行号区间，改为引用 `selfhost/check-all.sh`；历史记录里的六 / 七 / 八 / 九道保持原样 |

## 现象

L49 的严重度说明段写：

```text
- 硬关卡计数随阶段演进：6 → 7 → 8 → **9**（`check-warnings.sh` 接入后为九关；构成见
  [check-all.sh:72-80](../selfhost/check-all.sh#L72-L80)）。… 现状一律以 `check-all.sh` 的
  「9 hard gates green」与 roadmap 为准。
```

## 证据

- `grep -c '^run_gate "' selfhost/check-all.sh` → **11**：第 10 道是文档门禁、第 11 道是 std 层。
- 本轮实跑 `python3 test/docs/check-docs.py` 自报 `11 hard gates`。
- 引用的 `check-all.sh:72-80` 已漂移：当前 11 处 `run_gate` 分布在更靠后的行，该区间已不对应九关。

## 影响

`issues/README.md` 是审查台账的入口，且这一句自己声明「现状以它为准」——它把现状写成了九关，
与 `check-all.sh`、`docs/README.md`、roadmap 的十一关口径不一致。

## 修复建议

1. 该句改为「当前共 **11** 道硬门禁（文档门禁为第 10 道、std 层为第 11 道）」，并去掉会漂移的行号区间，
   改为引用 `selfhost/check-all.sh`（不带行号）。
2. 历史记录里出现的「六道 / 七道 / 八道 / 九道」保持原样（它们是当时口径）。
