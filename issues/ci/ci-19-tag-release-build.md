# CI-19 · tag 触发的 `ct-linux-x64` 发布构建与冒烟

| 项 | 值 |
| --- | --- |
| 模块 | ci（发布产物） |
| 定性 | 发布流程硬化（去掉对本机交叉工具链的依赖） |
| 严重度 | Medium |
| 锚点 | `a141badb`（`v1.0.0`；2026-11-24） |
| 依据 | [dist.md](../../docs/dist.md)、[make-dist.sh](../../selfhost/make-dist.sh)；v1.0.0 发布记录（[v1 路线](../../docs/planning/v1-release-plan.md)） |
| 状态 | open |
| 负责人 | DEV（`.github/**` 与构建脚本归 DEV；REQ 只写验收） |
| 处置证据 | **accepted（2026-11-24 所有者同意：发版构建移入 CI，本机不再依赖 zig）** |

## 1. 背景

v1.0.0 的 `ct-linux-x64.tar.gz` 是在 macOS 上用 **zig 交叉编译**产出的，且
`make-dist.sh` 的冒烟为 `UNVERIFIED`（本机无 qemu-user）。这带来两个问题：

- 发版依赖"某个人本机恰好装了什么"；同一个人换机器就要重装工具链；
- 产物没有在目标平台上真正跑过。

ubuntu runner 本身就是 x86_64，**原生 `cc -static` 即可**，也可以直接运行产物做冒烟，
不需要 zig，也不需要 qemu。

## 2. 交付

新增 `.github/workflows/release.yml`：

| 步骤 | 内容 |
| --- | --- |
| 触发 | `push` tag `v*.*.*`；另加 `workflow_dispatch`（可对既有 tag 手动重建） |
| 构建 | `cc -O2 -std=c99 -static -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o ct` |
| 自检 | `file ct` 必须是 ELF 64-bit x86-64；`./ct -v` 必须等于 tag 版本（去掉 `v` 前缀） |
| 冒烟 | `./ct compile examples/50_ref_out/prog.ct -o /tmp/p.c && cc /tmp/p.c -o /tmp/p && /tmp/p`，输出与期望一致；再跑一个 `Box` 样例（52） |
| 打包 | `ct` + `ctc -> ct` 符号链接 → `ct-linux-x64.tar.gz` + `.sha256`（与 `dist.md` 一致） |
| 上传 | `gh release upload <tag> ... --clobber`；release 不存在时先 `gh release create --verify-tag` |
| 记录 | run summary 写 digest、`ct -v` 与冒烟输出，便于追溯 |

## 3. 验收

- 用 `workflow_dispatch` 对 `v1.0.0` 重建一次并覆盖资产：run 绿，产物 `ct -v` = `1.0.0`，冒烟通过；
- release 资产的 sha256 与 run summary 一致；`docs/dist.md` 的下载路径仍有效；
- 全程不使用 zig、交叉 gcc 或本机 Linux 容器；
- 仓库不因本卡改动任何 tag、源码或 `make-dist.sh` 的行为。

## 4. 非目标

- 不新增 macOS / Windows 产物（仍按 D-014 第 6 条只发 `linux-x64`）；
- 不追求逐字节可复现（不同 gcc 版本的产物二进制允许不同，行为必须一致）；
- 不重打 `v1.0.0` tag，也不改版本号；
- 不把 `make-dist.sh` 从本地路径删掉（本机构建仍可用，只是不再是发版必经路径）。

## 5. 关联

- [dist.md](../../docs/dist.md)（产物名、下载路径、smoke 说明）
- [make-dist.sh](../../selfhost/make-dist.sh)（本地构建路径）
- [v1 路线](../../docs/planning/v1-release-plan.md)（v1.0.0 发布记录）
- [CI-18](ci-18-box-build-drop-prototype.md)（build 模式 Box 的发现在 CI 中的先例）

## 6. 派工（REQ，2026-11-24）

按 [DOC-99](../docs/doc-99-v11-prework-tracker.md) 的 P-1 派给 **DEV**：新增
`.github/workflows/release.yml`，按 §2 的六个步骤实现，按 §3 验收。

REQ 的边界：本节与 §2/§3 已给出工作流形态与判据，不代改 `.github/**`、不代跑
`workflow_dispatch`。DEV 交付时在卡内贴：run 链接、`ct -v` 输出、冒烟输出、
资产 sha256，并说明是否覆盖了 `v1.0.0` 的既有资产。
