---
id: CI-14
status: open
title: "G6 baseline tracking fixture"
---

# CI-14 tracking fixture

This fixture stands in for the real CI-14 issue so the ratchet mode can verify
that a whitelist hangs on a live tracking issue. It is a test fixture only.

## 退出条件

1. `issues/.g6-baseline.tsv` 为空或已删除；
2. `g6` 在严格模式下通过；
3. 遗留项各有去向。

The `g6` gate must accept this file as tracking metadata.
