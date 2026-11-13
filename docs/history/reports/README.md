# 历史报告（离线 HTML）

> 中文。这些 HTML 是历史快照，保留当时的样式与图表；不再更新内容。

三份 HTML 报告（`ct-language-features`、`selfhost-readiness`、`ctc-ct-analysis`）
共用 `_shared/` 下的字体与 JS（echarts / mermaid），引用形如 `../_shared/js/...`。
2026-11-13 之前每份报告各带一份副本；现收敛到一处，减少 checkout 体积。

**单独拷走某份报告时要连同 `_shared/` 一起拷**，否则字体与图表脚本缺失
（报告本身是纯静态的，不联网加载任何资源）。
