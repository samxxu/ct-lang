# DOC-61 · roadmap 英文表 Phase 18 仍为 `in progress`

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [docs/roadmap.md:33](../../docs/roadmap.md#L33)（中文表）、[L975](../../docs/roadmap.md#L975)（英文表） |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

roadmap 的阶段总览有中英两张表，Phase 18 的状态不一致：

- 中文 `:33`：`✅ 完成（2026-11-02）`，并写明 18.0–18.6 全部落地、收口 bump 到 `v0.18.0`；
- 英文 `:975`：仍为 `🟨 in progress`。

Phase 19 的英文行已经是 done，只有 Phase 18 漏改。

## 证据

```text
$ grep -nE "\| 18 \|" docs/roadmap.md
975:| 18 | Ecosystem ... | 🟨 in progress | ... |

$ grep -n "| Phase 18 |" docs/roadmap.md
33:| Phase 18 | 生态建设 ... | ✅ 完成（2026-11-02） | ... |
```

`docs/roadmap.md` 同文件的「版本记录」已列 `v0.18.0 | Phase 18 生态建设`，与英文表状态自相矛盾。

## 影响

英文读者会认为 Phase 18 尚未完成，从而低估 `ct-pkg` / `hal` / 索引仓库的可用性。docs 门禁当前只校验
中文 `| Phase n |` 行（见 TEST-15），所以这类漂移不会被自动发现。

## 修复建议

1. 英文行改为 `✅ done (2026-11-02)`，并补一句与中文等价的收口描述（18.0–18.6、`v0.18.0`、D18-1–D18-11）；
2. 顺带核对 Phase 19 英文行的措辞与中文一致；
3. 与 TEST-15 一并考虑，把英文行纳入门禁。

## 验证

- `grep -nE "\| 18 \|" docs/roadmap.md` 的状态与中文 `:33` 一致；
- `python3 test/docs/check-docs.py` 通过；
- 人工通读中英两张表，逐行比较状态列。

## 处置

**认可，已修。** 采纳建议 1、2、3。

- 英文 Phase 18 行改为 `✅ done (2026-11-02; 18.0–18.6 all landed … closing bump to v0.18.0; …)`，
  与中文行等价，见 [docs/roadmap.md:975](../../docs/roadmap.md#L975)。
- Phase 19 的英文行已核对，与中文一致。
- 建议 3 已在 TEST-15 落地：[check-docs.py](../../test/docs/check-docs.py) 的 `check_phase_status`
  同时校验 `| n |` 英文行，英文状态与设计文档不一致即失败。
- 双向验证：把英文 Phase 18 临时改回 `🟨 in progress` → 门禁报
  `English roadmap row disagrees with status '完成'`；恢复后绿。
