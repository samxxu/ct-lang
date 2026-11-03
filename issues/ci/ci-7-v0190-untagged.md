# CI-7 · `v0.19.0` 没有 tag：验收口径与安装口径不可用

| 项 | 值 |
| --- | --- |
| 模块 | ci |
| 严重度 | Medium |
| 锚点 | commit `4b9946b`（2026-11-03，`v0.19.0` + 1 commit） |
| 文件 | [install.sh:27](../../install.sh#L27)（`-V/--version REF`）、[L72](../../install.sh#L72)（`archive/$ref.tar.gz`）；验收口径 [docs/roadmap.md:33](../../docs/roadmap.md#L33) |
| 状态 | 待明确指令（不擅自动 tag / bump） |

## 现象

roadmap / README 把 `v0.19.0` 当作 Phase 19 的收口版本，但仓库没有对应 git tag，`install.sh` 依赖的
`archive/v0.19.0.tar.gz` 也不存在。安装入口因此无法按文档所指的版本定位。

## 证据

```text
$ git tag -l 'v0.19*'
（空输出）

$ git log -1 --oneline
4b9946b fix(review): close the four Phase 19 review findings

$ ct -v
ct v0.16.2
```

- `install.sh:27` 定义 `-V, --version REF`；
- `install.sh:72` 读取 `archive/$ref.tar.gz`；
- `docs/roadmap.md:33` 已写 `✅ 完成（2026-11-03；19.0–19.4；v0.19.0）`。

## 影响

Medium：文档说 `v0.19.0` 已收口，安装器却拉不到该版本；用户无法按版本安装或回滚，也无法验证
「README 的 `v0.19.0` 验收口径」对应哪一份源码。对「可复现分发」这一目标而言是可察觉的缺口。

## 修复建议

1. 在收口 commit（`4b9946b` 或其后的版本 bump commit）打 `v0.19.0` tag，并生成 `archive/v0.19.0.tar.gz`；
2. 若本轮不打算发版，把 README / roadmap 的验收口径改为 `4b9946b`（或 `HEAD`），不要写未发布的版本号；
3. `install.sh` 在归档缺失时报明确错误（`unknown version: v0.19.0`）并列出可用 ref，而不是泛泛的下载失败。

## 验证

- `git tag -l 'v0.19.0'` 非空且指向预期 commit；
- `install.sh --version v0.19.0` 能取到归档并完成安装；
- roadmap / README 中的版本号与 tag 一一对应。

## 处置

**现象认可；建议 1 暂不执行，建议 2 不采纳，建议 3 暂不实施。**

- 建议 1（`git tag v0.19.0`）：维护者已明确「没有明确指令不要 bump 和打 tag」。本轮只提交代码，
  不打 tag、不动 `CTC_VERSION`。**建议**：在维护者确认收口后 `git tag -a v0.19.0 -m ...` 并推送，
  届时 `install.sh --version v0.19.0` 即可用。
- 建议 2（把验收口径改成 commit）：与 docs 门禁冲突——`check_version` 要求 README 的 `vX.Y.Z`
  与 `CTC_VERSION` 一致，而 `CTC_VERSION` 已是 `0.19.0`。要改口径就得先回退版本号，等于把已完成的
  19.4 收口退回，代价大于收益。
- 建议 3（`install.sh` 明确报 `unknown version`）：需要网络探测 tags 或维护可用列表，且只在「按不存在
  的 tag 安装」时才有价值；在 tag 补齐前不构成修复合集的一部分，留作独立改进。
- 旁注：`$ ct -v` 显示 `v0.16.2` 是复核机器上安装的旧二进制，与仓库源码无关，不计入本条。
