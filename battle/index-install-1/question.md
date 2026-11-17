# battle/index-install-1 — install.sh 自动拉 index + `ct pkg` 调发布脚本

| 字段 | 值 |
| --- | --- |
| 争点 | 是否在 `install.sh` 默认把 `ct-pkg/index` 拉到 `~/.ct`，并让 `ct pkg` 映射调用 index 仓的发布脚本 |
| 当前 HEAD | `792d5bc1`（v0.65.1；`ct-pkg/index` 为外部仓） |
| 触发理由 | 用户希望安装即带索引，并让发布脚本可经 `ct pkg` 调用；要求 battle |
| proposer | REQ（主张 A：默认自动拉 + 发布脚本映射） |
| opposition | REVIEW（主张 B：安装不默认联网；索引更新显式；发布脚本留在 CI） |
| judge | EDITOR |
| 禁止触碰 | `install.sh`、`selfhost/**`、`test/**`、`docs/language-spec.md`；只写 `battle/index-install-1/` 与 `/tmp` |

## 位置 A（默认自动拉 + 发布脚本映射）

1. `install.sh` 安装 `ct` 后，默认 `git clone https://github.com/ct-pkg/index` 到 `~/.ct/index`；
2. 后续 `ct get` 默认使用它（`CT_INDEX=~/.ct/index/index`）；
3. `ct pkg index update` 拉最新索引；
4. `ct pkg publish` / `ct pkg index publish` 直接调用 index 仓的发布脚本，完成校验/签名/提交；
5. 安装失败时 index 拉取失败不阻断 `ct` 安装（降级）。

## 位置 B（安装不默认联网；发布留在 CI）

1. `install.sh` 只装编译器，不默认 clone 索引；需要索引时显式 `ct index update` 或 `CT_INDEX`；
2. `ct pkg` 只读索引/本地包，不执行发布脚本；发布仍由 index 仓 CI 做；
3. 索引更新必须 pin commit/签名，不能匿名拉 main；
4. 发布脚本带 credentials/写权限，不能进编译器二进制；
5. 离线安装、可复现安装优先；网络失败不污染 `~/.ct`。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 安装离线/可复现：默认联网是否可接受，失败如何降级 | 断网/代理/重复安装矩阵 |
| J-2 | 供应链安全：匿名 main、索引可变、签名/pin | 威胁模型 |
| J-3 | 架构边界：编译器零网络/零子进程是否被破坏 | 代码路径审计 |
| J-4 | UX：安装即用 vs 手动一步；发布命令是否真的更方便 | 命令对照 |
| J-5 | 发布工作流：credentials、CI、审计、回滚 | 发布脚本/权限清单 |
| J-6 | 实现/维护成本：install.sh、ct pkg、索引仓 CI | 文件/行数/失败模式 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点核 `install.sh` 现有网络/离线路径、`ct get` 的 `CT_INDEX`/`CT_REGISTRY`、`ct pkg` 当前只读边界、AGENTS 的零网络/子进程例外、index 仓发布脚本的权限。
