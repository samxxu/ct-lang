# battle/index-pkg-1 — `ct pkg` 是否作为 index 仓 `package.sh` 的透传捷径

| 字段 | 值 |
| --- | --- |
| 争点 | `ct pkg` 首次提示/执行 `ct pkg init` 拉取 index 仓，之后把参数透传给 index 仓的 `package.sh`；`install.sh` 不再拉 index |
| 当前 HEAD | `a979ce0d`（v0.65.1；`ct pkg` 当前是 `ct install` 别名） |
| 触发理由 | 用户希望把 index 仓的 package.sh 变成 `ct pkg` 的统一入口，替代 install.sh 拉索引 |
| proposer | REQ（主张 A：init + 透传 package.sh） |
| opposition | REVIEW（主张 B：不复用 `ct pkg`，发布脚本留在 index CI/独立工具） |
| judge | EDITOR |
| 禁止触碰 | `install.sh`、`selfhost/**`、`test/**`、`docs/language-spec.md`；只写 `battle/index-pkg-1/` 与 `/tmp` |

## 位置 A（init + 透传）

1. `ct pkg` 首次运行检测 `$CT_HOME/index`；不存在则提示 `ct pkg init`；
2. `ct pkg init` clone/pin `ct-pkg/index` 到 `$CT_HOME/index`；
3. 之后 `ct pkg <args>` 直接执行 `$CT_HOME/index/package.sh <args>`，参数透传；
4. `install.sh` 不拉 index；
5. 失败/未 init/脚本缺失给出明确诊断。

## 位置 B（不复用 ct pkg）

1. `ct pkg` 保持包管理/只读语义，不变成任意脚本入口；
2. `package.sh` 是 index 仓维护者工具，带 credentials/写权限，留在 CI 或独立 `ct-pkg` 工具；
3. 若需要 init，只做索引拉取/校验，不执行 package.sh；
4. 避免“ct 参数透传”带来的权限/兼容/审计问题。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 语义/命令兼容：`ct pkg` 当前是 install 别名，改成脚本入口是否破坏 | 命令对照 |
| J-2 | 安全：package.sh 的 credentials/写权限、任意参数透传 | 威胁模型 |
| J-3 | 架构：ct 零网络/子进程边界，index 可变 main | 代码路径 |
| J-4 | UX：init 一次 vs 直接跑；首次提示是否足够 | 交互矩阵 |
| J-5 | 索引质量：五字段/无签名/package.sh 发布脚本现状 | 外部仓证据 |
| J-6 | 成本/回退：init、脚本查找、失败模式 | 文件/行数 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点核 `main.ct:121-122`（`ct pkg` 别名）、`Pkg.h.ct` 的 `ct pkg check` 只读、`install.sh` 无 index、index 仓 `package.sh`/`index.yml` 的 credentials。
