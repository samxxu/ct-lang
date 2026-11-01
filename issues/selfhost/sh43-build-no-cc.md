# SH-43 · `ct build` 只发 `.c/.h` 并打印 `cc` 行，不代为编译

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（CLI / 工具链） |
| 严重度 | Info（已文档化的行为，属工具缺口而非缺陷；是否补能力需维护者决定） |
| 锚点 | commit `61e35e4`（`v0.16.1`，2026-11-01） |
| 文件 | [README.md](../../README.md)（`ct build` 条目）、[Driver.h.ct](../../selfhost/ct-ast/tool/driver/Driver.h.ct) |
| 状态 | 待决（2026-11-01 复核维持）：本轮不实现 `--emit-build-plan` / `--cc`，也不改默认行为；能力变更留待维护者决定 |

## 现象

`ct build -I <dir> <unit>.ct -o <out>` 只写 `.c/.h`，然后**打印**一条建议的 `cc` 命令行，
不调用 `cc`，也不透传 `-l/-L/-D`。因此每个项目都要自写 `build.sh`（`examples/**` 与 `test/**` 均是如此）。

```text
$ ct build -I /tmp/chk5 /tmp/chk5/main.ct -o /tmp/chk5/out
cc -std=c99 /tmp/chk5/out/main.c /tmp/chk5/out/shapes.c /tmp/chk5/out/impl_dog.c -o a.out
$ echo $?
0
```

README 已写明 `ctc install` 校验后「打印建议的 `ct build …`（不调用 `cc`）」，`build` 同理，
所以这**不是文档漂移**，而是有意的边界。第三方评估把它列为 D8 的工具链缺口，成立。

## 为什么不直接当缺陷修

- 加 `--cc` 会引入「ct 承担链接与 C 编译」的新语义：`-l/-L/-I/-D` 的归属、失败退出码、
  与 `--diagnostics` 的输出顺序都要重新定义，属于**能力变更**（需授权，且要同步 README / spec / usage / 门禁）；
- 现形态对「产物可读、名字可预期」这条定位是有利的：用户看得到真正执行的那条 `cc`。

## 可选的两种做法（供决定）

1. **低风险**：加 `--emit-build-plan <file|->`，输出 JSON（`sources[] / includes[] / defines[] / libs[]`），
   不执行任何外部命令——对 LSP / 构建系统最友好，且不动默认行为；
2. **高风险**：加 `--cc`（真编译 + 透传 `-l/-L/-I/-D`），需新增门禁用例覆盖失败退出码，
   并明确「ct 不解析 `cc` 的诊断」。

## 验收（若采纳第 1 种）

- 默认行为逐字节不变（现有 `test/**` 的 `cc` 行断言不受影响）；
- `--emit-build-plan` 的 JSON 与打印的 `cc` 行一一对应；
- 九关全绿；README 中英同步。

## 关联

- [CI-4](../ci/ci-4-no-ci-config.md)：同一轮第三方评估的 P0-1（CI 仍缺 workflow）
- [SH-24](cli-parser-duplication.md)：两套 CLI 解析器——新增开关需要同时改两处（或先合并）
