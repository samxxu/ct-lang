# CI-6 · CI 两个 job 名仍写 `nine hard gates`

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | Low |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [.github/workflows/ci.yml:22](../../.github/workflows/ci.yml#L22)、[L33](../../.github/workflows/ci.yml#L33) |
| 状态 | 已修复（本轮，2026-11-03） |

## 现象

两个 job 的 `name:` 都写 `nine hard gates`，而 `check-all.sh` 当前实际执行 12 道。这是 DOC-56 → DOC-58
两次台账漂移在 CI 侧的同源残留：数量文案散落在多处，没有单一来源。

## 证据

```text
$ grep -n "hard gates" .github/workflows/ci.yml
22:    name: nine hard gates (...)
33:    name: nine hard gates (...)

$ bash selfhost/check-all.sh 2>&1 | tail -1
check-all: OK (12 hard gates green)
```

`issues/README.md` 已有机器可读标记 `<!-- gates:12 -->`，但 `ci.yml` 不读它（见 TEST-15）。

## 影响

Low：不影响构建结果，但 CI 页面上的 job 名与实际门禁数不符，与 README / 台账的「12 道」口径分叉；
同类漂移已三次，说明「手写数字」这一做法本身不可靠。

## 修复建议

1. 短期：两处改为 `12 hard gates`；
2. 长期：job 名只写主题（如 `hard gates (linux / clang)`），数量由 `<!-- gates:12 -->` 单一来源派生，
   避免第三次漂移；
3. 可选：把 `ci.yml` 的文案纳入 docs 门禁（与 TEST-15 一起做）。

## 验证

- `grep -n "hard gates" .github/workflows/ci.yml` 不再出现 `nine`；
- CI 运行后 job 名与 `check-all.sh` 的 summary 一致；
- `python3 test/docs/check-docs.py` 通过。

## 处置

**认可，已修。采纳建议 2（长期方案），不采纳建议 1。**

- 两处 step 名从 `nine hard gates` 改为 `hard gates`，数量彻底移出 CI 文案，见
  [.github/workflows/ci.yml:22](../../.github/workflows/ci.yml#L22)、[L33](../../.github/workflows/ci.yml#L33)。
  建议 1 只是把 `nine` 换成 `12`，下一次加门禁仍会漂移，所以不采用。
- 建议 3 已在 TEST-15 落地：`check_gate_count` 现在解析 `ci.yml`，任何 `N hard gates` /
  `nine|ten|eleven|twelve hard gates` 与实际 `run_gate` 数不符即失败。
- 双向验证：临时把 step 名改回 `nine hard gates` → 门禁报
  `.github/workflows/ci.yml: states 9 hard gates, check-all.sh runs 12`；恢复后绿。
- job 名里的 `(ubuntu / gcc)` / `(macos / clang)` 保留，无数字。
