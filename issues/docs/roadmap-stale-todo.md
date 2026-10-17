# DOC-5 · roadmap.md 残留「待做 / PENDING」条目，已被后续进展取代

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Low** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | [docs/roadmap.md](../../docs/roadmap.md#L680-L682) L680、L682 |
| 状态 | 已修复（commit `b6b3dc4`） |

## 现象

roadmap 同一阶段内按时间追加了多条「进展」，但早先条目的「待做」未随之后续条目更新：

- L680：「**待做**：多文件 `.h.ct` / `pub` / `ct build` / `import`——`test/archive/{multifile,import}/` 的四个单元仍 PENDING。」
- L682：「**待做**：Phase 2 的 `--line` 与 Phase 3+ 的恢复项；`--line` / `--no-line` 覆盖开关仍归 Phase 4。」

## 证据

- 紧随其后的 L681 已记「多文件 `ct build`、`pub`、`import` 与 `.h.ct` / `-I` **均达成**」；L683 记 Phase 2 收口。
- `bash selfhost/check-archive.sh` 实测：`multi-unit goldens: 4 pass, 0 pending`。
- roadmap 总览表 L23 记 Phase 4 ✅ 完成，故「`--line` 仍归 Phase 4」亦已过时。

## 影响

单一文档内「待做」与「已完成」并存，读者需自行判断哪条为准；roadmap 是阶段真相来源，残留会让其自贬值。

## 修复建议

将 L680、L682 的「待做」句改为「（已被下方 2026-10-16 条目取代）」或直接删除。**注意**：roadmap 是**追加式**历史记录，建议只做最小订正、不重写历史条目。

## 验证

改后全文 `grep -n '待做\|PENDING' docs/roadmap.md`，确认剩余条目均仍有意义；与 `check-archive.sh` 的四态输出一致。
